#' Check the engine against the bundled synthetic fixtures
#'
#' Recomputes every bundled synthetic fixture and compares it with the stored
#' expected output. The fixtures are small non-square, impulse, constant, zero,
#' point-pair, ring and ramp images. The expected outputs were produced by the
#' package's engine definition, so this is a regression check of the
#' installation, not an independent validation of the method or of any
#' application.
#'
#' A fixture passes when its dimensions match and
#' `max(abs(got - expected)) <= tolerance * (1 + max(abs(expected)))`.
#'
#' @param tolerance Single non-negative number.
#' @return A data frame with one row per fixture (`fixture_id`, parameters,
#'   `max_abs_error`, `passed`), with attribute `all_passed` (`TRUE` or `FALSE`).
#' @examples
#' st <- mssr_selftest()
#' attr(st, "all_passed")
#' @export
mssr_selftest <- function(tolerance = 1e-10) {
  call <- sys.call()
  tolerance <- check_positive(tolerance, "tolerance", call, allow_zero = TRUE)
  dir <- system.file("extdata", "fixtures", package = "mssrscopR", mustWork = TRUE)
  run_fixtures(dir, tolerance)
}

# Internal: recompute the fixtures listed in `dir`/index.csv.
run_fixtures <- function(dir, tolerance) {
  idx <- utils::read.csv(file.path(dir, "index.csv"), stringsAsFactors = FALSE)
  rd <- function(f) unname(as.matrix(utils::read.csv(file.path(dir, f), header = FALSE)))
  out <- do.call(rbind, lapply(seq_len(nrow(idx)), function(i) {
    f <- idx[i, ]
    got <- mssr(rd(f$input_file), fwhm = f$fwhm, amp = f$amp, order = f$order,
                intensity_normalize = f$intensity_normalize, mesh = f$mesh, grid = f$grid,
                kernel = f$kernel, rounding = f$rounding)$values
    expected <- rd(f$expected_file)
    same_dim <- identical(dim(got), dim(expected))
    abs_err <- if (same_dim) max(abs(got - expected)) else Inf
    data.frame(fixture_id = f$fixture_id, amp = f$amp, fwhm = f$fwhm, order = f$order,
               intensity_normalize = f$intensity_normalize, grid = f$grid, kernel = f$kernel,
               max_abs_error = abs_err,
               passed = isTRUE(same_dim && abs_err <= tolerance * (1 + max(abs(expected)))),
               stringsAsFactors = FALSE)
  }))
  attr(out, "all_passed") <- isTRUE(all(out$passed))
  out
}
