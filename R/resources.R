#' Estimate whole-frame MSSR resources
#'
#' Reports a conservative allocation model before allocating an output frame.
#' The estimate includes a 192 MiB runtime allowance, 64 double buffers per
#' output pixel, five input buffers, and reflected-index/offset storage.
#' It is a planning guard, not a hard process-memory limit: R, loaded packages,
#' retained objects, garbage collection and the allocator can change peak RSS.
#' Calibration evidence covers the workload ladder described in the package
#' documentation; estimates outside that ladder are extrapolations.
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
  peak <- 192 * 1024^2 + 8 * (64 * n_out + 5 * prod(input_dim)) +
    8 * (2 * hs + 1) * sum(output_dim) + 64 * n_offsets
  list(input_dim = as.integer(input_dim), output_dim = output_dim,
       output_pixels = n_out, half_size = hs, n_offsets = n_offsets,
       estimated_work = work, estimated_peak_bytes = peak,
       model = "whole_frame_buffers_v1", hard_limit = FALSE,
       limitation = "Allocation estimate; retained objects and runtime can increase process RSS.")
}
