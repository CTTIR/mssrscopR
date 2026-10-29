# Result schema is independent of the engine definition and package version.
mssr_result_contract <- function() {
  list(
    schema_version = "1.0.0",
    input = list(
      axes = c("y", "x"), sampling = NULL, sampling_unit = NULL,
      signal_role = "unspecified", source_identity = NULL
    ),
    evidence = list(status = "numerical_tool_only", quantitative = FALSE)
  )
}

result_fields <- function() {
  c(
    "values", "role", "transform", "parameters", "engine", "diagnostics",
    "schema_version", "input", "evidence"
  )
}

result_scalar_text <- function(x) {
  is.character(x) && !is.object(x) && length(x) == 1L && !is.na(x) &&
    nchar(x, type = "bytes") > 0L && nchar(x, type = "bytes") <= 1000L
}

result_plain_list <- function(x) {
  is.list(x) && !is.object(x) && !is.null(names(x)) &&
    !anyNA(names(x)) && all(nzchar(names(x))) && !anyDuplicated(names(x))
}

#' Validate a complete result record
#'
#' Checks values, geometry, settings, engine identity and diagnostic consistency.
#' This establishes the stored contract, not image authenticity, numerical
#' recomputation, scientific validation or a calibrated confidence estimate.
#' Coordinate and mask functions retain their narrower matrix/grid validation.
#'
#' @param result A result returned by [mssr()].
#' @return The validated result invisibly, unchanged.
#' @details Results without a schema field are treated as legacy records; they
#' must still have the original six documented fields. Their engine identity is
#' retained. Schema 1.0.0 adds explicit unknown input calibration and a separate
#' evidence status. Unknown schema versions and unexpected fields are refused.
#' @examples
#' r <- mssr(matrix(1:20, 4, 5), fwhm = 2)
#' mssr_validate_result(r)
#' @export
mssr_validate_result <- function(result) {
  call <- sys.call()
  check_result(result, call)
  fail <- function(message) mssr_abort("result", message, call)
  if (typeof(result$values) != "double" ||
        !identical(attributes(result$values), list(dim = dim(result$values)))) {
    fail("Result values must be a plain double matrix without additional metadata.")
  }
  if (!identical(class(result), "mssr_result") ||
        any(!names(attributes(result)) %in% c("names", "class"))) {
    fail("Unsupported result class or attributes.")
  }
  if (!setequal(names(result$transform), c("amp", "grid", "input_dim", "output_dim",
                                           "first_center", "spacing", "field_of_view"))) {
    fail("Unexpected or missing transform fields.")
  }
  fields <- names(result)
  legacy <- !"schema_version" %in% fields
  required <- if (legacy) result_fields()[1:6] else result_fields()
  if (!setequal(fields, required)) fail("Unexpected or missing result fields.")
  for (name in c("parameters", "engine", "diagnostics")) {
    if (!result_plain_list(result[[name]])) fail(paste("Invalid result", name, "record."))
  }
  p <- result$parameters
  if (!setequal(names(p), c(
    "fwhm", "amp", "order", "intensity_normalize", "mesh",
    "kernel", "rounding", "half_size"
  ))) {
    fail("Unexpected or missing parameter fields.")
  }
  fwhm <- check_positive(p$fwhm, "fwhm", call)
  amp <- check_whole(p$amp, "amp", 1L, 64L, call)
  order <- check_whole(p$order, "order", 0L, 10L, call)
  weighted <- check_flag(p$intensity_normalize, "intensity_normalize", call)
  mesh <- check_flag(p$mesh, "mesh", call)
  kernel <- check_choice(p$kernel, c("disk", "square"), "kernel", call)
  rounding <- check_choice(p$rounding, c("half_even", "half_up"), "rounding", call)
  hs <- check_whole(p$half_size, "half_size", 1L, 1000L, call)
  if (length(p$kernel) != 1L || length(p$rounding) != 1L ||
        amp != result$transform$amp || (amp == 1L && mesh) ||
        hs != mssr_half_size(fwhm, amp, rounding)) {
    fail("Inconsistent resolved parameters.")
  }
  role <- if (weighted) "intensity_weighted_structure" else "structure"
  if (!identical(result$role, role)) fail("Result role disagrees with its weighting setting.")
  e <- result$engine
  if (!setequal(names(e), c("id", "package_version", "method")) ||
        !all(vapply(e, result_scalar_text, logical(1)))) {
    fail("Invalid engine identity.")
  }
  if (!e$id %in% c("mssr_r_rev1", "mssr_r_rev2", "mssr_r_rev3")) {
    fail("Unsupported engine identity; no engine migration is inferred.")
  }
  d <- result$diagnostics
  base_diagnostics <- c(
    "degenerate", "degenerate_reason", "order_steps_skipped",
    "zero_fraction", "negative_fraction", "n_offsets", "quantitative"
  )
  qualified_diagnostics <- c(base_diagnostics, "qualification_scope", "high_order_unqualified")
  has_qualification <- setequal(names(d), qualified_diagnostics)
  if (!has_qualification && !(legacy && setequal(names(d), base_diagnostics))) {
    fail("Unexpected or missing diagnostic fields.")
  }
  if (has_qualification &&
        (!identical(d$qualification_scope, "bounded_synthetic_domain") ||
           !identical(d$high_order_unqualified, order > 3L))) {
    fail("Inconsistent numerical qualification diagnostic.")
  }
  check_flag(d$degenerate, "degenerate", call)
  check_flag(d$quantitative, "quantitative", call)
  skipped <- check_whole(d$order_steps_skipped, "order_steps_skipped", 0L, order, call)
  if (d$quantitative || (d$degenerate && (any(result$values != 0) || skipped != 0L))) {
    fail("Inconsistent degenerate or quantitative diagnostic.")
  }
  if (d$degenerate) {
    if (!result_scalar_text(d$degenerate_reason)) fail("A degenerate result needs a reason.")
  } else if (!identical(d$degenerate_reason, NA_character_)) {
    fail("Non-degenerate result must have an unknown degenerate reason.")
  }
  for (name in c("zero_fraction", "negative_fraction")) {
    value <- d[[name]]
    expected <- if (name == "zero_fraction") mean(result$values == 0) else mean(result$values < 0)
    if (!plain_real(value) || length(value) != 1L || !is.finite(value) || value != expected) {
      fail(paste("Inconsistent", name, "diagnostic."))
    }
  }
  offsets <- check_whole(d$n_offsets, "n_offsets", 0L, .Machine$integer.max, call)
  expected_offsets <- if (kernel == "square") {
    (2 * hs + 1)^2 - 1
  } else {
    sum(2 * floor(sqrt(pmax(0, hs^2 - (-hs:hs)^2))) + 1) - 1
  }
  if (offsets != expected_offsets) {
    fail("Neighborhood count disagrees with resolved parameters.")
  }
  if (!legacy) {
    if (!identical(result$schema_version, "1.0.0")) fail("Unsupported result schema version.")
    if (!identical(result$input, mssr_result_contract()$input) ||
          !identical(result$evidence, mssr_result_contract()$evidence)) {
      fail("Unsupported input metadata or evidence contract.")
    }
  }
  invisible(result)
}

#' Inspect a structure-map result
#'
#' @param object,x An `mssr_result`.
#' @param ... Further arguments. For plotting, passed to [graphics::image()].
#' @return `summary()` returns a named list of class `summary.mssr_result` with
#'   role, dimensions, grid, range, diagnostics, parameters and version
#'   identities; it prints as a short report. `plot()` draws the stored
#'   map in input-pixel coordinates and invisibly returns the result. It does
#'   not transform the stored values or infer physical sampling.
#' @examples
#' r <- mssr(matrix(1:20, 4, 5), fwhm = 2)
#' summary(r)
#' plot(r)
#' @name inspect_mssr_result
NULL

#' @rdname inspect_mssr_result
#' @export
summary.mssr_result <- function(object, ...) {
  mssr_validate_result(object)
  structure(list(
    role = object$role, input_dim = object$transform$input_dim,
    output_dim = dim(object$values), value_range = range(object$values),
    parameters = object$parameters, diagnostics = object$diagnostics,
    engine = object$engine,
    schema_version = if (is.null(object$schema_version)) {
      "legacy_unversioned"
    } else {
      object$schema_version
    },
    evidence = if (is.null(object$evidence)) {
      list(status = "unspecified_legacy")
    } else {
      object$evidence
    },
    grid = object$transform$grid
  ), class = "summary.mssr_result")
}

#' @rdname inspect_mssr_result
#' @export
print.summary.mssr_result <- function(x, ...) {
  p <- x$parameters
  d <- x$diagnostics
  cat("MSSR result summary: ", x$role, "\n", sep = "")
  cat(sprintf("  Grid:        input %d x %d -> output %d x %d (amp %d, %s grid)\n",
              x$input_dim[1], x$input_dim[2], x$output_dim[1], x$output_dim[2], p$amp, x$grid))
  cat(sprintf("  Parameters:  fwhm %g px, order %d, kernel %s (half-size %d), rounding %s\n",
              p$fwhm, p$order, p$kernel, as.integer(p$half_size), p$rounding))
  cat(sprintf("               intensity weighting %s, mesh %s\n",
              p$intensity_normalize, p$mesh))
  cat(sprintf("  Values:      range %s to %s; zero fraction %.3f; negative fraction %.3f\n",
              format(x$value_range[1], digits = 4), format(x$value_range[2], digits = 4),
              d$zero_fraction, d$negative_fraction))
  status <- if (d$degenerate) paste0("degenerate (", d$degenerate_reason, ")") else "defined"
  cat(sprintf("  Diagnostics: %s; %d undefined order step(s) skipped; %d offsets\n",
              status, as.integer(d$order_steps_skipped), as.integer(d$n_offsets)))
  if (isTRUE(d$high_order_unqualified)) {
    cat("               order above 3: outside the qualified numerical domain\n")
  }
  cat(sprintf("  Engine:      %s, mssrscopR %s; result schema %s; evidence %s\n",
              x$engine$id, x$engine$package_version, x$schema_version, x$evidence$status))
  cat("  Not a quantitative intensity: measure on the original data.\n")
  invisible(x)
}

#' @rdname inspect_mssr_result
#' @export
plot.mssr_result <- function(x, ...) {
  mssr_validate_result(x)
  coords <- mssr_coords(x)
  # image() expects x as its first matrix dimension; transpose keeps rows = y.
  args <- list(
    x = coords$col, y = coords$row, z = t(x$values),
    xlab = "Column (input pixels)", ylab = "Row (input pixels)",
    main = x$role, ylim = rev(range(coords$row)),
    col = grDevices::hcl.colors(64L, "Viridis"), useRaster = TRUE
  )
  supplied <- list(...)
  if (length(supplied) && (is.null(names(supplied)) || any(!nzchar(names(supplied))))) {
    mssr_abort("parameter", "Plot arguments in `...` must be named.", sys.call())
  }
  for (name in names(supplied)) args[[name]] <- supplied[[name]]
  do.call(graphics::image, args)
  invisible(x)
}

result_io_dependencies <- function(call) {
  for (package in c("jsonlite", "digest")) {
    if (!requireNamespace(package, quietly = TRUE)) {
      message <- sprintf("Result exchange needs optional package '%s'.", package)
      mssr_abort("dependency", message, call)
    }
  }
}

# Encode metadata numbers as hexadecimal strings to preserve every binary digit.
result_encode_node <- function(x) {
  if (identical(x, NA_character_)) {
    return(list(type = "missing_character", names = NULL, data = NULL))
  }
  type <- if (is.null(x)) "null" else typeof(x)
  if (!type %in% c("null", "list", "double", "integer", "logical", "character") ||
        is.object(x) || !is.null(dim(x)) || (type != "list" && anyNA(x)) ||
        any(!names(attributes(x)) %in% "names")) {
    mssr_abort("result", "Unsupported metadata value.")
  }
  data <- switch(type,
    null = NULL,
    list = lapply(x, result_encode_node),
    double = as.list(sprintf("%a", x)),
    integer = as.list(as.character(x)),
    as.list(x)
  )
  if (type == "list") names(data) <- NULL
  list(type = type, names = if (is.null(names(x))) NULL else as.list(names(x)), data = data)
}

result_decode_node <- function(node, depth = 0L) {
  fail <- function() mssr_abort("result", "Malformed typed metadata.")
  if (depth > 12L || !result_plain_list(node) ||
        !setequal(names(node), c("type", "names", "data")) ||
        !result_scalar_text(node$type)) {
    fail()
  }
  type <- node$type
  if (type %in% c("null", "missing_character")) {
    if (!is.null(node$names) || !is.null(node$data)) fail()
    return(if (type == "null") NULL else NA_character_)
  }
  if (!type %in% c("list", "double", "integer", "logical", "character") ||
        !is.list(node$data) || !is.null(names(node$data))) {
    fail()
  }
  data <- node$data
  if (type == "list") {
    x <- lapply(data, result_decode_node, depth = depth + 1L)
  } else {
    storage <- if (type == "logical") "logical" else "character"
    if (!all(vapply(
      data, function(z) typeof(z) == storage && length(z) == 1L && !is.na(z),
      logical(1)
    ))) {
      fail()
    }
    x <- unlist(data, use.names = FALSE)
    if (!length(data)) {
      x <- switch(storage,
        logical = logical(),
        character = character()
      )
    }
    if (type == "double") {
      if (!all(grepl("^-?0x[0-9a-f]+(\\.[0-9a-f]*)?p[+-][0-9]+$", x))) fail()
      x <- suppressWarnings(as.numeric(x))
      if (any(!is.finite(x))) fail()
    } else if (type == "integer") {
      if (!all(grepl("^-?[0-9]+$", x))) fail()
      x <- suppressWarnings(as.integer(x))
      if (anyNA(x)) fail()
    }
  }
  if (!is.null(node$names)) {
    n <- node$names
    if (!is.list(n) || length(n) != length(x) || !is.null(names(n)) ||
          !all(vapply(n, result_scalar_text, logical(1)))) {
      fail()
    }
    names(x) <- unlist(n, use.names = FALSE)
    if (anyDuplicated(names(x))) fail()
  }
  x
}

result_check_json_depth <- function(bytes) {
  quoted <- FALSE
  escaped <- FALSE
  depth <- 0L
  for (b in as.integer(bytes)) {
    if (quoted) {
      if (escaped) {
        escaped <- FALSE
      } else if (b == 92L) {
        escaped <- TRUE
      } else if (b == 34L) {
        quoted <- FALSE
      }
    } else if (b == 34L) {
      quoted <- TRUE
    } else if (b %in% c(91L, 123L)) {
      depth <- depth + 1L
      if (depth > 40L) mssr_abort("result", "Metadata nesting exceeds the supported limit.")
    } else if (b %in% c(93L, 125L)) {
      depth <- depth - 1L
    }
  }
}

result_path <- function(path, writing, call) {
  if (!result_scalar_text(path)) mssr_abort("parameter", "`path` must be one file path.", call)
  link <- Sys.readlink(path)
  if (!is.na(link) && nzchar(link)) {
    mssr_abort("io", "Result paths must not be symbolic links.", call)
  }
  parent <- dirname(path)
  if (!dir.exists(parent)) mssr_abort("io", "The result directory must already exist.", call)
  path <- file.path(normalizePath(parent, winslash = "/", mustWork = TRUE), basename(path))
  if (dir.exists(path) || (!writing && !file.exists(path)) ||
        (file.exists(path) && !utils::file_test("-f", path))) {
    mssr_abort("io", "The result path must identify a regular file.", call)
  }
  path
}

#' Write and read an exact, bounded result record
#'
#' Stores only the documented result contract, with exact binary double values,
#' typed JSON metadata and SHA-256 corruption detection. No R expressions,
#' serialized R objects, source image, source path or acquisition identity are
#' stored. A matching checksum is not proof of origin or scientific validity.
#'
#' @param result A validated result from [mssr()].
#' @param path Explicit path to a single result file; its directory must exist.
#' @param overwrite Replace an existing file, if the filesystem supports atomic
#'   replacement. Defaults to `FALSE`.
#' @param max_bytes Maximum total record size in bytes, below 2^31 - 1.
#' @param max_output_pixels Maximum decoded matrix size when reading.
#' @return The writer invisibly returns the normalized file path. The reader
#'   returns the stored result without changing its schema or engine identity.
#' @details Optional packages `jsonlite` and `digest` are required only for these
#' functions. The writer stages and reads back the complete record before
#' installing it. With `overwrite = FALSE`, installation uses an exclusive hard
#' link; filesystems without hard-link support fail without writing a completed
#' destination. With `overwrite = TRUE`, atomic rename must succeed; an existing
#' file is never deleted as a fallback. Symbolic-link file paths are refused.
#'
#' The reader checks file size, a fixed 1 MiB metadata ceiling, metadata nesting,
#' schema, dimensions, exact payload length and SHA-256 before returning a result.
#' It reads at most `max_bytes` plus one byte before decoding. The record and
#' decoded matrix coexist in memory, so the byte ceiling is not a process memory
#' cap. No compression or external references are accepted.
#' @examples
#' if (requireNamespace("jsonlite", quietly = TRUE) &&
#'   requireNamespace("digest", quietly = TRUE)) {
#'   r <- mssr(matrix(1:20, 4, 5), fwhm = 2)
#'   path <- tempfile(fileext = ".mssr")
#'   mssr_write_result(r, path)
#'   identical(mssr_read_result(path), r)
#'   unlink(path)
#' }
#' @name mssr_result_io
NULL

#' @rdname mssr_result_io
#' @export
mssr_write_result <- function(result, path, overwrite = FALSE, max_bytes = 64 * 1024^2) {
  call <- sys.call()
  result_io_dependencies(call)
  mssr_validate_result(result)
  overwrite <- check_flag(overwrite, "overwrite", call)
  max_bytes <- check_positive(max_bytes, "max_bytes", call)
  if (max_bytes >= .Machine$integer.max) {
    mssr_abort("resource", "Byte limit must be below 2^31 - 1.", call)
  }
  path <- result_path(path, TRUE, call)
  if (file.exists(path) && !overwrite) mssr_abort("io", "Destination already exists.", call)
  metadata <- unclass(result)
  metadata$values <- NULL
  encoded <- result_encode_node(list(field_order = names(result), record = metadata))
  json <- jsonlite::toJSON(encoded, auto_unbox = TRUE, null = "null", digits = NA)
  header <- charToRaw(enc2utf8(as.character(json)))
  n_bytes <- 12 + length(header) + 8 * length(result$values) + 64
  if (length(header) > 1024^2 || n_bytes > max_bytes) {
    mssr_abort("resource", "Result record exceeds its byte or metadata budget.", call)
  }
  stage <- tempfile(pattern = ".mssr-result-", tmpdir = dirname(path))
  on.exit(unlink(stage), add = TRUE)
  con <- file(stage, "wb")
  tryCatch(
    {
      writeBin(charToRaw("MSSRRES1"), con)
      writeBin(as.integer(length(header)), con, size = 4L, endian = "little")
      writeBin(header, con)
      writeBin(as.double(result$values), con, size = 8L, endian = "little")
    },
    finally = close(con)
  )
  hash <- digest::digest(file = stage, algo = "sha256", serialize = FALSE)
  con <- file(stage, "ab")
  tryCatch(writeBin(charToRaw(hash), con), finally = close(con))
  checked <- mssr_read_result(stage,
    max_bytes = max_bytes,
    max_output_pixels = length(result$values)
  )
  if (!identical(checked, result)) mssr_abort("io", "Staged result failed exact readback.", call)
  installed <- suppressWarnings(if (overwrite) file.rename(stage, path) else file.link(stage, path))
  if (!installed) {
    mssr_abort("io", "Atomic result installation failed; destination preserved.", call)
  }
  invisible(path)
}

#' @rdname mssr_result_io
#' @export
mssr_read_result <- function(path, max_bytes = 64 * 1024^2, max_output_pixels = 5e7) {
  call <- sys.call()
  result_io_dependencies(call)
  max_bytes <- check_positive(max_bytes, "max_bytes", call)
  max_output_pixels <- check_positive(max_output_pixels, "max_output_pixels", call)
  if (max_bytes >= .Machine$integer.max) {
    mssr_abort("resource", "Byte limit must be below 2^31 - 1.", call)
  }
  path <- result_path(path, FALSE, call)
  size <- file.info(path)$size
  if (is.na(size) || size < 76 || size > max_bytes) {
    mssr_abort("resource", "Result file is too small or exceeds its byte budget.", call)
  }
  con <- file(path, "rb")
  bytes <- tryCatch(readBin(con, "raw", n = min(size + 1, max_bytes + 1)), finally = close(con))
  if (length(bytes) != size) {
    mssr_abort("io", "Result file changed or was truncated during reading.", call)
  }
  payload <- bytes[seq_len(size - 64L)]
  trailer <- bytes[seq.int(size - 63L, size)]
  hash <- charToRaw(digest::digest(payload, algo = "sha256", serialize = FALSE))
  if (!identical(hash, trailer)) {
    mssr_abort("result", "Result checksum mismatch.", call)
  }
  con <- rawConnection(payload, "rb")
  on.exit(close(con), add = TRUE)
  if (!identical(readBin(con, "raw", 8L), charToRaw("MSSRRES1"))) {
    mssr_abort("result", "Unsupported result container version.", call)
  }
  n_meta <- readBin(con, "integer", 1L, size = 4L, endian = "little")
  if (length(n_meta) != 1L || is.na(n_meta) || n_meta < 1 || n_meta > 1024^2 ||
        12 + n_meta > length(payload)) {
    mssr_abort("result", "Invalid metadata length.", call)
  }
  meta <- readBin(con, "raw", n_meta)
  result_check_json_depth(meta)
  decoded <- tryCatch(
    {
      text <- rawToChar(meta)
      if (!jsonlite::validate(text)) mssr_abort("result", "Invalid result metadata.", call)
      result_decode_node(jsonlite::fromJSON(text, simplifyVector = FALSE))
    },
    error = function(e) mssr_abort("result", "Invalid result metadata.", call)
  )
  if (!result_plain_list(decoded) || !setequal(names(decoded), c("field_order", "record")) ||
        !is.character(decoded$field_order) || anyNA(decoded$field_order) ||
        anyDuplicated(decoded$field_order)) {
    mssr_abort("result", "Invalid record field order.", call)
  }
  record <- decoded$record
  if (!result_plain_list(record) || "values" %in% names(record) ||
        !is.list(record$transform)) {
    mssr_abort("result", "Invalid result metadata fields.", call)
  }
  dims <- record$transform$output_dim
  if (!plain_real(dims) || length(dims) != 2L || any(!is.finite(dims)) ||
        any(dims < 1 | dims != floor(dims) | dims > .Machine$integer.max)) {
    mssr_abort("result", "Invalid decoded dimensions.", call)
  }
  n_values <- prod(as.double(dims))
  if (n_values > max_output_pixels) {
    mssr_abort("resource", "Decoded result exceeds pixel budget.", call)
  }
  if (12 + n_meta + 8 * n_values != length(payload)) {
    mssr_abort("result", "Payload length disagrees with result dimensions.", call)
  }
  values <- matrix(readBin(con, "double", n_values, size = 8L, endian = "little"),
    nrow = dims[1], ncol = dims[2]
  )
  # Preserve the documented field order, including the unversioned legacy form.
  result <- c(list(values = values), record)
  if (!setequal(names(result), decoded$field_order)) {
    mssr_abort("result", "Stored field order disagrees with result fields.", call)
  }
  result <- structure(result[decoded$field_order], class = "mssr_result")
  mssr_validate_result(result)
  result
}
