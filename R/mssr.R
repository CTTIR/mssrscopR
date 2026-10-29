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
#' `intensity_normalize = FALSE`, tested non-degenerate examples agree with
#' the authors' single-frame R function after its final 90-degree rotation is
#' undone (`kernel = "disk"`) or
#' their Python function (`kernel = "square"`) within floating-point tolerance.
#' Extreme numeric ranges and undefined refinement steps can differ (see below). For
#' `amp > 1`, `mssr()` uses the supplement's cubic kernel (Keys cubic
#' convolution, a = -1/2). The authors' R script interpolates with akima's Akima
#' method and their Python script with a SciPy spline, and their R mesh shifts
#' asymmetrically, so the amplified input already differs beyond rounding;
#' MSSR's range normalization and refinement are nonlinear and can enlarge such
#' differences locally. Do not expect pixel-wise agreement with their amplified
#' maps, even with `grid = "endpoint"`, which reproduces their sample positions.
#' With the default
#' `intensity_normalize = TRUE` their R function multiplies the rotated map by
#' the unrotated input, so it agrees with `mssr()` only for frames that a
#' 90-degree rotation leaves unchanged (and fails for non-square frames).
#'
#' **Several channels or bands.** `mssr()` processes one 2D frame. Applied to
#' each channel or band of multichannel or spectral data, it gives every channel
#' its own nonlinear structure map, scaled by that channel's maxima.
#' Intensity-weighted outputs (the default) are guaranteed to keep the channels'
#' intensity ratios only when one whole frame, background included, is a scaled
#' copy of another; a different background or another object elsewhere in the
#' frame can change the ratios, and the structure maps
#' (`intensity_normalize = FALSE`) of scaled copies are identical. So do not
#' compare channels, form ratios or indices, or assemble spectra from the
#' outputs; measure them on the original data.
#'
#' **Degenerate input.** A flat frame, a frame whose amplified maximum is not
#' positive, a frame without any positive mean shift and a refinement step that
#' leaves no positive value (possible only with signed input) return zeros with
#' `diagnostics$degenerate = TRUE` and a `degenerate_reason`. A refinement step
#' (`order >= 1`) is undefined when the mean-shift map already equals the
#' normalized input, for example for isolated impulses on an exactly zero
#' background. Such a step leaves the map unchanged, is counted in
#' `diagnostics$order_steps_skipped` and gives a warning of class
#' `mssrscopR_warning_skipped_steps`: the result is not the limit for slightly
#' perturbed input, because any positive background makes the step defined and
#' changes the map. The authors' R function returns `NaN` in
#' all of these cases; their Python function returns zeros, which equals
#' `mssr()` for the degenerate frames but not for skipped refinement steps.
#'
#' **Negative values and background.** MSSR assumes non-negative intensities.
#' Negative input gives a warning of class `mssrscopR_warning_negative`, and
#' intensity-weighted output can then be negative. Non-negative input is not
#' free of offset effects either: the order-0 structure map
#' (`intensity_normalize = FALSE`) does not change with a constant background,
#' but every refinement step (`order >= 1`) compares the map with the input
#' divided by its maximum, which a background changes, and intensity weighting
#' multiplies by the input. Subtracting a background is therefore a
#' preprocessing choice that changes the result; record it with the result.
#' The range normalizer adapts to the largest local difference at each pixel,
#' so even rounding-level ripple on an otherwise flat frame is stretched to
#' full contrast: only an exactly flat frame is degenerate.
#'
#' **Numeric domain.** Input and numeric parameters must use plain integer or
#' double storage, without explicit classes. Convert calibrated or other
#' classed data deliberately before calling. The engine uses internal
#' power-of-two scaling, centered interpolation for non-negative input and
#' weighted local differences to limit overflow, underflow and cancellation.
#' A nonzero input lost during scaling or an overflowing final result
#' raises `mssrscopR_error_numerical`. Rounding already present in the supplied
#' data cannot be recovered. Intensity-weighted output is rescaled to
#' the original numeric units but remains non-quantitative; subnormal output
#' still has limited precision and can round to zero.
#'
#' **Cost.** Every order step uses image-wide maxima, so frames must be
#' processed whole. Time grows with the number of output pixels times the
#' number of neighborhood offsets (about `pi * h^2` for the disk kernel and
#' `(2 * h + 1)^2 - 1` for the square kernel, with half-size `h`, recorded in
#' `parameters$half_size`). Calls whose
#' estimated work exceeds 1e10 operations, whose output exceeds
#' `max_output_pixels`, or whose kernel half-size exceeds 1000 pixels are
#' refused before computing.
#'
#' @param x A plain integer or double matrix (rows = y, columns = x) with
#'   finite values and no explicit class. Input dimnames and other attributes
#'   are discarded; acquisition metadata are never inferred from attributes.
#' @param fwhm Full width at half maximum of the point-spread function, in
#'   **input pixels**. Required; there is no default because it is a property
#'   of the acquisition. Prefer a measured PSF: a theoretical value such as
#'   `0.51 * wavelength / NA` (emission wavelength, divided by the pixel size)
#'   describes an ideal widefield system, and aberrations, defocus and pixel
#'   size can widen the recorded PSF. Under noise an `fwhm` below the true PSF
#'   makes false peaks more likely, while a larger one gives a shallower dip
#'   between close sources; when unsure, choose the larger plausible value. An
#'   `fwhm` larger than the PSF's FWHM enlarges the neighborhood and gives
#'   smoother maps with fewer fragments; choose it per data set and record it.
#'   Whatever the value, MSSR maps are visual aids, not a basis for segmentation
#'   or quantification. Only
#'   the kernel half-size, `0.5 * fwhm * amp` rounded as set by `rounding` and at
#'   least 1 (recorded in `parameters$half_size`), enters the computation, so
#'   nearby values can give identical results.
#' @param amp Amplification factor (whole number from 1 to 64).
#' @param order MSSR order (whole number from 0 to 10). Orders above 3
#'   are experimental: bounded high-precision checks found larger errors at
#'   order 10. They emit `mssrscopR_warning_unqualified_order`. Checks at orders
#'   0 through 3 cover only the documented synthetic domain, not every input.
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
#' @param max_memory_bytes Optional positive allocation-estimate ceiling.
#'   `NULL` leaves this guard disabled. This is not a hard process-memory cap;
#'   see [mssr_estimate_resources()].
#'
#' @return An object of class `mssr_result`: a list with `values` (numeric
#'   matrix), `role` (`"structure"` or `"intensity_weighted_structure"`),
#'   `transform`, `parameters`, `engine` and `diagnostics`. `transform` holds
#'   `amp`, `grid`, `input_dim`, `output_dim`, the first output pixel center
#'   and the spacing (input-pixel units), and `field_of_view`: the input frame's
#'   extent from pixel edge 0.5 to `n + 0.5`. Output samples cover it exactly on
#'   the extent grid; on the endpoint grid they span only the first to the last
#'   input pixel center. The input is not
#'   stored. `schema_version` identifies the result contract separately from
#'   the numerical engine; `input` records known axes and unknown calibration;
#'   `evidence` identifies the numerical-only scope. Qualification diagnostics
#'   disclose conservative high-order limits without assigning confidence.
#' @references Torres-Garcia E, Pinto-Camara R, Linares A, et al. Extending
#'   resolution within a single imaging frame. *Nature Communications*
#'   2022;13:7452. \doi{10.1038/s41467-022-34693-9}
#' @seealso [mssr_coords()], [mssr_mask()], [mssr_selftest()], and
#'   [mssr_temporal()] for temporal statistics of a frame sequence
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
                 rounding = c("half_even", "half_up"), max_output_pixels = 5e7,
                 max_memory_bytes = NULL) {
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
  grid <- check_choice(grid, c("extent", "endpoint"), "grid", call)
  kernel <- check_choice(kernel, c("disk", "square"), "kernel", call)
  rounding <- check_choice(rounding, c("half_even", "half_up"), "rounding", call)
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
  estimate <- mssr_estimate_resources(dim(x), fwhm, amp, kernel, rounding,
                                      max_output_pixels)
  work <- estimate$estimated_work
  if (work > 1e10) {
    msg <- sprintf("Estimated work of %.2g operations exceeds 1e10; %s", work,
                   "reduce the frame size, `amp` or `fwhm`.")
    mssr_abort("resource", msg, call)
  }
  if (!is.null(max_memory_bytes)) {
    max_memory_bytes <- check_positive(max_memory_bytes, "max_memory_bytes", call)
    if (estimate$estimated_peak_bytes > max_memory_bytes) {
      mssr_abort("resource", "Estimated allocation exceeds `max_memory_bytes`.", call)
    }
  }
  if (order > 3L) {
    mssr_warn("unqualified_order", paste(
      "Orders above 3 are outside the conservatively qualified numerical domain.",
      "High-order refinement can amplify rounding errors; independent checks found",
      "larger discrepancies at order 10. Lower orders have bounded synthetic evidence",
      "and are not guaranteed accurate for every input."
    ))
  }
  if (any(x < 0)) {
    mssr_warn("negative", paste("`x` contains negative values. MSSR assumes non-negative",
                                "intensities; the structure map then depends on the data offset."))
  }
  e <- mssr_engine(x, amp, fwhm, order, intensity_normalize, mesh, grid, kernel, rounding, call)
  if (e$order_steps_skipped > 0L) {
    mssr_warn("skipped_steps", sprintf(paste(
      "%d of %d refinement step(s) were undefined (the mean-shift map already equals the",
      "normalized input, e.g. impulses on an exactly zero background) and were skipped.",
      "The result is not the limit for slightly perturbed input: any positive background",
      "makes these steps defined and changes the map."
    ), e$order_steps_skipped, order))
  }
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
    engine = list(id = "mssr_r_rev3",
                  package_version = as.character(utils::packageVersion("mssrscopR")),
                  method = "Torres-Garcia et al. 2022, doi:10.1038/s41467-022-34693-9"),
    diagnostics = list(degenerate = e$degenerate, degenerate_reason = e$degenerate_reason,
                       order_steps_skipped = e$order_steps_skipped,
                       zero_fraction = mean(e$values == 0),
                       negative_fraction = mean(e$values < 0),
                       n_offsets = e$n_offsets, quantitative = FALSE,
                       qualification_scope = "bounded_synthetic_domain",
                       high_order_unqualified = order > 3L),
    schema_version = mssr_result_contract()$schema_version,
    input = mssr_result_contract()$input,
    evidence = mssr_result_contract()$evidence
  ), class = "mssr_result")
}

#' @export
print.mssr_result <- function(x, ...) {
  p <- x$parameters
  d <- x$diagnostics
  cat("<mssr_result> ", x$role, "\n", sep = "")
  if (result_is_temporal(x)) {
    cat(sprintf("  input %d x %d -> output %d x %d (amp %d, %s grid)\n", x$transform$input_dim[1],
                x$transform$input_dim[2], x$transform$output_dim[1], x$transform$output_dim[2],
                p$amp, x$transform$grid))
    cat(sprintf("  %s of %d frame(s) (frames %d to %d)%s\n", p$statistic, p$frames,
                p$first_frame, p$first_frame + p$frames - 1L,
                if (p$sign == "absolute") ", absolute value" else ""))
    cat(sprintf("  per frame: fwhm %g px, order %d, kernel %s (half-size %d)%s\n", p$fwhm,
                p$order, p$kernel, as.integer(p$half_size),
                if (p$amp > 1L) paste0(", mesh ", p$mesh) else ""))
    cat(sprintf("  %d degenerate frame(s), %d frame(s) with warnings; path %s\n",
                d$degenerate_frames, d$warning_frames, d$path))
    cat(sprintf("  trend (last / first tenth of frames) %s%s\n",
                if (is.null(d$trend)) "undefined" else format(d$trend, digits = 3),
                if (is.null(d$mesh_index)) "" else sprintf("; mesh index %.3g (%s)",
                                                           d$mesh_index, d$mesh_region)))
    cat("  Temporal statistic of nonlinear structure maps, not a quantitative intensity.\n")
    return(invisible(x))
  }
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

result_is_temporal <- function(x) {
  is.character(x$role) && length(x$role) == 1L && !is.na(x$role) &&
    startsWith(x$role, "temporal_")
}
