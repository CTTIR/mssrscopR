test_that("positive mask fractions cannot silently select zero pixels", {
  r <- mssr(matrix(1:100, 10, 10), fwhm = 2)
  for (fraction in c(1e-20, 1e-12)) {
    m <- mssr_mask(r, fraction = fraction)
    expect_equal(sum(m), 1)
    expect_equal(attr(m, "coverage"), 0.01)
    expect_true(is.finite(attr(m, "tie_fraction")))
  }
  expect_equal(sum(mssr_mask(r, fraction = 0.14)), 14)
  expect_equal(sum(mssr_mask(r, fraction = 0.14000000001)), 15)
})

test_that("matrix inputs reject complex values and explicit numeric classes", {
  expect_error(mssr(matrix(1 + 2i, 2, 3), fwhm = 2),
               class = "mssrscopR_error_input")
  x <- structure(matrix(1:6, 2, 3), class = c("calibrated", "matrix", "array"))
  expect_error(mssr(x, fwhm = 2), class = "mssrscopR_error_input")
  expect_no_error(mssr(matrix(1:6, 2, 3), fwhm = 2))
})

test_that("numeric arguments reject complex and classed scalars consistently", {
  x <- matrix(1:6, 2, 3)
  r <- mssr(x, fwhm = 2)
  for (bad in list(2 + 1i, structure(2, class = "calibrated"))) {
    expect_error(mssr(x, fwhm = bad), class = "mssrscopR_error_parameter")
    expect_error(mssr(x, fwhm = 2, amp = bad), class = "mssrscopR_error_parameter")
    expect_error(mssr_mask(r, seed = bad), class = "mssrscopR_error_parameter")
    expect_error(mssr_selftest(tolerance = bad), class = "mssrscopR_error_parameter")
  }
  for (bad in list(0.5 + 0.1i, structure(0.5, class = "calibrated"))) {
    expect_error(mssr_mask(r, fraction = bad), class = "mssrscopR_error_parameter")
  }
})

test_that("coordinate and mask consumers refuse corrupt result geometry", {
  r <- mssr(matrix(1:6, 2, 3), fwhm = 2)
  bad <- list(structure(list(), class = "mssr_result"))
  mutate <- function(field, value) {
    z <- r
    z$transform[[field]] <- value
    z
  }
  bad <- c(bad, list(
    mutate("input_dim", c(0, 3)),
    mutate("input_dim", c(NA, 3)),
    mutate("input_dim", c(3, 2)),
    mutate("output_dim", c(3, 2)),
    mutate("amp", 0),
    mutate("grid", "unknown"),
    mutate("first_center", c(row = 7, col = 1)),
    mutate("spacing", c(row = 2, col = 1)),
    mutate("field_of_view", c(row_min = 0, row_max = 2.5, col_min = 0.5, col_max = 3.5))
  ))
  z <- r
  z$values[1, 1] <- Inf
  bad <- c(bad, list(z))
  z <- r
  z$values <- matrix("a", 2, 3)
  bad <- c(bad, list(z))
  for (z in bad) {
    expect_s3_class(suppressWarnings(tryCatch(mssr_coords(z), error = identity)),
                    "mssrscopR_error_input")
    expect_s3_class(suppressWarnings(tryCatch(mssr_mask(z), error = identity)),
                    "mssrscopR_error_input")
  }
})

test_that("high finite input is conditioned without intermediate overflow", {
  positive <- matrix(c(rep(1e308, 8), 1e307), 3, 3)
  signed <- matrix(c(-1e308, 1e308, rep(0, 7)), 3, 3)
  for (x in list(positive, signed)) {
    got <- suppressWarnings(mssr(x, fwhm = 3, intensity_normalize = FALSE))
    ref <- suppressWarnings(mssr(x / 1e308, fwhm = 3, intensity_normalize = FALSE))
    expect_equal(got$values, ref$values, tolerance = 1e-12)
    expect_true(all(is.finite(suppressWarnings(mssr(x, fwhm = 3))$values)))
  }
  x <- matrix(c(0, 0, 1, 1, 0, 1, 1, 0, 0), 3) * .Machine$double.xmax
  expect_error(mssr(x, fwhm = 2, amp = 2, mesh = FALSE, order = 0),
               class = "mssrscopR_error_numerical")
})

test_that("amplified mask averaging preserves finite high-range scores", {
  r <- mssr(matrix(1:6, 2, 3), fwhm = 2, amp = 2)
  scores <- matrix(c(1e308, 8e307, 6e307, 4e307, 2e307, 1e307), 2, 3)
  r$values <- scores[rep(1:2, each = 2), rep(1:3, each = 2)]
  expect_equal(mssr_block_mean(r$values, 2), scores)
  for (seed in 1:5) {
    mask <- mssr_mask(r, fraction = 1 / 6, seed = seed)
    expect_identical(which(mask), 1L)
    expect_equal(attr(mask, "tie_fraction"), 0)
  }
})

test_that("a bright block cannot erase distinct scores in other blocks", {
  r <- mssr(matrix(1:6, 2, 3), fwhm = 2, amp = 2)
  scores <- matrix(c(1e308, 1e-100, 2e-100, 3e-100, 4e-100, 5e-100), 2, 3)
  r$values <- scores[rep(1:2, each = 2), rep(1:3, each = 2)]
  expect_identical(mssr_block_mean(r$values, 2), scores)
  for (seed in 1:5) {
    # The dim scores are far below 1e-6 of the bright block, which warns.
    mask <- mask_quietly(r, fraction = 2 / 6, seed = seed)
    expect_identical(which(mask), c(1L, 6L))
    expect_equal(attr(mask, "tie_fraction"), 0)
  }
})
