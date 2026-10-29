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

test_that("the allocation estimate bounds measured peak memory on a small ladder", {
  skip_on_cran()
  skip_on_covr()
  skip_if_not_installed("callr")
  skip_if_not(file.exists("/proc/self/status"), "peak RSS is read from /proc")
  ns <- asNamespace("mssrscopR")
  root <- getNamespaceInfo(ns, "path")
  development <- exists(".__DEVTOOLS__", ns, inherits = FALSE)
  if (development) skip_if_not_installed("pkgload")
  ladder <- list(c(n = 256, amp = 2, order = 1), c(n = 384, amp = 2, order = 3),
                 c(n = 512, amp = 1, order = 1))
  for (step in ladder) {
    measured <- callr::r(function(root, development, step) {
      if (development) {
        pkgload::load_all(root, quiet = TRUE)
      } else {
        loadNamespace("mssrscopR", lib.loc = dirname(root))
      }
      ns <- asNamespace("mssrscopR")
      set.seed(1)
      x <- matrix(stats::rpois(step[["n"]]^2, 20) + 0, step[["n"]], step[["n"]])
      get("mssr", ns)(x, fwhm = 3, amp = step[["amp"]], order = step[["order"]])
      status <- readLines("/proc/self/status")
      as.numeric(sub("^VmHWM:\\s+([0-9]+) kB$", "\\1", grep("^VmHWM", status, value = TRUE))) * 1024
    }, args = list(root = root, development = development, step = step), libpath = .libPaths())
    estimate <- mssr_estimate_resources(rep(step[["n"]], 2), fwhm = 3,
                                        amp = step[["amp"]])$estimated_peak_bytes
    label <- paste(step, collapse = "/")
    # The model is one machine's calibration, so by default this only catches
    # gross regressions; MSSRSCOPR_STRICT_MEMORY_TEST=true asserts the bound
    # itself. pkgload in development children adds to the measured baseline.
    slack <- if (identical(Sys.getenv("MSSRSCOPR_STRICT_MEMORY_TEST"), "true")) 1 else 1.25
    if (development) slack <- slack * 1.5
    expect_lte(measured, estimate * slack, label = label)
    expect_lte(estimate, 4 * measured, label = label)
  }
})
