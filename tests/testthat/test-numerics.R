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

test_that("channel ratios are kept only by whole-frame scaled copies", {
  g <- expand.grid(r = 1:21, c = 1:31)
  spot <- function(c0, a = 1, r0 = 11) {
    a * exp(-((g$r - r0)^2 + (g$c - c0)^2) / (2 * (3 / 2.3548)^2))
  }
  a <- matrix(spot(10) + spot(21) + 0.05, 21, 31)
  b <- matrix(spot(10) + spot(21, 0.5) + 0.05, 21, 31)
  ra <- mssr(a, fwhm = 3)$values
  for (factor in c(0.37, 3.1)) {
    expect_equal(mssr(factor * a, fwhm = 3)$values, factor * ra, tolerance = 1e-12)
  }
  expect_equal(mssr(0.5 * a, fwhm = 3, intensity_normalize = FALSE)$values,
               mssr(a, fwhm = 3, intensity_normalize = FALSE)$values, tolerance = 1e-12)
  ratio <- mssr(b, fwhm = 3)$values[11, 21] / ra[11, 21]
  expect_lt(ratio, 0.75 * b[11, 21] / a[11, 21])
  # Output ratio relative to the input ratio, over the signal pixels.
  sel <- ra > 0.05 * max(ra)
  deviation <- function(z) range((mssr(z, fwhm = 3)$values / ra)[sel] / (z / a)[sel])
  expect_gt(deviation(a + 0.5)[2], 1.2)
  expect_gt(deviation(0.5 * a + 0.05)[2], 1.1)
  expect_lt(deviation(0.5 * a + matrix(spot(27, 2, r0 = 4), 21, 31))[1], 0.5)
})

test_that("under noise an fwhm below the PSF splits single sources more often", {
  g <- expand.grid(r = 1:21, c = 1:21)
  x0 <- matrix(exp(-((g$r - 11)^2 + (g$c - 11)^2) / (2 * (3 / 2.3548)^2)) + 0.05, 21, 21)
  split_share <- function(fwhm) {
    mean(vapply(1:30, function(seed) {
      set.seed(seed)
      v <- mssr(pmax(x0 + stats::rnorm(length(x0), sd = 0.08), 0), fwhm = fwhm)$values
      peaks <- 0L
      for (i in 7:15) for (j in 7:15) {
        w <- v[(i - 1):(i + 1), (j - 1):(j + 1)]
        strict_max <- v[i, j] == max(w) && sum(w == v[i, j]) == 1L
        if (v[i, j] > 0.2 * max(v) && strict_max) peaks <- peaks + 1L
      }
      peaks >= 2L
    }, TRUE))
  }
  expect_gt(split_share(2), split_share(3) + 0.2)
})

test_that("a larger fwhm gives a shallower dip between close sources", {
  g <- expand.grid(r = 1:21, c = 1:31)
  spot <- function(c0) exp(-((g$r - 11)^2 + (g$c - c0)^2) / (2 * (3 / 2.3548)^2))
  x <- matrix(spot(18) + spot(21) + 0.05, 21, 31)
  dip <- function(fwhm) {
    r <- mssr(x, fwhm = fwhm, amp = 2)
    co <- mssr_coords(r)
    v <- as.matrix(r)[which.min(abs(co$row - 11)), ]
    stats::approx(co$col, v, 19.5)$y / stats::approx(co$col, v, 18)$y
  }
  expect_gt(dip(5), dip(3) + 0.1)
})

test_that("fwhm enters only through the kernel half-size", {
  x <- precision_frame()
  a <- mssr(x, fwhm = 2.6, amp = 2)
  b <- mssr(x, fwhm = 3.4, amp = 2)
  expect_identical(a$parameters$half_size, b$parameters$half_size)
  expect_identical(a$values, b$values)
  expect_false(identical(a$values, mssr(x, fwhm = 3.6, amp = 2)$values))
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
