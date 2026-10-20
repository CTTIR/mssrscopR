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
#'
#' **Limits.** To keep the app responsive, runs whose estimated work exceeds
#' 5e8 operations are refused; call [mssr()] directly for larger runs. The
#' structure map is not a quantitative intensity, and nothing in the app
#' implies a gain in physical resolution.
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
  missing_pkgs <- mssr_app_missing(c("shiny", "bslib", "jsonlite"))
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
# refused in the app; about 20 s on a current laptop.
mssr_app_work_limit <- 5e8

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
    return(list(x = x, info = sprintf("Text table, %d x %d", nrow(x), ncol(x))))
  }
  if (ext == "png") {
    mssr_app_need("png", "PNG files")
    img <- list(png::readPNG(path))
    kind <- "PNG"
  } else if (ext %in% c("tif", "tiff")) {
    mssr_app_need("tiff", "TIFF files")
    img <- tiff::readTIFF(path, all = TRUE, as.is = TRUE)
    kind <- "TIFF"
  } else {
    mssr_abort("input", "Unsupported file type; use .csv, .tsv, .txt, .png, .tif or .tiff.")
  }
  page <- check_whole(page, "page", 1L, length(img))
  a <- img[[page]]
  n_ch <- if (length(dim(a)) == 3L) dim(a)[3] else 1L
  channel <- check_whole(channel, "channel", 1L, n_ch)
  x <- if (n_ch > 1L) a[, , channel] else a
  x <- matrix(as.numeric(x), nrow(x), ncol(x))
  pages <- if (length(img) > 1L) sprintf(", page %d of %d", page, length(img)) else ""
  info <- sprintf("%s, %d x %d, %d channel(s) (using %d)%s", kind, nrow(x), ncol(x), n_ch,
                  channel, pages)
  list(x = x, info = info)
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

mssr_app_plot_maps <- function(x, res, palette = "gray", dark = FALSE, guide = NULL,
                               stacked = FALSE) {
  op <- mssr_app_par(dark, if (stacked) c(2, 1) else c(1, 2))
  on.exit(graphics::par(op))
  pal <- mssr_app_palette(palette)
  co <- mssr_coords(res)
  p <- res$parameters
  mssr_app_image(x, seq_len(nrow(x)), seq_len(ncol(x)), dim(x), pal, "Input")
  mssr_app_guide(guide, dark)
  main <- sprintf("MSSR (amp %d, order %d)", p$amp, p$order)
  mssr_app_image(res$values, co$row, co$col, dim(x), pal, main)
  mssr_app_guide(guide, dark)
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

mssr_app_record <- function(run, source, mask = NULL) {
  res <- run$result
  rec <- list(
    created_utc = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    source = source, input_dim = res$transform$input_dim,
    engine = res$engine, parameters = res$parameters, transform = res$transform,
    diagnostics = res$diagnostics, role = res$role, seconds = round(run$seconds, 3)
  )
  if (!is.null(mask)) {
    rec$mask <- list(fraction = mask$fraction, seed = mask$seed,
                     coverage = attr(mask$mask, "coverage"),
                     tie_fraction = attr(mask$mask, "tie_fraction"),
                     n_region = attr(mask$mask, "n_region"))
  }
  jsonlite::toJSON(mssr_app_jsonable(rec), auto_unbox = TRUE, pretty = TRUE, digits = NA)
}

mssr_app_write_matrix <- function(m, file) {
  utils::write.table(m, file, sep = ",", row.names = FALSE, col.names = FALSE)
}

# ---- User interface ------------------------------------------------------------

mssr_app_css <- "
:root { --ms-fg:#1b2733; --ms-bg:#f7f9fc; --ms-panel:#ffffff; --ms-line:#dbe3ec;
  --ms-mute:#6b7c8f; --ms-accent:#185FA5; }
[data-bs-theme=\"dark\"] { --ms-fg:#dbe4f0; --ms-bg:#0b1626; --ms-panel:#10213a;
  --ms-line:#22395a; --ms-mute:#8aa0b8; --ms-accent:#93C5FD; }
body { background:var(--ms-bg); color:var(--ms-fg); }
.ms-brand { display:flex; align-items:center; gap:.75rem; padding:.55rem 1rem;
  background:var(--ms-panel); border-bottom:1px solid var(--ms-line); }
.ms-brand img { height:46px; width:auto; }
.ms-brand .ms-title { font-weight:600; letter-spacing:.02em; font-size:1.15rem; }
.ms-brand .ms-sub { color:var(--ms-mute); font-size:.9rem; }
.bslib-sidebar-layout > .sidebar { background:var(--ms-panel);
  border-right:1px solid var(--ms-line); }
.ms-section { font-size:.78rem; text-transform:uppercase; letter-spacing:.08em;
  color:var(--ms-mute); margin:.6rem 0 .3rem; font-weight:600; }
.card { border:1px solid var(--ms-line); box-shadow:none; background:var(--ms-panel); }
.btn-primary { background:var(--ms-accent); border-color:var(--ms-accent); }
[data-bs-theme=\"dark\"] .btn-primary { color:#0b1626; }
.ms-note { color:var(--ms-mute); font-size:.85rem; }
.ms-stale { color:#b45309; font-size:.85rem; margin-top:.4rem; }
[data-bs-theme=\"dark\"] .ms-stale { color:#fbbf24; }
.ms-about { max-width:780px; }
.ms-about h5 { margin-top:1.1rem; }
pre.shiny-text-output { background:transparent; border:1px solid var(--ms-line);
  color:var(--ms-fg); }
"

mssr_app_ui <- function() {
  www <- system.file("app", "www", package = "mssrscopR")
  if (nzchar(www)) shiny::addResourcePath("mssrscopR-www", www)
  bslib::page_sidebar(
    title = NULL,
    window_title = "mssrscopR",
    theme = bslib::bs_theme(version = 5, primary = "#185FA5", "border-radius" = "0.3rem"),
    fillable = FALSE,
    shiny::tags$head(shiny::tags$style(shiny::HTML(mssr_app_css))),
    shiny::div(
      class = "ms-brand",
      shiny::tags$img(src = "mssrscopR-www/logo.svg", alt = "mssrscopR hex sticker"),
      shiny::div(shiny::div(class = "ms-title", "mssrscopR"),
                 shiny::div(class = "ms-sub", "Mean-Shift Super-Resolution explorer")),
      shiny::div(class = "ms-auto ms-3", style = "margin-left:auto;",
                 bslib::input_dark_mode(id = "dark_mode", mode = "light"))
    ),
    sidebar = bslib::sidebar(
      width = 330,
      shiny::div(class = "ms-section", "Input"),
      shiny::radioButtons("source", NULL, inline = TRUE,
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
      shiny::sliderInput("amp", "Amplification", min = 1, max = 8, value = 2, step = 1),
      shiny::sliderInput("order", "Order", min = 0, max = 5, value = 1, step = 1),
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
      shiny::uiOutput("stale"),
      shiny::div(class = "ms-section", "Download"),
      shiny::downloadButton("dl_values", "Structure map (CSV)", class = "w-100 mb-1 btn-sm"),
      shiny::downloadButton("dl_figure", "Figure (PNG)", class = "w-100 mb-1 btn-sm"),
      shiny::downloadButton("dl_record", "Run record (JSON)", class = "w-100 btn-sm")
    ),
    bslib::navset_card_tab(
      id = "tabs",
      bslib::nav_panel(
        "Maps",
        shiny::div(class = "d-flex justify-content-end",
                   shiny::selectInput("palette", NULL, width = "160px",
                                      choices = c(Gray = "gray", Viridis = "viridis",
                                                  Inferno = "inferno"))),
        shiny::plotOutput("maps", height = "auto"),
        shiny::verbatimTextOutput("summary")
      ),
      bslib::nav_panel(
        "Profile",
        bslib::layout_columns(
          col_widths = c(4, 8),
          shiny::radioButtons("profile_axis", "Along", inline = TRUE,
                              choices = c("input row" = "row", "input column" = "col")),
          shiny::sliderInput("profile_index", "Position (input px)", min = 1, max = 31,
                             value = 16, step = 1, width = "100%")
        ),
        shiny::plotOutput("profile", height = "360px"),
        shiny::div(class = "ms-note",
                   paste("Each line is scaled to its own maximum. The dashed line in the Maps tab",
                         "marks the position. Amplification adds samples, not observations."))
      ),
      bslib::nav_panel(
        "Mask",
        bslib::layout_columns(
          col_widths = c(6, 3, 3),
          shiny::sliderInput("mask_fraction", "Fraction of pixels to keep", min = 0.005, max = 1,
                             value = 0.02, step = 0.005, width = "100%"),
          shiny::numericInput("mask_seed", "Tie-break seed", 1, step = 1),
          shiny::div(class = "pt-4", shiny::downloadButton("dl_mask", "Mask (CSV)",
                                                           class = "btn-sm"))
        ),
        bslib::layout_columns(
          col_widths = c(7, 5),
          shiny::plotOutput("mask_plot", height = "380px"),
          shiny::div(
            shiny::tableOutput("mask_table"),
            shiny::uiOutput("mask_warning"),
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
        shiny::uiOutput("selftest_status"),
        shiny::tableOutput("selftest_table")
      ),
      bslib::nav_panel("About", mssr_app_about())
    )
  )
}

mssr_app_about <- function() {
  shiny::div(
    class = "ms-about",
    shiny::h5("What the app shows"),
    shiny::p("The single-frame Mean-Shift Super-Resolution (MSSR) structure map of",
             "Torres-Garcia et al. (2022), computed by mssr() with the parameters on the left.",
             "Input and result share the same input-pixel axes."),
    shiny::h5("How to read it"),
    shiny::tags$ul(
      shiny::tags$li("The structure map is not a quantitative intensity. Take measurements on",
                     "the original data, for example with a mask (Mask tab)."),
      shiny::tags$li("MSSR deepens dips that exist in the input; it does not separate sources",
                     "the blur has already merged (compare the 3 px and 2.4 px examples)."),
      shiny::tags$li("Dim structures next to bright ones are suppressed; broad filled objects",
                     "can be hollowed (dim-bright and disk examples)."),
      shiny::tags$li("No gain in physical resolution and no benefit for any application is",
                     "implied.")
    ),
    shiny::h5("Uploads"),
    shiny::p("Files are read by the R process that runs this app; the app sends nothing",
             "elsewhere. Multi-channel images are not converted to gray: choose a channel."),
    shiny::h5("Reference"),
    shiny::p("Torres-Garcia E, Pinto-Camara R, Linares A, et al. Extending resolution within a",
             "single imaging frame. Nature Communications 2022;13:7452.",
             shiny::a("doi:10.1038/s41467-022-34693-9",
                      href = "https://doi.org/10.1038/s41467-022-34693-9", target = "_blank")),
    shiny::p(class = "ms-note",
             sprintf("mssrscopR %s, engine mssr_r_rev2.", utils::packageVersion("mssrscopR")))
  )
}

# ---- Server --------------------------------------------------------------------

mssr_app_server <- function(input, output, session) {
  dark <- shiny::reactive(identical(input$dark_mode, "dark"))

  frame <- shiny::reactive({
    if (identical(input$source, "upload")) {
      shiny::req(input$file)
      mssr_app_try(mssr_app_read(input$file$datapath[1], input$file$name[1],
                                 mssr_app_or(input$channel, 1), mssr_app_or(input$page, 1)))
    } else {
      id <- mssr_app_or(input$example, "pair_3")
      label <- names(mssr_app_examples)[match(id, mssr_app_examples)]
      list(x = mssr_app_example(id), info = sprintf("Synthetic example: %s", label),
           source = sprintf("example:%s", id))
    }
  })

  run <- shiny::bindEvent(shiny::reactive({
    fr <- frame()
    shiny::req(fr)
    out <- shiny::withProgress(message = "Computing MSSR", value = 0.3, {
      mssr_app_try(mssr_app_compute(fr$x, mssr_app_args(input)))
    })
    shiny::req(out)
    c(out, list(x = fr$x, info = fr$info, source = mssr_app_or(fr$source, "upload")))
  }), input$compute, frame(), ignoreNULL = FALSE)

  shiny::observeEvent(frame(), {
    fr <- frame()
    shiny::req(fr)
    axis <- mssr_app_or(input$profile_axis, "row")
    n <- if (axis == "row") nrow(fr$x) else ncol(fr$x)
    shiny::updateSliderInput(session, "profile_index", max = n, value = ceiling(n / 2))
  })
  shiny::observeEvent(input$profile_axis, {
    fr <- frame()
    shiny::req(fr)
    n <- if (input$profile_axis == "row") nrow(fr$x) else ncol(fr$x)
    shiny::updateSliderInput(session, "profile_index", max = n, value = ceiling(n / 2))
  }, ignoreInit = TRUE)

  guide <- shiny::reactive({
    r <- run()
    axis <- mssr_app_or(input$profile_axis, "row")
    n <- if (axis == "row") nrow(r$x) else ncol(r$x)
    list(axis = axis, index = min(max(1L, mssr_app_or(input$profile_index, 1L)), n))
  })

  output$stale <- shiny::renderUI({
    r <- run()
    if (!identical(r$args, mssr_app_args(input))) {
      shiny::div(class = "ms-stale", "Parameters changed: press Compute to update.")
    }
  })

  # Below 700 px the two maps are stacked instead of side by side.
  narrow <- shiny::reactive(mssr_app_or(session$clientData$output_maps_width, 900) < 700)

  output$maps <- shiny::renderPlot({
    r <- run()
    mssr_app_plot_maps(r$x, r$result, mssr_app_or(input$palette, "gray"), dark(), guide(),
                       stacked = narrow())
  }, height = function() if (narrow()) 760 else 440, bg = "transparent")

  output$summary <- shiny::renderText({
    r <- run()
    paste(c(r$info, utils::capture.output(print(r$result)),
            sprintf("Computed in %.2f s.", r$seconds)), collapse = "\n")
  })

  output$profile <- shiny::renderPlot({
    r <- run()
    g <- guide()
    mssr_app_plot_profile(r$x, r$result, g$axis, g$index, dark())
  }, bg = "transparent")

  mask <- shiny::reactive({
    r <- run()
    tr <- r$result$transform
    shiny::validate(shiny::need(
      tr$amp == 1L || tr$grid == "extent",
      "Masks need the extent grid when amp > 1 (More options > Output grid)."
    ))
    fraction <- mssr_app_or(input$mask_fraction, 0.02)
    seed <- mssr_app_or(input$mask_seed, 1)
    m <- mssr_app_try(mssr_mask(r$result, fraction = fraction, seed = seed))
    shiny::req(m)
    list(mask = m, fraction = fraction, seed = seed)
  })

  output$mask_plot <- shiny::renderPlot({
    mssr_app_plot_mask(run()$x, mask()$mask, dark())
  }, bg = "transparent")

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
      mssr_app_plot_maps(r$x, r$result, mssr_app_or(input$palette, "gray"))
    }
  )

  output$dl_record <- shiny::downloadHandler(
    filename = function() "mssr_run_record.json",
    content = function(file) {
      r <- run()
      m <- tryCatch(mask(), error = function(e) NULL)
      writeLines(mssr_app_record(r, r$source, m), file)
    }
  )
}
