#' Process and resume independent complete frames
#'
#' Processes an explicitly named list of matrices sequentially. Each frame uses
#' the same settings and the public [mssr()] function. Completed files are reused
#' only after input/settings identity, SHA-256 and result readback checks.
#' Changed input or settings creates a new identity and preserves prior output.
#' Failed frames remain in the returned table. No data are downloaded or sent.
#'
#' @details
#' Requires optional packages `digest` and `jsonlite`, as do result files.
#' A directory lock prevents simultaneous writers. A lock left by a terminated
#' process must be reviewed and removed manually once its owner has stopped.
#' Cancellation is checked between frames; it does not interrupt a numerical
#' call already in progress. An interrupted output is retained and a new attempt
#' receives a distinct filename. Keep this output directory local and trusted;
#' hashes establish consistency, not authenticity.
#'
#' All input matrices are already resident in memory. The budget adds their
#' storage to the per-frame allocation estimate; it is not an OS memory cap.
#' `workers` is deliberately absent: parallel processing remains unqualified.
#'
#' @param frames A nonempty named list of plain numeric matrices. Names are
#'   unique opaque IDs containing only letters, digits, underscore or hyphen.
#' @param output_dir Explicit directory for result files and recovery records.
#' @param settings Named list of [mssr()] arguments, including `fwhm`; `x` and
#'   `max_memory_bytes` are supplied by the runner and cannot be overridden.
#' @param resume Reuse matching, verified completed results.
#' @param max_memory_bytes Positive estimated-memory budget; default 2 GiB. A
#'   frame runs only if its [mssr_estimate_resources()] estimate plus the size of
#'   all input frames held in `frames` fits within it.
#' @param max_result_bytes Positive serialized-result limit; default 256 MiB.
#' @param cancel Optional function with no arguments returning a single logical.
#'   `TRUE` marks remaining frames cancelled without running them.
#' @return A data frame with one row per input: ID, status, reuse flag, output
#'   path, elapsed seconds and message. Individual JSON records retain warnings,
#'   identities, completion state and hashes. Complete results use `.mssr` files.
#' @export
mssr_batch <- function(frames, output_dir, settings, resume = TRUE,
                       max_memory_bytes = 2 * 1024^3, max_result_bytes = 256 * 1024^2,
                       cancel = NULL) {
  call <- sys.call()
  for (pkg in c("digest", "jsonlite")) {
    if (!requireNamespace(pkg, quietly = TRUE)) {
      msg <- sprintf("Install the optional package `%s` to use batch output.", pkg)
      mssr_abort("dependency", msg, call)
    }
  }
  ids <- names(frames)
  if (!is.list(frames) || is.object(frames) || !length(frames) ||
        length(ids) != length(frames) || anyNA(ids) || anyDuplicated(ids) ||
        any(!grepl("^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$", ids))) {
    mssr_abort("input", "`frames` needs unique opaque names and at least one numeric matrix.", call)
  }
  if (!is.list(settings) || is.object(settings) || is.null(names(settings)) ||
        anyNA(names(settings)) || anyDuplicated(names(settings)) ||
        !"fwhm" %in% names(settings) ||
        any(!names(settings) %in% setdiff(names(formals(mssr)), c("x", "max_memory_bytes")))) {
    mssr_abort("parameter", "`settings` must name MSSR arguments, including `fwhm`.", call)
  }
  settings <- batch_resolve_settings(settings, call)
  resume <- check_flag(resume, "resume", call)
  max_memory_bytes <- check_positive(max_memory_bytes, "max_memory_bytes", call)
  max_result_bytes <- check_positive(max_result_bytes, "max_result_bytes", call)
  if (!is.null(cancel) && !is.function(cancel)) {
    mssr_abort("parameter", "`cancel` must be NULL or a function.", call)
  }
  if (!is.character(output_dir) || length(output_dir) != 1L || is.na(output_dir) ||
        !nzchar(output_dir)) {
    mssr_abort("input", "`output_dir` must be an explicit directory path.", call)
  }
  if (!dir.exists(output_dir) && !dir.create(output_dir, recursive = FALSE)) {
    mssr_abort("io", "Cannot create `output_dir`; its parent must exist.", call)
  }
  root <- normalizePath(output_dir, mustWork = TRUE)
  lock <- file.path(root, ".mssr-lock")
  if (!dir.create(lock, showWarnings = FALSE)) {
    mssr_abort("io", "Batch directory is locked; verify its owner before recovering a stale lock.",
               call)
  }
  on.exit(unlink(lock, recursive = TRUE), add = TRUE)
  writeLines(as.character(Sys.getpid()), file.path(lock, "owner_pid"))
  identity <- function(x) {
    digest::digest(serialize(x, NULL, version = 2), algo = "sha256", serialize = FALSE)
  }
  settings_hash <- identity(list(settings = settings, engine = "mssr_r_rev3",
                                 package = as.character(utils::packageVersion("mssrscopR")),
                                 batch_schema = "1.0.0"))
  resident_bytes <- sum(vapply(frames, function(x) as.double(utils::object.size(x)), numeric(1)))
  stopped <- FALSE
  rows <- vector("list", length(frames))
  for (i in seq_along(frames)) {
    id <- ids[i]
    start <- proc.time()[["elapsed"]]
    row <- list(id = id, status = "failed", reused = FALSE, output = "",
                elapsed_seconds = 0, message = "")
    warnings <- character()
    record <- NULL
    record_path <- NULL
    tryCatch({
      if (!is.null(cancel) && !stopped) stopped <- check_flag(cancel(), "cancel()", call)
      if (stopped) {
        row$status <- "cancelled"
        row$message <- "Cancelled before starting this frame."
      } else {
        x <- check_matrix(frames[[i]], call)
        resource_fields <- c("fwhm", "amp", "kernel", "rounding", "max_output_pixels")
        args <- c(list(input_dim = dim(x)), settings[intersect(names(settings), resource_fields)])
        estimate <- do.call(mssr_estimate_resources, args)
        if (estimate$estimated_peak_bytes + resident_bytes > max_memory_bytes) {
          mssr_abort("resource", "Batch input storage plus frame estimate exceeds memory budget.",
                     call)
        }
        input_hash <- identity(x)
        key <- identity(list(input_hash, settings_hash))
        record_path <- file.path(root, paste0(id, "-", key, ".json"))
        previous <- batch_read_record(record_path, id, key, call)
        if (!is.null(previous)) {
          expected_name <- paste0(id, "-", key, "-", previous$attempt, ".mssr")
          if (!identical(previous$output, expected_name) ||
                !identical(previous$input_sha256, input_hash) ||
                !identical(previous$settings_sha256, settings_hash) ||
                !isTRUE(all.equal(previous$settings, settings, tolerance = 0,
                                  check.attributes = FALSE)) ||
                !identical(previous$engine, "mssr_r_rev3") ||
                !identical(previous$package_version,
                           as.character(utils::packageVersion("mssrscopR")))) {
            mssr_abort("integrity", "Recovery identity or output filename is inconsistent.", call)
          }
        }
        if (!is.null(previous) && identical(previous$status, "complete") && resume) {
          output <- batch_child(root, previous$output, call)
          file_ok <- isTRUE(utils::file_test("-f", output)) &&
            file.info(output)$size <= max_result_bytes
          if (!file_ok || !identical(digest::digest(file = output, algo = "sha256"),
                                     previous$output_sha256)) {
            mssr_abort("integrity", "Batch output is missing or its SHA-256 changed.", call)
          }
          restored <- mssr_read_result(output, max_bytes = max_result_bytes)
          batch_check_result(restored, dim(x), settings, call)
          row$status <- "complete"
          row$reused <- TRUE
          row$output <- output
        } else {
          attempt <- if (is.null(previous)) 1L else previous$attempt + 1L
          if (!is.finite(attempt) || attempt > 1000000) {
            mssr_abort("integrity", "Batch attempt counter is invalid.", call)
          }
          name <- paste0(id, "-", key, "-", attempt, ".mssr")
          output <- batch_child(root, name, call)
          if (file.exists(output)) {
            mssr_abort("integrity", "An unrecorded output already exists.", call)
          }
          record <- list(schema = "1.0.0", id = id, key = key, attempt = attempt,
                         status = "pending", input_sha256 = input_hash,
                         settings_sha256 = settings_hash, settings = settings,
                         engine = "mssr_r_rev3",
                         package_version = as.character(utils::packageVersion("mssrscopR")),
                         output = name)
          batch_write_record(record, record_path, call)
          record$status <- "running"
          record$estimated_peak_bytes <- estimate$estimated_peak_bytes + resident_bytes
          batch_write_record(record, record_path, call)
          collect_warning <- function(w) {
            warnings <<- c(warnings, class(w)[1])
            invokeRestart("muffleWarning")
          }
          run_frame <- function() do.call(mssr, c(list(x = x), settings))
          result <- withCallingHandlers(run_frame(), warning = collect_warning)
          mssr_write_result(result, output, max_bytes = max_result_bytes)
          restored <- mssr_read_result(output, max_bytes = max_result_bytes)
          if (!identical(result$values, restored$values)) {
            mssr_abort("integrity", "Batch result readback changed numeric values.", call)
          }
          record$output_sha256 <- digest::digest(file = output, algo = "sha256")
          record$status <- "complete"
          record$warning_classes <- warnings
          record$elapsed_seconds <- proc.time()[["elapsed"]] - start
          batch_write_record(record, record_path, call)
          row$status <- "complete"
          row$output <- output
        }
      }
    }, interrupt = function(e) {
      stopped <<- TRUE
      row$status <<- "cancelled"
      row$message <<- "Interrupted during frame processing."
    }, error = function(e) {
      row$message <<- conditionMessage(e)
    })
    row$elapsed_seconds <- proc.time()[["elapsed"]] - start
    if (!is.null(record) && row$status != "complete") {
      record$status <- row$status
      record$message <- row$message
      record$warning_classes <- warnings
      batch_write_record(record, record_path, call)
    }
    rows[[i]] <- as.data.frame(row, stringsAsFactors = FALSE)
  }
  report <- do.call(rbind, rows)
  report_path <- tempfile("batch-run-", tmpdir = root, fileext = ".json")
  batch_write_record(list(schema = "1.0.0", settings_sha256 = settings_hash, settings = settings,
                          engine = "mssr_r_rev3",
                          package_version = as.character(utils::packageVersion("mssrscopR")),
                          frames = report), report_path, call)
  attr(report, "run_record") <- report_path
  report
}

batch_child <- function(root, name, call) {
  if (!is.character(name) || length(name) != 1L || is.na(name) ||
        !grepl("^[A-Za-z0-9_-]+\\.mssr$", name)) {
    mssr_abort("integrity", "Invalid batch output filename.", call)
  }
  path <- file.path(root, name)
  if (isTRUE(nzchar(Sys.readlink(path), keepNA = TRUE))) {
    mssr_abort("integrity", "Symlink outputs are refused.", call)
  }
  path
}

batch_read_record <- function(path, id, key, call) {
  if (isTRUE(nzchar(Sys.readlink(path), keepNA = TRUE))) {
    mssr_abort("integrity", "Symlink records are refused.", call)
  }
  if (!file.exists(path)) return(NULL)
  if (!isTRUE(utils::file_test("-f", path)) || file.info(path)$size > 1024^2) {
    mssr_abort("integrity", "Invalid or oversized batch record.", call)
  }
  raw <- readBin(path, "raw", n = 1024^2 + 1L)
  if (length(raw) > 1024^2) mssr_abort("integrity", "Oversized batch record.", call)
  result_check_json_depth(raw)
  r <- tryCatch(jsonlite::fromJSON(rawToChar(raw), simplifyVector = FALSE),
                error = function(e) NULL)
  if (!is.list(r) || anyDuplicated(names(r)) || !identical(r$schema, "1.0.0") ||
        !identical(r$id, id) || !identical(r$key, key) ||
        !is.numeric(r$attempt) || length(r$attempt) != 1L || !is.finite(r$attempt) ||
        r$attempt < 1 || r$attempt != round(r$attempt) ||
        !is.character(r$status) || length(r$status) != 1L ||
        !r$status %in% c("pending", "running", "complete", "failed", "cancelled")) {
    mssr_abort("integrity", "Invalid batch recovery record.", call)
  }
  r
}

batch_write_record <- function(record, path, call) {
  if (isTRUE(nzchar(Sys.readlink(path), keepNA = TRUE))) {
    mssr_abort("integrity", "Symlink records are refused.", call)
  }
  tmp <- tempfile(".record-", tmpdir = dirname(path))
  on.exit(unlink(tmp), add = TRUE)
  jsonlite::write_json(record, tmp, auto_unbox = TRUE, pretty = TRUE, digits = NA)
  if (!file.rename(tmp, path)) mssr_abort("io", "Cannot atomically replace batch record.", call)
  invisible(NULL)
}

batch_check_result <- function(result, input_dim, settings, call) {
  expected <- list(fwhm = settings$fwhm, amp = 1L, order = 1L,
                   intensity_normalize = TRUE, mesh = TRUE,
                   kernel = "disk", rounding = "half_even")
  fields <- intersect(names(settings), names(expected))
  expected[fields] <- settings[fields]
  expected$kernel <- check_choice(expected$kernel, c("disk", "square"), "kernel", call)
  expected$rounding <- check_choice(expected$rounding, c("half_even", "half_up"), "rounding", call)
  expected$mesh <- expected$mesh && expected$amp > 1L
  expected$half_size <- mssr_half_size(expected$fwhm, expected$amp, expected$rounding)
  grid <- if (is.null(settings$grid)) "extent" else settings$grid
  grid <- check_choice(grid, c("extent", "endpoint"), "grid", call)
  same <- function(x, y) isTRUE(all.equal(x, y, tolerance = 0, check.attributes = FALSE))
  if (!identical(result$engine$id, "mssr_r_rev3") ||
        !identical(result$engine$package_version,
                   as.character(utils::packageVersion("mssrscopR"))) ||
        !same(result$transform$input_dim, input_dim) ||
        !identical(result$transform$grid, grid) ||
        !all(vapply(names(expected), function(n) same(result$parameters[[n]], expected[[n]]),
                    logical(1)))) {
    mssr_abort("integrity", "Cached result differs from the current input grid or settings.", call)
  }
  invisible(result)
}

batch_resolve_settings <- function(settings, call) {
  defaults <- list(fwhm = settings$fwhm, amp = 1L, order = 1L,
                   intensity_normalize = TRUE, mesh = TRUE, grid = "extent",
                   kernel = "disk", rounding = "half_even", max_output_pixels = 5e7)
  defaults[names(settings)] <- settings
  defaults$fwhm <- check_positive(defaults$fwhm, "fwhm", call)
  defaults$amp <- check_whole(defaults$amp, "amp", 1L, 64L, call)
  defaults$order <- check_whole(defaults$order, "order", 0L, 10L, call)
  for (n in c("intensity_normalize", "mesh")) {
    if (is.object(defaults[[n]])) {
      mssr_abort("parameter", "Batch flags must be plain logicals.", call)
    }
    defaults[[n]] <- check_flag(defaults[[n]], n, call)
  }
  defaults$grid <- check_choice(defaults$grid, c("extent", "endpoint"), "grid", call)
  defaults$kernel <- check_choice(defaults$kernel, c("disk", "square"), "kernel", call)
  defaults$rounding <- check_choice(defaults$rounding, c("half_even", "half_up"), "rounding", call)
  defaults$max_output_pixels <- check_positive(defaults$max_output_pixels,
                                               "max_output_pixels", call)
  defaults
}
