test_that("every bundled synthetic fixture is reproduced", {
  st <- mssr_selftest()
  expect_equal(nrow(st), 10L)
  expect_true(attr(st, "all_passed"))
  expect_true(all(st$max_abs_error <= 1e-10))
})

test_that("a perturbed fixture fails with FALSE, not NA", {
  src <- system.file("extdata", "fixtures", package = "mssrscopR")
  dir <- withr::local_tempdir()
  file.copy(list.files(src, full.names = TRUE), dir)
  f <- file.path(dir, "fx05_amp1_o1__expected.csv")
  v <- as.matrix(utils::read.csv(f, header = FALSE))
  v[8, 8] <- v[8, 8] + 1e-6
  utils::write.table(v, f, sep = ",", row.names = FALSE, col.names = FALSE)
  st <- run_fixtures(dir, 1e-10)
  expect_false(st$passed[st$fixture_id == "fx05_amp1_o1"])
  expect_identical(attr(st, "all_passed"), FALSE)
  expect_true(all(st$passed[st$fixture_id != "fx05_amp1_o1"]))
})

test_that("the self-test tolerance is validated", {
  expect_error(mssr_selftest("1"), class = "mssrscopR_error_parameter")
  expect_error(mssr_selftest(NA_real_), class = "mssrscopR_error_parameter")
  expect_error(mssr_selftest(-1), class = "mssrscopR_error_parameter")
  # Zero tolerance is valid input; amplified fixtures differ in the last bits
  # because interpolation sums its four taps in a fixed order.
  expect_type(attr(mssr_selftest(0), "all_passed"), "logical")
})
