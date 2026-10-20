test_that("flat frames are degenerate at every amplification and grid", {
  for (amp in 1:3) {
    for (grid in c("extent", "endpoint")) {
      r <- mssr(matrix(pi, 6, 8), fwhm = 3, amp = amp, grid = grid)
      expect_true(r$diagnostics$degenerate)
      expect_identical(r$diagnostics$degenerate_reason, "flat input")
      expect_true(all(as.matrix(r) == 0))
      expect_equal(dim(as.matrix(r)), c(6L, 8L) * amp)
    }
  }
  expect_true(mssr(matrix(3, 1, 1), fwhm = 2, amp = 3)$diagnostics$degenerate)
})

test_that("isolated impulses on a zero background survive refinement", {
  z <- matrix(0, 15, 15)
  z[4, 4] <- 1
  z[11, 10] <- 0.5
  r0 <- mssr(z, fwhm = 3, order = 0)
  for (ord in 1:3) {
    r <- mssr(z, fwhm = 3, order = ord)
    expect_false(r$diagnostics$degenerate)
    expect_identical(r$diagnostics$order_steps_skipped, as.integer(ord))
    expect_equal(as.matrix(r), as.matrix(r0))
  }
  expect_true(any(grepl("3 undefined order step(s) skipped",
                        utils::capture.output(print(mssr(z, fwhm = 3, order = 3))), fixed = TRUE)))
  v <- as.matrix(r0)
  expect_equal(which(v == max(v), arr.ind = TRUE)[1, ], c(row = 4, col = 4))
  expect_gt(v[11, 10], 0)
})

test_that("negative input warns and is reported", {
  x <- matrix(stats::runif(100), 10, 10)
  expect_warning(r <- mssr(-x, fwhm = 3), class = "mssrscopR_warning_negative")
  expect_true(r$diagnostics$degenerate)
  expect_identical(r$diagnostics$degenerate_reason, "non-positive maximum")
  expect_warning(mssr(x - 0.5, fwhm = 3), class = "mssrscopR_warning_negative")
  expect_no_warning(mssr(x, fwhm = 3))
})

test_that("tiny frames work", {
  expect_equal(dim(as.matrix(mssr(matrix(3, 1, 1), fwhm = 2))), c(1L, 1L))
  expect_true(all(is.finite(as.matrix(mssr(matrix(1:6 + 0, 2, 3), fwhm = 2)))))
})

test_that("invalid input fails with classed errors", {
  x <- matrix(stats::runif(25), 5, 5)
  bad <- x
  bad[2, 2] <- NA
  expect_error(mssr(bad, fwhm = 2), class = "mssrscopR_error_nonfinite")
  bad[2, 2] <- Inf
  expect_error(mssr(bad, fwhm = 2), class = "mssrscopR_error_nonfinite")
  expect_error(mssr(array(0, c(4, 4, 3)), fwhm = 2), class = "mssrscopR_error_input")
  expect_error(mssr(as.data.frame(x), fwhm = 2), class = "mssrscopR_error_input")
  expect_error(mssr(matrix("a", 2, 2), fwhm = 2), class = "mssrscopR_error_input")
  expect_error(mssr(matrix(numeric(), 0, 3), fwhm = 2), class = "mssrscopR_error_input")
  expect_error(mssr(x), class = "mssrscopR_error_parameter")
  expect_error(mssr(x, fwhm = -1), class = "mssrscopR_error_parameter")
  expect_error(mssr(x, fwhm = 1e10), class = "mssrscopR_error_parameter")
  expect_error(mssr(x, fwhm = 2, amp = 1.5), class = "mssrscopR_error_parameter")
  expect_error(mssr(x, fwhm = 2, order = -1), class = "mssrscopR_error_parameter")
  expect_error(mssr(x, fwhm = 2, mesh = NA), class = "mssrscopR_error_parameter")
  expect_error(mssr(x, fwhm = 2, max_output_pixels = "a"), class = "mssrscopR_error_parameter")
  expect_error(mssr(x, fwhm = 2, max_output_pixels = c(1, 2)), class = "mssrscopR_error_parameter")
  expect_error(mssr(x, fwhm = 2, amp = 4, max_output_pixels = 100),
               class = "mssrscopR_error_resource")
  expect_error(mssr(matrix(stats::runif(100), 10, 10), fwhm = 3, amp = 64),
               class = "mssrscopR_error_resource")
  expect_no_error(mssr(x, fwhm = 2))
})

test_that("errors name the function the user called", {
  err <- tryCatch(mssr(matrix(NA_real_, 2, 2), fwhm = 2), error = identity)
  expect_s3_class(err, "mssrscopR_error")
  expect_identical(as.character(conditionCall(err)[[1]]), "mssr")
})

test_that("the structure role stays within [0, 1] and is labeled non-quantitative", {
  x <- matrix(stats::runif(400), 20, 20)
  r <- mssr(x, fwhm = 3, order = 2, intensity_normalize = FALSE)
  expect_identical(r$role, "structure")
  expect_true(all(as.matrix(r) >= 0 & as.matrix(r) <= 1))
  expect_false(r$diagnostics$quantitative)
  expect_identical(mssr(x, fwhm = 3)$role, "intensity_weighted_structure")
})

test_that("kernel, rounding and mesh options behave as documented", {
  x <- matrix(stats::runif(144), 12, 12)
  expect_equal(mssr(x, fwhm = 5)$parameters$half_size, 2)
  expect_equal(mssr(x, fwhm = 5, rounding = "half_up")$parameters$half_size, 3)
  expect_equal(mssr(x, fwhm = 4, kernel = "square")$diagnostics$n_offsets, 24L)
  expect_equal(mssr(x, fwhm = 4, kernel = "disk")$diagnostics$n_offsets, 12L)
  expect_false(isTRUE(all.equal(as.matrix(mssr(x, fwhm = 3, amp = 2)),
                                as.matrix(mssr(x, fwhm = 3, amp = 2, mesh = FALSE)))))
  expect_false(mssr(x, fwhm = 3)$parameters$mesh)
})

test_that("printing shows a bounded summary, not values", {
  r <- mssr(matrix(stats::runif(100), 10, 10), fwhm = 3)
  out <- utils::capture.output(print(r))
  expect_lt(length(out), 8)
  expect_true(any(grepl("Not a quantitative intensity", out)))
  flat <- utils::capture.output(print(mssr(matrix(1, 3, 3), fwhm = 2)))
  expect_true(any(grepl("DEGENERATE (flat input)", flat, fixed = TRUE)))
})
