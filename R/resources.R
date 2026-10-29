#' Estimate whole-frame MSSR resources
#'
#' Reports a conservative allocation model before allocating an output frame.
#' The estimate includes a 128 MiB runtime allowance, 24 double buffers per
#' output pixel, six per input pixel, and reflected-index and offset storage.
#' It was calibrated on the peak resident memory of fresh R processes on one
#' Linux machine over a workload ladder of 65,536 to 16,777,216 output pixels
#' (amplification 1 to 4, orders 0 to 3, mesh and intensity weighting on and
#' off, disk and square kernels), where it exceeded every measured peak by 30
#' to 220 percent; the margin is smallest for order 3 with mesh and weighting,
#' and garbage-collection timing changes peaks from run to run.
#' It is a planning guard, not a hard process-memory limit: other platforms,
#' loaded packages, retained objects, garbage collection and the allocator can
#' change peak RSS, and estimates outside that ladder are extrapolations.
#'
#' @param input_dim Two positive whole numbers: input rows and columns.
#' @param fwhm,amp,kernel,rounding,max_output_pixels As in [mssr()].
#' @return A list with input/output dimensions, pixels, offsets, estimated work,
#'   estimated peak bytes, model ID, and limitations.
#' @export
#' @examples
#' mssr_estimate_resources(c(128, 192), fwhm = 3, amp = 2)
mssr_estimate_resources <- function(input_dim, fwhm, amp = 1L,
                                    kernel = c("disk", "square"),
                                    rounding = c("half_even", "half_up"),
                                    max_output_pixels = 5e7) {
  call <- sys.call()
  if (!plain_real(input_dim) || !is.null(dim(input_dim)) || length(input_dim) != 2L ||
        any(!is.finite(input_dim)) || any(input_dim < 1 | input_dim != round(input_dim)) ||
        any(input_dim > .Machine$integer.max)) {
    mssr_abort("parameter", "`input_dim` needs positive integer row and column counts.", call)
  }
  fwhm <- check_positive(fwhm, "fwhm", call)
  amp <- check_whole(amp, "amp", 1L, 64L, call)
  kernel <- check_choice(kernel, c("disk", "square"), "kernel", call)
  rounding <- check_choice(rounding, c("half_even", "half_up"), "rounding", call)
  limit <- check_positive(max_output_pixels, "max_output_pixels", call)
  output_dim <- as.double(input_dim) * amp
  n_out <- prod(output_dim)
  hs <- mssr_half_size(fwhm, amp, rounding)
  if (hs > 1000 || any(output_dim > .Machine$integer.max) || n_out > limit) {
    mssr_abort("resource", "The requested grid or neighborhood exceeds the resource limits.", call)
  }
  # Count offsets without constructing a potentially four-million-row grid.
  n_offsets <- if (kernel == "square") {
    (2 * hs + 1)^2 - 1
  } else {
    sum(2 * floor(sqrt(pmax(0, hs^2 - (-hs:hs)^2))) + 1) - 1
  }
  work <- n_out * n_offsets
  if (work > 1e10) {
    mssr_abort("resource", "Estimated neighborhood work exceeds 1e10 operations.", call)
  }
  # Calibrated on peak RSS of the compiled engine (see the help page).
  peak <- 128 * 1024^2 + 8 * (24 * n_out + 6 * prod(input_dim)) +
    4 * (2 * hs + 1) * sum(output_dim) + 64 * n_offsets
  list(input_dim = as.integer(input_dim), output_dim = output_dim,
       output_pixels = n_out, half_size = hs, n_offsets = n_offsets,
       estimated_work = work, estimated_peak_bytes = peak,
       model = "whole_frame_buffers_v2", hard_limit = FALSE,
       limitation = "Allocation estimate; retained objects and runtime can increase process RSS.")
}
