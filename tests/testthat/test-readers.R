# Independent classic TIFF fixtures assembled from format fields and raw samples.
# No image writer is used for the known-value or malformed-file cases.
reader_uint <- function(x, width, endian = "little") {
  bytes <- as.raw(floor(x / 256^(0:(width - 1L))) %% 256)
  if (endian == "big") rev(bytes) else bytes
}

reader_fixture <- function(path, bits = 8L, channels = 1L, endian = "little",
                           orientation = 1L, sample_format = 1L, tiled = FALSE) {
  width <- 3L
  height <- 2L
  values <- seq_len(width * height * channels)
  if (bits == 12L) values <- c(0, 1, 255, 256, 2048, 4095)
  if (bits == 16L) values <- c(0, 1, 255, 256, 32768, 65535)
  if (bits == 32L && sample_format == 1L) values <- c(0, 1, 2^31 - 1, 2^31, 3e9, 2^32 - 1)
  if (sample_format == 3L) values <- c(-0.5, 0, 0.25, 2.5, 2^20, 2^-20)
  scalar <- function(tag, type, value) list(tag = tag, type = type, values = value)
  tags <- list(scalar(256, 4, width), scalar(257, 4, height),
               scalar(258, 3, rep(bits, channels)), scalar(259, 3, 1),
               scalar(262, 3, if (channels == 3L) 2 else 1),
               scalar(274, 3, orientation), scalar(277, 3, channels),
               scalar(284, 3, 1), scalar(339, 3, rep(sample_format, channels)))
  if (tiled) {
    tile <- matrix(0, 16, 16)
    tile[1:2, 1:3] <- matrix(values, 2, 3, byrow = TRUE)
    payload_values <- as.vector(t(tile))
    tags <- c(tags, list(scalar(322, 4, 16), scalar(323, 4, 16),
                         scalar(324, 4, 0), scalar(325, 4, 256)))
  } else {
    payload_values <- values
    tags <- c(tags, list(scalar(273, 4, 0), scalar(278, 4, height),
                         scalar(279, 4, ceiling(width * channels * bits / 8) * height)))
  }
  if (bits == 12L) {
    payload <- as.raw(unlist(lapply(seq(1, length(values), by = width), function(i) {
      row_bits <- unlist(lapply(values[i:(i + width - 1L)], function(v) {
        floor(v / 2^(11:0)) %% 2
      }))
      row_bits <- c(row_bits, rep(0, (-length(row_bits)) %% 8))
      colSums(matrix(row_bits, 8) * 2^(7:0))
    })))
  } else if (sample_format == 3L) {
    payload <- writeBin(as.double(payload_values), raw(), size = 4, endian = endian)
  } else {
    payload <- do.call(c, lapply(payload_values, reader_uint, width = bits / 8, endian = endian))
  }
  tags <- tags[order(vapply(tags, function(x) x$tag, numeric(1)))]
  offset <- 8 + 2 + length(tags) * 12 + 4
  external <- raw()
  entries <- raw()
  for (entry in tags) {
    n <- length(entry$values)
    value_bytes <- do.call(c, lapply(entry$values, reader_uint,
                                     width = if (entry$type == 3) 2 else 4, endian = endian))
    if (length(value_bytes) > 4) {
      pointer <- reader_uint(offset + length(external), 4, endian)
      external <- c(external, value_bytes)
    } else {
      pointer <- c(value_bytes, as.raw(rep(0, 4 - length(value_bytes))))
    }
    entries <- c(entries, reader_uint(entry$tag, 2, endian),
                 reader_uint(entry$type, 2, endian), reader_uint(n, 4, endian), pointer)
  }
  strip_tag <- if (tiled) 324 else 273
  strip_index <- which(vapply(tags, function(x) x$tag, numeric(1)) == strip_tag)
  entries[(12 * (strip_index - 1) + 9):(12 * strip_index)] <-
    reader_uint(offset + length(external), 4, endian)
  bytes <- c(charToRaw(if (endian == "little") "II" else "MM"),
             reader_uint(42, 2, endian), reader_uint(8, 4, endian),
             reader_uint(length(tags), 2, endian), entries, reader_uint(0, 4, endian),
             external, payload)
  writeBin(bytes, path)
  list(bytes = bytes, values = values, tags = tags)
}

test_that("independent TIFF samples preserve values and top-left orientation", {
  skip_if_not_installed("tiff")
  path <- withr::local_tempfile(fileext = ".tif")
  for (endian in c("little", "big")) {
    for (bits in c(8L, 16L, 32L)) {
      f <- reader_fixture(path, bits = bits, endian = endian)
      got <- mssr_app_read(path, "independent.tif")
      expect_identical(got$x, matrix(as.double(f$values), 2, 3, byrow = TRUE))
      expect_identical(got$metadata$orientation, "top-left")
      expect_null(got$metadata$physical_sampling)
    }
    f <- reader_fixture(path, bits = 32L, endian = endian, sample_format = 3L)
    expect_identical(mssr_app_read(path, "float.tif")$x,
                     matrix(f$values, 2, 3, byrow = TRUE))
    f <- reader_fixture(path, channels = 3L, endian = endian)
    for (ch in 1:3) {
      got <- mssr_app_read(path, "rgb.tif", channel = ch)
      expect_identical(got$x, matrix(as.double(f$values[seq(ch, 18, by = 3)]), 2, 3,
                                     byrow = TRUE))
      expect_identical(got$metadata$channel, ch)
    }
  }
})

test_that("packed 12-bit TIFF is refused before the known inaccurate decode", {
  skip_if_not_installed("tiff")
  path <- withr::local_tempfile(fileext = ".tif")
  reader_fixture(path, bits = 12L)
  reader <- tiff::readTIFF
  calls <- 0L
  local_mocked_bindings(readTIFF = function(...) {
    args <- list(...)
    expect_false(args$payload)
    calls <<- calls + 1L
    reader(...)
  }, .package = "tiff")
  expect_error(mssr_app_read(path, "packed.tif"), "12-bit", class = "mssrscopR_error_unsupported")
  expect_identical(calls, 1L)
})

test_that("independent tiled TIFF preserves the image extent and values", {
  skip_if_not_installed("tiff")
  path <- withr::local_tempfile(fileext = ".tif")
  f <- reader_fixture(path, tiled = TRUE)
  expect_identical(mssr_app_read(path, "tile.tif")$x,
                   matrix(as.double(f$values), 2, 3, byrow = TRUE))
})

test_that("unqualified TIFF orientations are refused before library access", {
  path <- withr::local_tempfile(fileext = ".tif")
  for (orientation in 2:8) {
    reader_fixture(path, orientation = orientation)
    expect_error(mssr_app_tiff_preflight(path, 1L), "top-left",
                 class = "mssrscopR_error_unsupported")
  }
})

test_that("TIFF directory traversal stops on cycles, truncation and budget violations", {
  path <- withr::local_tempfile(fileext = ".tif")
  f <- reader_fixture(path)
  next_ifd <- 8 + 2 + length(f$tags) * 12 + 1:4
  bytes <- f$bytes
  bytes[next_ifd] <- reader_uint(8, 4)
  writeBin(bytes, path)
  expect_error(mssr_app_tiff_preflight(path, 1L), "cycle", class = "mssrscopR_error_input")
  writeBin(f$bytes[1:20], path)
  expect_error(mssr_app_tiff_preflight(path, 1L), class = "mssrscopR_error_input")
  writeBin(f$bytes, path)
  local_mocked_bindings(mssr_app_tiff_page_limit = 0L)
  expect_error(mssr_app_tiff_preflight(path, 1L), "256 pages", class = "mssrscopR_error_resource")
  local_mocked_bindings(mssr_app_tiff_page_limit = 256L, mssr_app_tiff_tag_limit = 1L)
  expect_error(mssr_app_tiff_preflight(path, 1L), "4096 tags", class = "mssrscopR_error_resource")
  local_mocked_bindings(mssr_app_tiff_tag_limit = 4096L, mssr_app_tiff_metadata_limit = 10)
  expect_error(mssr_app_tiff_preflight(path, 1L), "4 MiB", class = "mssrscopR_error_resource")
  local_mocked_bindings(mssr_app_tiff_metadata_limit = 4 * 1024^2, mssr_app_tiff_file_limit = 10)
  expect_error(mssr_app_tiff_preflight(path, 1L), "256 MiB", class = "mssrscopR_error_resource")
})

test_that("BigTIFF and nested directories are explicit unsupported inputs", {
  path <- withr::local_tempfile(fileext = ".tif")
  f <- reader_fixture(path)
  bytes <- f$bytes
  bytes[3:4] <- reader_uint(43, 2)
  writeBin(bytes, path)
  expect_error(mssr_app_tiff_preflight(path, 1L), "BigTIFF", class = "mssrscopR_error_unsupported")
  bytes <- f$bytes
  bytes[11:12] <- reader_uint(330, 2)
  writeBin(bytes, path)
  expect_error(mssr_app_tiff_preflight(path, 1L), "nested", class = "mssrscopR_error_unsupported")
})

test_that("oversized or out-of-file tag payloads fail before decoding", {
  path <- withr::local_tempfile(fileext = ".tif")
  f <- reader_fixture(path)
  bytes <- f$bytes
  bytes[15:18] <- reader_uint(2^31, 4)
  writeBin(bytes, path)
  expect_error(mssr_app_tiff_preflight(path, 1L), "4 MiB", class = "mssrscopR_error_resource")
  bytes[15:18] <- reader_uint(2, 4)
  bytes[19:22] <- reader_uint(2^32 - 1, 4)
  writeBin(bytes, path)
  expect_error(mssr_app_tiff_preflight(path, 1L), "beyond", class = "mssrscopR_error_input")
  bytes <- f$bytes
  bytes[13:14] <- reader_uint(0, 2)
  writeBin(bytes, path)
  expect_error(mssr_app_tiff_preflight(path, 1L), "field types", class = "mssrscopR_error_input")
})

test_that("reader warnings cannot silently return incomplete pixels", {
  expect_error(mssr_app_decode({
    cli::cli_warn("incomplete strip")
    matrix(0, 2, 3)
  }),
  class = "mssrscopR_error_input")
})

test_that("huge TIFF dimensions are refused before library metadata allocation", {
  skip_if_not_installed("tiff")
  path <- withr::local_tempfile(fileext = ".tif")
  f <- reader_fixture(path)
  f$bytes[19:22] <- reader_uint(2^32 - 1, 4)
  writeBin(f$bytes, path)
  local_mocked_bindings(readTIFF = function(...) cli::cli_abort("library must not open this file"),
                        .package = "tiff")
  expect_error(mssr_app_read(path, "huge.tif"), class = "mssrscopR_error_resource")
})

test_that("TIFF segment bounds are checked before the library can allocate", {
  skip_if_not_installed("tiff")
  path <- withr::local_tempfile(fileext = ".tif")
  local_mocked_bindings(readTIFF = function(...) cli::cli_abort("library must not open this file"),
                        .package = "tiff")
  for (endian in c("little", "big")) {
    for (tiled in c(FALSE, TRUE)) {
      f <- reader_fixture(path, endian = endian, tiled = tiled)
      ids <- vapply(f$tags, function(x) x$tag, numeric(1))
      for (tag in if (tiled) c(324, 325) else c(273, 279)) {
        slot <- 10 + (which(ids == tag) - 1L) * 12 + 9:12
        for (value in c(0, length(f$bytes) + 1, 2^32 - 1)) {
          bytes <- f$bytes
          bytes[slot] <- reader_uint(value, 4, endian)
          writeBin(bytes, path)
          expect_error(mssr_app_read(path, "bad-segment.tif"), "segments",
                       class = "mssrscopR_error_input")
        }
      }
    }
  }
})

test_that("independent compressed strips and edge tiles preserve samples", {
  skip_if_not_installed("tiff")
  root <- test_path("fixtures", "tiff-codecs")
  cases <- utils::read.csv(file.path(root, "index.csv"), stringsAsFactors = FALSE)
  for (i in seq_len(nrow(cases))) {
    spec <- cases[i, ]
    expected <- unname(as.matrix(utils::read.csv(
      file.path(root, spec$expected_values), header = FALSE
    )))
    storage.mode(expected) <- "double"
    got <- mssr_app_read(file.path(root, spec$fixture), spec$fixture,
                         channel = spec$channel, page = spec$page)
    expect_identical(got$x, expected, info = spec$fixture)
    expect_identical(got$metadata$page, spec$page)
    expect_identical(got$metadata$pages, spec$pages)
    expect_identical(got$metadata$channel, spec$channel)
  }
})

test_that("TIFF segment descriptors must use matched unsigned arrays", {
  path <- withr::local_tempfile(fileext = ".tif")
  f <- reader_fixture(path)
  ids <- vapply(f$tags, function(x) x$tag, numeric(1))
  entry <- 10 + (which(ids == 279) - 1L) * 12
  bytes <- f$bytes
  bytes[entry + 3:4] <- reader_uint(9, 2)
  writeBin(bytes, path)
  expect_error(mssr_app_tiff_preflight(path, 1), "unsigned integers",
               class = "mssrscopR_error_input")
  bytes <- f$bytes
  bytes[entry + 1:2] <- reader_uint(40000, 2)
  writeBin(bytes, path)
  expect_error(mssr_app_tiff_preflight(path, 1), "missing or inconsistent",
               class = "mssrscopR_error_input")
  bytes <- f$bytes
  bytes[entry + 1:2] <- reader_uint(325, 2)
  writeBin(bytes, path)
  expect_error(mssr_app_tiff_preflight(path, 1), "missing or inconsistent",
               class = "mssrscopR_error_input")
  bytes <- readBin(test_path("fixtures", "tiff-codecs",
                             "core_deflate_s_le_u16_c1_p1.tif"),
                   "raw", 1e5)
  count <- sum(as.numeric(bytes[9:10]) * c(1, 256))
  ids <- vapply(seq_len(count), function(i) {
    sum(as.numeric(bytes[10 + (i - 1L) * 12 + 1:2]) * c(1, 256))
  }, numeric(1))
  entry <- 10 + (which(ids == 279) - 1L) * 12
  bytes[entry + 5:8] <- reader_uint(1, 4)
  writeBin(bytes, path)
  expect_error(mssr_app_tiff_preflight(path, 1), "missing or inconsistent",
               class = "mssrscopR_error_input")
})

test_that("short encoded streams fail even when segment extents fit the file", {
  skip_if_not_installed("tiff")
  for (codec in c("lzw", "deflate", "packbits")) {
    name <- paste0("short_", codec, ".tif")
    path <- test_path("fixtures", "tiff-codecs", name)
    expect_identical(mssr_app_tiff_preflight(path, 1L)$pages, 1L)
    expect_error(mssr_app_read(path, name), class = "mssrscopR_error_input")
  }
})
