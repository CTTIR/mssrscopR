precision_frame <- function() {
  matrix(c(1, 4, 2, 7, 11, 3, 5, 2, 6, 9, 4, 8, 3, 10, 5, 2, 1, 6, 4, 7), 4, 5)
}

test_that("structure maps retain scale invariance across the numeric range", {
  x <- precision_frame()
  for (amp in c(1L, 2L)) {
    for (order in c(0L, 2L)) {
      expected <- mssr(x, fwhm = 2, amp = amp, order = order,
                       intensity_normalize = FALSE)$values
      for (exponent in c(-1060, 1020)) {
        r <- mssr(x * 2^exponent, fwhm = 2, amp = amp, order = order,
                  intensity_normalize = FALSE)
        expect_equal(r$values, expected, tolerance = 1e-12)
        expect_false(r$diagnostics$degenerate)
        expect_identical(r$engine$id, "mssr_r_rev3")
      }
    }
  }
})

test_that("order-zero structure maps retain large-background invariance", {
  x <- precision_frame()
  for (amp in 1:3) {
    for (grid in c("extent", "endpoint")) {
      for (mesh in c(FALSE, TRUE)) {
        transform <- function(x) {
          mssr(x, fwhm = 2, amp = amp, order = 0, grid = grid, mesh = mesh,
               intensity_normalize = FALSE)$values
        }
        expect_equal(transform(x + 2^40), transform(x), tolerance = 1e-12)
      }
    }
  }
})

test_that("higher-order large-background maps agree with a high-precision oracle", {
  # The original weighted-absolute-intensity equations were independently
  # evaluated with 100 decimal digits on the exact integer input. This is not
  # an offset-invariance claim: higher orders use the normalized full input.
  expected <- matrix(c(
    0, 1, 0, 0, 0,
    0.0154753600191195358, 0, 0, 0.2339378081077346354, 0.00815139658075303214,
    0, 0.00248509525050676705, 0, 0.0121925219876273765, 0,
    0.0139463565821019741, 0, 0.0477717076527345349, 0, 0.0146176840781007229
  ), 4, 5, byrow = TRUE)
  actual <- mssr(precision_frame() + 2^40, fwhm = 2, order = 2,
                 intensity_normalize = FALSE)$values
  expect_equal(actual, expected, tolerance = 1e-12)
  without_background <- mssr(precision_frame(), fwhm = 2, order = 2,
                             intensity_normalize = FALSE)$values
  expect_gt(max(abs(actual - without_background)), 0.01)
})

test_that("intensity weighting returns to input scale with subnormal rounding", {
  x <- precision_frame()
  reference <- mssr(x, fwhm = 2, amp = 2, order = 2)$values
  for (exponent in c(-1060, 1020)) {
    scaled <- mssr(x * 2^exponent, fwhm = 2, amp = 2, order = 2)$values
    tolerance <- if (exponent == -1060) 2^-14 else 1e-12
    expect_lte(max(abs(scaled / 2^exponent - reference)), tolerance)
    expect_true(all(is.finite(scaled)))
  }
})

test_that("conditioning refuses to erase nonzero values across an excessive range", {
  x <- matrix(c(1e308, 1e-100, rep(0, 7)), 3, 3)
  expect_error(mssr(x, fwhm = 2), class = "mssrscopR_error_numerical")
})

test_that("intensity weighting preserves a representable distant dim structure", {
  x <- matrix(0, 9, 9)
  x[3, 3] <- 1e308
  x[7, 7] <- 1e50
  r <- mssr(x, fwhm = 2, order = 0)
  expect_equal(r$values[3, 3] / 1e308, 1)
  expect_equal(r$values[7, 7] / 1e-208, 1, tolerance = 1e-12)
})
