#' Single-frame Mean-Shift Super-Resolution
#'
#' Computes the Mean-Shift Super-Resolution (MSSR) structure map of one 2D
#' frame (Torres-Garcia et al. 2022). The result is a structural map for
#' display, structure analysis or mask derivation. It is **not** a quantitative
#' intensity: MSSR is nonlinear, suppresses dim structures next to bright ones
#' and can hollow or split broad objects. Take measurements from the original
#' data (see [mssr_mask()]).
#'
#' @details
#' **Geometry.** The output keeps the input orientation. With
#' `grid = "extent"` the amplified grid preserves the field of view: output
#' pixel centers lie at `(k - 0.5) / amp + 0.5` input pixels, so the spacing is
#' exactly `1 / amp`. Amplification adds samples, not independent observations.
#'
#' **Relation to the authors' code.** At `amp = 1` with
#' `intensity_normalize = FALSE`, the output equals the authors' single-frame R
#' function after its final 90-degree rotation is undone (`kernel = "disk"`) or
#' their Python function (`kernel = "square"`), wherever their code returns
#' finite values. For `amp > 1`, Keys cubic convolution is used, which is not
#' numerically identical to the authors' interpolation.
#'
#' **Degenerate input.** A flat frame, a frame whose amplified maximum is not
#' positive, and a frame without any positive mean shift return zeros with
#' `diagnostics$degenerate = TRUE` and a `degenerate_reason`. A refinement step
#' (`order >= 1`) is undefined when the mean-shift map already equals the
#' normalized input, for example for isolated impulses on an exactly zero
#' background. Such a step leaves the map unchanged and is counted in
#' `diagnostics$order_steps_skipped`. The authors' code returns `NaN` in all of
#' these cases.
#'
#' **Negative values.** MSSR assumes non-negative intensities. With negative
#' input the structure map depends on the offset of the data and
#' intensity-weighted output can be negative, so a warning of class
#' `mssrscopR_warning_negative` is given.
#'
#' **Numeric domain.** Input and numeric parameters must use plain integer or
#' double storage, without explicit classes. Convert calibrated or other
#' classed data deliberately before calling. Finite input can still overflow
#' intermediate arithmetic; this raises `mssrscopR_error_numerical` rather than
#' returning an invalid or misleading zero map. Extreme underflow is not a
#' calibrated intensity regime; retain any input rescaling in provenance.
#'
#' **Cost.** Every order step uses image-wide maxima, so frames must be
#' processed whole. Time grows with the number of output pixels times the
#' number of neighborhood offsets (about `pi * (0.5 * fwhm * amp)^2`). Calls whose
#' estimated work exceeds 1e10 operations, whose output exceeds
#' `max_output_pixels`, or whose kernel half-size exceeds 1000 pixels are
#' refused before computing.
#'
#' @param x A plain integer or double matrix (rows = y, columns = x) with
#'   finite values and no explicit class.
#' @param fwhm Full width at half maximum of the point-spread function, in
#'   **input pixels**. Required; there is no default because it is a property
#'   of the acquisition.
#' @param amp Amplification factor (whole number from 1 to 64).
#' @param order MSSR order (whole number from 0 to 10).
#' @param intensity_normalize If `TRUE` (the authors' default) the structure
#'   map is multiplied by the (amplified) input.
#' @param mesh Mesh compensation after amplification (only used if `amp > 1`).
#' @param grid `"extent"` (field-of-view-preserving, default) or `"endpoint"`
#'   (samples from the first to the last input pixel center, as the authors'
#'   code does; for comparison only).
#' @param kernel Neighborhood shape: `"disk"` (authors' R code) or
#'   `"square"` (authors' Python code).
#' @param rounding Rounding of the kernel half-size `0.5 * fwhm * amp`:
#'   `"half_even"` (R and Python default) or `"half_up"`.
#' @param max_output_pixels Upper limit on output pixels, checked before any
#'   computation.
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
  if (missing(fwhm)) {
    mssr_abort("parameter",
               "`fwhm` is required (point-spread-function FWHM in input pixels).", call)
  }
  fwhm <- check_positive(fwhm, "fwhm", call)
  amp <- check_whole(amp, "amp", 1L, 64L, call)
  order <- check_whole(order, "order", 0L, 10L, call)
  intensity_normalize <- check_flag(intensity_normalize, "intensity_normalize", call)
  mesh <- check_flag(mesh, "mesh", call)
  grid <- match.arg(grid)
  kernel <- match.arg(kernel)
  rounding <- match.arg(rounding)
  max_output_pixels <- check_positive(max_output_pixels, "max_output_pixels", call)
  if (grid == "endpoint" && amp > 1L && min(dim(x)) < 2L) {
    mssr_abort("unsupported",
               "The endpoint grid needs at least two pixels along each axis when `amp > 1`.", call)
  }
  hs <- mssr_half_size(fwhm, amp, rounding)
  if (hs > 1000) {
    msg <- sprintf("Kernel half-size %.0f px (0.5 * fwhm * amp) exceeds 1000; check `fwhm`, `amp`.",
                   hs)
    mssr_abort("parameter", msg, call)
  }
  n_out <- as.numeric(nrow(x)) * ncol(x) * amp^2
  if (n_out > max_output_pixels) {
    msg <- sprintf("Output would have %.0f pixels, above `max_output_pixels` (%.0f).",
                   n_out, max_output_pixels)
    mssr_abort("resource", msg, call)
  }
  work <- n_out * nrow(mssr_offsets(hs, kernel))
  if (work > 1e10) {
    msg <- sprintf("Estimated work of %.2g operations exceeds 1e10; %s", work,
                   "reduce the frame size, `amp` or `fwhm`.")
    mssr_abort("resource", msg, call)
  }
  if (any(x < 0)) {
    mssr_warn("negative", paste("`x` contains negative values. MSSR assumes non-negative",
                                "intensities; the structure map then depends on the data offset."))
  }
  e <- mssr_engine(x, amp, fwhm, order, intensity_normalize, mesh, grid, kernel, rounding, call)
  spacing <- function(n) {
    if (grid == "extent") 1 / amp else if (n > 1L) (n - 1) / (n * amp - 1) else 1
  }
  structure(list(
    values = e$values,
    role = if (intensity_normalize) "intensity_weighted_structure" else "structure",
    transform = list(amp = amp, grid = grid, input_dim = dim(x), output_dim = dim(e$values),
                     first_center = c(row = mssr_grid_positions(nrow(x), amp, grid)[1],
                                      col = mssr_grid_positions(ncol(x), amp, grid)[1]),
                     spacing = c(row = spacing(nrow(x)), col = spacing(ncol(x))),
                     field_of_view = c(row_min = 0.5, row_max = nrow(x) + 0.5,
                                       col_min = 0.5, col_max = ncol(x) + 0.5)),
    parameters = list(fwhm = fwhm, amp = amp, order = order,
                      intensity_normalize = intensity_normalize, mesh = mesh && amp > 1L,
                      kernel = kernel, rounding = rounding, half_size = e$half_size),
    engine = list(id = "mssr_r_rev2",
                  package_version = as.character(utils::packageVersion("mssrscopR")),
                  method = "Torres-Garcia et al. 2022, doi:10.1038/s41467-022-34693-9"),
    diagnostics = list(degenerate = e$degenerate, degenerate_reason = e$degenerate_reason,
                       order_steps_skipped = e$order_steps_skipped,
                       zero_fraction = mean(e$values == 0),
                       negative_fraction = mean(e$values < 0),
                       n_offsets = e$n_offsets, quantitative = FALSE)
  ), class = "mssr_result")
}

#' @export
print.mssr_result <- function(x, ...) {
  p <- x$parameters
  d <- x$diagnostics
  cat("<mssr_result> ", x$role, "\n", sep = "")
  cat(sprintf("  input %d x %d -> output %d x %d (amp %d, %s grid)\n", x$transform$input_dim[1],
              x$transform$input_dim[2], x$transform$output_dim[1], x$transform$output_dim[2], p$amp,
              x$transform$grid))
  cat(sprintf("  fwhm %g px, order %d, kernel %s (half-size %d)%s\n", p$fwhm, p$order, p$kernel,
              as.integer(p$half_size), if (p$amp > 1L) paste0(", mesh ", p$mesh) else ""))
  cat(sprintf("  engine %s; zero fraction %.3f", x$engine$id, d$zero_fraction))
  if (d$degenerate) cat("; DEGENERATE (", d$degenerate_reason, "): all zeros", sep = "")
  if (d$order_steps_skipped > 0) {
    cat(sprintf("; %d undefined order step(s) skipped", d$order_steps_skipped))
  }
  cat("\n  Not a quantitative intensity: measure on the original data.\n")
  invisible(x)
}

#' @export
as.matrix.mssr_result <- function(x, ...) x$values
