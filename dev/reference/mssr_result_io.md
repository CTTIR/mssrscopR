# Write and read an exact, bounded result record

Stores only the documented result contract, with exact binary double
values, typed JSON metadata and SHA-256 corruption detection. No R
expressions, serialized R objects, source image, source path or
acquisition identity are stored. A matching checksum is not proof of
origin or scientific validity.

## Usage

``` r
mssr_write_result(result, path, overwrite = FALSE, max_bytes = 64 * 1024^2)

mssr_read_result(path, max_bytes = 64 * 1024^2, max_output_pixels = 5e+07)
```

## Arguments

- result:

  A validated result from
  [`mssr()`](https://cttir.github.io/mssrscopR/dev/reference/mssr.md).

- path:

  Explicit path to a single result file; its directory must exist.

- overwrite:

  Replace an existing file, if the filesystem supports atomic
  replacement. Defaults to `FALSE`.

- max_bytes:

  Maximum total record size in bytes, below 2^31 - 1.

- max_output_pixels:

  Maximum decoded matrix size when reading.

## Value

The writer invisibly returns the normalized file path. The reader
returns the stored result without changing its schema or engine
identity.

## Details

Optional packages `jsonlite` and `digest` are required only for these
functions. The writer stages and reads back the complete record before
installing it. With `overwrite = FALSE`, installation uses an exclusive
hard link; filesystems without hard-link support fail without writing a
completed destination. With `overwrite = TRUE`, atomic rename must
succeed; an existing file is never deleted as a fallback. Symbolic-link
file paths are refused.

The reader checks file size, a fixed 1 MiB metadata ceiling, metadata
nesting, schema, dimensions, exact payload length and SHA-256 before
returning a result. It reads at most `max_bytes` plus one byte before
decoding. The record and decoded matrix coexist in memory, so the byte
ceiling is not a process memory cap. No compression or external
references are accepted.

## Examples

``` r
if (requireNamespace("jsonlite", quietly = TRUE) &&
  requireNamespace("digest", quietly = TRUE)) {
  r <- mssr(matrix(1:20, 4, 5), fwhm = 2)
  path <- tempfile(fileext = ".mssr")
  mssr_write_result(r, path)
  identical(mssr_read_result(path), r)
  unlink(path)
}
```
