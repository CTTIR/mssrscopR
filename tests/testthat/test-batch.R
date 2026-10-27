test_that("sequential batches agree with direct calls and verify reuse", {
  skip_if_not_installed("digest")
  skip_if_not_installed("jsonlite")
  root <- withr::local_tempdir()
  frames <- list(a = matrix(1:12, 3, 4), b = matrix(12:1, 3, 4))
  settings <- list(fwhm = 3, amp = 2, order = 0, intensity_normalize = FALSE)
  first <- mssr_batch(frames, root, settings)
  expect_identical(first$status, rep("complete", 2))
  expect_false(any(first$reused))
  expect_true(file.exists(attr(first, "run_record")))
  for (i in 1:2) {
    actual <- mssr_read_result(first$output[i])
    direct <- do.call(mssr, c(list(x = frames[[i]]), settings))
    expect_identical(actual$values, direct$values)
  }
  second <- mssr_batch(frames, root, settings)
  expect_true(all(second$reused))
  expect_identical(first$output, second$output)
  refused_reuse <- mssr_batch(frames, root, settings, max_memory_bytes = 100)
  expect_identical(refused_reuse$status, rep("failed", 2))
  frames$a[1] <- 17
  changed <- mssr_batch(frames, root, settings)
  expect_identical(changed$reused, c(FALSE, TRUE))
  expect_true(file.exists(first$output[1]))
  settings$order <- 1
  new_settings <- mssr_batch(frames, root, settings)
  expect_false(any(new_settings$reused))
  expect_false(dir.exists(file.path(root, ".mssr-lock")))
})

test_that("matching file hashes cannot conceal mismatched cached settings", {
  skip_if_not_installed("digest")
  skip_if_not_installed("jsonlite")
  root <- withr::local_tempdir()
  x <- matrix(1:12, 3, 4)
  first <- mssr_batch(list(a = x), root, list(fwhm = 3))
  wrong <- mssr(x, fwhm = 5)
  mssr_write_result(wrong, first$output, overwrite = TRUE)
  path <- list.files(root, pattern = "^a-.*json$", full.names = TRUE)
  record <- jsonlite::fromJSON(path, simplifyVector = FALSE)
  record$output_sha256 <- digest::digest(file = first$output, algo = "sha256")
  jsonlite::write_json(record, path, auto_unbox = TRUE)
  actual <- mssr_batch(list(a = x), root, list(fwhm = 3))
  expect_identical(actual$status, "failed")
  expect_match(actual$message, "settings")
  writeLines(paste0(strrep("[", 50), "0", strrep("]", 50)), path)
  expect_identical(mssr_batch(list(a = x), root, list(fwhm = 3))$status, "failed")
})

test_that("failures and cancellation retain the input denominator", {
  skip_if_not_installed("digest")
  skip_if_not_installed("jsonlite")
  root <- withr::local_tempdir()
  frames <- list(good = matrix(1:12, 3, 4), bad = matrix(NA_real_, 3, 4))
  result <- mssr_batch(frames, root, list(fwhm = 3))
  expect_identical(result$status, c("complete", "failed"))
  expect_match(result$message[2], "NA")
  low <- mssr_batch(frames[1], root, list(fwhm = 4), max_memory_bytes = 100)
  expect_identical(low$status, "failed")
  expect_match(low$message, "memory budget")
  stopped <- mssr_batch(frames, root, list(fwhm = 3), cancel = function() TRUE)
  expect_identical(stopped$status, rep("cancelled", 2))
  counter <- 0L
  interrupt <- function() {
    counter <<- counter + 1L
    if (counter == 2L) {
      rlang::cnd_signal(structure(list(message = "stop"), class = c("interrupt", "condition")))
    }
    FALSE
  }
  partial <- mssr_batch(frames, root, list(fwhm = 3), cancel = interrupt)
  expect_identical(partial$status, c("complete", "cancelled"))
})

test_that("corrupt output, records and path aliases cannot become completed reuse", {
  skip_if_not_installed("digest")
  skip_if_not_installed("jsonlite")
  root <- withr::local_tempdir()
  frames <- list(a = matrix(1:12, 3, 4))
  settings <- list(fwhm = 3)
  first <- mssr_batch(frames, root, settings)
  writeBin(as.raw(1:4), first$output)
  bad <- mssr_batch(frames, root, settings)
  expect_identical(bad$status, "failed")
  expect_match(bad$message, "SHA-256")
  record <- list.files(root, pattern = "^a-.*json$", full.names = TRUE)
  writeLines('{"schema":"99"}', record)
  expect_identical(mssr_batch(frames, root, settings)$status, "failed")
  unlink(record)
  if (.Platform$OS.type != "windows") {
    target <- tempfile(tmpdir = root)
    writeLines("preserve", target)
    expect_true(file.symlink(target, record))
    expect_identical(mssr_batch(frames, root, settings)$status, "failed")
    expect_identical(readLines(target), "preserve")
  }
  expect_error(mssr_batch(setNames(frames, "../escape"), root, settings),
               class = "mssrscopR_error_input")
  expect_error(mssr_batch(frames, root, list(x = 3, fwhm = 3)),
               class = "mssrscopR_error_parameter")
  dir.create(file.path(root, ".mssr-lock"))
  expect_error(mssr_batch(frames, root, settings), class = "mssrscopR_error_io")
})

test_that("an unfinished attempt is retained and retried under a distinct filename", {
  skip_if_not_installed("digest")
  skip_if_not_installed("jsonlite")
  root <- withr::local_tempdir()
  frames <- list(a = matrix(1:12, 3, 4))
  settings <- list(fwhm = 3)
  first <- mssr_batch(frames, root, settings)
  path <- list.files(root, pattern = "^a-.*json$", full.names = TRUE)
  record <- jsonlite::fromJSON(path, simplifyVector = FALSE)
  record$status <- "running"
  jsonlite::write_json(record, path, auto_unbox = TRUE)
  retry <- mssr_batch(frames, root, settings)
  expect_identical(retry$status, "complete")
  expect_false(retry$reused)
  expect_false(identical(retry$output, first$output))
  expect_true(file.exists(first$output))
})
