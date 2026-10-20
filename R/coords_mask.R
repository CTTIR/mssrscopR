#' Output pixel-centre coordinates
#'
#' Coordinates of the output pixel centres of an [mssr()] result, in input-pixel
#' units (input pixel centres at 1..n). Use them to overlay results on the input
#' grid; amplification adds samples, not independent observations.
#'
#' @param result An `mssr_result`.
#' @return A list with numeric vectors `row` and `col`.
#' @examples
#' r <- mssr(matrix(runif(20), 4, 5), fwhm = 2, amp = 2)
#' mssr_coords(r)$col
#' @export
mssr_coords <- function(result) {
  call <- sys.call()
  if (!inherits(result, "mssr_result")) mssr_abort("input", "`result` must be an mssr_result.", call)
  tr <- result$transform
  list(row = mssr_grid_positions(tr$input_dim[1], tr$amp, tr$grid),
       col = mssr_grid_positions(tr$input_dim[2], tr$amp, tr$grid))
}

#' Structural mask on the input grid
#'
#' Selects exactly `ceiling(fraction * n)` pixels of a region with the highest
#' MSSR values, on the **input** grid (amplified results are averaged back over
#' each input pixel's children; this needs `grid = "extent"`). Ties are broken by
#' a seeded random permutation without changing the caller's random-number
#' state. MSSR maps often contain many exact zeros, so check the returned
#' `tie_fraction`: a large value means much of the selection is random.
#'
#' Use the mask to measure the **original** data, e.g. `mean(x[mask])`. A mask
#' changes which pixels are measured; it does not make MSSR values quantitative,
#' and selecting pixels by MSSR is not known to improve any downstream analysis.
#'
#' @param result An `mssr_result`.
#' @param fraction Fraction of the region to keep, in (0, 1].
#' @param region Optional logical matrix with the input dimensions; defaults to
#'   the whole frame.
#' @param seed Whole number used for tie-breaking.
#' @return A logical matrix (input dimensions) with attributes `coverage`,
#'   `tie_fraction` (share of region pixels tied at the selection threshold) and
#'   `n_region`.
#' @examples
#' x <- matrix(runif(400), 20, 20)
#' m <- mssr_mask(mssr(x, fwhm = 3), fraction = 0.5)
#' attr(m, "tie_fraction")
#' mean(x[m])
#' @export
mssr_mask <- function(result, fraction = 0.5, region = NULL, seed = 1L) {
  call <- sys.call()
  if (!inherits(result, "mssr_result")) mssr_abort("input", "`result` must be an mssr_result.", call)
  tr <- result$transform
  if (tr$amp > 1L && tr$grid != "extent") {
    mssr_abort("unsupported", "Masks are defined on the input grid only for results computed with grid = 'extent'.", call)
  }
  if (!is.numeric(fraction) || length(fraction) != 1L || !is.finite(fraction) || fraction <= 0 || fraction > 1) {
    mssr_abort("parameter", "`fraction` must be a single number in (0, 1].", call)
  }
  seed <- check_whole(seed, "seed", -.Machine$integer.max, .Machine$integer.max, call)
  score <- if (tr$amp > 1L) mssr_block_mean(result$values, tr$amp) else result$values
  if (is.null(region)) region <- matrix(TRUE, nrow(score), ncol(score))
  if (!is.logical(region) || !identical(dim(region), dim(score)) || anyNA(region) || !any(region)) {
    mssr_abort("parameter", "`region` must be a logical matrix with the input dimensions, without NA, selecting at least one pixel.", call)
  }
  idx <- which(region)
  s <- score[idx]
  # Seeded tie-breaking without touching the caller's RNG state.
  tiebreak <- withr::with_seed(seed, stats::runif(length(s)))
  o <- order(s, tiebreak, decreasing = TRUE)
  k <- ceiling(fraction * length(s))
  mask <- matrix(FALSE, nrow(score), ncol(score))
  mask[idx[o[seq_len(k)]]] <- TRUE
  structure(mask, coverage = k / length(s), tie_fraction = mean(s == s[o[k]]), n_region = length(s))
}
