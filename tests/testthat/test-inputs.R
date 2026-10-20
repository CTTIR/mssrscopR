test_that("flat input returns zeros flagged degenerate instead of NaN", {
  for (x in list(matrix(0, 6, 8), matrix(5, 6, 8))) {
    r <- mssr(x, fwhm = 3, order = 2)
    expect_true(r$diagnostics$degenerate)
    expect_true(all(as.matrix(r) == 0))
  }
})

test_that("tiny frames work", {
  expect_equal(dim(as.matrix(mssr(matrix(3, 1, 1), fwhm = 2))), c(1L, 1L))
  expect_true(all(is.finite(as.matrix(mssr(matrix(1:6 + 0, 2, 3), fwhm = 2)))))
})

test_that("invalid input fails with classed errors", {
  x <- matrix(stats::runif(25), 5, 5)
  bad <- x; bad[2, 2] <- NA
  expect_error(mssr(bad, fwhm = 2), class = "mssrscopR_error_nonfinite")
  bad[2, 2] <- Inf
  expect_error(mssr(bad, fwhm = 2), class = "mssrscopR_error_nonfinite")
  expect_error(mssr(array(0, c(4, 4, 3)), fwhm = 2), class = "mssrscopR_error_input")
  expect_error(mssr(as.data.frame(x), fwhm = 2), class = "mssrscopR_error_input")
  expect_error(mssr(matrix("a", 2, 2), fwhm = 2), class = "mssrscopR_error_input")
  expect_error(mssr(x), class = "mssrscopR_error_parameter")
  expect_error(mssr(x, fwhm = -1), class = "mssrscopR_error_parameter")
  expect_error(mssr(x, fwhm = 2, amp = 1.5), class = "mssrscopR_error_parameter")
  expect_error(mssr(x, fwhm = 2, order = -1), class = "mssrscopR_error_parameter")
  expect_error(mssr(x, fwhm = 2, amp = 4, max_output_pixels = 100), class = "mssrscopR_error_resource")
  expect_error(mssr(x, fwhm = 2), NA)
})

test_that("the structure role stays within [0, 1] and is labelled non-quantitative", {
  x <- matrix(stats::runif(400), 20, 20)
  r <- mssr(x, fwhm = 3, order = 2, intensity_normalize = FALSE)
  expect_identical(r$role, "structure")
  expect_true(all(as.matrix(r) >= 0 & as.matrix(r) <= 1))
  expect_false(r$diagnostics$quantitative)
  expect_identical(mssr(x, fwhm = 3)$role, "intensity_weighted_structure")
})

test_that("half-size rounding follows the documented rule", {
  x <- matrix(stats::runif(100), 10, 10)
  expect_equal(mssr(x, fwhm = 5)$parameters$half_size, 2L)
  expect_equal(mssr(x, fwhm = 5, rounding = "half_up")$parameters$half_size, 3L)
})

test_that("printing shows a bounded summary, not values", {
  r <- mssr(matrix(stats::runif(100), 10, 10), fwhm = 3)
  out <- utils::capture.output(print(r))
  expect_lt(length(out), 8)
  expect_true(any(grepl("Not a quantitative intensity", out)))
})
