test_that("masks select exactly the requested number of pixels", {
  x <- matrix(stats::runif(100), 10, 10)
  r <- mssr(x, fwhm = 3)
  for (f in c(0.07, 0.14, 0.28, 0.5, 1)) {
    expect_equal(sum(mssr_mask(r, fraction = f)), round(f * 100))
  }
  m2 <- mssr_mask(mssr(matrix(stats::runif(400), 20, 20), fwhm = 3, amp = 2), fraction = 0.25)
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
  expect_identical(attr(mssr_mask(r, fraction = 1), "tie_fraction"), 0)
})

test_that("masks respect a region and report the share decided by tie-breaking", {
  z <- matrix(0, 10, 10)
  z[5, 5] <- 1
  r <- mssr(z, fwhm = 3)
  region <- matrix(FALSE, 10, 10)
  region[3:8, 3:8] <- TRUE
  m <- mssr_mask(r, fraction = 0.5, region = region)
  expect_false(any(m & !region))
  expect_equal(sum(m), 18L)
  n_positive <- sum(as.matrix(r)[region] > 0)
  expect_equal(attr(m, "tie_fraction"), (18 - n_positive) / 18)
})

test_that("tie-breaking is seeded and leaves the caller's RNG state untouched", {
  z <- matrix(0, 10, 10)
  z[5, 5] <- 1
  r <- mssr(z, fwhm = 3)
  set.seed(42)
  before <- .Random.seed
  a <- mssr_mask(r, seed = 7)
  expect_identical(.Random.seed, before)
  expect_identical(a, mssr_mask(r, seed = 7))
  expect_false(identical(c(a), c(mssr_mask(r, seed = 8))))
})

test_that("mask arguments are validated", {
  r <- mssr(matrix(stats::runif(100), 10, 10), fwhm = 3)
  expect_error(mssr_mask(r, fraction = 0), class = "mssrscopR_error_parameter")
  expect_error(mssr_mask(r, region = matrix(TRUE, 5, 5)), class = "mssrscopR_error_parameter")
  endpoint <- mssr(matrix(stats::runif(100), 10, 10), fwhm = 3, amp = 2, grid = "endpoint")
  expect_error(mssr_mask(endpoint), class = "mssrscopR_error_unsupported")
  expect_error(mssr_mask("x"), class = "mssrscopR_error_input")
})
