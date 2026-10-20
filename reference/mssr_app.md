# Interactive MSSR explorer

Opens a Shiny app for trying
[`mssr()`](https://cttir.github.io/mssrscopR/reference/mssr.md) on
synthetic examples or on an uploaded frame. It shows the input and the
structure map side by side on the same input-pixel axes, line profiles,
structural masks applied to the original data
([`mssr_mask()`](https://cttir.github.io/mssrscopR/reference/mssr_mask.md))
and the fixture self-test
([`mssr_selftest()`](https://cttir.github.io/mssrscopR/reference/mssr_selftest.md)),
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
nothing elsewhere.

**Limits.** To keep the app responsive, runs whose estimated work
exceeds 5e8 operations are refused; call
[`mssr()`](https://cttir.github.io/mssrscopR/reference/mssr.md) directly
for larger runs. The structure map is not a quantitative intensity, and
nothing in the app implies a gain in physical resolution.

## Examples

``` r
if (interactive()) {
  mssr_app()
}
```
