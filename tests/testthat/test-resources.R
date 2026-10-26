test_that("resource estimates count neighborhoods without allocating them", {
  for (kernel in c("disk", "square")) {
    for (h in c(1, 2, 3, 10, 31)) {
      estimate <- mssr_estimate_resources(c(2, 3), 2 * h, kernel = kernel)
      expect_equal(estimate$n_offsets, nrow(mssr_offsets(h, kernel)))
      expect_equal(estimate$estimated_work, 6 * estimate$n_offsets)
      expect_false(estimate$hard_limit)
    }
  }
  small <- mssr_estimate_resources(c(64, 96), 3)
  large <- mssr_estimate_resources(c(64, 96), 3, amp = 2)
  expect_gt(large$estimated_peak_bytes, small$estimated_peak_bytes)
  expect_equal(large$output_dim, c(128, 192))
  expect_error(mssr_estimate_resources(c(1, NA), 3), class = "mssrscopR_error_parameter")
  expect_error(mssr_estimate_resources(c(1e9, 1e9), 3), class = "mssrscopR_error_resource")
  expect_error(mssr_estimate_resources(c(10, 10), 3000), class = "mssrscopR_error_resource")
  expect_error(mssr_estimate_resources(c(10, 10), 3, amp = 64),
               class = "mssrscopR_error_resource")
})

test_that("opt-in memory guard refuses before numerical evaluation", {
  x <- matrix(seq_len(12), 3, 4)
  expect_error(mssr(x, 3, max_memory_bytes = 100), class = "mssrscopR_error_resource")
  expect_error(mssr(x, 3, max_memory_bytes = NA), class = "mssrscopR_error_parameter")
  expect_identical(mssr(x, 3)$values, mssr(x, 3, max_memory_bytes = 1024^3)$values)
})
