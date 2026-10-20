test_that("masks select exactly the requested fraction on the input grid", {
  x <- matrix(stats::runif(400), 20, 20)
  m <- mssr_mask(mssr(x, fwhm = 3), fraction = 0.5)
  expect_equal(dim(m), dim(x))
  expect_equal(sum(m), 200L)
  expect_equal(attr(m, "coverage"), 0.5)
  m2 <- mssr_mask(mssr(x, fwhm = 3, amp = 2), fraction = 0.25)
  expect_equal(dim(m2), dim(x))
  expect_equal(sum(m2), 100L)
})

test_that("masks respect a region and report ties", {
  x <- matrix(0, 10, 10)
  x[5, 5] <- 1
  region <- matrix(FALSE, 10, 10)
  region[3:8, 3:8] <- TRUE
  m <- mssr_mask(mssr(x, fwhm = 3), fraction = 0.5, region = region)
  expect_false(any(m & !region))
  expect_equal(sum(m), 18L)
  expect_gt(attr(m, "tie_fraction"), 0.5)
})

test_that("tie-breaking is seeded and leaves the caller's RNG state untouched", {
  x <- matrix(0, 10, 10)
  x[5, 5] <- 1
  r <- mssr(x, fwhm = 3)
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
  expect_error(mssr_mask(mssr(matrix(stats::runif(100), 10, 10), fwhm = 3, amp = 2, grid = "endpoint")),
               class = "mssrscopR_error_unsupported")
  expect_error(mssr_mask("x"), class = "mssrscopR_error_input")
})
