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

test_that("amplified results keep the absolute orientation on both grids", {
  x <- matrix(1, 9, 13)
  x[3, 10] <- 10
  x[7, 2] <- 6
  for (amp in 2:3) {
    for (grid in c("extent", "endpoint")) {
      r <- mssr(x, fwhm = 2, amp = amp, grid = grid, intensity_normalize = FALSE)
      v <- as.matrix(r)
      co <- mssr_coords(r)
      pk <- which(v == max(v), arr.ind = TRUE)[1, ]
      expect_lte(abs(co$row[pk[["row"]]] - 3), 0.5)
      expect_lte(abs(co$col[pk[["col"]]] - 10), 0.5)
      lower_left <- v[co$row > 5, co$col < 5, drop = FALSE]
      pk2 <- which(lower_left == max(lower_left), arr.ind = TRUE)[1, ]
      expect_lte(abs(co$row[co$row > 5][pk2[["row"]]] - 7), 0.5)
      expect_lte(abs(co$col[co$col < 5][pk2[["col"]]] - 2), 0.5)
    }
  }
})

test_that("amplified results are transpose and flip equivariant", {
  x <- outer(1:7, 1:10, function(r, c) 2 + sin(r * 0.9) * cos(c * 0.6) + (r == 2 & c == 8) * 3)
  for (amp in 2:3) {
    for (grid in c("extent", "endpoint")) {
      run <- function(m) as.matrix(mssr(m, fwhm = 2.5, amp = amp, grid = grid))
      v <- run(x)
      expect_equal(run(t(x)), t(v), tolerance = 1e-12)
      expect_equal(run(x[rev(seq_len(nrow(x))), ]), v[rev(seq_len(nrow(v))), ], tolerance = 1e-12)
      expect_equal(run(x[, rev(seq_len(ncol(x)))]), v[, rev(seq_len(ncol(v)))], tolerance = 1e-12)
    }
  }
})
