skip_if_not_installed("shiny")
skip_if_not_installed("bslib")
skip_if_not_installed("jsonlite")

upload <- function(path, name) {
  data.frame(name = name, size = file.size(path), type = "", datapath = path,
             stringsAsFactors = FALSE)
}

# Fast state/render tests use an immediate handle; real child-process tests are
# separate and exercise the same job-value path plus lifecycle behavior.
app_test_job <- function(frame, args, mask, run_id) {
  snapshot <- list(frame = frame, args = args, mask = mask, run_id = run_id)
  value <- mssr_app_job_value(snapshot)
  value$source_definition_verified <- TRUE
  list(process = list(is_alive = function() FALSE, get_result = function() value,
                      cleanup = function() invisible(), wait = function(...) invisible(),
                      kill = function() invisible()),
       started = proc.time()[["elapsed"]], run_id = run_id, snapshot = snapshot)
}

test_that("the user interface contains every control and output", {
  html <- as.character(mssr_app_ui())
  ids <- c("source", "example", "file", "channel", "page", "fwhm", "amp", "order",
           "intensity_normalize", "mesh", "kernel", "grid", "rounding", "compute",
           "dl_values", "dl_figure", "dl_record", "palette", "maps", "summary",
           "profile_axis", "profile_index", "profile", "mask_fraction", "mask_seed",
           "dl_mask", "mask_plot", "mask_table", "selftest", "selftest_table", "dark_mode")
  for (id in ids) expect_match(html, sprintf("id=\"%s\"", id), fixed = TRUE)
  expect_match(html, "cttir-app-brand", fixed = TRUE)
  expect_false(grepl(" resizable=", html, fixed = TRUE))
  expect_s3_class(mssr_app_object(), "shiny.appobj")
})

test_that("the app computes the default example at start and reports it", {
  local_mocked_bindings(mssr_app_start_job = app_test_job)
  shiny::testServer(mssr_app_server, {
    session$flushReact()
    r <- run()
    expect_s3_class(r$result, "mssr_result")
    expect_identical(r$source, "example:pair_3")
    expect_identical(r$result$values, mssr(mssr_app_example("pair_3"), fwhm = 3, amp = 2)$values)
    expect_match(output$summary, "input 31 x 41 -> output 62 x 82", fixed = TRUE)
    expect_match(output$summary, "Not a quantitative intensity", fixed = TRUE)
    expect_match(output$maps$src, "^data:image/png;base64,")
    expect_match(output$profile$src, "^data:image/png;base64,")
    expect_null(output$stale)
  })
})

test_that("parameter changes are applied on Compute and flagged until then", {
  local_mocked_bindings(mssr_app_start_job = app_test_job)
  shiny::testServer(mssr_app_server, {
    session$flushReact()
    session$setInputs(fwhm = 3, amp = 1, order = 2, kernel = "square", compute = 0)
    expect_identical(run()$result$parameters$kernel, "square")
    session$setInputs(fwhm = 4)
    expect_match(output$stale$html, "press Compute")
    expect_identical(run()$result$parameters$fwhm, 3)
    session$setInputs(compute = 1)
    expect_identical(run()$result$parameters$fwhm, 4)
    expect_null(output$stale)
  })
})

test_that("changing the example recomputes without pressing Compute", {
  local_mocked_bindings(mssr_app_start_job = app_test_job)
  shiny::testServer(mssr_app_server, {
    session$flushReact()
    session$setInputs(source = "example", example = "disk")
    expect_identical(run()$source, "example:disk")
    expect_identical(dim(run()$x), c(31L, 41L))
  })
})

test_that("all synthetic examples are valid frames", {
  for (id in mssr_app_examples) {
    x <- mssr_app_example(id)
    expect_identical(dim(x), c(31L, 41L))
    expect_true(all(is.finite(x)) && all(x >= 0))
  }
  expect_error(mssr_app_example("nope"), class = "mssrscopR_error_parameter")
})

test_that("uploaded text frames are read and processed", {
  path <- withr::local_tempfile(fileext = ".csv")
  x <- matrix(seq_len(35) %% 7 + 1, 5, 7)
  utils::write.table(x, path, sep = ",", row.names = FALSE, col.names = FALSE)
  local_mocked_bindings(mssr_app_start_job = app_test_job)
  shiny::testServer(mssr_app_server, {
    session$flushReact()
    session$setInputs(source = "upload", file = upload(path, "frame.csv"), amp = 1)
    r <- run()
    expect_identical(r$source, "upload")
    expect_match(r$info, "Text table, 5 x 7", fixed = TRUE)
    expect_equal(r$x, x, ignore_attr = TRUE)
  })
  tsv <- withr::local_tempfile(fileext = ".txt")
  utils::write.table(x, tsv, sep = "\t", row.names = FALSE, col.names = FALSE)
  expect_equal(mssr_app_read(tsv, "frame.txt")$x, x, ignore_attr = TRUE)
})

test_that("unreadable uploads become notifications, not crashes", {
  bad <- withr::local_tempfile(fileext = ".csv")
  writeLines(c("a,b", "1,2"), bad)
  expect_error(mssr_app_read(bad, "bad.csv"), class = "mssrscopR_error_input")
  expect_error(mssr_app_read(bad, "bad.jpg"), class = "mssrscopR_error_input")
  expect_error(mssr_app_read(bad, "noextension"), class = "mssrscopR_error_input")
  local_mocked_bindings(mssr_app_start_job = app_test_job)
  shiny::testServer(mssr_app_server, {
    session$flushReact()
    session$setInputs(source = "upload", file = upload(bad, "bad.csv"))
    expect_null(frame())
    expect_error(run(), class = "shiny.silent.error")
  })
})

test_that("PNG uploads use the chosen channel", {
  skip_if_not_installed("png")
  path <- withr::local_tempfile(fileext = ".png")
  rgb <- array(0, c(6, 8, 3))
  rgb[, , 2] <- outer(1:6, 1:8) / 48
  png::writePNG(rgb, path)
  got <- mssr_app_read(path, "img.PNG", channel = 2)
  expect_equal(got$x, rgb[, , 2], tolerance = 1 / 255)
  expect_match(got$info, "PNG, 6 x 8, 3 channel(s) (using 2)", fixed = TRUE)
  expect_error(mssr_app_read(path, "img.png", channel = 4), class = "mssrscopR_error_parameter")
  gray <- withr::local_tempfile(fileext = ".png")
  png::writePNG(rgb[, , 2], gray)
  expect_match(mssr_app_read(gray, "g.png")$info, "1 channel(s)", fixed = TRUE)
})

test_that("one-pixel image axes survive channel selection", {
  skip_if_not_installed("png")
  skip_if_not_installed("tiff")
  for (dims in list(c(1L, 8L, 3L), c(8L, 1L, 3L), c(1L, 1L, 3L))) {
    rgb <- array(seq_len(prod(dims)) / prod(dims), dims)
    p <- withr::local_tempfile(fileext = ".png")
    png::writePNG(rgb, p)
    got <- mssr_app_read(p, "thin.png", channel = 2)$x
    expect_identical(dim(got), dims[1:2])
    expect_equal(c(got), c(rgb[, , 2]), tolerance = 1 / 255)
    t <- withr::local_tempfile(fileext = ".tif")
    tiff::writeTIFF(rgb, t)
    got <- mssr_app_read(t, "thin.tif", channel = 2)$x
    expect_identical(dim(got), dims[1:2])
    expect_equal(c(got) / 255, c(rgb[, , 2]), tolerance = 1 / 255)
  }
})

test_that("invalid image uploads use classed errors and app notifications", {
  skip_if_not_installed("png")
  skip_if_not_installed("tiff")
  path <- withr::local_tempfile()
  writeLines("not an image", path)
  for (name in c("broken.png", "broken.tif")) {
    expect_error(mssr_app_read(path, name), class = "mssrscopR_error_input")
    local_mocked_bindings(mssr_app_start_job = app_test_job)
    shiny::testServer(mssr_app_server, {
      session$flushReact()
      session$setInputs(source = "upload", file = upload(path, name))
      expect_null(frame())
      expect_error(run(), class = "shiny.silent.error")
    })
  }
})

test_that("oversized PNG headers are refused before decoding", {
  skip_if_not_installed("png")
  path <- withr::local_tempfile(fileext = ".png")
  con <- file(path, "wb")
  writeBin(as.raw(c(137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82)), con)
  writeBin(c(100000L, 100000L), con, size = 4, endian = "big")
  writeBin(as.raw(c(8, 2)), con)
  close(con)
  local_mocked_bindings(readPNG = function(...) cli::cli_abort("decoder must not run"),
                        .package = "png")
  expect_error(mssr_app_read(path, "large.png"), class = "mssrscopR_error_resource")
})

test_that("TIFF headers are checked before decoding only the selected page", {
  skip_if_not_installed("tiff")
  local_mocked_bindings(mssr_app_tiff_preflight = function(...) list(pages = 2L))
  calls <- list()
  meta <- data.frame(width = c(1e5, 3), length = c(1e5, 2), samples.per.pixel = c(1, 1),
                     bits.per.sample = c(8, 8))
  local_mocked_bindings(readTIFF = function(source, all, payload = TRUE, ...) {
    args <- list(...)
    calls[[length(calls) + 1L]] <<- list(all = all, payload = payload, as.is = args$as.is)
    if (!payload) return(meta)
    expect_identical(all, 2L)
    list(matrix(1:6 / 255, 2, 3))
  }, .package = "tiff")
  expect_error(mssr_app_read("unused", "large.tif"), class = "mssrscopR_error_resource")
  expect_length(calls, 1L)
  expect_false(calls[[1]]$payload)
  got <- mssr_app_read("unused", "stack.tif", page = 2)
  expect_equal(got$x, matrix(1:6, 2, 3))
  expect_length(calls, 3L)
  expect_false(calls[[3]]$as.is)
  expect_match(got$info, "page 2 of 2", fixed = TRUE)
})

# Minimal little-endian TIFF with four IEEE 754 float samples, one strip.
# The package's TIFF writer writes integer samples, so construct this small
# independent reader fixture directly from the format fields.
write_sample_tiff <- function(path, values, sample_format = 3L) {
  con <- file(path, "wb")
  on.exit(close(con))
  writeBin(as.integer(c(0x4949, 42)), con, size = 2, endian = "little")
  writeBin(8L, con, size = 4, endian = "little")
  tags <- c(256L, 257L, 258L, 259L, 262L, 273L, 277L, 278L, 279L, 284L, 339L)
  vals <- c(2L, 2L, 32L, 1L, 1L, 146L, 1L, 2L, 16L, 1L, sample_format)
  types <- c(4L, 4L, 3L, 3L, 3L, 4L, 3L, 4L, 4L, 3L, 3L)
  writeBin(length(tags), con, size = 2, endian = "little")
  for (i in seq_along(tags)) {
    writeBin(c(tags[i], types[i]), con, size = 2, endian = "little")
    writeBin(c(1L, vals[i]), con, size = 4, endian = "little")
  }
  writeBin(0L, con, size = 4, endian = "little")
  if (sample_format == 3L) {
    writeBin(values, con, size = 4, endian = "little")
  } else {
    for (v in values) writeBin(as.raw(floor(v / 256^(0:3)) %% 256), con)
  }
}

test_that("floating TIFF samples remain unscaled", {
  skip_if_not_installed("tiff")
  path <- withr::local_tempfile(fileext = ".tif")
  write_sample_tiff(path, c(-0.5, 0.25, 2.5, 1e8))
  got <- mssr_app_read(path, "float.tif")
  expect_identical(got$x, matrix(c(-0.5, 0.25, 2.5, 1e8), 2, 2, byrow = TRUE))
})

test_that("unsigned 32-bit TIFF samples above the R integer limit are preserved", {
  skip_if_not_installed("tiff")
  path <- withr::local_tempfile(fileext = ".tif")
  values <- c(0, 2^31, 3e9, 2^32 - 1)
  write_sample_tiff(path, values, sample_format = 1L)
  expect_identical(mssr_app_read(path, "uint32.tif")$x, matrix(values, 2, 2, byrow = TRUE))
})

test_that("TIFF formats with ambiguous stored values are rejected", {
  meta <- data.frame(bits.per.sample = 16, sample.format = "int", color.space = "black is zero")
  expect_error(mssr_app_tiff_scale(meta), class = "mssrscopR_error_unsupported")
  meta$sample.format <- "uint"
  meta$color.space <- "palette"
  expect_error(mssr_app_tiff_scale(meta), class = "mssrscopR_error_unsupported")
})

# Independent 2 x 2 RGB TIFF whose three sample planes occupy separate strips.
write_planar_tiff <- function(path) {
  con <- file(path, "wb")
  on.exit(close(con))
  writeBin(as.integer(c(0x4949, 42)), con, size = 2, endian = "little")
  writeBin(8L, con, size = 4, endian = "little")
  tags <- c(256L, 257L, 258L, 259L, 262L, 273L, 277L, 278L, 279L, 284L, 339L)
  types <- c(4L, 4L, 3L, 3L, 3L, 4L, 3L, 4L, 4L, 3L, 3L)
  counts <- c(1L, 1L, 3L, 1L, 1L, 3L, 1L, 1L, 3L, 1L, 3L)
  vals <- c(2L, 2L, 146L, 1L, 2L, 152L, 3L, 2L, 164L, 2L, 176L)
  writeBin(length(tags), con, size = 2, endian = "little")
  for (i in seq_along(tags)) {
    writeBin(c(tags[i], types[i]), con, size = 2, endian = "little")
    writeBin(c(counts[i], vals[i]), con, size = 4, endian = "little")
  }
  writeBin(0L, con, size = 4, endian = "little")
  writeBin(rep(8L, 3), con, size = 2, endian = "little")
  writeBin(c(182L, 186L, 190L), con, size = 4, endian = "little")
  writeBin(rep(4L, 3), con, size = 4, endian = "little")
  writeBin(rep(1L, 3), con, size = 2, endian = "little")
  writeBin(as.raw(c(1:4, 11:14, 21:24)), con)
}

test_that("multi-channel planar-separate TIFF is refused before decoding", {
  skip_if_not_installed("tiff")
  path <- withr::local_tempfile(fileext = ".tif")
  write_planar_tiff(path)
  reader <- tiff::readTIFF
  calls <- 0L
  local_mocked_bindings(readTIFF = function(...) {
    args <- list(...)
    expect_false(args$payload)
    calls <<- calls + 1L
    reader(...)
  }, .package = "tiff")
  expect_error(mssr_app_read(path, "planar.tif"), "planar-separate",
               class = "mssrscopR_error_unsupported")
  expect_identical(calls, 1L)
  gray <- data.frame(planar.config = "separate", samples.per.pixel = 1, bits.per.sample = 8)
  expect_equal(mssr_app_tiff_scale(gray), 255)
})

test_that("TIFF uploads keep stored values and select pages", {
  skip_if_not_installed("tiff")
  path <- withr::local_tempfile(fileext = ".tif")
  a <- matrix(c(0, 1000, 2000, 4095), 2, 2)
  b <- matrix(c(10, 20, 30, 40), 2, 2)
  tiff::writeTIFF(list(a / 65535, b / 65535), path, bits.per.sample = 16L)
  p1 <- mssr_app_read(path, "stack.tif")
  expect_equal(p1$x, a)
  expect_match(p1$info, "page 1 of 2", fixed = TRUE)
  expect_equal(mssr_app_read(path, "stack.tiff", page = 2)$x, b)
  expect_error(mssr_app_read(path, "stack.tif", page = 3), class = "mssrscopR_error_parameter")
})

test_that("volumetric TIFF pages are refused before decoding", {
  skip_if_not_installed("tiff")
  local_mocked_bindings(mssr_app_tiff_preflight = function(...) list(pages = 1L))
  calls <- 0L
  local_mocked_bindings(readTIFF = function(...) {
    args <- list(...)
    expect_false(args$payload)
    calls <<- calls + 1L
    data.frame(width = 2, length = 2, depth = 3, samples.per.pixel = 1, bits.per.sample = 8)
  }, .package = "tiff")
  expect_error(mssr_app_read("unused", "volume.tif"), "2D page",
               class = "mssrscopR_error_unsupported")
  expect_identical(calls, 1L)
})

test_that("missing optional readers give a classed error", {
  local_mocked_bindings(mssr_app_missing = function(pkgs) pkgs)
  expect_error(mssr_app_need("png", "PNG files"), class = "mssrscopR_error_dependency")
})

test_that("runs above the app work limit are refused before computing", {
  args <- list(fwhm = 3, amp = 8L, order = 1L, intensity_normalize = TRUE, mesh = TRUE,
               grid = "extent", kernel = "disk", rounding = "half_even")
  expect_gt(mssr_app_work(c(512, 512), args), mssr_app_work_limit)
  expect_error(mssr_app_compute(matrix(1, 512, 512), args), class = "mssrscopR_error_resource")
  sq <- utils::modifyList(args, list(kernel = "square", amp = 1L))
  expect_identical(mssr_app_work(c(10, 10), sq), 100 * ((2 * 2 + 1)^2 - 1))
  expect_true(is.na(mssr_app_work(c(10, 10), utils::modifyList(args, list(fwhm = NA)))))
})

test_that("package errors and warnings are shown as notifications", {
  local_mocked_bindings(mssr_app_start_job = app_test_job)
  shiny::testServer(mssr_app_server, {
    session$flushReact()
    session$setInputs(fwhm = -1, compute = 1)
    expect_error(run(), class = "shiny.silent.error")
  })
  path <- withr::local_tempfile(fileext = ".csv")
  utils::write.table(matrix(c(-1, 2, 3, 4, 5, 6), 2), path, sep = ",",
                     row.names = FALSE, col.names = FALSE)
  local_mocked_bindings(mssr_app_start_job = app_test_job)
  shiny::testServer(mssr_app_server, {
    session$flushReact()
    session$setInputs(source = "upload", file = upload(path, "neg.csv"), amp = 1)
    expect_no_warning(r <- run())
    expect_s3_class(r$result, "mssr_result")
  })
})

test_that("profiles follow the nearest output line in input coordinates", {
  x <- mssr_app_example("pair_3")
  res <- mssr(x, fwhm = 3, amp = 2)
  pr <- mssr_app_profile(x, res, "row", 16L)
  expect_equal(pr$center, 16)
  expect_equal(max(pr$val_in), 1)
  expect_equal(max(pr$val_out), 1)
  pc <- mssr_app_profile(x, res, "col", 18L)
  expect_length(pc$pos_in, 31L)
  expect_length(pc$val_out, 62L)
  flat <- mssr(matrix(1, 4, 4), fwhm = 2)
  expect_identical(mssr_app_profile(matrix(1, 4, 4), flat, "row", 2L)$val_out, rep(0, 4))
  local_mocked_bindings(mssr_app_start_job = app_test_job)
  shiny::testServer(mssr_app_server, {
    session$flushReact()
    session$setInputs(profile_axis = "col", profile_index = 18)
    expect_identical(guide(), list(axis = "col", index = 18))
    expect_match(output$profile$src, "^data:image/png")
    session$setInputs(profile_axis = "row")
    session$setInputs(profile_index = 99)
    expect_equal(guide(), list(axis = "row", index = 31))
  })
})

test_that("profile numeric edits require one finite input-pixel position", {
  local_mocked_bindings(mssr_app_start_job = app_test_job)
  shiny::testServer(mssr_app_server, {
    session$flushReact()
    completed <- run()$result$values
    # Shiny's numeric input handler maps a blank browser value to NA.
    for (invalid in list(16.5, NA_real_, NaN, Inf, -Inf)) {
      session$setInputs(profile_index = invalid)
      expect_error(guide(), "finite whole number", class = "shiny.silent.error")
      expect_error(output$profile, "finite whole number", class = "shiny.silent.error")
      expect_error(output$profile_table, "finite whole number", class = "shiny.silent.error")
      expect_error(output$maps, "finite whole number", class = "shiny.silent.error")
      expect_identical(run()$result$values, completed)
    }
    session$setInputs(profile_index = 16)
    expect_equal(guide(), list(axis = "row", index = 16))
    expect_match(output$profile$src, "^data:image/png")
    expect_match(output$maps$src, "^data:image/png")
    expect_match(output$profile_table, "position_input_pixels", fixed = TRUE)
    session$setInputs(profile_index = 99)
    expect_equal(guide()$index, 31)
    session$setInputs(profile_index = -2)
    expect_equal(guide()$index, 1)
  })
})

test_that("the mask tab measures the original input and needs the extent grid", {
  local_mocked_bindings(mssr_app_start_job = app_test_job)
  shiny::testServer(mssr_app_server, {
    session$flushReact()
    session$setInputs(mask_fraction = 0.2, mask_seed = 3)
    m <- mask()
    expect_identical(m$mask, mssr_mask(run()$result, fraction = 0.2, seed = 3))
    expect_match(output$mask_table, "input mean inside the mask", fixed = TRUE)
    expect_match(output$mask_plot$src, "^data:image/png")
    expect_match(output$mask_warning$html, "no structure", fixed = TRUE)
    session$setInputs(mask_fraction = 0.01)
    expect_null(output$mask_warning)
    session$setInputs(grid = "endpoint", compute = 1)
    expect_error(mask(), class = "validation")
  })
  x <- matrix(1:4, 2)
  all_in <- structure(matrix(TRUE, 2, 2), coverage = 1, tie_fraction = 0, cut_relative = 0.5)
  tab <- mssr_app_mask_table(x, all_in)
  expect_identical(tab$value[6], "NA")
})

test_that("the self-test runs on request", {
  local_mocked_bindings(mssr_app_start_job = app_test_job)
  shiny::testServer(mssr_app_server, {
    session$flushReact()
    session$setInputs(selftest = 1)
    expect_true(attr(selftest(), "all_passed"))
    expect_match(output$selftest_status$html, "14 of 14 fixtures passed.", fixed = TRUE)
    expect_match(output$selftest_table, "fx01", fixed = TRUE)
  })
})

test_that("downloads contain the result, the mask, a figure and a run record", {
  local_mocked_bindings(mssr_app_start_job = app_test_job)
  shiny::testServer(mssr_app_server, {
    session$flushReact()
    session$setInputs(mask_fraction = 0.5)
    values <- unname(as.matrix(utils::read.csv(output$dl_values, header = FALSE)))
    expect_equal(values, run()$result$values, tolerance = 1e-12)
    m <- unname(as.matrix(utils::read.csv(output$dl_mask, header = FALSE)))
    expect_identical(m, matrix(as.integer(mask()$mask), nrow(m)))
    if (requireNamespace("png", quietly = TRUE)) {
      expect_identical(dim(png::readPNG(output$dl_figure))[1:2], c(1150L, 2400L))
    }
    rec <- jsonlite::fromJSON(output$dl_record)
    expect_identical(rec$source, "example:pair_3")
    expect_identical(rec$engine$id, "mssr_r_rev3")
    expect_identical(rec$parameters$amp, 2L)
    expect_identical(rec$transform$first_center$row, 0.75)
    expect_identical(rec$mask$fraction, 0.5)
    expect_equal(rec$mask$cut_relative, attr(mask()$mask, "cut_relative"))
    expect_false(rec$diagnostics$quantitative)
  })
})

test_that("mssr_app() checks its dependencies and launches", {
  local_mocked_bindings(mssr_app_missing = function(pkgs) "bslib")
  expect_error(mssr_app(), class = "mssrscopR_error_dependency")
  local_mocked_bindings(mssr_app_missing = function(pkgs) character())
  expect_error(mssr_app(max_upload_mb = 0), class = "mssrscopR_error_parameter")
  local_mocked_bindings(runApp = function(app, ...) {
    list(app = app, max = getOption("shiny.maxRequestSize"), dots = list(...))
  }, .package = "shiny")
  got <- withVisible(mssr_app(max_upload_mb = 2, port = 1234))
  expect_false(got$visible)
  expect_s3_class(got$value$app, "shiny.appobj")
  expect_identical(got$value$max, 2 * 1024^2)
  expect_identical(got$value$dots$port, 1234)
  expect_false(identical(getOption("shiny.maxRequestSize"), 2 * 1024^2))
})

test_that("the maps can be stacked for narrow screens", {
  x <- mssr_app_example("pair_3")
  res <- mssr(x, fwhm = 3, amp = 2)
  path <- withr::local_tempfile(fileext = ".png")
  grDevices::png(path, width = 400, height = 760)
  mssr_app_plot_maps(x, res, stacked = TRUE, guide = list(axis = "col", index = 20))
  expect_identical(graphics::par("mfrow"), c(1L, 1L))
  grDevices::dev.off()
  expect_gt(file.size(path), 0)
})

test_that("palettes and dark mode change the rendering, not the result", {
  expect_length(mssr_app_palette("viridis"), 256L)
  expect_false(identical(mssr_app_palette("inferno"), mssr_app_palette("gray")))
  expect_false(identical(mssr_app_colors(TRUE), mssr_app_colors(FALSE)))
  local_mocked_bindings(mssr_app_start_job = app_test_job)
  shiny::testServer(mssr_app_server, {
    session$flushReact()
    light <- output$maps$src
    before <- run()$result$values
    session$setInputs(dark_mode = "dark", palette = "viridis")
    expect_true(dark())
    expect_false(identical(output$maps$src, light))
    expect_identical(run()$result$values, before)
  })
})

test_that("stale exports retain actual settings and original-data mask provenance", {
  local_mocked_bindings(mssr_app_start_job = app_test_job)
  shiny::testServer(mssr_app_server, {
    session$flushReact()
    session$setInputs(fwhm = 3, amp = 1, compute = 0, mask_fraction = 0.1)
    before <- run()$result$values
    session$setInputs(fwhm = 8)
    rec <- jsonlite::fromJSON(output$dl_record)
    expect_true(rec$controls_stale)
    expect_identical(rec$completion_state, "complete")
    expect_identical(rec$record_schema, "1.1.0")
    expect_identical(rec$parameters$fwhm, 3L)
    expect_identical(rec$input_metadata$format, "synthetic")
    expect_null(rec$input_metadata$physical_sampling)
    expect_identical(rec$mask$measurement_source, "original_input")
    expect_false(rec$mask$selection_bias_assessed)
    expect_equal(rec$mask$input_mean_all, mean(run()$x), tolerance = 1e-12)
    expect_equal(rec$mask$input_mean_selected, mean(run()$x[mask()$mask]), tolerance = 1e-12)
    expect_equal(unname(as.matrix(utils::read.csv(output$dl_values, header = FALSE))), before,
                 tolerance = 1e-12)
    expect_match(output$stale$html, "Downloads contain the last computed")
  })
})

test_that("app plots have text alternatives and dynamic status regions", {
  html <- as.character(mssr_app_ui())
  expect_match(html, 'aria-live="polite"', fixed = TRUE)
  expect_match(html, 'role="status"', fixed = TRUE)
  expect_match(html, 'for="palette"', fixed = TRUE)
  expect_match(html, "Input source", fixed = TRUE)
  expect_match(mssr_app_css, ":focus-visible", fixed = TRUE)
  expect_match(html, "Cancel computation", fixed = TRUE)
  local_mocked_bindings(mssr_app_start_job = app_test_job)
  shiny::testServer(mssr_app_server, {
    session$flushReact()
    expect_match(output$maps$alt, "shared input-pixel coordinates", fixed = TRUE)
    expect_match(output$profile$alt, "Profile values table", fixed = TRUE)
    expect_match(output$mask_plot$alt, "pixels selected", fixed = TRUE)
    expect_match(output$profile_table, "value_divided_by_line_maximum", fixed = TRUE)
  })
})
