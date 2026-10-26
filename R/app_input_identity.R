# Fixed byte representation: ASCII tag, two little-endian int32 dimensions,
# then little-endian binary64 samples in R column-major order. Attributes and
# filenames are excluded; numeric integer/double representations agree.
mssr_app_input_identity <- function(x, encoded_file_sha256 = NULL) {
  mssr_app_need("digest", "input content identities")
  x <- check_matrix(x, sys.call())
  path <- tempfile("mssr-frame-identity-", fileext = ".bin")
  con <- file(path, "wb")
  on.exit({
    if (!is.null(con)) close(con)
    unlink(path)
  })
  writeBin(charToRaw("mssr-input-binary64-v1\n"), con)
  writeBin(as.integer(dim(x)), con, size = 4, endian = "little")
  for (first in seq.int(1, length(x), by = 65536)) {
    last <- min(length(x), first + 65535)
    writeBin(as.double(x[first:last]), con, size = 8, endian = "little")
  }
  close(con)
  con <- NULL
  list(algorithm = "sha256", decoded_format = "mssr-input-binary64-v1",
       decoded_frame_sha256 = digest::digest(file = path, algo = "sha256", serialize = FALSE),
       encoded_file_sha256 = encoded_file_sha256,
       filename_retained = FALSE, authenticity_verified = FALSE)
}

mssr_app_read_identified <- function(path, name, channel = 1L, page = 1L) {
  mssr_app_need("digest", "input content identities")
  hash_file <- function() digest::digest(file = path, algo = "sha256", serialize = FALSE)
  before <- hash_file()
  frame <- mssr_app_read(path, name, channel, page)
  frame$metadata$identity <- mssr_app_input_identity(frame$x, before)
  if (!identical(before, hash_file())) {
    mssr_abort("integrity", "The uploaded file changed while it was being read; upload it again.")
  }
  frame
}
