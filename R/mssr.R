#' Single-frame Mean-Shift Super-Resolution
#'
#' Computes the Mean-Shift Super-Resolution (MSSR) structure map of one 2D
#' frame (Torres-Garcia et al. 2022). The result is a structural map for
#' display, structure analysis or mask derivation. It is **not** a quantitative
#' intensity: MSSR is nonlinear, suppresses dim structures next to bright ones
#' and can hollow or split broad objects. Take measurements from the original
#' data (see [mssr_mask()]).
#'
#' The implementation follows the published operator. It keeps the input
#' orientation, accepts non-square frames, returns zeros (flagged
#' `degenerate`) for flat input instead of `NaN`, and uses Keys cubic
#' convolution for amplification. With `grid = "extent"` the amplified grid
#' preserves the field of view: output pixel centres lie at
#' `(k - 0.5) / amp + 0.5` input pixels, so the spacing is exactly `1 / amp`.
#' At `amp = 1` the output equals the authors' single-frame R and Python code,
#' once their rotation and kernel conventions are taken into account. For
#' `amp > 1` it is not numerically identical to their interpolation. Every
#' order step uses whole-image maxima, so frames must be processed whole;
#' splitting a frame into tiles changes the result.
#'
#' @param x A numeric matrix (rows = y, columns = x) with finite values.
#' @param fwhm Full width at half maximum of the point-spread function, in
#'   **input pixels**. Required; there is no default because it is a property
#'   of the acquisition.
#' @param amp Amplification factor (positive whole number).
#' @param order MSSR order (non-negative whole number, at most 10).
#' @param intensity_normalize If `TRUE` (the authors' default) the structure
#'   map is multiplied by the (amplified) input.
#' @param mesh Mesh compensation after amplification (only used if `amp > 1`).
#' @param grid `"extent"` (field-of-view-preserving, default) or `"endpoint"`
#'   (samples from the first to the last input pixel centre, as the authors'
#'   code does; for comparison only).
#' @param kernel Neighbourhood shape: `"disk"` (authors' R code) or
#'   `"square"` (authors' Python code).
#' @param rounding Rounding of the kernel half-size `0.5 * fwhm * amp`:
#'   `"half_even"` (R and Python default) or `"half_up"`.
#' @param max_output_pixels Upper limit on output pixels, checked before any
#'   allocation.
#'
#' @return An object of class `mssr_result`: a list with `values` (numeric
#'   matrix), `role` (`"structure"` or `"intensity_weighted_structure"`),
#'   `transform`, `parameters`, `engine` and `diagnostics`. The input is not
#'   stored.
#' @references Torres-Garcia E, Pinto-Camara R, Linares A, et al. Extending
#'   resolution within a single imaging frame. *Nature Communications*
#'   2022;13:7452. \doi{10.1038/s41467-022-34693-9}
#' @seealso [mssr_coords()], [mssr_mask()], [mssr_selftest()]
#' @examples
#' # Two point sources 3 pixels apart, blurred with FWHM 3 px.
#' g <- expand.grid(r = 1:21, c = 1:25)
#' spot <- function(r0, c0) exp(-((g$r - r0)^2 + (g$c - c0)^2) / (2 * (3 / 2.3548)^2))
#' x <- matrix(spot(11, 11) + spot(11, 14) + 0.05, 21, 25)
#' res <- mssr(x, fwhm = 3, amp = 2)
#' res
#' dim(as.matrix(res))
#' @export
mssr <- function(x, fwhm, amp = 1L, order = 1L, intensity_normalize = TRUE, mesh = TRUE,
                 grid = c("extent", "endpoint"), kernel = c("disk", "square"),
                 rounding = c("half_even", "half_up"), max_output_pixels = 5e7) {
  call <- sys.call()
  x <- check_matrix(x, call)
  if (missing(fwhm) || !is.numeric(fwhm) || length(fwhm) != 1L || !is.finite(fwhm) || fwhm <= 0) {
    mssr_abort("parameter", "`fwhm` must be a single positive number (input pixels).", call)
  }
  amp <- check_whole(amp, "amp", 1L, 64L, call)
  order <- check_whole(order, "order", 0L, 10L, call)
  if (!is.logical(intensity_normalize) || length(intensity_normalize) != 1L || is.na(intensity_normalize)) {
    mssr_abort("parameter", "`intensity_normalize` must be TRUE or FALSE.", call)
  }
  if (!is.logical(mesh) || length(mesh) != 1L || is.na(mesh)) {
    mssr_abort("parameter", "`mesh` must be TRUE or FALSE.", call)
  }
  grid <- match.arg(grid)
  kernel <- match.arg(kernel)
  rounding <- match.arg(rounding)
  n_out <- as.numeric(nrow(x)) * ncol(x) * amp^2
  if (n_out > max_output_pixels) {
    mssr_abort("resource", sprintf("Output would have %.0f pixels, above `max_output_pixels` (%.0f).", n_out, max_output_pixels), call)
  }
  e <- mssr_engine(x, amp, fwhm, order, intensity_normalize, mesh, grid, kernel, rounding)
  rows <- mssr_grid_positions(nrow(x), amp, grid)
  cols <- mssr_grid_positions(ncol(x), amp, grid)
  structure(list(
    values = e$values,
    role = if (intensity_normalize) "intensity_weighted_structure" else "structure",
    transform = list(amp = amp, grid = grid, input_dim = dim(x), output_dim = dim(e$values),
                     first_centre = c(row = rows[1], col = cols[1]),
                     spacing = c(row = if (length(rows) > 1) rows[2] - rows[1] else NA_real_,
                                 col = if (length(cols) > 1) cols[2] - cols[1] else NA_real_),
                     field_of_view = c(row_min = 0.5, row_max = nrow(x) + 0.5, col_min = 0.5, col_max = ncol(x) + 0.5)),
    parameters = list(fwhm = fwhm, amp = amp, order = order, intensity_normalize = intensity_normalize, mesh = mesh,
                      kernel = kernel, rounding = rounding, half_size = e$half_size),
    engine = list(id = "mssr_r_rev1", package_version = as.character(utils::packageVersion("mssrscopR")),
                  method = "Torres-Garcia et al. 2022, doi:10.1038/s41467-022-34693-9"),
    diagnostics = list(degenerate = e$degenerate, zero_fraction = mean(e$values == 0), n_offsets = e$n_offsets, quantitative = FALSE)
  ), class = "mssr_result")
}

#' @export
print.mssr_result <- function(x, ...) {
  p <- x$parameters
  cat("<mssr_result> ", x$role, "\n", sep = "")
  cat(sprintf("  input %d x %d -> output %d x %d (amp %d, %s grid)\n", x$transform$input_dim[1], x$transform$input_dim[2],
              x$transform$output_dim[1], x$transform$output_dim[2], p$amp, x$transform$grid))
  cat(sprintf("  fwhm %g px, order %d, kernel %s (half-size %d), mesh %s\n", p$fwhm, p$order, p$kernel, p$half_size, p$mesh))
  cat(sprintf("  engine %s; zero fraction %.3f%s\n", x$engine$id, x$diagnostics$zero_fraction,
              if (x$diagnostics$degenerate) "; DEGENERATE (flat input): all zeros" else ""))
  cat("  Not a quantitative intensity: measure on the original data.\n")
  invisible(x)
}

#' @export
as.matrix.mssr_result <- function(x, ...) x$values
