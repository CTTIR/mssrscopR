precision_reduce <- function(values, statistic) {
  frame <- function(t, pass) {
    f <- values[, , t]
    dim(f) <- dim(values)[1:2]
    f
  }
  temporal_reduce(frame, dim(values)[3], statistic)
}

test_that("independent pixels retain representable temporal statistics at different scales", {
  cases <- list(
    mean = list(exponent = 1000, coefficient = 0.5, degree = 1),
    var = list(exponent = 500, coefficient = 0.25, degree = 2),
    tpm = list(exponent = 500, coefficient = 16, degree = 2),
    cv = list(exponent = 1000, coefficient = 0.5, degree = 1),
    sofi2 = list(exponent = 500, coefficient = -0.25, degree = 2),
    sofi3 = list(exponent = 330, coefficient = 2, degree = 3),
    sofi4 = list(exponent = 250, coefficient = -0.125, degree = 4)
  )
  for (statistic in names(cases)) {
    z <- cases[[statistic]]
    # Alternation has deviations +/-1/2; its lagged fourth cumulant is -1/8.
    # The period 0,0,3 has mean1 and every three-lag product equals2.
    series <- if (statistic == "sofi3") rep(c(0, 0, 3), 3) else rep(c(0, 1), 4)
    scales <- 2^c(-z$exponent, z$exponent)
    x <- array(as.vector(outer(scales, series)), c(1, 2, length(series)))
    expected <- z$coefficient * 2^(c(-z$exponent, z$exponent) * z$degree)
    got <- precision_reduce(x, statistic)
    expect_identical(as.vector(got), expected, info = statistic)
    expect_identical(precision_reduce(x[, 2:1, , drop = FALSE], statistic),
                     got[, 2:1, drop = FALSE], info = statistic)
  }
})

test_that("public temporal paths preserve independent dim impulses", {
  for (statistic in c("mean", "var")) {
    exponent <- if (statistic == "mean") 1000 else 500
    x <- array(0, c(2, 2, 2))
    x[1, 1, 1] <- 2^-exponent
    x[2, 2, 2] <- 2^exponent
    before <- x
    stack <- mssr_stack(x, fwhm = 1, order = 0)
    estimate <- mssr_estimate_resources(c(2, 2), 1, frames = 2, statistic = statistic)
    direct <- mssr_temporal(x, statistic, fwhm = 1, order = 0)
    recomputed <- mssr_temporal(x, statistic, fwhm = 1, order = 0,
                                max_memory_bytes = estimate$recompute_peak_bytes)
    stored <- mssr_temporal(stack, statistic)
    expected <- matrix(0, 2, 2)
    degree <- if (statistic == "mean") 1 else 2
    expected[1, 1] <- 2^(-degree * exponent - degree)
    expected[2, 2] <- 2^(degree * exponent - degree)
    expect_identical(direct$values, expected)
    expect_identical(recomputed$values, expected)
    expect_identical(stored$values, expected)
    expect_identical(x, before)
    expect_identical(mssr_validate_result(direct), direct)
    expect_error(mssr_temporal(stack, statistic, max_memory_bytes = 1),
                 class = "mssrscopR_error_resource")
  }
})

test_that("raw diagnostic means cannot overflow a finite constant stack", {
  x <- array(.Machine$double.xmax, c(2, 3, 2))
  stack <- mssr_stack(x, fwhm = 1, order = 0)
  expect_identical(stack$input_mean, matrix(.Machine$double.xmax, 2, 3))
  result <- mssr_temporal(stack, "mean")
  expect_identical(result$values, matrix(0, 2, 3))
  expect_identical(mssr_validate_result(result), result)
  expect_identical(x, array(.Machine$double.xmax, c(2, 3, 2)))
})

test_that("conditioning refuses an erased contribution within the same pixel", {
  for (series in list(c(1e300, -1e300, 1e-300), c(1e-300, 1e300, -1e300))) {
    values <- array(series, c(1, 1, 3))
    expect_error(precision_reduce(values, "mean"),
                 class = "mssrscopR_error_numerical")
    expect_error(mssr_stack(values, fwhm = 1, order = 0),
                 class = "mssrscopR_error_numerical")
  }
})

test_that("temporal products cannot erase a representable lagged cumulant", {
  # Exact centered products give SOFI4 = 1 - 1 - 1 - 1 = -2.
  # In conditioned units some factors have magnitude 1e-200, whose products
  # underflow before the final scaling could restore their magnitude.
  values <- array(c(1e100, -1e100, 1e-100, -1e-100), c(1, 1, 4))
  expect_error(precision_reduce(values, "sofi4"), "intermediate product",
               class = "mssrscopR_error_numerical")
  # A less extreme ratio keeps all intermediate products representable.
  ordinary <- array(c(1e10, -1e10, 1e-10, -1e-10), c(1, 1, 4))
  expect_equal(as.numeric(precision_reduce(ordinary, "sofi4")), -2,
               tolerance = 1e-12)
  # The first two values cancel before the first-pass scale grows. They must
  # still be checked when reread at the final exponent in the second pass.
  cancelled <- array(c(1e-300, -1e-300, 1e300, -1e300), c(1, 1, 4))
  expect_error(precision_reduce(cancelled, "sofi4"), "forming deviations",
               class = "mssrscopR_error_numerical")
})

test_that("cancelled sums cannot erase representable mean or TPM values", {
  # The residual mean is 2^-574 / 3, but at exponent500 its scaled sum is
  # the smallest subnormal; division by3 must not silently become zero.
  mean_input <- array(c(2^500, -2^500, 2^-574), c(1, 1, 3))
  expect_error(precision_reduce(mean_input, "mean"), "intermediate average or ratio",
               class = "mssrscopR_error_numerical")
  # The true squared residual sum is2^-1000, representable in binary64.
  tpm_input <- array(c(2^500, -2^500, 2^-500), c(1, 1, 3))
  expect_error(precision_reduce(tpm_input, "tpm"), "intermediate product",
               class = "mssrscopR_error_numerical")
})
