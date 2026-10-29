result_example <- function() mssr(matrix(1:20, 4, 5), fwhm = 2, amp = 2)

result_file <- function() {
  path <- tempfile(fileext = ".mssr")
  withr::defer(unlink(path), envir = parent.frame())
  path
}

rewrite_result_bytes <- function(path, change) {
  bytes <- readBin(path, "raw", file.info(path)$size)
  payload <- change(bytes[seq_len(length(bytes) - 64L)])
  hash <- charToRaw(digest::digest(payload, algo = "sha256", serialize = FALSE))
  writeBin(c(payload, hash), path)
}

test_that("result identity distinguishes schema, numerical engine and evidence", {
  r <- result_example()
  expect_identical(mssr_validate_result(r), r)
  expect_identical(r$schema_version, "1.0.0")
  expect_identical(r$engine$id, "mssr_r_rev3")
  expect_identical(r$input$axes, c("y", "x"))
  expect_null(r$input$sampling)
  expect_identical(r$evidence$status, "numerical_tool_only")
  legacy <- r[1:6]
  class(legacy) <- "mssr_result"
  legacy$diagnostics$qualification_scope <- NULL
  legacy$diagnostics$high_order_unqualified <- NULL
  expect_identical(mssr_validate_result(legacy), legacy)
  expect_identical(summary.mssr_result(legacy)$schema_version, "legacy_unversioned")
  expect_identical(summary.mssr_result(r)$value_range, range(r$values))
})

test_that("full validation rejects false roles, parameters, diagnostics and identities", {
  r <- result_example()
  changes <- list(
    function(z) {
      z$role <- "concentration"
      z
    },
    function(z) {
      z$parameters$amp <- 3L
      z
    },
    function(z) {
      z$parameters$half_size <- 4L
      z
    },
    function(z) {
      z$diagnostics$zero_fraction <- 0.123
      z
    },
    function(z) {
      z$diagnostics$quantitative <- TRUE
      z
    },
    function(z) {
      z$engine$id <- "future_unknown"
      z
    },
    function(z) {
      z$schema_version <- "2.0.0"
      z
    },
    function(z) {
      z$input$sampling <- c(1, 1)
      z
    },
    function(z) {
      z$evidence$status <- "clinical_validation"
      z
    },
    function(z) {
      z$source_path <- "private-path"
      z
    },
    function(z) {
      z$parameters$kernel <- c("disk", "square")
      z
    }
  )
  for (change in changes) expect_error(mssr_validate_result(change(r)), class = "mssrscopR_error")
  expect_no_error(mssr_validate_result(mssr(matrix(0, 2, 3), fwhm = 2)))
})

test_that("result exchange preserves every value and setting, including legacy records", {
  skip_if_not_installed("digest")
  skip_if_not_installed("jsonlite")
  path <- result_file()
  frames <- list(
    matrix(1:20, 4, 5), matrix(0, 2, 3),
    matrix(seq_len(20) * 2^-1070, 4, 5),
    matrix(seq_len(20) * 1e306, 4, 5)
  )
  for (x in frames) {
    r <- suppressWarnings(mssr(x, fwhm = 2, order = 0))
    mssr_write_result(r, path, overwrite = file.exists(path))
    back <- mssr_read_result(path)
    expect_identical(back, r)
    expect_identical(
      writeBin(as.double(back$values), raw(), size = 8L),
      writeBin(as.double(r$values), raw(), size = 8L)
    )
  }
  r <- result_example()[1:6]
  class(r) <- "mssr_result"
  r <- structure(r[c(2:6, 1)], class = "mssr_result")
  mssr_write_result(r, path, overwrite = TRUE)
  expect_identical(mssr_read_result(path), r)
})

test_that("no-overwrite, byte and decoded-pixel limits preserve complete output", {
  skip_if_not_installed("digest")
  skip_if_not_installed("jsonlite")
  path <- result_file()
  r <- result_example()
  expect_error(mssr_write_result(r, path, max_bytes = 100), class = "mssrscopR_error_resource")
  expect_false(file.exists(path))
  mssr_write_result(r, path)
  before <- digest::digest(file = path, algo = "sha256")
  expect_error(mssr_write_result(r, path), class = "mssrscopR_error_io")
  expect_identical(digest::digest(file = path, algo = "sha256"), before)
  expect_error(mssr_read_result(path, max_bytes = 100), class = "mssrscopR_error_resource")
  expect_error(mssr_read_result(path, max_output_pixels = 1), class = "mssrscopR_error_resource")
  expect_identical(mssr_read_result(path), r)
})

test_that("corruption, truncation and unsupported container contents fail closed", {
  skip_if_not_installed("digest")
  skip_if_not_installed("jsonlite")
  path <- result_file()
  r <- result_example()
  mssr_write_result(r, path)
  original <- readBin(path, "raw", file.info(path)$size)
  changed <- original
  changed[length(changed)] <- as.raw(0)
  writeBin(changed, path)
  expect_error(mssr_read_result(path), class = "mssrscopR_error_result")
  writeBin(original[-length(original)], path)
  expect_error(mssr_read_result(path), class = "mssrscopR_error_result")
  writeBin(original, path)
  rewrite_result_bytes(path, function(z) {
    z[1] <- as.raw(0)
    z
  })
  expect_error(mssr_read_result(path), class = "mssrscopR_error_result")
  writeBin(original, path)
  rewrite_result_bytes(path, function(z) {
    z[9:12] <- as.raw(255)
    z
  })
  expect_error(mssr_read_result(path), class = "mssrscopR_error_result")
  writeBin(original, path)
  rewrite_result_bytes(path, function(z) c(z, as.raw(0)))
  expect_error(mssr_read_result(path), class = "mssrscopR_error_result")
})

test_that("typed metadata rejects executable and ambiguous values", {
  expect_error(result_encode_node(function() NULL), class = "mssrscopR_error_result")
  expect_error(result_decode_node(list(type = "environment", names = NULL, data = list())),
    class = "mssrscopR_error_result"
  )
  node <- result_encode_node(list(a = 1))
  node <- c(node, list(type = "list"))
  expect_error(result_decode_node(node), class = "mssrscopR_error_result")
  expect_error(result_check_json_depth(charToRaw(paste(rep("[", 41), collapse = ""))),
    class = "mssrscopR_error_result"
  )
})

test_that("result file paths refuse symbolic links", {
  skip_on_os("windows")
  skip_if_not_installed("digest")
  skip_if_not_installed("jsonlite")
  path <- result_file()
  link <- result_file()
  mssr_write_result(result_example(), path)
  expect_true(file.symlink(path, link))
  expect_error(mssr_read_result(link), class = "mssrscopR_error_io")
  expect_error(mssr_write_result(result_example(), link, overwrite = TRUE),
    class = "mssrscopR_error_io"
  )
})

test_that("plot uses the original orientation and does not alter values", {
  path <- tempfile(fileext = ".pdf")
  withr::defer(unlink(path))
  grDevices::pdf(path)
  withr::defer(grDevices::dev.off())
  for (dims in list(c(4, 5), c(1, 5), c(5, 1), c(1, 1))) {
    r <- mssr(matrix(seq_len(prod(dims)), dims[1], dims[2]), fwhm = 2, order = 0)
    expect_identical(plot.mssr_result(r), r)
  }
})


test_that("high orders disclose their bounded numerical qualification", {
  x <- matrix(1:20, 4, 5)
  expect_warning(r <- mssr(x, fwhm = 2, order = 4),
    class = "mssrscopR_warning_unqualified_order"
  )
  expect_true(r$diagnostics$high_order_unqualified)
  expect_identical(r$diagnostics$qualification_scope, "bounded_synthetic_domain")
  expect_no_error(mssr_validate_result(r))
  expect_false(mssr(x, fwhm = 2, order = 3)$diagnostics$high_order_unqualified)
})


rewrite_result_metadata <- function(path, change) {
  rewrite_result_bytes(path, function(bytes) {
    n_meta <- readBin(bytes[9:12], "integer", n = 1L, size = 4L, endian = "little")
    metadata <- rawToChar(bytes[seq.int(13L, 12L + n_meta)])
    decoded <- result_decode_node(jsonlite::fromJSON(metadata, simplifyVector = FALSE))
    decoded$record <- change(decoded$record)
    encoded <- result_encode_node(decoded)
    text <- jsonlite::toJSON(encoded, auto_unbox = TRUE, null = "null", digits = NA)
    raw <- charToRaw(as.character(text))
    c(charToRaw("MSSRRES1"), writeBin(length(raw), raw(), size = 4L, endian = "little"),
      raw, bytes[seq.int(13L + n_meta, length(bytes))])
  })
}

test_that("a valid checksum never substitutes for record validation", {
  skip_if_not_installed("digest")
  skip_if_not_installed("jsonlite")
  path <- result_file()
  r <- result_example()
  changes <- list(
    function(z) {
      z$schema_version <- "999.0.0"
      z
    },
    function(z) {
      z$transform$output_dim <- c(2^30, 2^30)
      z
    },
    function(z) {
      z$diagnostics$quantitative <- TRUE
      z
    },
    function(z) {
      z$engine <- NULL
      z
    }
  )
  for (change in changes) {
    mssr_write_result(r, path, overwrite = file.exists(path))
    rewrite_result_metadata(path, change)
    expect_error(mssr_read_result(path), class = "mssrscopR_error")
  }
})


test_that("memory refusal precedes neighborhood allocation", {
  testthat::local_mocked_bindings(mssr_offsets = function(...) {
    cli::cli_abort("neighborhood should not have been allocated")
  })
  expect_error(mssr(matrix(1:6, 2, 3), fwhm = 2000, max_memory_bytes = 100),
               class = "mssrscopR_error_resource")
})


test_that("input attributes never become implicit result provenance", {
  original <- matrix(1:20, 4, 5)
  annotated <- original
  dimnames(annotated) <- list(paste0("row", 1:4), paste0("column", 1:5))
  attr(annotated, "source_path") <- "synthetic-private-example"
  for (amp in c(1, 2)) {
    plain <- mssr(original, fwhm = 2, amp = amp)
    stripped <- mssr(annotated, fwhm = 2, amp = amp)
    expect_identical(stripped, plain)
    expect_identical(attributes(stripped$values), list(dim = dim(stripped$values)))
  }
})


test_that("scalar attributes do not become implicit parameter metadata", {
  x <- matrix(1:20, 4, 5)
  note <- function(value) {
    names(value) <- "synthetic-private-label"
    attr(value, "source_path") <- "synthetic-private-example"
    value
  }
  plain <- mssr(x, fwhm = 2, intensity_normalize = TRUE, mesh = TRUE,
                grid = "extent", kernel = "disk", rounding = "half_even")
  annotated <- mssr(x, fwhm = note(2), intensity_normalize = note(TRUE), mesh = note(TRUE),
                    grid = note("extent"), kernel = note("disk"), rounding = note("half_even"))
  expect_identical(annotated, plain)
  expect_error(mssr(x, fwhm = 2, mesh = structure(TRUE, class = "custom_flag")),
               class = "mssrscopR_error_parameter")
})

test_that("typed metadata decoding rejects malformed nodes and keeps empty vectors", {
  node <- function(type, data = list(), names = NULL) list(type = type, names = names, data = data)
  bad <- list(
    node("null", list(1)),
    node("character", list(1)),
    node("logical", list(NA)),
    node("double", list("1.5")),
    node("double", list("0x1p+2000")),
    node("integer", list("1.5")),
    node("integer", list("99999999999")),
    node("character", list("x"), names = list("a", "b")),
    node("character", list("x", "y"), names = list("a", "a")),
    node("character", list("x"), names = list(1))
  )
  for (z in bad) expect_error(result_decode_node(z), class = "mssrscopR_error_result")
  deep <- node("character", list("x"))
  for (i in 1:13) deep <- node("list", list(deep))
  expect_error(result_decode_node(deep), class = "mssrscopR_error_result")
  expect_identical(result_decode_node(node("character")), character())
  expect_identical(result_decode_node(node("logical")), logical())
  expect_identical(result_decode_node(node("missing_character", NULL)), NA_character_)
})

rewrite_result_decoded <- function(path, change) {
  rewrite_result_bytes(path, function(bytes) {
    n_meta <- readBin(bytes[9:12], "integer", n = 1L, size = 4L, endian = "little")
    metadata <- rawToChar(bytes[seq.int(13L, 12L + n_meta)])
    decoded <- change(result_decode_node(jsonlite::fromJSON(metadata, simplifyVector = FALSE)))
    text <- if (is.character(decoded)) decoded else
      as.character(jsonlite::toJSON(result_encode_node(decoded), auto_unbox = TRUE,
                                    null = "null", digits = NA))
    raw <- charToRaw(text)
    c(charToRaw("MSSRRES1"), writeBin(length(raw), raw(), size = 4L, endian = "little"),
      raw, bytes[seq.int(13L + n_meta, length(bytes))])
  })
}

test_that("checksummed records with inconsistent structure are refused", {
  skip_if_not_installed("digest")
  skip_if_not_installed("jsonlite")
  path <- result_file()
  r <- result_example()
  changes <- list(
    not_json = function(z) "{not json",
    no_field_order = function(z) list(record = z$record),
    duplicated_order = function(z) {
      z$field_order <- c(z$field_order, z$field_order[1])
      z
    },
    values_in_record = function(z) {
      z$record$values <- 1
      z
    },
    transform_not_list = function(z) {
      z$record$transform <- "grid"
      z
    },
    zero_dimension = function(z) {
      z$record$transform$output_dim <- c(0, 10)
      z
    },
    fractional_dimension = function(z) {
      z$record$transform$output_dim <- c(8.5, 10)
      z
    },
    order_disagrees = function(z) {
      z$field_order <- setdiff(z$field_order, "evidence")
      z
    }
  )
  for (name in names(changes)) {
    mssr_write_result(r, path, overwrite = file.exists(path))
    rewrite_result_decoded(path, changes[[name]])
    expect_error(mssr_read_result(path), class = "mssrscopR_error_result", label = name)
  }
  mssr_write_result(r, path, overwrite = TRUE)
  expect_error(mssr_read_result(path, max_output_pixels = 10), class = "mssrscopR_error_resource")
  expect_identical(mssr_read_result(path), r)
})

test_that("summaries keep their fields and print a readable report", {
  r <- result_example()
  s <- summary(r)
  expect_s3_class(s, "summary.mssr_result")
  expect_identical(s$role, r$role)
  expect_identical(s$output_dim, dim(r$values))
  expect_identical(s$grid, "extent")
  expect_identical(s$engine, r$engine)
  out <- utils::capture.output(print(s))
  expect_match(out[1], "MSSR result summary: intensity_weighted_structure", fixed = TRUE)
  expect_true(any(grepl("input 4 x 5 -> output 8 x 10 (amp 2, extent grid)", out, fixed = TRUE)))
  expect_true(any(grepl("Not a quantitative intensity", out, fixed = TRUE)))
  flat <- summary(mssr(matrix(1, 3, 3), fwhm = 2))
  expect_true(any(grepl("degenerate (flat input)", utils::capture.output(print(flat)),
                        fixed = TRUE)))
  high <- suppressWarnings(mssr(matrix(1:20, 4, 5), fwhm = 2, order = 4))
  expect_true(any(grepl("order above 3", utils::capture.output(print(summary(high))),
                        fixed = TRUE)))
  utils::capture.output(printed <- print(s))
  expect_identical(printed, s)
})

test_that("a result written by version 0.1.0.9003 reads, validates and replays", {
  skip_if_not_installed("digest")
  skip_if_not_installed("jsonlite")
  dir <- test_path("fixtures", "results")
  stored <- mssr_read_result(file.path(dir, "result-0.1.0.9003.mssr"))
  expect_identical(stored$engine$id, "mssr_r_rev3")
  expect_identical(stored$engine$package_version, "0.1.0.9003")
  expect_no_error(mssr_validate_result(stored))
  x <- unname(as.matrix(utils::read.csv(file.path(dir, "input-0.1.0.9003.csv"),
                                        header = FALSE)))
  replay <- do.call(mssr, c(list(x = x), mssr_settings(stored)))
  # The compiled passes agree with the R passes that wrote it to within 1e-12;
  # bitwise identity depends on the platform and the R version.
  expect_lte(max(abs(replay$values - stored$values)) / max(abs(stored$values)), 1e-12)
  expect_identical(replay$transform, stored$transform)
  expect_identical(replay$parameters, stored$parameters)
})
