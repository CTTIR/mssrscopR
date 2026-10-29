# Interactive MSSR explorer

Opens a Shiny app for trying
[`mssr()`](https://cttir.github.io/mssrscopR/dev/reference/mssr.md) on
synthetic examples or on an uploaded frame. It shows the input and the
structure map side by side on the same input-pixel axes, line profiles,
structural masks applied to the original data
([`mssr_mask()`](https://cttir.github.io/mssrscopR/dev/reference/mssr_mask.md))
and the fixture self-test
([`mssr_selftest()`](https://cttir.github.io/mssrscopR/dev/reference/mssr_selftest.md)),
and offers the structure map, the mask, a figure and a run record for
download. The app calls the exported functions, so its results are the
same as in R; it adds no processing of its own.

## Usage

``` r
mssr_app(max_upload_mb = 50, ...)
```

## Arguments

- max_upload_mb:

  Maximum upload size in megabytes.

- ...:

  Passed to
  [`shiny::runApp()`](https://rdrr.io/pkg/shiny/man/runApp.html), for
  example `port` or `launch.browser`.

## Value

The value of
[`shiny::runApp()`](https://rdrr.io/pkg/shiny/man/runApp.html),
invisibly; called for its side effect.

## Details

**Uploads.** Delimited text (`.csv` comma-separated, `.tsv` or `.txt`
separated by tabs or spaces; numbers only, no header), PNG (needs the
`png` package; values as returned by
[`png::readPNG()`](https://rdrr.io/pkg/png/man/readPNG.html), scaled to
0..1) and TIFF (needs the `tiff` package; stored values, unscaled).
Multi-channel images are not converted to gray: choose one channel. For
multi-page TIFF choose a page. Files are read by the R process that runs
the app (your own session when started with `mssr_app()`); the app sends
nothing elsewhere. Run records include SHA-256 identities of uploaded
bytes and decoded matrix content (needs `digest`). Source filenames and
paths are excluded. Retain the original input and preprocessing
separately; a digest identifies content, not acquisition authenticity.
Compare a retained file with
`digest::digest(file = path, algo = "sha256", serialize = FALSE)`.

**Limits.** To keep the app responsive, runs whose estimated work
exceeds 5e8 operations are refused; call
[`mssr()`](https://cttir.github.io/mssrscopR/dev/reference/mssr.md)
directly for larger runs. The image header is checked before decoding;
image uploads are limited to 5e7 samples, conservatively allowing at
least four channels per pixel. Only the selected TIFF page is decoded.
Integer TIFF samples keep their stored values; floating-point TIFF
samples remain unscaled. The structure map is not a quantitative
intensity, and nothing in the app implies a gain in physical resolution.
Packed 12-bit, signed-integer, palette, multi-channel planar-separate
and volumetric TIFF images are unsupported; prepare an explicit
supported 2D frame before uploading. The TIFF preflight accepts classic
TIFF, top-left orientation, grayscale black-is-zero or RGB samples, at
most 256 pages, 4096 tags per page, 4 MiB of directory/tag metadata and
a 256 MiB file. BigTIFF, nested directories and other orientations/color
conversions are refused. These are workload guards, not a hard decoder
memory or time guarantee. Computation runs in one background R process
per app session (needs `callr`). Cancel stops only that session's job.
Incomplete results cannot be downloaded; the previous completed result
can be explicitly restored. A job is cancelled when its session closes
or after five minutes. The child inherits CPU affinity and uses one
numerical thread. Changed settings are marked stale; downloads retain
the computed input and settings. Development-source launches also need
`pkgload`. A job is refused when package files, functions or the native
library differ from what the R session loaded, instead of running other
code.

## Examples

``` r
if (interactive()) {
  mssr_app()
}
```
