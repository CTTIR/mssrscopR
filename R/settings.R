#' Extract resolved computation settings from a result
#'
#' Validates a result and returns arguments that can be passed to [mssr()]
#' with the retained original input. The grid is included explicitly; derived
#' kernel sizes and resource limits are not computation settings returned here.
#'
#' @param result A result returned by [mssr()], [mssr_temporal()] or
#'   [mssr_read_result()].
#' @return A named list containing `fwhm`, `amp`, `order`,
#'   `intensity_normalize`, `mesh`, `grid`, `kernel` and `rounding`. For a
#'   temporal result it also starts with `statistic` and `frames` (the frame
#'   indices of the original input), plus `sign` for the SOFI statistics, so
#'   that it can be passed to [mssr_temporal()] together with the original raw
#'   frames (not with an `mssr_stack`, which refuses per-frame settings).
#' @details These are resolved settings, not the original call. For example,
#'   `mesh` is `FALSE` when amplification is 1 because it had no effect.
#'   Records from a different numerical engine are refused: this helper does
#'   not migrate historical engines. A legacy result schema is accepted when
#'   its engine matches and its stored contract validates.
#'
#'   Retain the original input, preprocessing and channel/frame selection,
#'   acquisition information, and mask region, fraction and seed separately.
#'   Result files do not contain them. Set resource budgets explicitly when
#'   recomputing. Preserve the package and runtime environment, check engine
#'   identity, and compare recomputed values; matching settings alone do not
#'   guarantee identical arithmetic across environments or versions.
#'   This function needs no optional packages and does not modify the result.
#' @examples
#' x <- matrix(seq_len(35), 5, 7)
#' result <- mssr(x, fwhm = 2.5, amp = 2, grid = "endpoint")
#' replay <- do.call(mssr, c(list(x = x, max_memory_bytes = 1024^3),
#'                           mssr_settings(result)))
#' identical(replay$values, result$values)
#' @export
mssr_settings <- function(result) {
  mssr_validate_result(result)
  if (!identical(result$engine$id, "mssr_r_rev3")) {
    mssr_abort("unsupported", paste(
      "Settings replay requires the current engine 'mssr_r_rev3'.",
      "Use the original package environment for historical engine records;",
      "no engine migration is inferred."
    ), sys.call())
  }
  p <- result$parameters
  settings <- list(
    fwhm = p$fwhm, amp = p$amp, order = p$order,
    intensity_normalize = p$intensity_normalize, mesh = p$mesh,
    grid = result$transform$grid, kernel = p$kernel, rounding = p$rounding
  )
  if (!result_is_temporal(result)) return(settings)
  frames <- seq.int(p$first_frame, length.out = p$frames)
  temporal <- list(statistic = p$statistic, frames = frames)
  if (p$sign != "not_applicable") temporal$sign <- p$sign
  c(temporal, settings)
}
