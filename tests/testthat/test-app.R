skip_if_not_installed("shiny")
skip_if_not_installed("bslib")
skip_if_not_installed("jsonlite")

upload <- function(path, name) {
  data.frame(name = name, size = file.size(path), type = "", datapath = path,
             stringsAsFactors = FALSE)
}

test_that("the user interface contains every control and output", {
  html <- as.character(mssr_app_ui())
  ids <- c("source", "example", "file", "channel", "page", "fwhm", "amp", "order",
           "intensity_normalize", "mesh", "kernel", "grid", "rounding", "compute",
           "dl_values", "dl_figure", "dl_record", "palette", "maps", "summary",
           "profile_axis", "profile_index", "profile", "mask_fraction", "mask_seed",
           "dl_mask", "mask_plot", "mask_table", "selftest", "selftest_table", "dark_mode")
  for (id in ids) expect_match(html, sprintf("id=\"%s\"", id), fixed = TRUE)
  expect_match(html, "mssrscopR-www/logo.svg", fixed = TRUE)
  expect_s3_class(mssr_app_object(), "shiny.appobj")
})

test_that("the app computes the default example at start and reports it", {
  shiny::testServer(mssr_app_server, {
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
  shiny::testServer(mssr_app_server, {
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
  shiny::testServer(mssr_app_server, {
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
  shiny::testServer(mssr_app_server, {
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
  shiny::testServer(mssr_app_server, {
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
  shiny::testServer(mssr_app_server, {
    session$setInputs(fwhm = -1, compute = 1)
    expect_error(run(), class = "shiny.silent.error")
  })
  path <- withr::local_tempfile(fileext = ".csv")
  utils::write.table(matrix(c(-1, 2, 3, 4, 5, 6), 2), path, sep = ",",
                     row.names = FALSE, col.names = FALSE)
  shiny::testServer(mssr_app_server, {
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
  shiny::testServer(mssr_app_server, {
    session$setInputs(profile_axis = "col", profile_index = 18)
    expect_identical(guide(), list(axis = "col", index = 18))
    expect_match(output$profile$src, "^data:image/png")
    session$setInputs(profile_axis = "row")
    session$setInputs(profile_index = 99)
    expect_equal(guide(), list(axis = "row", index = 31))
  })
})

test_that("the mask tab measures the original input and needs the extent grid", {
  shiny::testServer(mssr_app_server, {
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
  shiny::testServer(mssr_app_server, {
    session$setInputs(selftest = 1)
    expect_true(attr(selftest(), "all_passed"))
    expect_match(output$selftest_status$html, "14 of 14 fixtures passed.", fixed = TRUE)
    expect_match(output$selftest_table, "fx01", fixed = TRUE)
  })
})

test_that("downloads contain the result, the mask, a figure and a run record", {
  shiny::testServer(mssr_app_server, {
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
    expect_identical(rec$engine$id, "mssr_r_rev2")
    expect_identical(rec$parameters$amp, 2L)
    expect_identical(rec$transform$first_center$row, 0.75)
    expect_identical(rec$mask$fraction, 0.5)
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
  shiny::testServer(mssr_app_server, {
    light <- output$maps$src
    before <- run()$result$values
    session$setInputs(dark_mode = "dark", palette = "viridis")
    expect_true(dark())
    expect_false(identical(output$maps$src, light))
    expect_identical(run()$result$values, before)
  })
})
