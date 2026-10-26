#' Interactive MSSR explorer
#'
#' Opens a Shiny app for trying [mssr()] on synthetic examples or on an
#' uploaded frame. It shows the input and the structure map side by side on
#' the same input-pixel axes, line profiles, structural masks applied to the
#' original data ([mssr_mask()]) and the fixture self-test ([mssr_selftest()]),
#' and offers the structure map, the mask, a figure and a run record for
#' download. The app calls the exported functions, so its results are the
#' same as in R; it adds no processing of its own.
#'
#' **Uploads.** Delimited text (`.csv` comma-separated, `.tsv` or `.txt`
#' separated by tabs or spaces; numbers only, no header), PNG (needs the `png`
#' package; values as returned by `png::readPNG()`, scaled to 0..1) and TIFF
#' (needs the `tiff` package; stored values, unscaled). Multi-channel images are
#' not converted to gray: choose one channel. For multi-page TIFF choose a
#' page. Files are read by the R process that runs the app (your own session
#' when started with `mssr_app()`); the app sends nothing elsewhere.
#' Run records include SHA-256 identities of uploaded bytes and decoded matrix
#' content (needs `digest`). Source filenames and paths are excluded. Retain the
#' original input and preprocessing separately; a digest identifies content,
#' not acquisition authenticity. Compare a retained file with
#' `digest::digest(file = path, algo = "sha256", serialize = FALSE)`.
#'
#' **Limits.** To keep the app responsive, runs whose estimated work exceeds
#' 5e8 operations are refused; call [mssr()] directly for larger runs. The
#' image header is checked before decoding; image uploads are limited to
#' 5e7 samples, conservatively allowing at least four channels per pixel.
#' Only the selected TIFF page is decoded. Integer TIFF samples keep their
#' stored values; floating-point TIFF samples remain unscaled. The structure
#' map is not a quantitative intensity, and nothing in the app
#' implies a gain in physical resolution.
#' Packed 12-bit, signed-integer, palette, multi-channel planar-separate and volumetric TIFF
#' images are unsupported; prepare an explicit supported 2D frame before
#' uploading. The TIFF preflight accepts classic TIFF, top-left orientation,
#' grayscale black-is-zero or RGB samples, at most 256 pages, 4096 tags per
#' page, 4 MiB of directory/tag metadata and a 256 MiB file. BigTIFF, nested
#' directories and other orientations/color conversions are refused. These
#' are workload guards, not a hard decoder memory or time guarantee.
#' Computation runs in one background R process per app session (needs `callr`).
#' Cancel stops only that session's job. Incomplete results cannot be downloaded;
#' the previous completed result can be explicitly restored. A job is cancelled
#' when its session closes or after five minutes. The child inherits CPU affinity
#' and uses one numerical thread. Changed settings are marked stale; downloads
#' retain the computed input and settings. Development-source launches also need
#' `pkgload`; source/function drift is refused instead of loading an older build.
#'
#' @param max_upload_mb Maximum upload size in megabytes.
#' @param ... Passed to [shiny::runApp()], for example `port` or
#'   `launch.browser`.
#' @return The value of [shiny::runApp()], invisibly; called for its side
#'   effect.
#' @examples
#' if (interactive()) {
#'   mssr_app()
#' }
#' @export
mssr_app <- function(max_upload_mb = 50, ...) {
  call <- sys.call()
  missing_pkgs <- mssr_app_missing(c("shiny", "bslib", "jsonlite", "callr", "digest"))
  if (length(missing_pkgs) > 0L) {
    msg <- sprintf("`mssr_app()` needs %s. Install with install.packages(c(%s)).",
                   paste(missing_pkgs, collapse = ", "),
                   paste0("\"", missing_pkgs, "\"", collapse = ", "))
    mssr_abort("dependency", msg, call)
  }
  max_upload_mb <- check_positive(max_upload_mb, "max_upload_mb", call)
  withr::local_options(shiny.maxRequestSize = max_upload_mb * 1024^2)
  invisible(shiny::runApp(mssr_app_object(), ...))
}

mssr_app_missing <- function(pkgs) {
  pkgs[!vapply(pkgs, requireNamespace, logical(1), quietly = TRUE)]
}

mssr_app_object <- function() shiny::shinyApp(mssr_app_ui(), mssr_app_server)

# Runs above this estimated work (output pixels x neighborhood offsets) are
# refused in the app. This is a workload limit, not a portable time guarantee.
mssr_app_work_limit <- 5e8
mssr_app_sample_limit <- 5e7
mssr_app_job_timeout <- 300
mssr_app_tiff_page_limit <- 256L
mssr_app_tiff_tag_limit <- 4096L
mssr_app_tiff_metadata_limit <- 4 * 1024^2
mssr_app_tiff_file_limit <- 256 * 1024^2

mssr_app_or <- function(x, default) if (is.null(x) || length(x) == 0L) default else x

# ---- Synthetic examples ---------------------------------------------------

mssr_app_examples <- c(
  "Two sources 3 px apart" = "pair_3",
  "Two sources 2.4 px apart" = "pair_2p4",
  "Two sources 3 px apart, noisy" = "pair_3_noisy",
  "Dim source beside a bright one (1:10)" = "dim_bright",
  "Filled disk" = "disk"
)

# The scenes of the vignette: 31 x 41 frames blurred with FWHM 3 px.
mssr_app_example <- function(id) {
  g <- expand.grid(r = 1:31, c = 1:41)
  spot <- function(r0, c0, a = 1) {
    a * exp(-((g$r - r0)^2 + (g$c - c0)^2) / (2 * (3 / 2.3548)^2))
  }
  pair <- function(sep) matrix(spot(16, 18) + spot(16, 18 + sep) + 0.05, 31, 41)
  switch(
    id,
    pair_3 = pair(3),
    pair_2p4 = pair(2.4),
    pair_3_noisy = withr::with_seed(
      1L, pmax(pair(3) + stats::rnorm(31 * 41, sd = 0.03), 0),
      .rng_kind = "Mersenne-Twister", .rng_normal_kind = "Inversion", .rng_sample_kind = "Rejection"
    ),
    dim_bright = matrix(spot(16, 14) + spot(16, 21.5, 0.1) + 0.02, 31, 41),
    disk = outer(1:31, 1:41, function(r, c) as.numeric((r - 16)^2 + (c - 21)^2 <= 81)) + 0.02,
    mssr_abort("parameter", sprintf("Unknown example '%s'.", id))
  )
}

# ---- Reading uploads --------------------------------------------------------

mssr_app_ext <- function(name) {
  if (grepl(".", name, fixed = TRUE)) tolower(sub(".*\\.", "", name)) else ""
}

# Bound decoded arrays before allocating them. Four channels reserve space
# for palette expansion and transparency, even for a grayscale file.
mssr_app_image_size <- function(width, height, channels = 4) {
  dims <- c(width, height, channels)
  if (length(dims) != 3L || any(!is.finite(dims)) || any(dims < 1 | dims != round(dims))) {
    mssr_abort("input", "The image header does not contain valid dimensions.")
  }
  samples <- as.double(width) * height * max(4, channels)
  if (samples > mssr_app_sample_limit) {
    mssr_abort("resource", paste("Decoded image size exceeds the app limit of 5e7 samples",
                                 "(allowing at least four channels per pixel).",
                                 "Upload a smaller frame or use mssr() in R."))
  }
  invisible(samples)
}

# PNG starts with an eight-byte signature and a 13-byte IHDR chunk. Read
# dimensions without decompressing pixel data; libpng checks the full file.
mssr_app_png_size <- function(path) {
  con <- file(path, "rb")
  on.exit(close(con))
  h <- readBin(con, "raw", 26L)
  prefix <- as.raw(c(137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82))
  if (length(h) != 26L || !identical(h[1:16], prefix)) {
    mssr_abort("input", "The file does not have a valid PNG header.")
  }
  width <- sum(as.double(h[17:20]) * 256^(3:0))
  height <- sum(as.double(h[21:24]) * 256^(3:0))
  mssr_app_image_size(width, height)
}

# Bound classic TIFF directory traversal before handing a file to libtiff.
# Numeric decoding uses doubles so unsigned 32-bit offsets never become NA.
# External tag payloads are range-checked; bounded segment arrays are read here.
mssr_app_tiff_preflight <- function(path, page) {
  size <- file.info(path)$size
  if (length(size) != 1L || is.na(size) || dir.exists(path) || size < 8) {
    mssr_abort("input", "The file does not have a complete TIFF header.")
  }
  if (size > mssr_app_tiff_file_limit) {
    mssr_abort("resource", "TIFF file exceeds the app limit of 256 MiB.")
  }
  con <- file(path, "rb")
  on.exit(close(con))
  take <- function(offset, n) {
    if (!is.finite(offset) || offset < 0 || offset + n > size) {
      mssr_abort("input", "TIFF directory or tag data extend beyond the file.")
    }
    seek(con, offset, origin = "start")
    bytes <- readBin(con, "raw", n)
    if (length(bytes) != n) mssr_abort("input", "TIFF metadata are truncated.")
    bytes
  }
  header <- take(0, 8L)
  little <- identical(header[1:2], charToRaw("II"))
  if (!little && !identical(header[1:2], charToRaw("MM"))) {
    mssr_abort("input", "The file does not have a valid TIFF byte-order marker.")
  }
  uint <- function(bytes) {
    if (!little) bytes <- rev(bytes)
    sum(as.double(bytes) * 256^(seq_along(bytes) - 1L))
  }
  magic <- uint(header[3:4])
  if (magic == 43) mssr_abort("unsupported", "BigTIFF uploads are not supported.")
  if (magic != 42) mssr_abort("input", "The file does not have a valid TIFF header.")
  offset <- uint(header[5:8])
  seen <- numeric()
  metadata_bytes <- 8
  selected <- NULL
  widths <- c(1, 1, 2, 4, 8, 1, 1, 2, 4, 8, 4, 8, 4)
  while (offset != 0) {
    if (offset < 8 || offset %in% seen) {
      mssr_abort("input", "TIFF directories contain an invalid offset or a cycle.")
    }
    if (length(seen) >= mssr_app_tiff_page_limit) {
      mssr_abort("resource", "TIFF exceeds the app limit of 256 pages.")
    }
    seen <- c(seen, offset)
    count <- uint(take(offset, 2L))
    if (count > mssr_app_tiff_tag_limit) {
      mssr_abort("resource", "TIFF directory exceeds the app limit of 4096 tags.")
    }
    metadata_bytes <- metadata_bytes + 6 + 12 * count
    if (metadata_bytes > mssr_app_tiff_metadata_limit) {
      mssr_abort("resource", "TIFF metadata exceed the app limit of 4 MiB.")
    }
    entries <- take(offset + 2, 12 * count + 4)
    tags <- numeric(count)
    scalars <- list()
    segments <- list()
    for (i in seq_len(count)) {
      entry <- entries[(12 * (i - 1L) + 1L):(12 * i)]
      tag <- uint(entry[1:2])
      type <- uint(entry[3:4])
      n <- uint(entry[5:8])
      if (type < 1 || type > length(widths) || n < 1) {
        mssr_abort("input", "TIFF has invalid field types or empty fields.")
      }
      tags[i] <- tag
      if (tag %in% c(330, 34665, 34853, 40965)) {
        mssr_abort("unsupported", paste("TIFF uploads with nested image or metadata directories",
                                        "are unsupported."))
      }
      bytes <- n * widths[type]
      if (bytes > 4) {
        metadata_bytes <- metadata_bytes + bytes
        if (metadata_bytes > mssr_app_tiff_metadata_limit) {
          mssr_abort("resource", "TIFF metadata exceed the app limit of 4 MiB.")
        }
        data_offset <- uint(entry[9:12])
        if (data_offset < 8 || data_offset + bytes > size) {
          mssr_abort("input", "TIFF tag data extend beyond the file.")
        }
      }
      if (tag %in% c(256, 257, 262, 274, 277, 322, 323)) {
        if (n != 1 || !type %in% c(3, 4)) {
          mssr_abort("input", "TIFF dimensions, orientation or photometric fields are malformed.")
        }
        scalars[[as.character(tag)]] <- uint(entry[9:(8 + widths[type])])
      }
      if (tag %in% c(273, 279, 324, 325)) {
        if (!type %in% c(3, 4)) {
          mssr_abort("input", "TIFF segment offsets and byte counts must be unsigned integers.")
        }
        values <- if (bytes <= 4) entry[9:(8 + bytes)] else take(data_offset, bytes)
        values <- matrix(as.double(values), nrow = widths[type])
        if (!little) values <- values[rev(seq_len(nrow(values))), , drop = FALSE]
        segments[[as.character(tag)]] <- as.numeric(
          crossprod(256^(seq_len(widths[type]) - 1L), values)
        )
      }
    }
    if (anyDuplicated(tags)) mssr_abort("input", "TIFF contains duplicate directory tags.")
    # libtiff can allocate strip bookkeeping even in metadata-only mode.
    # Bound every page before opening any directory through that library.
    mssr_app_image_size(scalars[["256"]], scalars[["257"]],
                        mssr_app_or(scalars[["277"]], 1))
    if (!is.null(scalars[["322"]]) || !is.null(scalars[["323"]])) {
      mssr_app_image_size(scalars[["322"]], scalars[["323"]],
                          mssr_app_or(scalars[["277"]], 1))
    }
    tiled <- any(c("324", "325") %in% names(segments))
    keys <- if (tiled) c("324", "325") else c("273", "279")
    if (!setequal(names(segments), keys) ||
          length(segments[[keys[1]]]) != length(segments[[keys[2]]])) {
      mssr_abort("input", "TIFF segment offsets and byte counts are missing or inconsistent.")
    }
    starts <- segments[[keys[1]]]
    lengths <- segments[[keys[2]]]
    if (any(starts < 8 | lengths < 1 | starts + lengths > size)) {
      mssr_abort("input", "TIFF image segments are empty or extend beyond the file.")
    }
    if (length(seen) == page) selected <- scalars
    offset <- uint(utils::tail(entries, 4L))
  }
  if (!length(seen)) mssr_abort("input", "TIFF contains no image directory.")
  page <- check_whole(page, "page", 1L, length(seen))
  orientation <- mssr_app_or(selected[["274"]], 1)
  if (orientation != 1) {
    mssr_abort("unsupported", "TIFF uploads require top-left orientation (orientation 1).")
  }
  if (is.null(selected[["262"]]) || !selected[["262"]] %in% c(1, 2)) {
    mssr_abort("unsupported", "TIFF uploads require black-is-zero grayscale or RGB sample values.")
  }
  list(pages = length(seen), orientation = orientation, metadata_bytes = metadata_bytes)
}

# Reader failures use the same condition contract as computation failures.
mssr_app_decode <- function(expr) {
  tryCatch(withCallingHandlers(expr, warning = function(w) {
    mssr_abort("input", paste("The image reader reported a warning;",
                              "incomplete or ambiguous images are refused."))
  }), error = function(e) {
    if (inherits(e, "mssrscopR_error")) stop(e)
    mssr_abort("input", "The image could not be decoded; check that it is a valid PNG or TIFF.")
  })
}

# readTIFF() returns scaled doubles for multi-channel integers even when
# as.is = TRUE; its single-channel integer path cannot represent all uint32
# values. Decode consistently as doubles and undo the reader's
# integer scaling. Palette entries have different semantics from input
# samples, and signed integers are not supported by the reader's direct mode.
mssr_app_tiff_scale <- function(meta) {
  if (!is.null(meta$depth) && !is.na(meta$depth) && meta$depth > 1) {
    mssr_abort("unsupported", "TIFF uploads need a 2D page; volumetric pages are unsupported.")
  }
  if (identical(meta$planar.config, "separate") && meta$samples.per.pixel > 1) {
    mssr_abort("unsupported", paste("Multi-channel planar-separate TIFF images are unsupported;",
                                    "convert to contiguous channels before uploading."))
  }
  fmt <- meta$sample.format
  if (is.null(fmt) || is.na(fmt)) fmt <- "uint"
  if (!fmt %in% c("uint", "float") || identical(meta$color.space, "palette")) {
    mssr_abort("unsupported", "TIFF uploads support unsigned integers or floats, without palettes.")
  }
  bits <- meta$bits.per.sample
  if (length(bits) != 1L || is.na(bits) || !bits %in% c(8, 16, 32) ||
        (fmt == "float" && bits != 32)) {
    mssr_abort("unsupported", paste(
      "TIFF uploads need 8/16/32-bit unsigned or 32-bit float samples;",
      "packed 12-bit samples are not qualified for this reader."
    ))
  }
  if (fmt == "float") return(1)
  if (bits == 32) 2^bits else 2^bits - 1
}

# Returns list(x = numeric matrix, info = one-line description).
mssr_app_read <- function(path, name, channel = 1L, page = 1L) {
  ext <- mssr_app_ext(name)
  if (ext %in% c("csv", "tsv", "txt")) {
    df <- tryCatch(
      if (ext == "csv") {
        utils::read.csv(path, header = FALSE, strip.white = TRUE)
      } else {
        utils::read.table(path, header = FALSE)
      },
      error = function(e) NULL
    )
    if (is.null(df) || !all(vapply(df, is.numeric, logical(1)))) {
      mssr_abort("input", paste("Text files must contain numbers only, without a header row;",
                                "`.csv` is comma-separated, `.tsv`/`.txt` tab- or",
                                "space-separated."))
    }
    x <- unname(as.matrix(df))
    return(list(x = x, info = sprintf("Text table, %d x %d", nrow(x), ncol(x)),
                metadata = list(format = "text", axes = c("row_y", "column_x"),
                                physical_sampling = NULL, sample_units = "user_supplied",
                                reader = "utils::read.table")))
  }
  if (ext == "png") {
    mssr_app_need("png", "PNG files")
    mssr_app_decode(mssr_app_png_size(path))
    page <- check_whole(page, "page", 1L, 1L)
    a <- mssr_app_decode(png::readPNG(path))
    n_pages <- 1L
    kind <- "PNG"
  } else if (ext %in% c("tif", "tiff")) {
    mssr_app_need("tiff", "TIFF files")
    page <- check_whole(page, "page", 1L, mssr_app_tiff_page_limit)
    header <- mssr_app_decode(mssr_app_tiff_preflight(path, page))
    meta <- mssr_app_decode(tiff::readTIFF(path, all = TRUE, payload = FALSE))
    n_pages <- nrow(meta)
    if (n_pages != header$pages) mssr_abort("input", "TIFF directory count changed during reading.")
    page <- check_whole(page, "page", 1L, n_pages)
    m <- meta[page, , drop = FALSE]
    mssr_app_image_size(m$width, m$length, m$samples.per.pixel)
    if (!is.null(m$tile.width) && !is.na(m$tile.width)) {
      mssr_app_image_size(m$tile.width, m$tile.length, m$samples.per.pixel)
    }
    scale <- mssr_app_tiff_scale(m)
    a <- mssr_app_decode(tiff::readTIFF(path, all = page, as.is = FALSE)[[1]])
    if (scale != 1) a <- round(a * scale)
    kind <- "TIFF"
  } else {
    mssr_abort("input", "Unsupported file type; use .csv, .tsv, .txt, .png, .tif or .tiff.")
  }
  n_ch <- if (length(dim(a)) == 3L) dim(a)[3] else 1L
  channel <- check_whole(channel, "channel", 1L, n_ch)
  x <- if (n_ch > 1L) a[, , channel] else a
  x <- matrix(as.numeric(x), nrow(a), ncol(a))
  pages <- if (n_pages > 1L) sprintf(", page %d of %d", page, n_pages) else ""
  info <- sprintf("%s, %d x %d, %d channel(s) (using %d)%s", kind, nrow(x), ncol(x), n_ch,
                  channel, pages)
  list(x = x, info = info, metadata = list(
    format = kind, channel = channel, page = page, pages = n_pages,
    axes = c("row_y", "column_x"),
    orientation = if (kind == "TIFF") "top-left" else "decoded_raster",
    physical_sampling = NULL,
    sample_units = if (kind == "TIFF") "stored_samples" else "decoded_0_to_1",
    reader = if (kind == "TIFF") "tiff::readTIFF" else "png::readPNG",
    reader_version = as.character(utils::packageVersion(if (kind == "TIFF") "tiff" else "png"))
  ))
}

mssr_app_need <- function(pkg, what) {
  if (length(mssr_app_missing(pkg)) > 0L) {
    mssr_abort("dependency", sprintf("Reading %s needs the %s package.", what, pkg))
  }
}

# ---- Computation -------------------------------------------------------------

mssr_app_args <- function(input) {
  list(fwhm = mssr_app_or(input$fwhm, 3), amp = mssr_app_or(input$amp, 2L),
       order = mssr_app_or(input$order, 1L),
       intensity_normalize = isTRUE(mssr_app_or(input$intensity_normalize, TRUE)),
       mesh = isTRUE(mssr_app_or(input$mesh, TRUE)), grid = mssr_app_or(input$grid, "extent"),
       kernel = mssr_app_or(input$kernel, "disk"),
       rounding = mssr_app_or(input$rounding, "half_even"))
}

# Estimated work (output pixels x offsets), or NA when the parameters are
# invalid; mssr() then reports the problem itself.
mssr_app_work <- function(dims, args) {
  fwhm <- args$fwhm
  amp <- args$amp
  ok <- is.numeric(fwhm) && length(fwhm) == 1L && is.finite(fwhm) && fwhm > 0 &&
    is.numeric(amp) && length(amp) == 1L && is.finite(amp) && amp >= 1
  if (!ok) return(NA_real_)
  hs <- mssr_half_size(fwhm, amp, args$rounding)
  n_off <- if (identical(args$kernel, "square")) (2 * hs + 1)^2 - 1 else pi * hs^2
  as.numeric(dims[1]) * dims[2] * amp^2 * n_off
}

mssr_app_compute <- function(x, args) {
  work <- mssr_app_work(dim(x), args)
  if (!is.na(work) && work > mssr_app_work_limit) {
    mssr_abort("resource", sprintf(paste(
      "Estimated work of %.2g operations exceeds the app limit of %.0e;",
      "reduce amp, fwhm or the frame size, or call mssr() in R."
    ), work, mssr_app_work_limit))
  }
  t0 <- proc.time()[["elapsed"]]
  res <- mssr(x, fwhm = args$fwhm, amp = args$amp, order = args$order,
              intensity_normalize = args$intensity_normalize, mesh = args$mesh,
              grid = args$grid, kernel = args$kernel, rounding = args$rounding)
  list(result = res, seconds = proc.time()[["elapsed"]] - t0, args = args)
}

# Definitions include functions and constants, excluding namespace runtime
# environments. The child checks package files before/after loading and execution.
mssr_app_code_signature <- function() {
  ns <- asNamespace("mssrscopR")
  nms <- sort(ls(ns, all.names = TRUE))
  nms <- nms[!vapply(nms, function(n) is.environment(get(n, ns, inherits = FALSE)), logical(1))]
  vapply(nms, function(n) {
    f <- get(n, ns, inherits = FALSE)
    if (is.function(f)) {
      paste(c(deparse(formals(f), width.cutoff = 500L), deparse(body(f), width.cutoff = 500L)),
            collapse = "\n")
    } else {
      paste(deparse(f, width.cutoff = 500L), collapse = "\n")
    }
  }, character(1))
}

mssr_app_code_identity <- function() {
  ns <- asNamespace("mssrscopR")
  root <- normalizePath(getNamespaceInfo(ns, "path"), mustWork = TRUE)
  development <- exists(".__DEVTOOLS__", ns, inherits = FALSE)
  if (development) mssr_app_need("pkgload", "a development-source app in a background process")
  files <- c(file.path(root, c("DESCRIPTION", "NAMESPACE")),
             list.files(file.path(root, "R"), full.names = TRUE))
  files <- sort(files[file.exists(files) & !dir.exists(files)])
  list(root = root, development = development, files = files,
       file_md5 = unname(tools::md5sum(files)), functions = mssr_app_code_signature())
}

mssr_app_mask_args <- function(input) {
  list(fraction = mssr_app_or(input$mask_fraction, 0.02),
       seed = mssr_app_or(input$mask_seed, 1))
}

# This is the only computation path, shared by the child and focused state tests.
mssr_app_job_value <- function(snapshot) {
  warnings <- character()
  tryCatch(withCallingHandlers({
    value <- mssr_app_compute(snapshot$frame$x, snapshot$args)
    value <- c(value, list(x = snapshot$frame$x, info = snapshot$frame$info,
                           source = mssr_app_or(snapshot$frame$source, "upload"),
                           metadata = snapshot$frame$metadata, mask_settings = snapshot$mask,
                           mask_settings_at_compute = snapshot$mask,
                           run_id = snapshot$run_id))
    list(ok = TRUE, value = value, warnings = warnings,
         thread_environment = Sys.getenv(c("OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS",
                                           "MKL_NUM_THREADS", "BLIS_NUM_THREADS")),
         affinity = if (file.exists("/proc/self/status")) {
           grep("^Cpus_allowed_list:", readLines("/proc/self/status"), value = TRUE)
         } else {
           character()
         })
  }, mssrscopR_warning = function(w) {
    warnings <<- c(warnings, conditionMessage(w))
    invokeRestart("muffleWarning")
  }), error = function(e) {
    list(ok = FALSE, message = conditionMessage(e), classes = class(e), warnings = warnings)
  })
}

mssr_app_start_job <- function(frame, args, mask, run_id) {
  mssr_app_need("callr", "background computation and cancellation")
  identity <- mssr_app_code_identity()
  snapshot <- list(frame = frame, args = args, mask = mask, run_id = run_id)
  env <- callr::rcmd_safe_env()
  env[c("OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS", "MKL_NUM_THREADS", "BLIS_NUM_THREADS",
        "VECLIB_MAXIMUM_THREADS", "NUMEXPR_NUM_THREADS")] <- "1"
  process <- callr::r_bg(function(snapshot, identity) {
    unchanged <- function() {
      files <- c(file.path(identity$root, c("DESCRIPTION", "NAMESPACE")),
                 list.files(file.path(identity$root, "R"), full.names = TRUE))
      files <- sort(files[file.exists(files) & !dir.exists(files)])
      identical(files, identity$files) &&
        identical(unname(tools::md5sum(files)), identity$file_md5)
    }
    if (!unchanged()) stop("Package files changed before the background job loaded them.")
    if (identity$development) {
      if (!requireNamespace("pkgload", quietly = TRUE)) stop("Development jobs require pkgload.")
      pkgload::load_all(identity$root, quiet = TRUE)
    } else {
      loadNamespace("mssrscopR", lib.loc = dirname(identity$root))
    }
    ns <- asNamespace("mssrscopR")
    signature <- get("mssr_app_code_signature", ns)()
    if (!unchanged() || !identical(signature, identity$functions)) {
      stop("Loaded package definitions differ from the app session; reload the app and retry.")
    }
    value <- get("mssr_app_job_value", ns)(snapshot)
    if (!unchanged()) stop("Package files changed while the background job was running.")
    value$source_definition_verified <- TRUE
    value$source_kind <- if (identity$development) "development" else "installed"
    value
  }, args = list(snapshot = snapshot, identity = identity), libpath = .libPaths(),
  env = env, user_profile = FALSE, system_profile = FALSE, supervise = TRUE,
  stdout = "|", stderr = "|")
  list(process = process, started = proc.time()[["elapsed"]], run_id = run_id, snapshot = snapshot)
}

mssr_app_validate_job <- function(job, envelope) {
  value <- envelope$value
  snapshot <- job$snapshot
  if (!is.list(value) || !is.list(snapshot) || !isTRUE(envelope$source_definition_verified) ||
        !identical(value$run_id, job$run_id) || !identical(value$x, snapshot$frame$x) ||
        !identical(value$args, snapshot$args) || !identical(value$mask_settings, snapshot$mask) ||
        !identical(value$mask_settings_at_compute, snapshot$mask) ||
        !identical(value$source, mssr_app_or(snapshot$frame$source, "upload")) ||
        !identical(value$info, snapshot$frame$info) ||
        !identical(value$metadata, snapshot$frame$metadata)) {
    mssr_abort("integrity", "Background result does not match its captured input and settings.")
  }
  mssr_validate_result(value$result)
  batch_check_result(value$result, dim(snapshot$frame$x), snapshot$args, NULL)
  check_positive(value$seconds, "seconds", allow_zero = TRUE)
  invisible(TRUE)
}

# Only the retained handle is signalled. No PID searches or machine-wide cleanup.
mssr_app_stop_job <- function(job) {
  p <- job$process
  if (p$is_alive()) p$kill()
  p$wait(timeout = 2000)
  if (p$is_alive()) mssr_abort("resource", "The owned job has not stopped; retry cancellation.")
  p$cleanup()
  invisible(TRUE)
}

# Evaluate `expr`; package errors and warnings become notifications.
mssr_app_try <- function(expr) {
  withCallingHandlers(
    tryCatch(expr, mssrscopR_error = function(e) {
      shiny::showNotification(conditionMessage(e), type = "error", duration = 10)
      NULL
    }),
    mssrscopR_warning = function(w) {
      shiny::showNotification(conditionMessage(w), type = "warning", duration = 10)
      invokeRestart("muffleWarning")
    }
  )
}

# ---- Plots -------------------------------------------------------------------

mssr_app_palette <- function(name, n = 256) {
  switch(name,
         viridis = grDevices::hcl.colors(n, "viridis"),
         inferno = grDevices::hcl.colors(n, "Inferno"),
         grDevices::gray.colors(n, 0, 1))
}

mssr_app_colors <- function(dark) {
  if (isTRUE(dark)) {
    list(fg = "#dbe4f0", accent = "#93C5FD", muted = "#8aa0b8", mask = "#FBBF24")
  } else {
    list(fg = "#1b2733", accent = "#185FA5", muted = "#6b7c8f", mask = "#F59E0B")
  }
}

mssr_app_par <- function(dark, mfrow = c(1, 1)) {
  cl <- mssr_app_colors(dark)
  graphics::par(mfrow = mfrow, mar = c(3, 3, 2, 0.6), mgp = c(1.7, 0.45, 0), tcl = -0.25,
                fg = cl$fg, col.axis = cl$fg, col.lab = cl$fg, col.main = cl$fg,
                cex.axis = 0.85, cex.main = 0.95, font.main = 1)
}

# Image on input-pixel axes with row 1 at the top. No box: with asp = 1 the
# plot region is usually larger than the image.
mssr_app_image <- function(m, rows, cols, input_dim, palette, main) {
  graphics::image(cols, rows, t(m), col = palette, useRaster = TRUE, asp = 1, axes = FALSE,
                  xlim = c(0.5, input_dim[2] + 0.5), ylim = c(input_dim[1] + 0.5, 0.5),
                  xlab = "column (input px)", ylab = "row (input px)", main = main)
  # Ticks only within the frame; asp = 1 can widen the axis range far beyond it.
  ticks <- function(n) {
    at <- pretty(c(1, n))
    at[at >= 1 & at <= n]
  }
  graphics::axis(1, at = ticks(input_dim[2]))
  graphics::axis(2, at = ticks(input_dim[1]), las = 1)
}

mssr_app_figure_caption <- function(res, run_id) {
  p <- res$parameters
  c("Non-quantitative MSSR structure map. Measure the original input.",
    "Panels are independently display-scaled; brightness is not comparable between panels.",
    sprintf("FWHM %s input px; amplification %d; order %d; grid %s.",
            format(p$fwhm, digits = 15, trim = TRUE), p$amp, p$order, res$transform$grid),
    paste("Run ID:", run_id))
}

mssr_app_plot_maps <- function(x, res, palette = "gray", dark = FALSE, guide = NULL,
                               stacked = FALSE, run_id = NULL) {
  op <- mssr_app_par(dark, if (stacked) c(2, 1) else c(1, 2))
  op$oma <- graphics::par("oma")
  on.exit(graphics::par(op))
  caption <- NULL
  if (!is.null(run_id)) {
    # Use the physical device width so the caption also fits portrait renders.
    # Long identifiers have no word boundaries: split them without dropping text.
    caption_cex <- 0.75
    width <- max(1L, floor((graphics::par("din")[1] - 0.4) /
                             graphics::strwidth("M", units = "inches", cex = caption_cex)))
    caption <- unlist(lapply(mssr_app_figure_caption(res, run_id), function(text) {
      unlist(lapply(strwrap(text, width = width), function(line) {
        start <- seq.int(1L, nchar(line), by = width)
        substring(line, start, pmin(start + width - 1L, nchar(line)))
      }), use.names = FALSE)
    }), use.names = FALSE)
    graphics::par(oma = c(length(caption) * 0.85 + 0.5, 0, 0, 0))
  }
  pal <- mssr_app_palette(palette)
  co <- mssr_coords(res)
  p <- res$parameters
  mssr_app_image(x, seq_len(nrow(x)), seq_len(ncol(x)), dim(x), pal, "Input")
  mssr_app_guide(guide, dark)
  main <- sprintf("MSSR (amp %d, order %d)", p$amp, p$order)
  mssr_app_image(res$values, co$row, co$col, dim(x), pal, main)
  mssr_app_guide(guide, dark)
  if (length(caption)) {
    graphics::mtext(caption, side = 1, outer = TRUE,
                    line = (seq_along(caption) - 1L) * 0.85 + 0.25,
                    cex = caption_cex, col = mssr_app_colors(dark)$fg)
  }
}

# Dashed line marking the profile position.
mssr_app_guide <- function(guide, dark) {
  if (is.null(guide)) return(invisible())
  col <- mssr_app_colors(dark)$accent
  if (guide$axis == "row") {
    graphics::abline(h = guide$index, col = col, lty = 2, lwd = 1.5)
  } else {
    graphics::abline(v = guide$index, col = col, lty = 2, lwd = 1.5)
  }
}

# Input and MSSR profiles along one input row or column, each scaled to its
# own maximum. The MSSR line is the output row/column whose center is closest
# to the chosen input pixel center; with even amplification two are equally
# close and their mean is used.
mssr_app_profile <- function(x, res, axis = "row", index = 1L) {
  co <- mssr_coords(res)
  scale1 <- function(v) if (max(v) > 0) v / max(v) else v
  nearest <- function(centers) {
    d <- abs(centers - index)
    which(d <= min(d) + 1e-9)
  }
  if (axis == "row") {
    k <- nearest(co$row)
    list(pos_in = seq_len(ncol(x)), val_in = scale1(x[index, ]), pos_out = co$col,
         val_out = scale1(colMeans(res$values[k, , drop = FALSE])), center = mean(co$row[k]))
  } else {
    k <- nearest(co$col)
    list(pos_in = seq_len(nrow(x)), val_in = scale1(x[, index]), pos_out = co$row,
         val_out = scale1(rowMeans(res$values[, k, drop = FALSE])), center = mean(co$col[k]))
  }
}

mssr_app_plot_profile <- function(x, res, axis = "row", index = 1L, dark = FALSE) {
  op <- mssr_app_par(dark)
  on.exit(graphics::par(op))
  cl <- mssr_app_colors(dark)
  pr <- mssr_app_profile(x, res, axis, index)
  along <- if (axis == "row") "column" else "row"
  graphics::plot(pr$pos_in, pr$val_in, type = "o", pch = 16, cex = 0.6, col = cl$muted,
                 ylim = c(0, 1.05), las = 1, xlab = sprintf("%s (input px)", along),
                 ylab = "value / maximum of the line",
                 main = sprintf("Profile along input %s %d (MSSR %s centered at %.3g)", axis,
                                index, axis, pr$center))
  graphics::lines(pr$pos_out, pr$val_out, col = cl$accent, lwd = 2)
  graphics::legend("topright", c("input", "MSSR"), col = c(cl$muted, cl$accent),
                   lty = 1, lwd = c(1, 2), pch = c(16, NA), bty = "n", text.col = cl$fg)
}

mssr_app_plot_mask <- function(x, mask, dark = FALSE) {
  op <- mssr_app_par(dark)
  on.exit(graphics::par(op))
  cl <- mssr_app_colors(dark)
  rows <- seq_len(nrow(x))
  cols <- seq_len(ncol(x))
  mssr_app_image(x, rows, cols, dim(x), mssr_app_palette("gray"),
                 "Mask on the input grid (highlighted pixels are selected)")
  overlay <- grDevices::adjustcolor(cl$mask, alpha.f = 0.6)
  graphics::image(cols, rows, t(mask * 1), col = c(NA, overlay), useRaster = TRUE, add = TRUE,
                  zlim = c(0, 1))
}

# Mask summary measured on the original data.
mssr_app_mask_table <- function(x, mask) {
  inside <- x[mask]
  outside <- x[!mask]
  mean_or_na <- function(v) if (length(v)) mean(v) else NA_real_
  data.frame(
    quantity = c("selected pixels", "coverage of the region", "tie_fraction",
                 "lowest selected score / maximum (cut_relative)",
                 "input mean inside the mask", "input mean outside the mask"),
    value = c(format(sum(mask)), sprintf("%.4g", attr(mask, "coverage")),
              sprintf("%.4g", attr(mask, "tie_fraction")),
              sprintf("%.3g", attr(mask, "cut_relative")),
              sprintf("%.6g", mean_or_na(inside)), sprintf("%.6g", mean_or_na(outside))),
    stringsAsFactors = FALSE
  )
}

# ---- Run record --------------------------------------------------------------

# Named vectors become JSON objects instead of unnamed arrays.
mssr_app_jsonable <- function(x) {
  if (is.list(x)) return(lapply(x, mssr_app_jsonable))
  if (!is.null(names(x))) return(as.list(x))
  x
}

mssr_app_record <- function(run, source, mask = NULL, current_args = NULL, current_mask = NULL) {
  res <- run$result
  rec <- list(
    created_utc = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    record_schema = "1.1.0", completion_state = "complete",
    source = source, input_dim = res$transform$input_dim, input_metadata = run$metadata,
    controls_stale = isTRUE(run$restored_previous) ||
      (!is.null(current_args) && !identical(run$args, current_args)) ||
      (!is.null(current_mask) && !identical(run$mask_settings, current_mask)),
    run_id = run$run_id, execution = run$execution,
    restored_previous = isTRUE(run$restored_previous),
    mask_settings_at_compute = run$mask_settings_at_compute,
    engine = res$engine, parameters = res$parameters, transform = res$transform,
    diagnostics = res$diagnostics, role = res$role, seconds = round(run$seconds, 3)
  )
  if (!is.null(mask)) {
    rec$mask <- list(fraction = mask$fraction, seed = mask$seed,
                     coverage = attr(mask$mask, "coverage"),
                     tie_fraction = attr(mask$mask, "tie_fraction"),
                     cut_relative = attr(mask$mask, "cut_relative"),
                     n_region = attr(mask$mask, "n_region"),
                     measurement_source = "original_input",
                     input_mean_all = mean(run$x),
                     input_mean_selected = if (any(mask$mask)) mean(run$x[mask$mask]) else NULL,
                     selection_bias_assessed = FALSE)
  }
  jsonlite::toJSON(mssr_app_jsonable(rec), auto_unbox = TRUE, pretty = TRUE, digits = NA,
                   null = "null")
}

mssr_app_write_matrix <- function(m, file) {
  utils::write.table(m, file, sep = ",", row.names = FALSE, col.names = FALSE)
}

# ---- User interface ------------------------------------------------------------

mssr_app_css <- "
:root { --ms-fg:#1b2733; --ms-bg:#f7f9fc; --ms-panel:#ffffff; --ms-line:#dbe3ec;
  --ms-mute:#5a6b7e; --ms-accent:#185FA5; }
[data-bs-theme=\"dark\"] { --ms-fg:#dbe4f0; --ms-bg:#0b1626; --ms-panel:#10213a;
  --ms-line:#22395a; --ms-mute:#8aa0b8; --ms-accent:#93C5FD; }
body { background:var(--ms-bg); color:var(--ms-fg); }
.ms-brand { display:flex; align-items:center; gap:.75rem; padding:.55rem 1rem;
  background:var(--ms-panel); border-bottom:1px solid var(--ms-line); }
.ms-brand img { height:46px; width:auto; }
.ms-brand .ms-title { font-weight:600; letter-spacing:.02em; font-size:1.15rem; margin:0; }
.ms-brand .ms-sub { color:var(--ms-mute); font-size:.9rem; }
.bslib-sidebar-layout > .sidebar { background:var(--ms-panel);
  border-right:1px solid var(--ms-line); }
.ms-section { font-size:.78rem; text-transform:uppercase; letter-spacing:.08em;
  color:var(--ms-mute); margin:.6rem 0 .3rem; font-weight:600; }
.card { border:1px solid var(--ms-line); box-shadow:none; background:var(--ms-panel); }
.btn-primary { background:var(--ms-accent); border-color:var(--ms-accent);
  --bs-btn-hover-color:#ffffff; --bs-btn-hover-bg:#124b84; --bs-btn-hover-border-color:#124b84;
  --bs-btn-active-color:#ffffff; --bs-btn-active-bg:#124b84; --bs-btn-active-border-color:#124b84; }
[data-bs-theme=\"dark\"] .btn-primary { color:#0b1626;
  --bs-btn-hover-color:#0b1626; --bs-btn-hover-bg:#bfdbfe; --bs-btn-hover-border-color:#bfdbfe;
  --bs-btn-active-color:#0b1626; --bs-btn-active-bg:#bfdbfe; --bs-btn-active-border-color:#bfdbfe; }
[data-bs-theme=\"dark\"] .text-success { color:#75b798 !important; }
[data-bs-theme=\"dark\"] .text-danger { color:#f1aeb5 !important; }
.ms-note { color:var(--ms-mute); font-size:.85rem; }
.ms-stale { color:#b45309; font-size:.85rem; margin-top:.4rem; }
[data-bs-theme=\"dark\"] .ms-stale { color:#fbbf24; }
.ms-about { max-width:780px; }
.ms-about h2 { margin-top:1.1rem; font-size:1.15rem; }
:focus-visible, .selectize-input:focus-within, .btn-file:focus-within {
  outline:3px solid #185FA5 !important; outline-offset:3px; }
[data-bs-theme=\"dark\"] :focus-visible,
[data-bs-theme=\"dark\"] .selectize-input:focus-within,
[data-bs-theme=\"dark\"] .btn-file:focus-within { outline-color:#93C5FD !important; }
pre.shiny-text-output { background:transparent; border:1px solid var(--ms-line);
  color:var(--ms-fg); white-space:pre-wrap; overflow-wrap:anywhere; }
"

mssr_app_sidebar <- function(...) {
  args <- list(...)
  if ("resizable" %in% names(formals(bslib::sidebar))) args$resizable <- FALSE
  do.call(bslib::sidebar, args)
}

mssr_app_ui <- function() {
  www <- system.file("app", "www", package = "mssrscopR")
  if (nzchar(www)) shiny::addResourcePath("mssrscopR-www", www)
  bslib::page_sidebar(
    title = NULL,
    window_title = "mssrscopR",
    lang = "en",
    theme = bslib::bs_theme(version = 5, primary = "#185FA5", "border-radius" = "0.3rem"),
    fillable = FALSE,
    shiny::tags$head(
      shiny::tags$style(shiny::HTML(mssr_app_css)),
      shiny::tags$script(src = "mssrscopR-www/accessibility.js")
    ),
    shiny::div(
      class = "ms-brand",
      shiny::tags$img(src = "mssrscopR-www/logo.svg", alt = "mssrscopR hex sticker"),
      shiny::div(shiny::h1(class = "ms-title", "mssrscopR"),
                 shiny::div(class = "ms-sub", "Mean-Shift Super-Resolution explorer")),
      shiny::div(class = "ms-auto ms-3", style = "margin-left:auto;",
                 bslib::input_dark_mode(id = "dark_mode", mode = "light"))
    ),
    sidebar = mssr_app_sidebar(
      width = 330,
      shiny::div(class = "ms-section", "Input"),
      shiny::radioButtons("source", "Input source", inline = TRUE,
                          choices = c("Synthetic example" = "example", "Upload" = "upload")),
      shiny::conditionalPanel(
        "input.source == 'example'",
        shiny::selectInput("example", "Example", choices = mssr_app_examples),
        shiny::div(class = "ms-note", "Synthetic scenes from the vignette, blurred with FWHM 3 px.")
      ),
      shiny::conditionalPanel(
        "input.source == 'upload'",
        shiny::fileInput("file", "Frame (.csv, .tsv, .txt, .png, .tif)",
                         accept = c(".csv", ".tsv", ".txt", ".png", ".tif", ".tiff")),
        bslib::layout_columns(
          shiny::numericInput("channel", "Channel", 1, min = 1, step = 1),
          shiny::numericInput("page", "TIFF page", 1, min = 1, step = 1)
        )
      ),
      shiny::div(class = "ms-section", "Parameters"),
      shiny::numericInput("fwhm", "PSF FWHM (input px)", 3, min = 0.1, step = 0.1),
      shiny::numericInput("amp", "Amplification", min = 1, max = 8, value = 2, step = 1),
      shiny::numericInput("order", "Order", min = 0, max = 5, value = 1, step = 1),
      bslib::accordion(
        open = FALSE,
        bslib::accordion_panel(
          "More options",
          shiny::checkboxInput("intensity_normalize", "Intensity-weighted (authors' default)",
                               TRUE),
          shiny::checkboxInput("mesh", "Mesh compensation (amp > 1)", TRUE),
          shiny::radioButtons("kernel", "Kernel", inline = TRUE,
                              choices = c("disk (R code)" = "disk",
                                          "square (Python code)" = "square")),
          shiny::radioButtons("grid", "Output grid", inline = TRUE,
                              choices = c(extent = "extent", endpoint = "endpoint")),
          shiny::radioButtons("rounding", "Half-size rounding", inline = TRUE,
                              choices = c("half even" = "half_even", "half up" = "half_up"))
        )
      ),
      shiny::actionButton("compute", "Compute", class = "btn-primary w-100 mt-2"),
      shiny::actionButton("cancel", "Cancel computation", class = "w-100 mt-1"),
      shiny::actionButton("restore", "Restore previous completed result", class = "w-100 mt-1"),
      shiny::div(role = "status", `aria-live` = "polite", `aria-atomic` = "true",
                 shiny::textOutput("job_status")),
      shiny::div(role = "status", `aria-live` = "polite", `aria-atomic` = "true",
                 shiny::uiOutput("stale")),
      shiny::div(class = "ms-note",
                 paste("One background job per session.",
                       "Cancelled or incomplete work cannot be downloaded.")),
      shiny::div(class = "ms-section", "Download"),
      shiny::conditionalPanel(
        "output.download_ready === 'true'",
        shiny::downloadButton("dl_values", "Structure map (CSV)", class = "w-100 mb-1 btn-sm"),
        shiny::downloadButton("dl_figure", "Figure (PNG)", class = "w-100 mb-1 btn-sm"),
        shiny::downloadButton("dl_record", "Run record (JSON)", class = "w-100 btn-sm")
      ),
      shiny::conditionalPanel(
        "output.download_ready !== 'true'",
        shiny::tags$button("Structure map (CSV)", type = "button", disabled = NA,
                           class = "btn btn-default w-100 mb-1 btn-sm"),
        shiny::tags$button("Figure (PNG)", type = "button", disabled = NA,
                           class = "btn btn-default w-100 mb-1 btn-sm"),
        shiny::tags$button("Run record (JSON)", type = "button", disabled = NA,
                           class = "btn btn-default w-100 btn-sm"),
        shiny::div(class = "ms-note", "Downloads require a completed computation.")
      )
    ),
    bslib::navset_card_tab(
      id = "tabs",
      bslib::nav_panel(
        "Maps",
        shiny::div(class = "d-flex justify-content-end",
                   shiny::selectInput("palette", "Display palette", width = "160px",
                                      choices = c(Gray = "gray", Viridis = "viridis",
                                                  Inferno = "inferno"))),
        shiny::plotOutput("maps", height = "auto"),
        shiny::div(role = "region", tabindex = "0", `aria-label` = "Computed result summary",
                   shiny::verbatimTextOutput("summary"))
      ),
      bslib::nav_panel(
        "Profile",
        bslib::layout_columns(
          col_widths = c(4, 8),
          shiny::radioButtons("profile_axis", "Along", inline = TRUE,
                              choices = c("input row" = "row", "input column" = "col")),
          shiny::numericInput("profile_index", "Position (input px)", min = 1, max = 31,
                              value = 16, step = 1, width = "100%")
        ),
        shiny::plotOutput("profile", height = "360px"),
        shiny::tags$details(shiny::tags$summary("Profile values"),
                            shiny::tableOutput("profile_table")),
        shiny::div(class = "ms-note",
                   paste("Each line is scaled to its own maximum. The dashed line in the Maps tab",
                         "marks the position. Amplification adds samples, not observations."))
      ),
      bslib::nav_panel(
        "Mask",
        bslib::layout_columns(
          col_widths = c(6, 3, 3),
          shiny::numericInput("mask_fraction", "Fraction of pixels to keep", min = 0.005, max = 1,
                              value = 0.02, step = 0.005, width = "100%"),
          shiny::numericInput("mask_seed", "Tie-break seed", 1, step = 1),
          shiny::div(
            class = "pt-4",
            shiny::conditionalPanel(
              "output.mask_download_ready === 'true'",
              shiny::downloadButton("dl_mask", "Mask (CSV)", class = "btn-sm")
            ),
            shiny::conditionalPanel(
              "output.mask_download_ready !== 'true'",
              shiny::tags$button("Mask (CSV)", type = "button", disabled = NA,
                                 class = "btn btn-default btn-sm"),
              shiny::div(class = "ms-note", "A completed result and a valid mask are required.")
            )
          )
        ),
        bslib::layout_columns(
          col_widths = c(7, 5),
          shiny::plotOutput("mask_plot", height = "380px"),
          shiny::div(
            shiny::tableOutput("mask_table"),
            shiny::div(role = "status", `aria-live` = "polite", shiny::uiOutput("mask_warning")),
            shiny::div(class = "ms-note",
                       paste("The mask selects pixels by their MSSR value; the means are measured",
                             "on the original input. Selecting by MSSR is not known to improve",
                             "any downstream analysis."))
          )
        )
      ),
      bslib::nav_panel(
        "Self-test",
        shiny::p(class = "ms-note",
                 paste("Recomputes the bundled synthetic fixtures and compares them with the",
                       "stored outputs: a regression check of this installation, not a",
                       "validation of the method.")),
        shiny::div(shiny::actionButton("selftest", "Run self-test", class = "btn-primary")),
        shiny::div(role = "status", `aria-live` = "polite", shiny::uiOutput("selftest_status")),
        shiny::tableOutput("selftest_table")
      ),
      bslib::nav_panel("About", mssr_app_about())
    )
  )
}

mssr_app_about <- function() {
  shiny::div(
    class = "ms-about",
    shiny::h2("What the app shows"),
    shiny::p("The single-frame Mean-Shift Super-Resolution (MSSR) structure map of",
             "Torres-Garcia et al. (2022), computed by mssr() with the parameters on the left.",
             "Input and result share the same input-pixel axes."),
    shiny::h2("How to read it"),
    shiny::tags$ul(
      shiny::tags$li("The structure map is not a quantitative intensity. Take measurements on",
                     "the original data, for example with a mask (Mask tab)."),
      shiny::tags$li("In the bundled examples, MSSR deepens the dip between the sources 3 px",
                     "apart; the sources 2.4 px apart remain merged."),
      shiny::tags$li("Dim structures next to bright ones are suppressed; broad filled objects",
                     "can be hollowed (dim-bright and disk examples)."),
      shiny::tags$li("No gain in physical resolution and no benefit for any application is",
                     "implied.")
    ),
    shiny::h2("Uploads"),
    shiny::p("Files are read by the R process that runs this app; the app sends nothing",
             "elsewhere. Multi-channel images are not converted to gray: choose a channel."),
    shiny::h2("Reference"),
    shiny::p("Torres-Garcia E, Pinto-Camara R, Linares A, et al. Extending resolution within a",
             "single imaging frame. Nature Communications 2022;13:7452.",
             shiny::a("doi:10.1038/s41467-022-34693-9",
                      href = "https://doi.org/10.1038/s41467-022-34693-9", target = "_blank")),
    shiny::p(class = "ms-note",
             sprintf("mssrscopR %s, engine mssr_r_rev3.", utils::packageVersion("mssrscopR")))
  )
}

# ---- Server --------------------------------------------------------------------

mssr_app_server <- function(input, output, session) {
  dark <- shiny::reactive(identical(input$dark_mode, "dark"))
  state <- shiny::reactiveValues(status = "idle", job = NULL, completed = NULL,
                                 last_success = NULL, restored = FALSE,
                                 message = "Waiting for an input.", sequence = 0L)

  frame <- shiny::reactive({
    if (identical(input$source, "upload")) {
      if (is.null(input$file)) return(NULL)
      mssr_app_try(mssr_app_read_identified(input$file$datapath[1], input$file$name[1],
                                            mssr_app_or(input$channel, 1),
                                            mssr_app_or(input$page, 1)))
    } else {
      id <- mssr_app_or(input$example, "pair_3")
      label <- names(mssr_app_examples)[match(id, mssr_app_examples)]
      x <- mssr_app_example(id)
      list(x = x, info = sprintf("Synthetic example: %s", label),
           source = sprintf("example:%s", id),
           metadata = list(format = "synthetic", axes = c("row_y", "column_x"),
                           sample_units = "synthetic_relative", physical_sampling = NULL,
                           psf_fwhm_input_pixels = 3,
                           identity = mssr_app_input_identity(x)))
    }
  })

  stop_job <- function(status = "cancelled", message = "Computation cancelled.") {
    job <- shiny::isolate(state$job)
    if (!is.null(job)) mssr_app_stop_job(job)
    state$job <- NULL
    state$completed <- NULL
    state$status <- status
    state$message <- message
    state$restored <- FALSE
    invisible(TRUE)
  }

  poll_job <- function() {
    job <- shiny::isolate(state$job)
    if (is.null(job)) return(invisible())
    if (job$process$is_alive()) {
      if (proc.time()[["elapsed"]] - job$started > mssr_app_job_timeout) {
        stop_job("failed", "Computation exceeded five minutes and was stopped.")
      }
      return(invisible())
    }
    value <- tryCatch(job$process$get_result(), error = function(e) {
      list(ok = FALSE, message = conditionMessage(e))
    })
    job$process$cleanup()
    state$job <- NULL
    if (!is.list(value)) value <- list(ok = FALSE, message = "Invalid background result envelope.")
    if (isTRUE(value$ok)) {
      valid <- tryCatch({
        mssr_app_validate_job(job, value)
        TRUE
      }, error = function(e) FALSE)
      if (!valid) value <- list(ok = FALSE, message = "Background result validation failed.")
    }
    if (!isTRUE(value$ok)) {
      state$status <- "failed"
      state$completed <- NULL
      state$message <- paste("Computation failed:", value$message)
      shiny::showNotification(state$message, type = "error", duration = 10)
      return(invisible())
    }
    completed <- value$value
    completed$restored_previous <- FALSE
    completed$execution <- list(
      background = TRUE, warning_messages = value$warnings,
      thread_environment = value$thread_environment, affinity = value$affinity,
      source_definition_verified = isTRUE(value$source_definition_verified),
      source_kind = value$source_kind
    )
    state$completed <- completed
    state$last_success <- completed
    state$status <- "complete"
    state$restored <- FALSE
    state$message <- "Computation complete. Downloads use this completed input and settings."
    for (warning in value$warnings) {
      shiny::showNotification(warning, type = "warning", duration = 10)
    }
    invisible()
  }

  shiny::observeEvent(list(input$compute, frame()), {
    # Replacing the input supersedes its owned job, never a different session's.
    if (!is.null(state$job)) stop_job()
    state$completed <- NULL
    state$restored <- FALSE
    state$status <- "failed"
    fr <- frame()
    if (is.null(fr)) {
      state$message <- "No valid input is available. Choose a valid frame and retry."
      return()
    }
    state$sequence <- state$sequence + 1L
    run_id <- sprintf("%s-%d", format(Sys.time(), "%Y%m%dT%H%M%OS6", tz = "UTC"), state$sequence)
    job <- tryCatch(mssr_app_start_job(fr, mssr_app_args(input), mssr_app_mask_args(input), run_id),
                    error = function(e) {
                      state$message <- paste("Computation could not start:", conditionMessage(e))
                      shiny::showNotification(state$message, type = "error", duration = 10)
                      NULL
                    })
    if (!is.null(job)) {
      state$job <- job
      state$status <- "running"
      state$message <- "Computing in a background process. Cancel stops this job only."
    }
  }, ignoreNULL = FALSE, priority = 10)

  shiny::observe({
    if (!is.null(state$job)) {
      shiny::invalidateLater(100, session)
      poll_job()
    }
  })
  shiny::observeEvent(input$cancel, {
    if (!is.null(state$job)) stop_job()
  }, ignoreInit = TRUE)
  shiny::observeEvent(input$restore, {
    if (is.null(state$job) && !is.null(state$last_success)) {
      restored <- state$last_success
      restored$restored_previous <- TRUE
      state$completed <- restored
      state$status <- "complete"
      state$restored <- TRUE
      state$message <- paste("Restored the previous completed input, settings and mask.",
                             "Controls may differ.")
    }
  }, ignoreInit = TRUE)
  shiny::observeEvent(mssr_app_mask_args(input), {
    # Mask controls can update a current completed result, but never a restored
    # input or the immutable launch snapshot of a running job.
    if (state$status == "complete" && !state$restored) {
      completed <- state$completed
      completed$mask_settings <- mssr_app_mask_args(input)
      state$completed <- completed
      state$last_success <- completed
    }
  }, ignoreInit = TRUE)
  session$onSessionEnded(function() {
    job <- shiny::isolate(state$job)
    if (!is.null(job)) try(mssr_app_stop_job(job), silent = TRUE)
  })
  output$job_status <- shiny::renderText(state$message)

  run <- shiny::reactive({
    shiny::req(identical(state$status, "complete"), state$completed)
    state$completed
  })

  output$download_ready <- shiny::renderText({
    if (identical(state$status, "complete") && !is.null(state$completed)) "true" else "false"
  })
  shiny::outputOptions(output, "download_ready", suspendWhenHidden = FALSE)

  shiny::observeEvent(frame(), {
    fr <- frame()
    shiny::req(fr)
    axis <- mssr_app_or(input$profile_axis, "row")
    n <- if (axis == "row") nrow(fr$x) else ncol(fr$x)
    shiny::updateNumericInput(session, "profile_index", max = n, value = ceiling(n / 2))
  })
  shiny::observeEvent(input$profile_axis, {
    fr <- frame()
    shiny::req(fr)
    n <- if (input$profile_axis == "row") nrow(fr$x) else ncol(fr$x)
    shiny::updateNumericInput(session, "profile_index", max = n, value = ceiling(n / 2))
  }, ignoreInit = TRUE)

  guide <- shiny::reactive({
    r <- run()
    axis <- mssr_app_or(input$profile_axis, "row")
    n <- if (axis == "row") nrow(r$x) else ncol(r$x)
    index <- mssr_app_or(input$profile_index, 1L)
    valid <- is.numeric(index) && length(index) == 1L && is.finite(index) &&
      index == floor(index)
    shiny::validate(shiny::need(valid, "Profile position must be a finite whole number."))
    list(axis = axis, index = min(max(1L, index), n))
  })

  output$stale <- shiny::renderUI({
    r <- run()
    if (state$restored) {
      shiny::div(class = "ms-stale", paste(
        "Restored previous completed input, settings and mask.",
        "Press Compute to process the current input and controls."
      ))
    } else if (!identical(r$args, mssr_app_args(input)) ||
                 !identical(r$mask_settings, mssr_app_mask_args(input))) {
      shiny::div(class = "ms-stale", paste(
        "Parameters changed: press Compute to update.",
        "Downloads contain the last computed result and settings."
      ))
    }
  })

  # Below 700 px the two maps are stacked instead of side by side.
  narrow <- shiny::reactive(mssr_app_or(session$clientData$output_maps_width, 900) < 700)

  output$maps <- shiny::renderPlot({
    r <- run()
    mssr_app_plot_maps(r$x, r$result, mssr_app_or(input$palette, "gray"), dark(), guide(),
                       stacked = narrow())
  }, height = function() if (narrow()) 760 else 440, bg = "transparent", alt = function() {
    r <- run()
    sprintf(paste("Original %d by %d frame and %s map on shared input-pixel coordinates.",
                  "Computed amplification %d and order %d. Numeric summary follows the plot."),
            nrow(r$x), ncol(r$x), r$result$role, r$result$parameters$amp, r$result$parameters$order)
  })

  output$summary <- shiny::renderText({
    r <- run()
    paste(c(r$info, utils::capture.output(print(r$result)),
            sprintf("Computed in %.2f s.", r$seconds)), collapse = "\n")
  })

  output$profile <- shiny::renderPlot({
    r <- run()
    g <- guide()
    mssr_app_plot_profile(r$x, r$result, g$axis, g$index, dark())
  }, bg = "transparent", alt = function() {
    g <- guide()
    sprintf(paste("Input and MSSR profiles along input %s %d, each divided by its own maximum.",
                  "Exact displayed values are in the Profile values table."), g$axis, g$index)
  })

  output$profile_table <- shiny::renderTable({
    r <- run()
    g <- guide()
    pr <- mssr_app_profile(r$x, r$result, g$axis, g$index)
    data.frame(series = c(rep("input", length(pr$pos_in)), rep("MSSR", length(pr$pos_out))),
               position_input_pixels = c(pr$pos_in, pr$pos_out),
               value_divided_by_line_maximum = c(pr$val_in, pr$val_out))
  }, digits = 6)

  mask <- shiny::reactive({
    r <- run()
    tr <- r$result$transform
    shiny::validate(shiny::need(
      tr$amp == 1L || tr$grid == "extent",
      "Masks need the extent grid when amp > 1 (More options > Output grid)."
    ))
    fraction <- r$mask_settings$fraction
    seed <- r$mask_settings$seed
    m <- mssr_app_try(mssr_mask(r$result, fraction = fraction, seed = seed))
    shiny::req(m)
    list(mask = m, fraction = fraction, seed = seed)
  })

  output$mask_download_ready <- shiny::renderText({
    if (!identical(state$status, "complete") || is.null(state$completed)) return("false")
    ready <- tryCatch(!is.null(mask()), error = function(e) FALSE)
    if (ready) "true" else "false"
  })
  shiny::outputOptions(output, "mask_download_ready", suspendWhenHidden = FALSE)

  output$mask_plot <- shiny::renderPlot({
    mssr_app_plot_mask(run()$x, mask()$mask, dark())
  }, bg = "transparent", alt = function() {
    sprintf(paste("MSSR quota mask on original data: %d of %d pixels selected.",
                  "Coverage, tie diagnostics and original-input means are in the adjacent table."),
            sum(mask()$mask), length(mask()$mask))
  })

  output$mask_table <- shiny::renderTable(mssr_app_mask_table(run()$x, mask()$mask),
                                          colnames = FALSE)

  output$mask_warning <- shiny::renderUI({
    m <- mask()$mask
    if (attr(m, "cut_relative") < 1e-6 || attr(m, "tie_fraction") > 0) {
      shiny::div(class = "ms-stale mb-2", paste(
        "The mask reaches pixels where MSSR found no structure (scores below 1e-6 of the",
        "maximum or decided by tie-breaking). Lower the fraction to stay on the structure."
      ))
    }
  })

  selftest <- shiny::bindEvent(shiny::reactive(mssr_selftest()), input$selftest)

  output$selftest_status <- shiny::renderUI({
    st <- selftest()
    ok <- attr(st, "all_passed")
    shiny::p(class = if (ok) "text-success mt-2" else "text-danger mt-2",
             sprintf("%d of %d fixtures passed.", sum(st$passed), nrow(st)))
  })

  output$selftest_table <- shiny::renderTable({
    st <- selftest()
    st$max_abs_error <- sprintf("%.2e", st$max_abs_error)
    st
  })

  output$dl_values <- shiny::downloadHandler(
    filename = function() "mssr_structure_map.csv",
    content = function(file) mssr_app_write_matrix(run()$result$values, file)
  )

  output$dl_mask <- shiny::downloadHandler(
    filename = function() "mssr_mask.csv",
    content = function(file) mssr_app_write_matrix(mask()$mask * 1L, file)
  )

  output$dl_figure <- shiny::downloadHandler(
    filename = function() "mssr_maps.png",
    content = function(file) {
      r <- run()
      grDevices::png(file, width = 2400, height = 1150, res = 200)
      on.exit(grDevices::dev.off())
      mssr_app_plot_maps(r$x, r$result, mssr_app_or(input$palette, "gray"), run_id = r$run_id)
    }
  )

  output$dl_record <- shiny::downloadHandler(
    filename = function() "mssr_run_record.json",
    content = function(file) {
      r <- run()
      m <- tryCatch(mask(), error = function(e) NULL)
      record <- mssr_app_record(r, r$source, m, mssr_app_args(input), mssr_app_mask_args(input))
      writeLines(record, file)
    }
  )
}
