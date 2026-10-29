test_that("masks select exactly the requested number of pixels", {
  x <- matrix(stats::runif(100), 10, 10)
  r <- mssr(x, fwhm = 3)
  for (f in c(0.07, 0.14, 0.28, 0.5, 1)) {
    expect_equal(sum(mask_quietly(r, fraction = f)), round(f * 100))
  }
  m2 <- mask_quietly(mssr(matrix(stats::runif(400), 20, 20), fwhm = 3, amp = 2), fraction = 0.25)
  expect_equal(dim(m2), c(20L, 20L))
  expect_equal(sum(m2), 100L)
})

test_that("without ties the mask holds the top-scoring pixels", {
  x <- matrix(stats::runif(400), 20, 20)
  r <- mssr(x, fwhm = 3, intensity_normalize = FALSE)
  v <- as.matrix(r)
  positive <- v > 0
  m <- mssr_mask(r, fraction = 0.1, region = positive)
  expect_gte(min(v[m]), max(v[positive & !m]))
  expect_identical(attr(m, "tie_fraction"), 0)
  expect_identical(attr(mask_quietly(r, fraction = 1), "tie_fraction"), 0)
})

test_that("masks respect a region and report the share decided by tie-breaking", {
  z <- matrix(0, 10, 10)
  z[5, 5] <- 1
  expect_warning(r <- mssr(z, fwhm = 3), class = "mssrscopR_warning_skipped_steps")
  region <- matrix(FALSE, 10, 10)
  region[3:8, 3:8] <- TRUE
  expect_warning(m <- mssr_mask(r, fraction = 0.5, region = region),
                 class = "mssrscopR_warning_mask_ties")
  expect_false(any(m & !region))
  expect_equal(sum(m), 18L)
  n_positive <- sum(as.matrix(r)[region] > 0)
  expect_equal(attr(m, "tie_fraction"), (18 - n_positive) / 18)
})

test_that("tie-breaking is seeded and leaves the caller's RNG state untouched", {
  z <- matrix(0, 10, 10)
  z[5, 5] <- 1
  expect_warning(r <- mssr(z, fwhm = 3), class = "mssrscopR_warning_skipped_steps")
  set.seed(42)
  before <- .Random.seed
  a <- mask_quietly(r, fraction = 0.5, seed = 7)
  expect_identical(.Random.seed, before)
  expect_identical(a, mask_quietly(r, fraction = 0.5, seed = 7))
  expect_false(identical(c(a), c(mask_quietly(r, fraction = 0.5, seed = 8))))
})

test_that("mask arguments are validated", {
  r <- mssr(matrix(stats::runif(100), 10, 10), fwhm = 3)
  expect_error(mssr_mask(r, fraction = 0), class = "mssrscopR_error_parameter")
  expect_error(mssr_mask(r), "is required", class = "mssrscopR_error_parameter")
  expect_error(mssr_mask(r, fraction = 0.5, region = matrix(TRUE, 5, 5)),
               class = "mssrscopR_error_parameter")
  endpoint <- mssr(matrix(stats::runif(100), 10, 10), fwhm = 3, amp = 2, grid = "endpoint")
  expect_error(mssr_mask(endpoint), class = "mssrscopR_error_unsupported")
  expect_error(mssr_mask("x"), class = "mssrscopR_error_input")
})

test_that("cut_relative exposes masks that reach into near-zero scores", {
  g <- expand.grid(r = 1:31, c = 1:41)
  spot <- function(r0, c0) exp(-((g$r - r0)^2 + (g$c - c0)^2) / (2 * (3 / 2.3548)^2))
  x <- matrix(spot(16, 18) + spot(16, 21) + 0.05, 31, 41)
  r <- mssr(x, fwhm = 3, amp = 2)
  small <- expect_no_warning(mssr_mask(r, fraction = 0.01))
  expect_warning(wide <- mssr_mask(r, fraction = 0.2), class = "mssrscopR_warning_mask_ties")
  expect_gt(attr(small, "cut_relative"), 0.01)
  expect_lt(attr(wide, "cut_relative"), 1e-6)
  # Derive boundary ties independently from each input pixel's four children.
  # Stable arithmetic may leave exact zeros where subtraction used to leave
  # positive rounding noise, so this scene need not have zero boundary ties.
  v <- r$values
  rows <- seq.int(1L, nrow(v), 2L)
  cols <- seq.int(1L, ncol(v), 2L)
  score <- (v[rows, cols] + v[rows + 1L, cols] +
              v[rows, cols + 1L] + v[rows + 1L, cols + 1L]) / 4
  boundary <- min(score[wide])
  tied_selected <- sum(score[wide] == boundary)
  tied_excluded <- sum(score[!wide] == boundary)
  expected <- if (tied_excluded > 0) tied_selected / sum(wide) else 0
  expect_identical(attr(wide, "tie_fraction"), expected)
  expect_identical(attr(mssr_mask(r, fraction = 1 / 1271), "cut_relative"), 1)
  flat <- mask_quietly(mssr(matrix(1, 4, 4), fwhm = 2), fraction = 0.5)
  expect_identical(attr(flat, "cut_relative"), 0)
})

test_that("distinct tiny positive mask scores are not reported as ties", {
  r <- mssr(matrix(1, 4, 4), fwhm = 2)
  r$values <- matrix(c(1, 1e-8, 1e-16, rep(0, 13)), 4, 4)
  positive <- mask_quietly(r, fraction = 3 / 16)
  expect_identical(which(positive), 1:3)
  expect_identical(attr(positive, "cut_relative"), 1e-16)
  expect_identical(attr(positive, "tie_fraction"), 0)
  into_zeros <- mask_quietly(r, fraction = 4 / 16)
  expect_identical(attr(into_zeros, "cut_relative"), 0)
  expect_identical(attr(into_zeros, "tie_fraction"), 1 / 4)
})

test_that("masks do not depend on the caller's RNG kind", {
  r <- mssr(matrix(c(0, 1, 1, 0, 1, 1, 0, 1, 0), 3), fwhm = 2)
  ref <- mask_quietly(r, fraction = 0.5, seed = 7)
  withr::local_seed(1, .rng_kind = "L'Ecuyer-CMRG")
  expect_identical(mask_quietly(r, fraction = 0.5, seed = 7), ref)
  expect_identical(RNGkind()[1], "L'Ecuyer-CMRG")
})

test_that("masks dominated by ties or near-zero scores warn", {
  z <- matrix(0, 10, 10)
  z[5, 5] <- 1
  r <- suppressWarnings(mssr(z, fwhm = 3))
  # Mostly exact zeros: tie-breaking decides most of the selection.
  expect_warning(m <- mssr_mask(r, fraction = 0.5), class = "mssrscopR_warning_mask_ties")
  expect_gt(attr(m, "tie_fraction"), 0.5)
  expect_identical(sum(m), 50L)
  # Distinct but negligible scores: no ties, yet the cut is near zero.
  tiny <- r
  tiny$values <- matrix(c(1, 1e-8, 1e-12, 1e-14, seq(1e-15, 1e-16, length.out = 96)), 10, 10)
  expect_warning(t2 <- mssr_mask(tiny, fraction = 0.1), class = "mssrscopR_warning_mask_ties")
  expect_identical(attr(t2, "tie_fraction"), 0)
  expect_lte(attr(t2, "cut_relative"), 1e-6)
  # A share below the positive one stays on the structure without a warning.
  x <- matrix(stats::runif(400), 20, 20)
  rx <- mssr(x, fwhm = 3)
  share <- mean(as.matrix(rx) > 0)
  expect_no_warning(mssr_mask(rx, fraction = share / 4))
})
