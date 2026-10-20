test_that("an off-center impulse stays where it is (no rotation)", {
  x <- matrix(1, 9, 9)
  x[2, 6] <- 10
  for (norm in c(TRUE, FALSE)) {
    v <- as.matrix(mssr(x, fwhm = 2, order = 1, intensity_normalize = norm))
    expect_equal(which(v == max(v), arr.ind = TRUE)[1, ], c(row = 2, col = 6))
  }
  # With intensity normalization the peak keeps the input's peak value.
  expect_equal(max(as.matrix(mssr(x, fwhm = 2))), 10)
})

test_that("a horizontal line stays horizontal", {
  x <- matrix(1, 9, 9)
  x[3, ] <- 5
  v <- as.matrix(mssr(x, fwhm = 2, order = 0, intensity_normalize = FALSE))
  expect_equal(which.max(rowMeans(v)), 3L)
})

test_that("non-square frames keep their shape and are transpose/flip equivariant", {
  x <- matrix(1, 7, 11)
  x[1, 1] <- 10
  x[1, 11] <- 20
  x[7, 1] <- 30
  x[7, 11] <- 40
  x[3, 8] <- 15
  v <- as.matrix(mssr(x, fwhm = 2))
  expect_equal(dim(v), c(7L, 11L))
  expect_equal(as.matrix(mssr(t(x), fwhm = 2)), t(v), tolerance = 1e-12)
  expect_equal(as.matrix(mssr(x[7:1, ], fwhm = 2)), v[7:1, ], tolerance = 1e-12)
  expect_equal(as.matrix(mssr(x[, 11:1], fwhm = 2)), v[, 11:1], tolerance = 1e-12)
})

test_that("the extent grid preserves the field of view; the endpoint grid does not", {
  x <- matrix(stats::runif(9 * 9), 9, 9)
  ext <- mssr_coords(mssr(x, fwhm = 3, amp = 2))
  expect_equal(diff(ext$row)[1], 0.5)
  expect_equal(range(ext$col), c(0.75, 9.25))
  end <- mssr_coords(mssr(x, fwhm = 3, amp = 2, grid = "endpoint"))
  expect_equal(diff(end$row)[1], 8 / 17)
  expect_equal(range(end$col), c(1, 9))
  r <- mssr(x, fwhm = 3, amp = 2)
  expect_equal(unname(r$transform$spacing), c(0.5, 0.5))
  expect_equal(dim(as.matrix(r)), c(18L, 18L))
})

test_that("odd amplification and single-row or single-column frames work", {
  x <- matrix(stats::runif(5 * 6) + 0.1, 5, 6)
  r3 <- mssr(x, fwhm = 2, amp = 3)
  expect_equal(dim(as.matrix(r3)), c(15L, 18L))
  expect_equal(unname(r3$transform$spacing), c(1 / 3, 1 / 3))
  expect_equal(range(mssr_coords(r3)$row), c(0.5 + 1 / 6, 5.5 - 1 / 6))
  row_frame <- matrix(c(1, 3, 2, 5, 1, 4) + 0.1, 1, 6)
  r <- mssr(row_frame, fwhm = 2, amp = 2)
  expect_equal(dim(as.matrix(r)), c(2L, 12L))
  expect_equal(unname(r$transform$spacing), c(0.5, 0.5))
  expect_true(all(is.finite(as.matrix(r))))
  expect_equal(dim(as.matrix(mssr(t(row_frame), fwhm = 2, amp = 2))), c(12L, 2L))
  r_end <- mssr(row_frame, fwhm = 2, grid = "endpoint")
  expect_equal(mssr_coords(r_end)$row, 1)
  expect_equal(unname(r_end$transform$spacing), c(1, 1))
  expect_error(mssr(row_frame, fwhm = 2, amp = 2, grid = "endpoint"),
               class = "mssrscopR_error_unsupported")
})

test_that("an amplified impulse peaks among its own pixel's children", {
  x <- matrix(1, 9, 9)
  x[5, 3] <- 10
  v <- as.matrix(mssr(x, fwhm = 3, amp = 2, intensity_normalize = FALSE))
  pk <- which(v == max(v), arr.ind = TRUE)[1, ]
  expect_true(pk[["row"]] %in% 9:10 && pk[["col"]] %in% 5:6)
})
