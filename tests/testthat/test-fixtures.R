test_that("every bundled synthetic fixture is reproduced within 1e-10", {
  st <- mssr_selftest()
  expect_equal(nrow(st), 10L)
  expect_true(attr(st, "all_passed"))
  expect_true(all(st$max_abs_error <= 1e-10 | st$max_rel_error <= 1e-10))
})

test_that("a tighter tolerance than the data allow is reported, not hidden", {
  st <- mssr_selftest(tolerance = 0)
  expect_s3_class(st, "data.frame")
  expect_type(attr(st, "all_passed"), "logical")
})
