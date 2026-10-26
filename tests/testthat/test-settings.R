settings_frame <- function() {
  outer(1:7, 1:11, function(r, c) {
    0.03 + 0.003 * r + 0.005 * c +
      3 * exp(-((r - 2)^2 / 1.5 + (c - 8)^2 / 2)) +
      exp(-((r - 6)^2 / 2 + (c - 3)^2 / 2))
  })
}

test_that("resolved settings replay asymmetric results on both grids", {
  x <- settings_frame()
  for (grid in c("extent", "endpoint")) {
    result <- mssr(x, fwhm = 2.5, amp = 2, order = 2,
                   intensity_normalize = FALSE, mesh = FALSE,
                   grid = grid, kernel = "square", rounding = "half_up")
    before <- serialize(result, NULL)
    settings <- mssr_settings(result)
    replay <- do.call(mssr, c(list(x = x, max_memory_bytes = 1024^3), settings))
    expect_identical(replay$values, result$values)
    expect_identical(mssr_coords(replay), mssr_coords(result))
    expect_identical(replay$parameters, result$parameters)
    expect_identical(serialize(result, NULL), before)
    expect_false(any(c("x", "half_size", "max_memory_bytes", "max_output_pixels") %in%
                       names(settings)))
  }
})

test_that("saved result settings replay without manually repairing metadata", {
  skip_if_not_installed("digest")
  skip_if_not_installed("jsonlite")
  x <- settings_frame()
  path <- tempfile(fileext = ".mssr")
  withr::defer(unlink(path))
  for (grid in c("extent", "endpoint")) {
    result <- mssr(x, fwhm = 2.5, amp = 2, order = 2,
                   intensity_normalize = FALSE, mesh = FALSE,
                   grid = grid, kernel = "square", rounding = "half_up")
    mssr_write_result(result, path, overwrite = file.exists(path))
    restored <- mssr_read_result(path)
    replay <- do.call(mssr, c(list(x = x), mssr_settings(restored)))
    expect_identical(restored, result)
    expect_identical(replay$values, restored$values)
    expect_identical(replay$transform, restored$transform)
  }
})

test_that("settings validate the record before allowing replay", {
  result <- mssr(settings_frame(), fwhm = 2.5, amp = 2)
  corrupt <- result
  corrupt$parameters$amp <- 3L
  expect_error(mssr_settings(corrupt), class = "mssrscopR_error")
  corrupt <- result
  corrupt$values[1, 1] <- NA_real_
  expect_error(mssr_settings(corrupt), class = "mssrscopR_error")
  for (engine in c("mssr_r_rev1", "mssr_r_rev2")) {
    historical <- result
    historical$engine$id <- engine
    expect_no_error(mssr_validate_result(historical))
    expect_error(mssr_settings(historical), class = "mssrscopR_error_unsupported")
  }
})

test_that("resolved mesh and current-engine legacy schemas remain usable", {
  x <- settings_frame()
  result <- mssr(x, fwhm = 2.5, amp = 1, mesh = TRUE)
  expect_false(mssr_settings(result)$mesh)
  legacy <- result[1:6]
  class(legacy) <- "mssr_result"
  legacy$diagnostics$qualification_scope <- NULL
  legacy$diagnostics$high_order_unqualified <- NULL
  expect_identical(mssr_settings(legacy), mssr_settings(result))
  replay <- do.call(mssr, c(list(x = x), mssr_settings(legacy)))
  expect_identical(replay$values, result$values)
})
