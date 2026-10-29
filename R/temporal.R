# Temporal MSSR (t-MSSR, article Fig. 7a; Supplementary Note 5.2): single-frame
# MSSR of every frame of a sequence, then a pixel-wise temporal function of the
# resulting stack. Definitions follow Supplementary Table S2, with the SOFI rows
# read as the lagged, signed auto-cumulants of the SOFI reference the table
# cites. tools/qualification/METHOD_CONCORDANCE.md records the sources and the
# differences from the authors' tools.

temporal_statistics <- c("mean", "var", "tpm", "cv", "sofi2", "sofi3", "sofi4")
temporal_min_frames <- c(mean = 1L, var = 2L, tpm = 1L, cv = 2L,
                         sofi2 = 2L, sofi3 = 3L, sofi4 = 4L)
# Degree of each statistic under x -> s * x (used to undo internal scaling).
temporal_degree <- c(mean = 1L, var = 2L, tpm = 2L, cv = 1L,
                     sofi2 = 2L, sofi3 = 3L, sofi4 = 4L)
# Output-sized double buffers the reduction holds (model "temporal_buffers_v1").
temporal_buffers <- c(mean = 4, var = 6, tpm = 4, cv = 6, sofi2 = 7, sofi3 = 8, sofi4 = 15)
temporal_schema_version <- "1.1.0"
temporal_definition <- "table_s2_lagged"
temporal_paths <- c("stored", "recompute", "single_pass", "stack")
# Without `max_memory_bytes`, per-frame maps are stored up to this size.
temporal_default_stack_bytes <- 2 * 1024^3
temporal_frame_arguments <- c("fwhm", "amp", "order", "intensity_normalize", "mesh", "grid",
                              "kernel", "rounding", "max_output_pixels")

#' Temporal statistics of per-frame MSSR maps
#'
#' Computes single-frame MSSR ([mssr()]) for every frame of an image sequence
#' and reduces the stack of maps pixel by pixel with one temporal statistic, as
#' in the temporal MSSR (t-MSSR) of Torres-Garcia et al. (2022, Fig. 7a and
#' Supplementary Note 5.2). The output is a temporal statistic of nonlinear
#' structure maps: it is not a quantitative intensity, and no gain in
#' resolution is implied (see **Interpretation**). `mssr_stack()` stores the
#' per-frame maps so that several statistics can be computed without
#' recomputing MSSR.
#'
#' @details
#' **Definitions.** Per output pixel, `x_1, ..., x_M` are the values of the `M`
#' selected frames' MSSR maps, `m` is their mean and `d_t = x_t - m`. Following
#' Supplementary Table S2:
#'
#' | `statistic` | Value | Minimum `M` |
#' |---|---|---|
#' | `"mean"` | `m` | 1 |
#' | `"var"` | `(1/M) sum(d_t^2)` | 2 |
#' | `"tpm"` | `(sum(x_t))^2` | 1 |
#' | `"cv"` | `var / m`, and 0 where `m = 0` | 2 |
#' | `"sofi2"` | `(1/(M-1)) sum_{t=1}^{M-1} d_t d_{t+1}` | 2 |
#' | `"sofi3"` | `(1/(M-2)) sum_{t=1}^{M-2} d_t d_{t+1} d_{t+2}` | 3 |
#' | `"sofi4"` | `A(0,1,2,3) - A(0,1)A(2,3) - A(0,2)A(1,3) - A(0,3)A(1,2)` | 4 |
#'
#' For `"sofi4"`, `A(L)` is the average over `t = 1, ..., M - 3` of the product
#' of `d_{t+l}` for the lags `l` in `L`; all its terms use the same frames.
#' - `"var"` is the population variance; the sample variance is larger by
#'   `M / (M - 1)`.
#' - `"tpm"` equals `M^2 * mean^2`. For non-negative maps it is a monotone
#'   function of the mean and shows nothing that `"mean"` does not; it is offered
#'   because every implementation by the authors computes it.
#' - `"cv"` is the supplement's "CV", literally `Var / Mean`: an index of
#'   dispersion, not the standard deviation divided by the mean. It takes the
#'   sign of the mean, so it is negative where the mean is negative.
#' - `"sofi2"` to `"sofi4"` are lagged auto-cumulants of signed deviations.
#'   Noise that is independent from frame to frame does not enter their
#'   expectation. Orders 3 and 4 change sign with the emitters' duty cycle, so
#'   displays usually need `sign = "absolute"`.
#'
#' The "SOFI" outputs of the authors' Python, MATLAB and Fiji tools are other
#' statistics, so they do not match these values by design. The Python and
#' MATLAB tools use absolute deviations at zero lag, which makes their order 2
#' the variance without the first frame. The Fiji plugin uses absolute
#' deviations with lags that wrap around the ends of the acquisition. Their
#' variance divides by `M - 1` except in the Python tool. See
#' `vignette("method-concordance")`.
#'
#' **Interpretation.** `"var"`, `"cv"` and the SOFI statistics depend on how
#' the emitters blink and on the noise, and every map is a nonlinear function
#' of its frame. Treat the outputs as visual aids:
#' - Variance, `"cv"` and SOFI of per-frame MSSR maps, and higher MSSR orders,
#'   can show two maxima where there is a single emitter.
#' - When emitters are rarely on and dim, MSSR of nearly empty frames adds
#'   maxima to every statistic.
#' - With `amp > 1`, signal-free regions show a sub-pixel grid with the period
#'   `amp`; `diagnostics$mesh_index` reports its size there (see **Value**).
#' - The article recommends Fourier interpolation for temporal analysis. The
#'   package amplifies with the supplement's cubic kernel and mesh
#'   compensation instead; Fourier interpolation is not implemented.
#'
#' No drift, bleaching or background correction is applied. `"var"`, `"cv"`
#' and the SOFI statistics treat slow intensity trends (bleaching, drift, focus
#' changes) as fluctuation, so a large trend inflates them. Correct the frames
#' first, and record what was done; `diagnostics$trend` reports the ratio of the
#' raw intensity at the end and at the start of the selected frames.
#'
#' **Computation.** Every statistic is formed from centered deviations in
#' frame order, in a power-of-two scaled range so that products of up to four
#' deviations stay representable; the scaling is undone exactly at the end.
#' `"mean"` and `"tpm"` need one pass over the frames. The others need the mean
#' first and then a second pass. The per-frame maps are stored for it when they
#' fit (`diagnostics$path` `"stored"`), else every frame's MSSR is computed again
#' (`"recompute"`), which doubles the time. Both paths give the same values. With
#' `max_memory_bytes = NULL` the maps are stored when they take at most 2 GiB;
#' with a budget, they are stored when the estimate fits it, and a call whose
#' recompute path does not fit is refused. [mssr_estimate_resources()] reports
#' both estimates.
#'
#' Each frame must satisfy the checks of [mssr()]; errors name the frame.
#' Warnings of the frames' [mssr()] calls (negative values, skipped refinement
#' steps) are collected and given once per class, with the number of frames
#' concerned. A call-level `mssrscopR_warning_unqualified_order` is given for
#' orders above 3.
#'
#' @param x Either a plain numeric array with dimensions rows x columns x
#'   frames (rows = y, columns = x) and finite values, or an `mssr_stack` from
#'   `mssr_stack()`. For an `mssr_stack`, the per-frame arguments (`fwhm` to
#'   `rounding` and `max_output_pixels`) must not be given; the stored maps
#'   already fix them.
#' @param statistic One of `"mean"`, `"var"`, `"tpm"`, `"cv"`, `"sofi2"`,
#'   `"sofi3"` or `"sofi4"`. Required: none of them is a safe default.
#' @param fwhm,amp,order,intensity_normalize,mesh,grid,kernel,rounding,max_output_pixels
#'   Per-frame MSSR settings, exactly as in [mssr()]. `fwhm` is required for
#'   raw frames.
#' @param frames Optional contiguous, increasing frame indices; the lags need
#'   consecutive frames. Defaults to all frames.
#' @param sign For `"sofi2"`, `"sofi3"` and `"sofi4"`: `"signed"` (default)
#'   returns the cumulant, `"absolute"` its absolute value. Other statistics
#'   accept only `"signed"`.
#' @param background Optional logical matrix on the input grid that marks
#'   signal-free pixels for `diagnostics$mesh_index`. By default these are the
#'   pixels whose raw temporal mean is below the median of that mean.
#' @param max_memory_bytes Optional positive allocation-estimate budget (see
#'   **Computation**). This is not a hard process-memory cap.
#'
#' @return `mssr_temporal()` returns an `mssr_result` (result schema 1.1.0)
#'   with `role` `"temporal_<statistic>"`, `values` on the amplified grid and
#'   the same `transform` as [mssr()]. `parameters` holds the per-frame MSSR
#'   settings plus `statistic`, `frames` (the number of frames used),
#'   `first_frame` (the first frame's index in the original input), `sign`
#'   (`"not_applicable"` for statistics other than SOFI) and `definition`.
#'   `diagnostics` counts `degenerate_frames`, `warning_frames` and
#'   `order_steps_skipped` over the frames, and gives `zero_fraction`,
#'   `negative_fraction`, `mesh_index`, `mesh_region`, `trend` and the
#'   computation `path`. `mssr_stack()` returns an object of class
#'   `mssr_stack`: `values` (an array of the per-frame maps), `transform`,
#'   `parameters` (with `frames` and `first_frame`), `engine`, `diagnostics` (a
#'   data frame with one row per frame, including the raw frame's mean
#'   `input_mean`) and `input_mean` (the raw temporal mean on the input grid).
#'
#'   `diagnostics$mesh_index` measures the sub-pixel grid on signal-free input
#'   pixels only, because where structure is present the index mixes structure
#'   and grid. Each such input pixel contributes its whole `amp x amp` block of
#'   output pixels; the index is the range of the mean over the `amp x amp`
#'   sub-pixel phases, divided by the absolute mean of these blocks.
#'   `mesh_region` is `"below_median"` when the pixels are those whose raw
#'   temporal mean lies below its median (for an `mssr_stack`, the mean over all
#'   its frames), `"background"` for a supplied `background` mask, and
#'   `"not_computed"` for `amp = 1`. `mesh_index` is `NULL` for `amp = 1`, when
#'   no pixel qualifies, or when the mean of the blocks is 0.
#'
#'   `diagnostics$trend` is the mean of the raw frames over the whole field in
#'   the last tenth of the selected frames divided by that in the first tenth
#'   (at least one frame each); `NULL` when the first is 0. It is reported for
#'   every statistic and corrects nothing.
#' @references Torres-Garcia E, Pinto-Camara R, Linares A, et al. Extending
#'   resolution within a single imaging frame. *Nature Communications*
#'   2022;13:7452. \doi{10.1038/s41467-022-34693-9}
#'
#'   Dertinger T, Colyer R, Iyer G, Weiss S, Enderlein J. Fast,
#'   background-free, 3D super-resolution optical fluctuation imaging (SOFI).
#'   *PNAS* 2009;106:22287-22292. \doi{10.1073/pnas.0907866106}
#' @seealso [mssr()], [mssr_estimate_resources()], `vignette("temporal")`
#' @examples
#' # Two blinking emitters, 40 frames, Poisson noise (synthetic).
#' set.seed(1)
#' g <- expand.grid(r = 1:16, c = 1:16)
#' spot <- function(r0, c0) exp(-((g$r - r0)^2 + (g$c - c0)^2) / (2 * (3 / 2.3548)^2))
#' x <- array(0, c(16, 16, 40))
#' for (t in 1:40) {
#'   on <- stats::runif(2) < 0.4
#'   x[, , t] <- stats::rpois(256, 20 * (on[1] * spot(8, 7) + on[2] * spot(8, 10)) + 2)
#' }
#' s <- mssr_stack(x, fwhm = 3)
#' v <- mssr_temporal(s, "var")
#' v
#' m <- mssr_temporal(s, "mean")
#' all.equal(mssr_temporal(s, "tpm")$values, 40^2 * m$values^2)
#' @export
mssr_temporal <- function(x, statistic, fwhm, amp = 1L, order = 1L, intensity_normalize = TRUE,
                          mesh = TRUE, grid = c("extent", "endpoint"),
                          kernel = c("disk", "square"), rounding = c("half_even", "half_up"),
                          frames = NULL, sign = c("signed", "absolute"), background = NULL,
                          max_output_pixels = 5e7, max_memory_bytes = NULL) {
  call <- sys.call()
  if (missing(statistic)) {
    mssr_abort("parameter", sprintf("`statistic` is required: one of %s.",
                                    paste0("\"", temporal_statistics, "\"", collapse = ", ")),
               call)
  }
  statistic <- temporal_check_statistic(statistic, call)
  sign <- check_choice(sign, c("signed", "absolute"), "sign", call)
  sofi <- startsWith(statistic, "sofi")
  if (!sofi && sign != "signed") {
    mssr_abort("parameter", "`sign = \"absolute\"` applies only to the SOFI statistics.", call)
  }
  if (!sofi) sign <- "not_applicable"
  if (!is.null(max_memory_bytes)) {
    max_memory_bytes <- check_positive(max_memory_bytes, "max_memory_bytes", call)
  }
  supplied <- intersect(names(as.list(match.call()))[-1], temporal_frame_arguments)
  if (inherits(x, "mssr_stack")) {
    if (length(supplied)) {
      mssr_abort("parameter", sprintf(paste(
        "The maps of an `mssr_stack` are already computed; do not pass %s."
      ), paste0("`", supplied, "`", collapse = ", ")), call)
    }
    stack <- temporal_check_stack(x, call)
    index <- temporal_check_frames(frames, dim(stack$values)[3], statistic, call)
    region <- temporal_region(background, stack$input_mean, call)
    values <- stack$values
    # Stored maps are read, never recomputed.
    source <- function(t, pass) {
      f <- values[, , index[t]]
      dim(f) <- dim(values)[1:2]
      f
    }
    counts <- temporal_counts(stack$diagnostics[index, , drop = FALSE])
    reduced <- temporal_reduce(source, length(index), statistic, call)
    return(temporal_result(reduced, statistic, sign, length(index),
                           stack$parameters$first_frame + index[1] - 1L, stack$transform,
                           stack$parameters, stack$engine, counts, "stack", region,
                           temporal_trend(stack$diagnostics$input_mean[index])))
  }
  x <- temporal_check_array(x, call)
  if (missing(fwhm)) {
    mssr_abort("parameter",
               "`fwhm` is required (point-spread-function FWHM in input pixels).", call)
  }
  settings <- temporal_check_settings(x, fwhm, amp, order, intensity_normalize, mesh, grid,
                                      kernel, rounding, max_output_pixels, call)
  index <- temporal_check_frames(frames, dim(x)[3], statistic, call)
  region <- temporal_region(background, temporal_input_mean(x, index), call)
  estimate <- mssr_estimate_resources(dim(x)[1:2], settings$fwhm, settings$amp, settings$kernel,
                                      settings$rounding, settings$max_output_pixels,
                                      frames = length(index), statistic = statistic)
  path <- temporal_choose_path(statistic, estimate, max_memory_bytes, call)
  temporal_order_warning(settings$order)
  runner <- temporal_frame_runner(x, index, settings, store = path == "stored", call)
  reduced <- temporal_reduce(runner$frame, length(index), statistic, call)
  info <- runner$info()
  temporal_frame_warnings(info$diagnostics)
  temporal_result(reduced, statistic, sign, length(index), index[1], info$transform,
                  info$parameters, info$engine, temporal_counts(info$diagnostics), path, region,
                  temporal_trend(info$diagnostics$input_mean))
}

#' @rdname mssr_temporal
#' @export
mssr_stack <- function(x, fwhm, amp = 1L, order = 1L, intensity_normalize = TRUE, mesh = TRUE,
                       grid = c("extent", "endpoint"), kernel = c("disk", "square"),
                       rounding = c("half_even", "half_up"), frames = NULL,
                       max_output_pixels = 5e7, max_memory_bytes = NULL) {
  call <- sys.call()
  x <- temporal_check_array(x, call)
  if (missing(fwhm)) {
    mssr_abort("parameter",
               "`fwhm` is required (point-spread-function FWHM in input pixels).", call)
  }
  settings <- temporal_check_settings(x, fwhm, amp, order, intensity_normalize, mesh, grid,
                                      kernel, rounding, max_output_pixels, call)
  index <- temporal_check_frames(frames, dim(x)[3], "mean", call)
  estimate <- mssr_estimate_resources(dim(x)[1:2], settings$fwhm, settings$amp, settings$kernel,
                                      settings$rounding, settings$max_output_pixels,
                                      frames = length(index), statistic = "mean")
  if (!is.null(max_memory_bytes)) {
    max_memory_bytes <- check_positive(max_memory_bytes, "max_memory_bytes", call)
    if (estimate$stored_peak_bytes > max_memory_bytes) {
      mssr_abort("resource", "Estimated stack allocation exceeds `max_memory_bytes`.", call)
    }
  }
  temporal_order_warning(settings$order)
  runner <- temporal_frame_runner(x, index, settings, store = TRUE, call)
  for (t in seq_along(index)) runner$frame(t, 1L)
  info <- runner$info()
  temporal_frame_warnings(info$diagnostics)
  structure(list(
    values = runner$stack(),
    transform = info$transform,
    parameters = c(info$parameters, list(frames = length(index), first_frame = index[1])),
    engine = info$engine,
    diagnostics = info$diagnostics,
    input_mean = temporal_input_mean(x, index)
  ), class = "mssr_stack")
}

#' @export
print.mssr_stack <- function(x, ...) {
  d <- dim(x$values)
  p <- x$parameters
  cat(sprintf("<mssr_stack> %d frames of %d x %d MSSR maps (amp %d, order %d, fwhm %g px)\n",
              d[3], d[1], d[2], p$amp, p$order, p$fwhm))
  cat(sprintf("  frames %d to %d of the input; %d degenerate; engine %s\n", p$first_frame,
              p$first_frame + d[3] - 1L, sum(x$diagnostics$degenerate), x$engine$id))
  cat("  Use mssr_temporal() for a temporal statistic of the maps.\n")
  invisible(x)
}

temporal_check_statistic <- function(statistic, call) {
  if (!is.character(statistic) || is.object(statistic) || length(statistic) != 1L ||
        is.na(statistic) || !statistic %in% temporal_statistics) {
    mssr_abort("parameter", sprintf("`statistic` must be one of %s.",
                                    paste0("\"", temporal_statistics, "\"", collapse = ", ")),
               call)
  }
  statistic
}

temporal_check_array <- function(x, call) {
  if (is.data.frame(x) || !is.array(x) || length(dim(x)) != 3L || !plain_real(x)) {
    extra <- if (is.matrix(x)) " For one frame use mssr(), or add a frame dimension." else ""
    mssr_abort("input", paste0("`x` must be a plain integer or double array with dimensions ",
                               "rows x columns x frames.", extra), call)
  }
  d <- dim(x)
  if (any(d < 1L)) {
    mssr_abort("input", "`x` needs at least one row, one column and one frame.", call)
  }
  bad <- which(!is.finite(x))
  if (length(bad)) {
    frame <- (bad[1] - 1) %/% (as.double(d[1]) * d[2]) + 1
    mssr_abort("nonfinite", sprintf(paste(
      "Frame %d of `x` contains NA, NaN or infinite values; MSSR is undefined for them."
    ), as.integer(frame)), call)
  }
  storage.mode(x) <- "double"
  # Attributes can carry private acquisition metadata; keep only dimensions.
  attributes(x) <- list(dim = d)
  x
}

temporal_check_settings <- function(x, fwhm, amp, order, intensity_normalize, mesh, grid,
                                    kernel, rounding, max_output_pixels, call) {
  settings <- list(
    fwhm = check_positive(fwhm, "fwhm", call),
    amp = check_whole(amp, "amp", 1L, 64L, call),
    order = check_whole(order, "order", 0L, 10L, call),
    intensity_normalize = check_flag(intensity_normalize, "intensity_normalize", call),
    mesh = check_flag(mesh, "mesh", call),
    grid = check_choice(grid, c("extent", "endpoint"), "grid", call),
    kernel = check_choice(kernel, c("disk", "square"), "kernel", call),
    rounding = check_choice(rounding, c("half_even", "half_up"), "rounding", call),
    max_output_pixels = check_positive(max_output_pixels, "max_output_pixels", call)
  )
  if (settings$grid == "endpoint" && settings$amp > 1L && min(dim(x)[1:2]) < 2L) {
    mssr_abort("unsupported",
               "The endpoint grid needs at least two pixels along each axis when `amp > 1`.", call)
  }
  settings
}

temporal_check_frames <- function(frames, n, statistic, call) {
  if (is.null(frames)) {
    index <- seq_len(n)
  } else {
    ok <- plain_real(frames) && is.null(dim(frames)) && length(frames) >= 1L &&
      all(is.finite(frames)) && all(frames == round(frames)) && all(frames >= 1 & frames <= n) &&
      (length(frames) == 1L || all(diff(frames) == 1))
    if (!ok) {
      mssr_abort("parameter", sprintf(paste(
        "`frames` must be contiguous, increasing frame indices between 1 and %d."
      ), n), call)
    }
    index <- as.integer(frames)
  }
  needed <- temporal_min_frames[[statistic]]
  if (length(index) < needed) {
    mssr_abort("input", sprintf("Statistic \"%s\" needs at least %d frames; %d selected.",
                                statistic, needed, length(index)), call)
  }
  index
}

temporal_choose_path <- function(statistic, estimate, budget, call) {
  if (!is.null(budget) && estimate$recompute_peak_bytes > budget) {
    mssr_abort("resource", "Estimated allocation exceeds `max_memory_bytes`.", call)
  }
  if (statistic %in% c("mean", "tpm")) return("single_pass")
  store <- if (is.null(budget)) {
    estimate$stack_bytes <= temporal_default_stack_bytes
  } else {
    estimate$stored_peak_bytes <= budget
  }
  if (store) "stored" else "recompute"
}

temporal_order_warning <- function(order) {
  if (order > 3L) {
    mssr_warn("unqualified_order", paste(
      "Orders above 3 are outside the conservatively qualified numerical domain.",
      "High-order refinement can amplify rounding errors; independent checks found",
      "larger discrepancies at order 10. Lower orders have bounded synthetic evidence",
      "and are not guaranteed accurate for every input."
    ))
  }
}

# Computes frame maps on demand. Pass 1 records per-frame diagnostics and, when
# storing, keeps the maps; pass 2 reads stored maps or computes them again.
temporal_frame_runner <- function(x, index, settings, store, call) {
  state <- new.env(parent = emptyenv())
  state$first <- NULL
  state$values <- NULL
  n <- length(index)
  state$rows <- vector("list", n)
  compute <- function(t) {
    frame <- x[, , index[t]]
    dim(frame) <- dim(x)[1:2]
    warned <- new.env(parent = emptyenv())
    warned$classes <- character()
    res <- withCallingHandlers(
      tryCatch(
        do.call(mssr, c(list(x = frame), settings)),
        mssrscopR_error = function(e) {
          subclass <- sub("^mssrscopR_error_", "", class(e)[1])
          mssr_abort(subclass, sprintf("Frame %d: %s", index[t], conditionMessage(e)), call)
        }
      ),
      mssrscopR_warning = function(w) {
        warned$classes <- c(warned$classes, class(w)[1])
        invokeRestart("muffleWarning")
      }
    )
    list(result = res, warnings = unique(warned$classes), input_mean = mean(frame))
  }
  frame <- function(t, pass) {
    if (pass == 2L && store) {
      f <- state$values[, , t]
      dim(f) <- dim(state$values)[1:2]
      return(f)
    }
    out <- compute(t)
    res <- out$result
    if (pass == 1L) {
      if (is.null(state$first)) {
        state$first <- res
        if (store) state$values <- array(0, c(dim(res$values), n))
      }
      if (store) state$values[, , t] <- res$values
      d <- res$diagnostics
      state$rows[[t]] <- data.frame(
        frame = index[t], degenerate = d$degenerate, degenerate_reason = d$degenerate_reason,
        order_steps_skipped = as.integer(d$order_steps_skipped),
        negative_input = "mssrscopR_warning_negative" %in% out$warnings,
        zero_fraction = d$zero_fraction, input_mean = out$input_mean, stringsAsFactors = FALSE
      )
    }
    res$values
  }
  list(
    frame = frame,
    stack = function() state$values,
    info = function() {
      first <- state$first
      list(transform = first$transform, parameters = first$parameters, engine = first$engine,
           diagnostics = do.call(rbind, state$rows))
    }
  )
}

temporal_frame_warnings <- function(diagnostics) {
  negative <- sum(diagnostics$negative_input)
  if (negative > 0L) {
    mssr_warn("negative", sprintf(paste(
      "%d of %d frame(s) contain negative values. MSSR assumes non-negative intensities;",
      "their maps then depend on the data offset."
    ), negative, nrow(diagnostics)))
  }
  skipped <- diagnostics$order_steps_skipped
  if (any(skipped > 0L)) {
    mssr_warn("skipped_steps", sprintf(paste(
      "%d of %d frame(s) had undefined refinement steps (%d in total; e.g. impulses on an",
      "exactly zero background), which were skipped. Their maps are not the limit for",
      "slightly perturbed input."
    ), sum(skipped > 0L), nrow(diagnostics), sum(skipped)))
  }
}

temporal_counts <- function(diagnostics) {
  list(degenerate_frames = sum(diagnostics$degenerate),
       warning_frames = sum(diagnostics$negative_input | diagnostics$order_steps_skipped > 0L),
       order_steps_skipped = sum(diagnostics$order_steps_skipped))
}

# x * 2^k without an intermediate overflow or underflow of 2^k itself.
temporal_ldexp <- function(x, k) {
  while (k > 1000) {
    x <- x * 2^1000
    k <- k - 1000
  }
  while (k < -1000) {
    x <- x * 2^-1000
    k <- k + 1000
  }
  x * 2^k
}

# The engine's power-of-two exponent rule (R/engine.R).
temporal_exponent <- function(m) {
  max(-1074, min(1023, floor(log2(m))))
}

# Two-pass reduction over frames delivered in order by `frame(t, pass)`.
# Pass 1 forms the frame sum in units of 2^e, e the exponent of the largest
# magnitude seen so far; rescaling by powers of two is exact, so the sum equals
# one formed directly in the final units. Pass 2 forms the deviation products in
# those units, which keeps products of up to four deviations in range.
temporal_reduce <- function(frame, n, statistic, call = NULL) {
  e <- -Inf
  total <- NULL
  for (t in seq_len(n)) {
    f <- frame(t, 1L)
    m <- max(abs(f))
    if (m > 0) {
      et <- temporal_exponent(m)
      if (et > e) {
        if (!is.null(total) && is.finite(e)) total <- temporal_ldexp(total, e - et)
        e <- et
      }
    }
    unit <- if (is.finite(e)) e else 0
    scaled <- temporal_ldexp(f, -unit)
    total <- if (is.null(total)) scaled else total + scaled
  }
  if (!is.finite(e)) e <- 0
  center <- total / n
  degree <- temporal_degree[[statistic]]
  values <- switch(statistic,
    mean = center,
    tpm = total * total,
    temporal_deviations(frame, n, statistic, center, e)
  )
  values <- temporal_ldexp(values, degree * e)
  if (any(!is.finite(values))) {
    mssr_abort("numerical", paste("The temporal statistic exceeded the finite numeric range.",
                                  "Use a documented input rescaling before retrying."), call)
  }
  values
}

temporal_deviations <- function(frame, n, statistic, center, e) {
  acc <- matrix(0, nrow(center), ncol(center))
  keep <- c(var = 0L, cv = 0L, sofi2 = 1L, sofi3 = 2L, sofi4 = 3L)[[statistic]]
  lagged <- list()
  if (statistic == "sofi4") {
    a <- rep(list(acc), 7L)
    names(a) <- c("a0123", "a01", "a23", "a02", "a13", "a03", "a12")
  }
  for (t in seq_len(n)) {
    d <- temporal_ldexp(frame(t, 2L), -e) - center
    if (statistic %in% c("var", "cv")) {
      acc <- acc + d * d
    } else if (statistic == "sofi2" && t >= 2L) {
      acc <- acc + lagged[[1]] * d
    } else if (statistic == "sofi3" && t >= 3L) {
      acc <- acc + (lagged[[2]] * lagged[[1]]) * d
    } else if (statistic == "sofi4" && t >= 4L) {
      d0 <- lagged[[3]]
      d1 <- lagged[[2]]
      d2 <- lagged[[1]]
      a$a0123 <- a$a0123 + ((d0 * d1) * d2) * d
      a$a01 <- a$a01 + d0 * d1
      a$a23 <- a$a23 + d2 * d
      a$a02 <- a$a02 + d0 * d2
      a$a13 <- a$a13 + d1 * d
      a$a03 <- a$a03 + d0 * d
      a$a12 <- a$a12 + d1 * d2
    }
    if (keep > 0L) lagged <- c(list(d), lagged)[seq_len(min(t, keep))]
  }
  switch(statistic,
    var = acc / n,
    cv = {
      v <- acc / n
      ifelse(center == 0, 0, v / center)
    },
    sofi2 = acc / (n - 1),
    sofi3 = acc / (n - 2),
    sofi4 = {
      k <- n - 3
      a$a0123 / k - (a$a01 / k) * (a$a23 / k) - (a$a02 / k) * (a$a13 / k) -
        (a$a03 / k) * (a$a12 / k)
    }
  )
}

# Raw temporal mean of the selected frames on the input grid.
temporal_input_mean <- function(x, index) {
  d <- dim(x)
  m <- x[, , index]
  dim(m) <- c(d[1] * d[2], length(index))
  matrix(rowMeans(m), d[1], d[2])
}

# Signal-free input pixels for the mesh index: a supplied background mask, or
# the pixels whose raw temporal mean is below the median of that mean.
temporal_region <- function(background, input_mean, call) {
  if (is.null(background)) {
    return(list(mask = input_mean < stats::median(input_mean), rule = "below_median"))
  }
  if (!is.logical(background) || is.object(background) || !is.matrix(background) ||
        !identical(dim(background), dim(input_mean)) || anyNA(background) || !any(background)) {
    mssr_abort("parameter", sprintf(paste(
      "`background` must be a logical matrix of %d x %d input pixels without NA",
      "that marks at least one signal-free pixel."
    ), nrow(input_mean), ncol(input_mean)), call)
  }
  list(mask = unname(background), rule = "background")
}

# Range of the mean over the amp x amp sub-pixel phases of the selected input
# pixels' output blocks, divided by their absolute mean.
temporal_mesh_index <- function(values, amp, mask) {
  if (amp < 2L || !any(mask)) return(NULL)
  idx <- which(mask, arr.ind = TRUE)
  phase_means <- numeric(amp^2)
  for (p in seq_len(amp)) {
    for (q in seq_len(amp)) {
      cells <- cbind((idx[, 1] - 1L) * amp + p, (idx[, 2] - 1L) * amp + q)
      phase_means[(p - 1L) * amp + q] <- mean(values[cells])
    }
  }
  center <- mean(phase_means)
  if (!is.finite(center) || center == 0) return(NULL)
  index <- (max(phase_means) - min(phase_means)) / abs(center)
  if (is.finite(index)) as.double(index) else NULL
}

# Mean of the last tenth of the frames over the mean of the first tenth, on the
# raw frames' field means.
temporal_trend <- function(frame_means) {
  n <- length(frame_means)
  k <- max(1L, n %/% 10L)
  first <- mean(frame_means[seq_len(k)])
  last <- mean(frame_means[seq.int(n - k + 1L, n)])
  if (!is.finite(first) || first == 0) return(NULL)
  ratio <- last / first
  if (is.finite(ratio)) as.double(ratio) else NULL
}

temporal_result <- function(values, statistic, sign, n_frames, first_frame, transform,
                            frame_parameters, engine, counts, path, region, trend) {
  if (sign == "absolute") values <- abs(values)
  dim(values) <- transform$output_dim
  storage.mode(values) <- "double"
  p <- frame_parameters[c("fwhm", "amp", "order", "intensity_normalize", "mesh", "kernel",
                          "rounding", "half_size")]
  n_offsets <- if (p$kernel == "square") {
    (2 * p$half_size + 1)^2 - 1
  } else {
    sum(2 * floor(sqrt(pmax(0, p$half_size^2 - (-p$half_size:p$half_size)^2))) + 1) - 1
  }
  structure(list(
    values = values,
    role = paste0("temporal_", statistic),
    transform = transform,
    parameters = c(p, list(statistic = statistic, frames = as.integer(n_frames),
                           first_frame = as.integer(first_frame), sign = sign,
                           definition = temporal_definition)),
    engine = engine,
    diagnostics = list(
      degenerate_frames = as.integer(counts$degenerate_frames),
      warning_frames = as.integer(counts$warning_frames),
      order_steps_skipped = as.integer(counts$order_steps_skipped),
      zero_fraction = mean(values == 0), negative_fraction = mean(values < 0),
      mesh_index = temporal_mesh_index(values, p$amp, region$mask),
      mesh_region = if (p$amp > 1L) region$rule else "not_computed", trend = trend, path = path,
      n_offsets = as.integer(n_offsets), quantitative = FALSE,
      qualification_scope = "bounded_synthetic_domain", high_order_unqualified = p$order > 3L
    ),
    schema_version = temporal_schema_version,
    input = mssr_result_contract()$input,
    evidence = mssr_result_contract()$evidence
  ), class = "mssr_result")
}

temporal_check_stack <- function(x, call) {
  fail <- function(message) mssr_abort("input", message, call)
  if (!identical(class(x), "mssr_stack") || !result_plain_list(unclass(x)) ||
        !setequal(names(x), c("values", "transform", "parameters", "engine", "diagnostics",
                              "input_mean"))) {
    fail("`x` is not a complete `mssr_stack`.")
  }
  v <- x$values
  if (typeof(v) != "double" || length(dim(v)) != 3L ||
        !identical(attributes(v), list(dim = dim(v))) || any(!is.finite(v))) {
    fail("The maps of an `mssr_stack` must be a finite plain double array.")
  }
  first <- v[, , 1]
  dim(first) <- dim(v)[1:2]
  probe <- structure(list(values = first, transform = x$transform), class = "mssr_result")
  check_result(probe, call)
  p <- x$parameters
  frame_fields <- c("fwhm", "amp", "order", "intensity_normalize", "mesh", "kernel",
                    "rounding", "half_size")
  if (!result_plain_list(p) || !setequal(names(p), c(frame_fields, "frames", "first_frame"))) {
    fail("Unexpected or missing `mssr_stack` parameters.")
  }
  validate_frame_parameters(p, x$transform, call)
  check_whole(p$frames, "frames", 1L, .Machine$integer.max, call)
  check_whole(p$first_frame, "first_frame", 1L, .Machine$integer.max, call)
  d <- x$diagnostics
  columns <- c("frame", "degenerate", "degenerate_reason", "order_steps_skipped",
               "negative_input", "zero_fraction", "input_mean")
  if (!is.data.frame(d) || !identical(names(d), columns) || nrow(d) != dim(v)[3] ||
        p$frames != dim(v)[3] || !is.logical(d$degenerate) || anyNA(d$degenerate) ||
        !is.logical(d$negative_input) || anyNA(d$negative_input) ||
        !plain_real(d$order_steps_skipped) || anyNA(d$order_steps_skipped) ||
        !plain_real(d$input_mean) || any(!is.finite(d$input_mean))) {
    fail("Inconsistent `mssr_stack` diagnostics.")
  }
  m <- x$input_mean
  grid_dim <- list(dim = as.integer(x$transform$input_dim))
  if (typeof(m) != "double" || !identical(attributes(m), grid_dim) || any(!is.finite(m))) {
    fail("The input mean of an `mssr_stack` must be a finite matrix on the input grid.")
  }
  e <- x$engine
  if (!result_plain_list(e) || !setequal(names(e), c("id", "package_version", "method")) ||
        !all(vapply(e, result_scalar_text, logical(1)))) {
    fail("Invalid `mssr_stack` engine identity.")
  }
  x
}
