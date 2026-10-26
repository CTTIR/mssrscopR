skip_if_not_installed("digest")

test_that("decoded input identity has a portable independent byte fixture", {
  x <- matrix(1:4, 2, 2)
  got <- mssr_app_input_identity(x)
  # Independently computed from the documented tag and little-endian struct
  # encoding of dimensions (2, 2) and binary64 values (1, 2, 3, 4).
  expect_identical(got$decoded_frame_sha256,
                   "add08791e160f4e4a0b4e81f3981bd872fb7232d4811a56deadc8414e30346d4")
  y <- x * 1.0
  attr(y, "source_path") <- "/private/identity-must-not-be-retained"
  expect_identical(mssr_app_input_identity(y), got)
  expect_false(identical(mssr_app_input_identity(t(x)), got))
  expect_false(identical(mssr_app_input_identity(matrix(x, 1)), got))
  expect_null(got$encoded_file_sha256)
  expect_false(got$filename_retained)
  expect_false(got$authenticity_verified)
  expect_identical(x, matrix(1:4, 2, 2))
})

test_that("upload identity distinguishes encoded bytes from decoded values", {
  first <- withr::local_tempfile(fileext = ".csv")
  second <- withr::local_tempfile(fileext = ".csv")
  writeLines(c("1,3", "2,4"), first)
  writeLines(c("1.0,3.0", "2.0,4.0"), second)
  a <- mssr_app_read_identified(first, "private-name.csv")
  b <- mssr_app_read_identified(second, "another-name.csv")
  expect_identical(a$metadata$identity$decoded_frame_sha256,
                   b$metadata$identity$decoded_frame_sha256)
  expect_false(identical(a$metadata$identity$encoded_file_sha256,
                         b$metadata$identity$encoded_file_sha256))
  expect_identical(a$metadata$identity$encoded_file_sha256,
                   digest::digest(file = first, algo = "sha256", serialize = FALSE))
  expect_false(any(grepl("private-name|another-name", unlist(a$metadata))))
  local_mocked_bindings(mssr_app_read = function(path, ...) {
    writeLines("changed", path)
    list(x = matrix(1:4, 2), metadata = list())
  })
  expect_error(mssr_app_read_identified(first, "changed.csv"),
               class = "mssrscopR_error_integrity")
})

test_that("download availability follows completed results and valid masks", {
  skip_if_not_installed("shiny")
  skip_if_not_installed("bslib")
  skip_if_not_installed("jsonlite")
  local_mocked_bindings(mssr_app_start_job = function(frame, args, mask, run_id) {
    snapshot <- list(frame = frame, args = args, mask = mask, run_id = run_id)
    value <- mssr_app_job_value(snapshot)
    value$source_definition_verified <- TRUE
    list(process = list(is_alive = function() FALSE, get_result = function() value,
                        cleanup = function() invisible()),
         started = proc.time()[["elapsed"]], run_id = run_id, snapshot = snapshot)
  })
  shiny::testServer(mssr_app_server, {
    session$flushReact()
    identity <- run()$metadata$identity
    expect_match(identity$decoded_frame_sha256, "^[0-9a-f]{64}$")
    expect_identical(output$download_ready, "true")
    expect_identical(output$mask_download_ready, "true")
    session$setInputs(fwhm = 0, compute = 1)
    expect_identical(output$download_ready, "false")
    expect_identical(output$mask_download_ready, "false")
    session$setInputs(restore = 1)
    expect_identical(output$download_ready, "true")
    expect_identical(run()$metadata$identity, identity)
    record <- jsonlite::fromJSON(mssr_app_record(run(), run()$source))
    expect_identical(record$record_schema, "1.1.0")
    expect_identical(record$input_metadata$identity$decoded_frame_sha256,
                     identity$decoded_frame_sha256)
    session$setInputs(fwhm = 3, grid = "endpoint", amp = 2, compute = 2)
    expect_identical(output$download_ready, "true")
    expect_identical(output$mask_download_ready, "false")
    session$setInputs(grid = "extent", compute = 3)
    expect_identical(output$mask_download_ready, "true")
  })
})
