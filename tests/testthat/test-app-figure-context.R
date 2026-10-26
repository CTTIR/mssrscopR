test_that("figure downloads retain completed settings and the JSON run identity", {
  skip_if_not_installed("shiny")
  skip_if_not_installed("bslib")
  skip_if_not_installed("jsonlite")
  immediate_job <- function(frame, args, mask, run_id) {
    snapshot <- list(frame = frame, args = args, mask = mask, run_id = run_id)
    value <- mssr_app_job_value(snapshot)
    value$source_definition_verified <- TRUE
    list(process = list(is_alive = function() FALSE, get_result = function() value,
                        cleanup = function() invisible(), wait = function(...) invisible(),
                        kill = function() invisible()),
         started = proc.time()[["elapsed"]], run_id = run_id, snapshot = snapshot)
  }
  drawn <- NULL
  plot_maps <- mssr_app_plot_maps
  local_mocked_bindings(
    mssr_app_start_job = immediate_job,
    mssr_app_plot_maps = function(x, res, ..., run_id = NULL) {
      if (!is.null(run_id)) drawn <<- list(result = res, run_id = run_id)
      plot_maps(x, res, ..., run_id = run_id)
    }
  )
  shiny::testServer(mssr_app_server, {
    session$flushReact()
    session$setInputs(fwhm = 9, amp = 3, order = 2)
    record <- jsonlite::fromJSON(output$dl_record)
    expect_true(record$controls_stale)
    expect_gt(file.size(output$dl_figure), 0)
    expect_identical(drawn$run_id, record$run_id)
    expect_equal(drawn$result$parameters$fwhm, record$parameters$fwhm)
    expect_equal(drawn$result$parameters$amp, record$parameters$amp)
    expect_equal(drawn$result$parameters$order, record$parameters$order)
    caption <- mssr_app_figure_caption(drawn$result, drawn$run_id)
    expect_match(paste(caption, collapse = " "),
                 "Non-quantitative MSSR structure map", fixed = TRUE)
    expect_match(paste(caption, collapse = " "), "independently display-scaled", fixed = TRUE)
    expect_match(paste(caption, collapse = " "),
                 "FWHM 3 input px; amplification 2; order 1; grid extent.", fixed = TRUE)
    expect_match(paste(caption, collapse = " "), record$run_id, fixed = TRUE)
  })
})

test_that("figure context wraps long identifiers and remains inside wide and portrait rasters", {
  skip_if_not_installed("png")
  x <- matrix(2, 9, 13)
  x[2, 3] <- 80
  x[7, 11] <- 40
  result <- mssr(x, fwhm = 3, amp = 2)
  run_id <- paste0("20261024T190000-", paste(rep("1234567890abcdef", 12), collapse = ""))
  rendered_text <- NULL
  rendered_line <- NULL
  mtext <- graphics::mtext
  local_mocked_bindings(mtext = function(text, ...) {
    rendered_text <<- text
    rendered_line <<- list(...)$line
    mtext(text, ...)
  }, .package = "graphics")
  for (dims in list(c(2400, 1150), c(1200, 2000))) {
    path <- withr::local_tempfile(fileext = ".png")
    grDevices::png(path, width = dims[1], height = dims[2], res = 200)
    previous <- graphics::par(c("mfrow", "oma"))
    mssr_app_plot_maps(x, result, stacked = dims[1] < dims[2], run_id = run_id)
    expect_identical(graphics::par(c("mfrow", "oma")), previous)
    grDevices::dev.off()
    # Every identifier character reaches the actual drawing call, including
    # the suffix beyond the first wrapped line.
    compact <- gsub("[[:space:]]", "", paste(rendered_text, collapse = ""))
    expect_match(compact, paste0("RunID:", run_id), fixed = TRUE)
    expect_true(all(diff(rendered_line) > 0))
    raster <- png::readPNG(path)
    expect_identical(dim(raster)[1:2], as.integer(rev(dims)))
    caption_band <- raster[seq.int(floor(dims[2] * 0.8), dims[2]), , 1:3, drop = FALSE]
    expect_gt(sum(caption_band < 0.8), 100)
    # The bottom border remains blank rather than cutting off the last line.
    expect_true(all(raster[seq.int(dims[2] - 4L, dims[2]), , 1:3] > 0.99))
  }
})
