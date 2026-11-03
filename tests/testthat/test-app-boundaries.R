skip_if_not_installed("jsonlite")

test_that("app CSV preserves finite computed values at binary64 limits", {
  path <- withr::local_tempfile(fileext = ".csv")
  x <- matrix(0, 5, 7)
  x[3, 4] <- .Machine$double.xmax
  result <- mssr(x, fwhm = 2, amp = 1, order = 0)
  mssr_app_write_matrix(result$values, path)
  restored <- mssr_app_read(path, "result.csv")$x
  expect_true(all(is.finite(restored)))
  expect_identical(restored, result$values)

  # The CSV is a numerical download, independent of display precision/locale.
  values <- matrix(c(.Machine$double.xmax, -.Machine$double.xmax,
                     .Machine$double.xmin, 2^-1074, pi, 1 / 3, 0, 1), 2)
  withr::local_options(list(digits = 3, OutDec = ","))
  mssr_app_write_matrix(values, path)
  restored <- mssr_app_read(path, "result.csv")$x
  expect_identical(restored, values)
})

test_that("signed profiles keep every displayed value within the plot range", {
  x <- matrix(c(-2, -1, 1, -1, 2, -1, 1, 2, 1), 3, 3)
  expect_warning(result <- mssr(x, fwhm = 2, amp = 1, order = 0),
                 class = "mssrscopR_warning_negative")
  profile <- mssr_app_profile(x, result, "row", 1L)
  grDevices::pdf(withr::local_tempfile(fileext = ".pdf"))
  withr::defer(grDevices::dev.off())
  mssr_app_plot_profile(x, result, "row", 1L)
  limits <- graphics::par("usr")[3:4]
  values <- c(profile$val_in, profile$val_out)
  expect_lte(limits[1], min(values))
  expect_gte(limits[2], max(values))
})

test_that("profile scaling reports when a nonpositive line is unchanged", {
  x <- matrix(c(-4, 1, -2, 2, -1, 3), 2, 3)
  expect_warning(result <- mssr(x, fwhm = 2, amp = 1, order = 0),
                 class = "mssrscopR_warning_negative")
  profile <- mssr_app_profile(x, result, "row", 1L)
  expect_identical(profile$val_in, x[1, ])
  expect_identical(profile$normalization_in, "original values (no positive maximum)")
  expect_identical(profile$normalization_out, "original values (no positive maximum)")
  positive <- mssr_app_profile(x, result, "row", 2L)
  expect_identical(positive$val_in, x[2, ] / max(x[2, ]))
  expect_identical(positive$normalization_in, "divided by positive line maximum")
})

test_that("numbers-only uploads do not silently remove comment rows or fields", {
  path <- withr::local_tempfile()
  for (name in c("frame.txt", "frame.tsv")) {
    for (lines in list(c("1 2", "#3 4", "5 6"), c("1 2 #3", "4 5 #6"))) {
      writeLines(lines, path)
      expect_error(mssr_app_read(path, name), "numbers only", class = "mssrscopR_error_input")
    }
    writeLines(c("1\t2", "3\t4"), path)
    expect_identical(mssr_app_read(path, name)$x, matrix(c(1, 3, 2, 4), 2))
  }
})

test_that("text parsing preserves ordinary numeric syntax and rejects partial tokens", {
  path <- withr::local_tempfile()
  writeLines(c("+1,.5,1.,0001.25,1e+03,0x1p2", "-1,-.5,-1.,-0001.25,-1e+03,-0x1p2"), path)
  expected <- rbind(c(1, 0.5, 1, 1.25, 1000, 4), c(-1, -0.5, -1, -1.25, -1000, -4))
  expect_identical(mssr_app_read(path, "syntax.csv")$x, expected)
  for (token in c("1oops", "1e", "0x", "1;2", "1#2", "[1]")) {
    writeLines(paste(token, "2", sep = ","), path)
    expect_error(mssr_app_read(path, "invalid.csv"), class = "mssrscopR_error_input")
  }
  for (token in c("NA", "NaN", "Inf", "-Inf", "1e309")) {
    writeLines(paste(token, "2", sep = ","), path)
    expect_error(mssr_app_read(path, "invalid.csv"), class = "mssrscopR_error_nonfinite")
  }
  writeLines(c("1,2", "3,4,5"), path)
  expect_error(mssr_app_read(path, "ragged.csv"), class = "mssrscopR_error_input")
})

test_that("CSV re-upload retains the exact decoded identity and separate byte identity", {
  skip_if_not_installed("digest")
  x <- matrix(c(.Machine$double.xmax, 2^-1074, 1 / 3, pi), 2)
  path <- withr::local_tempfile(fileext = ".csv")
  mssr_app_write_matrix(x, path)
  frame <- mssr_app_read_identified(path, "private-name.csv")
  expected <- mssr_app_input_identity(x)
  expect_identical(frame$x, x)
  expect_identical(frame$metadata$identity$decoded_frame_sha256,
                   expected$decoded_frame_sha256)
  expect_identical(frame$metadata$identity$encoded_file_sha256,
                   digest::digest(file = path, algo = "sha256", serialize = FALSE))
  expect_identical(frame$metadata$numeric_parser[["decimal"]], "jsonlite::fromJSON")
  expect_false(grepl("private-name", paste(unlist(frame$metadata), collapse = " ")))
})
