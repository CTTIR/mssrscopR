skip_if_not_installed("shiny")
skip_if_not_installed("bslib")
skip_if_not_installed("jsonlite")
skip_if_not_installed("callr")

async_frame <- function(id = "pair_3") {
  list(x = mssr_app_example(id), info = paste("Synthetic", id), source = paste0("example:", id),
       metadata = list(format = "synthetic"))
}

async_wait <- function(session, state, poll_job, timeout = 20) {
  deadline <- proc.time()[["elapsed"]] + timeout
  repeat {
    session$flushReact()
    shiny::isolate(poll_job())
    session$flushReact()
    status <- shiny::isolate(state$status)
    if (status != "running") return(status)
    if (proc.time()[["elapsed"]] > deadline) {
      cli::cli_abort("Background test exceeded its deadline.")
    }
    Sys.sleep(0.025)
  }
}

async_ready <- function(frame, args, mask, run_id) {
  snapshot <- list(frame = frame, args = args, mask = mask, run_id = run_id)
  value <- mssr_app_job_value(snapshot)
  value$source_definition_verified <- TRUE
  list(process = list(is_alive = function() FALSE, get_result = function() value,
                      cleanup = function() invisible(), wait = function(...) invisible(),
                      kill = function() invisible()),
       started = proc.time()[["elapsed"]], run_id = run_id, snapshot = snapshot)
}

# A deliberate sleeping child is a lifecycle fixture, never production job input.
async_sleeping <- function(...) {
  list(process = callr::r_bg(function() Sys.sleep(60), supervise = TRUE,
                             user_profile = FALSE, system_profile = FALSE),
       started = proc.time()[["elapsed"]], run_id = "controlled-sleep-fixture")
}

test_that("the real background job matches the loaded package and inherits CPU policy", {
  frame <- async_frame()
  args <- mssr_app_args(list(amp = 1))
  job <- mssr_app_start_job(frame, args, list(fraction = 0.1, seed = 2), "direct-equivalence")
  withr::defer(mssr_app_stop_job(job))
  job$process$wait(timeout = 20000)
  expect_false(job$process$is_alive())
  got <- job$process$get_result()
  expect_true(got$ok)
  expect_true(got$source_definition_verified)
  expect_identical(got$value$result$values, mssr(frame$x, fwhm = 3, amp = 1)$values)
  expect_identical(got$value$mask_settings, list(fraction = 0.1, seed = 2))
  expect_true(all(got$thread_environment == "1"))
  if (file.exists("/proc/self/status")) {
    parent_affinity <- grep("^Cpus_allowed_list:", readLines("/proc/self/status"), value = TRUE)
    expect_identical(got$affinity, parent_affinity)
  }
})

test_that("owned cancellation leaves a different child alive", {
  owned <- async_sleeping()
  other <- async_sleeping()
  withr::defer(mssr_app_stop_job(owned))
  withr::defer(mssr_app_stop_job(other))
  expect_true(owned$process$is_alive())
  expect_true(other$process$is_alive())
  expect_true(mssr_app_stop_job(owned))
  expect_false(owned$process$is_alive())
  expect_true(other$process$is_alive())
})

test_that("cancellation blocks exports and restores the previous input and mask snapshot", {
  starts <- 0L
  local_mocked_bindings(mssr_app_start_job = function(frame, args, mask, run_id) {
    starts <<- starts + 1L
    if (starts == 1L) async_ready(frame, args, mask, run_id) else async_sleeping()
  })
  shiny::testServer(mssr_app_server, {
    session$flushReact()
    expect_identical(state$status, "complete")
    session$setInputs(mask_fraction = 0.1, mask_seed = 3)
    previous <- run()
    session$setInputs(example = "disk")
    owned <- state$job$process
    expect_identical(state$status, "running")
    expect_true(owned$is_alive())
    expect_error(run(), class = "shiny.silent.error")
    session$setInputs(mask_fraction = 0.8, mask_seed = 9, fwhm = 8)
    session$setInputs(cancel = 1)
    expect_false(owned$is_alive())
    expect_identical(state$status, "cancelled")
    expect_null(state$job)
    expect_error(run(), class = "shiny.silent.error")
    expect_error(output$dl_values, class = "shiny.silent.error")
    session$setInputs(restore = 1)
    expect_identical(run()$x, previous$x)
    expect_identical(run()$source, "example:pair_3")
    expect_identical(run()$mask_settings, list(fraction = 0.1, seed = 3))
    expect_identical(mask()$fraction, 0.1)
    expect_true(run()$restored_previous)
    record <- jsonlite::fromJSON(output$dl_record)
    expect_true(record$restored_previous)
    expect_identical(record$mask$fraction, 0.1)
    expect_identical(record$source, "example:pair_3")
    expect_match(output$job_status, "Restored the previous completed input")
  })
})

test_that("a real failed job can be retried without accepting partial work", {
  shiny::testServer(mssr_app_server, {
    session$setInputs(fwhm = -1, compute = 1)
    expect_identical(async_wait(session, state, poll_job), "failed")
    expect_error(run(), class = "shiny.silent.error")
    expect_null(state$job)
    session$setInputs(fwhm = 3, compute = 2)
    expect_identical(async_wait(session, state, poll_job), "complete")
    expect_identical(run()$result$parameters$fwhm, 3)
    expect_null(state$job)
  })
})

test_that("session end stops the session-owned job", {
  local_mocked_bindings(mssr_app_start_job = async_sleeping)
  child <- NULL
  shiny::testServer(mssr_app_server, {
    session$flushReact()
    child <<- state$job$process
    expect_true(child$is_alive())
    session$setInputs(example = "disk")
    expect_false(child$is_alive())
    child <<- state$job$process
    expect_true(child$is_alive())
    session$close()
    expect_false(child$is_alive())
  })
  expect_false(child$is_alive())
})

test_that("mask controls changed during a real job do not mutate its launch snapshot", {
  shiny::testServer(mssr_app_server, {
    session$setInputs(mask_fraction = 0.1, mask_seed = 3, compute = 1)
    expect_identical(state$status, "running")
    session$setInputs(mask_fraction = 0.8, mask_seed = 9)
    expect_identical(async_wait(session, state, poll_job), "complete")
    expect_identical(mask()$fraction, 0.1)
    record <- jsonlite::fromJSON(output$dl_record)
    expect_true(record$controls_stale)
    expect_identical(record$mask_settings_at_compute$fraction, 0.1)
    expect_identical(record$mask$fraction, 0.1)
    session$setInputs(mask_fraction = 0.2)
    expect_identical(mask()$fraction, 0.2)
    expect_identical(run()$mask_settings_at_compute$fraction, 0.1)
  })
})

test_that("a malformed background result is not accepted as complete", {
  local_mocked_bindings(mssr_app_start_job = function(frame, args, mask, run_id) {
    job <- async_ready(frame, args, mask, run_id)
    value <- job$process$get_result()
    value$value$result$values[1] <- NA_real_
    job$process$get_result <- function() value
    job
  })
  shiny::testServer(mssr_app_server, {
    session$flushReact()
    expect_identical(state$status, "failed")
    expect_error(run(), class = "shiny.silent.error")
    expect_match(output$job_status, "validation failed")
  })
})

test_that("timeout retains failure status and cannot become a complete result", {
  # A negative limit expires even when a coarse elapsed clock (Windows) has not
  # advanced since the job started.
  local_mocked_bindings(mssr_app_start_job = async_sleeping, mssr_app_job_timeout = -1)
  shiny::testServer(mssr_app_server, {
    session$flushReact()
    expect_identical(state$status, "failed")
    expect_null(state$job)
    expect_error(run(), class = "shiny.silent.error")
    expect_match(output$job_status, "exceeded five minutes")
  })
})

test_that("loaded definition drift is refused by the real background process", {
  original <- mssr_app_code_signature
  local_mocked_bindings(mssr_app_code_signature = function() {
    x <- original()
    x[1] <- paste0(x[1], "\nchanged")
    x
  })
  job <- mssr_app_start_job(async_frame(), mssr_app_args(list()),
                            list(fraction = 0.1, seed = 1), "drift")
  withr::defer(mssr_app_stop_job(job))
  job$process$wait(timeout = 20000)
  expect_error(job$process$get_result(), "differ from the app session")
})

test_that("package files changed before the child loads them are refused", {
  identity <- mssr_app_code_identity()
  local_mocked_bindings(mssr_app_code_identity = function() {
    identity$file_md5[1] <- strrep("0", 32)
    identity
  })
  job <- mssr_app_start_job(async_frame(), mssr_app_args(list()),
                            list(fraction = 0.1, seed = 1), "file-drift")
  withr::defer(mssr_app_stop_job(job))
  job$process$wait(timeout = 20000)
  err <- tryCatch(job$process$get_result(), error = function(e) e)
  expect_match(conditionMessage(err$parent), "changed since this R session loaded them")
  expect_s3_class(err$parent, "mssrscopR_error_integrity")
})

test_that("a source file edited after the package loaded is refused", {
  loaded <- mssr_loaded_code$files
  skip_if(is.null(loaded), "no load-time snapshot")
  withr::defer(mssr_loaded_code$files <- loaded)
  # Pretend the file on disk was different when this session loaded it; in a
  # development checkout that file is the C source of the compiled passes.
  edited <- grep("[/\\\\]src[/\\\\]neighborhood[.]c$", loaded$files)
  if (!length(edited)) edited <- 1L
  mssr_loaded_code$files$file_md5[edited] <- strrep("0", 32)
  job <- mssr_app_start_job(async_frame(), mssr_app_args(list()),
                            list(fraction = 0.1, seed = 1), "edited-after-load")
  withr::defer(mssr_app_stop_job(job))
  job$process$wait(timeout = 20000)
  err <- tryCatch(job$process$get_result(), error = function(e) e)
  expect_match(conditionMessage(err$parent), "changed since this R session loaded them")
})

test_that("a native library that differs from the session's is refused", {
  identity <- mssr_app_code_identity()
  local_mocked_bindings(mssr_app_code_identity = function() {
    identity$dll_md5 <- strrep("0", 32)
    identity
  })
  job <- mssr_app_start_job(async_frame(), mssr_app_args(list()),
                            list(fraction = 0.1, seed = 1), "native-drift")
  withr::defer(mssr_app_stop_job(job))
  job$process$wait(timeout = 20000)
  err <- tryCatch(job$process$get_result(), error = function(e) e)
  expect_match(conditionMessage(err$parent), "native library differs")
  expect_s3_class(err$parent, "mssrscopR_error_integrity")
})

test_that("loaded policy constants cannot silently differ from the child", {
  local_mocked_bindings(mssr_app_work_limit = 0)
  expect_error(mssr_app_compute(async_frame()$x, mssr_app_args(list())),
               class = "mssrscopR_error_resource")
  job <- mssr_app_start_job(async_frame(), mssr_app_args(list()),
                            list(fraction = 0.1, seed = 1), "constant-drift")
  withr::defer(mssr_app_stop_job(job))
  job$process$wait(timeout = 20000)
  expect_error(job$process$get_result(), "differ from the app session")
})

test_that("valid results with mismatched grid, settings or run identity are refused", {
  frame <- async_frame()
  args <- mssr_app_args(list(amp = 1))
  job <- async_ready(frame, args, list(fraction = 0.1, seed = 1), "snapshot-validation")
  original <- job$process$get_result()
  expect_true(mssr_app_validate_job(job, original))
  changed <- original
  changed$value$result <- mssr(t(frame$x), fwhm = 3, amp = 1)
  expect_error(mssr_app_validate_job(job, changed), class = "mssrscopR_error_integrity")
  changed <- original
  changed$value$result <- mssr(frame$x, fwhm = 4, amp = 1)
  expect_error(mssr_app_validate_job(job, changed), class = "mssrscopR_error_integrity")
  changed <- original
  changed$value$run_id <- "different-run"
  expect_error(mssr_app_validate_job(job, changed), class = "mssrscopR_error_integrity")
  changed <- original
  changed$value$x[1] <- changed$value$x[1] + 1
  expect_error(mssr_app_validate_job(job, changed), class = "mssrscopR_error_integrity")
  changed <- original
  changed$value$mask_settings$fraction <- 0.8
  expect_error(mssr_app_validate_job(job, changed), class = "mssrscopR_error_integrity")
})

test_that("the code identity covers compiled sources and native routines", {
  identity <- mssr_app_code_identity()
  if (identity$development) {
    expect_true(any(grepl("[/\\\\]src[/\\\\]neighborhood[.]c$", identity$files)))
  }
  dll <- getLoadedDLLs()[["mssrscopR"]][["path"]]
  expect_identical(identity$dll_md5, unname(tools::md5sum(dll)))
  # A registered routine is identified by name and arity, not by its address.
  expect_identical(unname(identity$functions["mssr_neighborhood_c"]),
                   "native mssr_neighborhood_c 4")
  expect_identical(mssr_app_code_signature(), identity$functions)
})
