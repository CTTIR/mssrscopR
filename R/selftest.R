#' Check the engine against the bundled synthetic fixtures
#'
#' Recomputes every bundled synthetic fixture (small non-square, impulse,
#' constant, zero, point-pair, ring and ramp images with known expected
#' outputs) and reports the maximum absolute and relative errors. Use it to
#' confirm that an installation reproduces the validated engine definition
#' `mssr_r_rev1` on the current platform. It does not validate any
#' application.
#'
#' @param tolerance Maximum allowed absolute or relative error.
#' @return A data frame with one row per fixture (`fixture_id`, parameters,
#'   `max_abs_error`, `max_rel_error`, `passed`), with attribute `all_passed`.
#' @examples
#' st <- mssr_selftest()
#' attr(st, "all_passed")
#' @export
mssr_selftest <- function(tolerance = 1e-10) {
  dir <- system.file("extdata", "fixtures", package = "mssrscopR", mustWork = TRUE)
  idx <- utils::read.csv(file.path(dir, "index.csv"), stringsAsFactors = FALSE)
  rd <- function(f) unname(as.matrix(utils::read.csv(file.path(dir, f), header = FALSE)))
  out <- do.call(rbind, lapply(seq_len(nrow(idx)), function(i) {
    f <- idx[i, ]
    got <- mssr(rd(f$input_file), fwhm = f$fwhm, amp = f$amp, order = f$order,
                intensity_normalize = f$intensity_normalize, grid = f$grid)$values
    exp <- rd(f$expected_file)
    same_dim <- identical(dim(got), dim(exp))
    abs_err <- if (same_dim) max(abs(got - exp)) else Inf
    rel_err <- if (same_dim) abs_err / max(max(abs(exp)), .Machine$double.xmin) else Inf
    data.frame(fixture_id = f$fixture_id, amp = f$amp, fwhm = f$fwhm, order = f$order,
               intensity_normalize = f$intensity_normalize, grid = f$grid,
               max_abs_error = abs_err, max_rel_error = rel_err,
               passed = same_dim && (abs_err <= tolerance || rel_err <= tolerance), stringsAsFactors = FALSE)
  }))
  attr(out, "all_passed") <- all(out$passed)
  out
}
