# Single-frame MSSR with mssrscopR

![mssrscopR logo](figures/logo.svg)![mssrscopR
logo](figures/logo-dark.svg)

All images here are synthetic and generated in this document, so the
true scene is known.

## The operator

Mean-Shift Super-Resolution (MSSR; Torres-García et al. 2022,
<doi:10.1038/s41467-022-34693-9>) subtracts a local, range-weighted
mean-shift estimate from each pixel and refines the result over `order`
steps. `fwhm` is the point-spread-function width in **input pixels** and
has no default.

``` r

g <- expand.grid(r = 1:31, c = 1:41)
spot <- function(r0, c0, a = 1) a * exp(-((g$r - r0)^2 + (g$c - c0)^2) / (2 * (3 / 2.3548)^2))
pair <- function(sep) matrix(spot(16, 18) + spot(16, 18 + sep) + 0.05, 31, 41)
x <- pair(3)                       # two sources 3 px apart, FWHM 3 px
res <- mssr(x, fwhm = 3, amp = 2)
res
#> <mssr_result> intensity_weighted_structure
#>   input 31 x 41 -> output 62 x 82 (amp 2, extent grid)
#>   fwhm 3 px, order 1, kernel disk (half-size 3), mesh TRUE
#>   engine mssr_r_rev3; zero fraction 0.633
#>   Not a quantitative intensity: measure on the original data.
op <- par(mfrow = c(1, 2), mar = c(0.5, 0.5, 2, 0.5))
show(x, "input"); show(as.matrix(res), "mssr(amp = 2)")
```

![](mssrscopR_files/figure-html/points-1.png)

``` r

par(op)
```

The amplified grid only adds samples.
[`mssr_coords()`](https://cttir.github.io/mssrscopR/reference/mssr_coords.md)
places them in input-pixel units, and the field of view stays
`[0.5, n + 0.5]`:

``` r

range(mssr_coords(res)$col)
#> [1]  0.75 41.25
res$transform$spacing
#> row col 
#> 0.5 0.5
```

How far does the separation go? Compare the value at the midpoint
between the two sources with the value at a source center, in the input
and in the MSSR map (values below 1 mean a dip between the sources):

``` r

mid_ratio <- function(sep) {
  x <- pair(sep)
  r <- mssr(x, fwhm = 3, amp = 2)
  v <- as.matrix(r)
  co <- mssr_coords(r)
  row <- which.min(abs(co$row - 16))
  at_input <- function(cc) stats::approx(1:41, x[16, ], cc)$y
  at_mssr <- function(cc) stats::approx(co$col, v[row, ], cc)$y
  c(input = at_input(18 + sep / 2) / at_input(18), mssr = at_mssr(18 + sep / 2) / at_mssr(18))
}
round(rbind(`2.4 px` = mid_ratio(2.4), `2.6 px` = mid_ratio(2.6), `3 px` = mid_ratio(3)), 3)
#>        input  mssr
#> 2.4 px 1.086 1.235
#> 2.6 px 1.054 0.815
#> 3 px   0.968 0.255
```

At 3 px the input shows only a shallow dip, which MSSR deepens strongly.
At 2.6 px the input pixels have a single maximum, between the sources,
yet MSSR returns two peaks with a clear dip (ratio below 1): it can
separate sources that the pixels show merged. Its peaks move toward each
other, so a ratio taken at the source centers can stay above 1 although
two peaks exist. The peak positions along row 16 show this directly
(true sources at 18 and 18 + separation):

``` r

peaks <- function(sep, amp = 2) {
  r <- mssr(pair(sep), fwhm = 3, amp = amp)
  co <- mssr_coords(r)
  v <- as.matrix(r)[which.min(abs(co$row - 16)), ]
  i <- which(diff(sign(diff(v))) == -2) + 1
  co$col[i[v[i] > 0.05 * max(v)]]
}
list(`2.4 px` = peaks(2.4), `2.4 px, amp 4` = peaks(2.4, amp = 4), `2.6 px` = peaks(2.6))
#> $`2.4 px`
#> [1] 19.75
#> 
#> $`2.4 px, amp 4`
#> [1] 18.625 19.625
#> 
#> $`2.6 px`
#> [1] 18.25 20.25
```

At 2.4 px MSSR returns a single, sharper peak at `amp = 2`; at `amp = 4`
it shows two peaks with a barely visible dip, 1 px apart for sources 2.4
px apart. The spacing of MSSR peaks therefore underestimates the true
separation near this limit.

## Known failure modes

MSSR is nonlinear. A dim structure next to a bright one is strongly
suppressed, and broad filled objects can be hollowed or fragmented:

``` r

y <- matrix(spot(16, 14) + spot(16, 21.5, 0.1) + 0.02, 31, 41)   # 10:1 brightness
disk <- outer(1:31, 1:41, function(r, c) as.numeric((r - 16)^2 + (c - 21)^2 <= 81))
disk <- disk + 0.02
ry <- as.matrix(mssr(y, fwhm = 3))
rd <- as.matrix(mssr(disk, fwhm = 3))
c(input_ratio = y[16, 22] / y[16, 14], mssr_ratio = ry[16, 22] / ry[16, 14],
  disk_center = rd[16, 21])
#> input_ratio  mssr_ratio disk_center 
#> 0.110379995 0.008616307 0.000000000
op <- par(mfrow = c(1, 3), mar = c(0.5, 0.5, 2, 0.5))
show(ry, "dim beside bright"); show(disk, "filled disk"); show(rd, "mssr(disk)")
```

![](mssrscopR_files/figure-html/failures-1.png)

``` r

par(op)
```

Extended objects are emphasized at their edges: the filled disk becomes
a ring with a zero center, so segment filled objects such as nuclei on
the original data. A rod three FWHM long becomes two peaks near its
ends, with a lower interior:

``` r

rod <- matrix(Reduce(`+`, lapply(seq(16.5, 25.5, length.out = 41),
                                 function(cc) spot(16, cc, 1 / 41))) + 0.002, 31, 41)
rr <- mssr(rod, fwhm = 3, amp = 2)
co <- mssr_coords(rr)
op <- par(mar = c(4, 4, 0.5, 0.5))
plot(co$col, as.matrix(rr)[which.min(abs(co$row - 16)), ], type = "l",
     xlab = "column (input px)", ylab = "mssr along row 16")
lines(1:41, rod[16, ] / max(rod[16, ]) * max(rr$values), lty = 2)
legend("topright", c("mssr", "input (scaled)"), lty = 1:2, bty = "n")
```

![](mssrscopR_files/figure-html/rod-1.png)

``` r

par(op)
```

With noise, the mean shift also responds to noise maxima: single sources
and short rods can break into several peaks, one source can look like a
pair, and dim sources are lost first. An `fwhm` smaller than the true
PSF makes false pairs more likely, and higher `order` values add
further, mostly weak, maxima. Compare results with the input, and test
settings on a synthetic noisy scene of known content that resembles your
data.

These failure modes are why the outputs are **not quantitative**;
`res$diagnostics$quantitative` is always `FALSE`.

## Several channels or bands

[`mssr()`](https://cttir.github.io/mssrscopR/reference/mssr.md) takes
one 2D frame, so multichannel and spectral data are processed one
channel at a time, and each channel gets its own structure map. Here
channel `b` holds the same two sources as channel `a`, but its second
source is half as bright; `0.5 * a` is a scaled copy of `a`:

``` r

a <- matrix(spot(16, 14) + spot(16, 26) + 0.05, 31, 41)
b <- matrix(spot(16, 14) + spot(16, 26, 0.5) + 0.05, 31, 41)
ra <- as.matrix(mssr(a, fwhm = 3))
rb <- as.matrix(mssr(b, fwhm = 3))
rc <- as.matrix(mssr(0.5 * a, fwhm = 3))
round(c(input = b[16, 26] / a[16, 26], mssr = rb[16, 26] / ra[16, 26],
        scaled_copy = rc[16, 26] / ra[16, 26]), 3)
#>       input        mssr scaled_copy 
#>       0.524       0.243       0.500
```

The ratio of `b` to `a` at the second source falls to about half its
input value, while the scaled copy keeps its ratio. A different
background or another object elsewhere in one channel also changes the
ratios. Ratios between channels, indices and spectra therefore belong to
the original data, for example measured under a mask as below.

## Masks with measurements on the original data

A structure map can select pixels, but measurements belong to the
original image.
[`mssr_mask()`](https://cttir.github.io/mssrscopR/reference/mssr_mask.md)
keeps an exact number of pixels of a region. `tie_fraction` reports the
share of the selected pixels that random tie-breaking decided, and
`cut_relative` the lowest selected score relative to the highest. The
mean shift is clipped at zero, so most of this map is exactly zero; keep
a share below the positive one.

``` r

r <- mssr(x, fwhm = 3)
mean(as.matrix(r) > 0)             # share of pixels with any structure
#> [1] 0.0220299
m <- mssr_mask(r, fraction = 0.02)
c(coverage = attr(m, "coverage"), tie_fraction = attr(m, "tie_fraction"),
  cut_relative = attr(m, "cut_relative"))
#>     coverage tie_fraction cut_relative 
#>  0.020456334  0.000000000  0.002531077
c(mean_all = mean(x), mean_masked = mean(x[m]))
#>    mean_all mean_masked 
#>  0.06604718  0.58442567
```

A larger share reaches into the zeros. Tie-breaking then decides most of
the mask, which
[`mssr_mask()`](https://cttir.github.io/mssrscopR/reference/mssr_mask.md)
reports with a warning:

``` r

wide <- mssr_mask(r, fraction = 0.2)
#> Warning: The mask reaches pixels where the MSSR map shows no structure: 89% of the
#> selected pixels were chosen by tie-breaking and the lowest selected score is 0
#> of the highest. Choose a smaller `fraction` or a `region`.
attr(wide, "tie_fraction")
#> [1] 0.8901961
```

Selecting pixels this way changes the measured population. It is not
known to improve any downstream analysis, so evaluate it for your own
task.

## Degenerate input and unsupported requests

Flat frames return zeros flagged as degenerate. Requests the package
cannot honor fail with classed errors:

``` r

mssr(matrix(1, 5, 5), fwhm = 3)$diagnostics[c("degenerate", "degenerate_reason")]
#> $degenerate
#> [1] TRUE
#> 
#> $degenerate_reason
#> [1] "flat input"
try(mssr(array(0, c(4, 4, 3)), fwhm = 3))     # no axis is guessed
#> Error in mssr(array(0, c(4, 4, 3)), fwhm = 3) : 
#>   `x` has 3 dimensions; process one 2D frame at a time (no axis is
#> inferred).
try(mssr(matrix(c(1, NA, 3, 4), 2), fwhm = 3)) # non-finite input
#> Error in mssr(matrix(c(1, NA, 3, 4), 2), fwhm = 3) : 
#>   `x` contains NA, NaN or infinite values; MSSR is undefined for them.
```

## Interactive exploration

[`mssr_app()`](https://cttir.github.io/mssrscopR/reference/mssr_app.md)
opens the same computations in a Shiny app (it needs the shiny, bslib,
jsonlite, callr and digest packages). It shows the input and the
structure map on the same input-pixel axes, line profiles, masks
measured on the input and the self-test, and offers the results for
download. The examples above are available there, and frames can be
uploaded as text tables, PNG or TIFF.

Computation runs in one background job per app session. Cancel stops the
owned job, and incomplete results cannot be exported. A previous
completed input, settings and mask can be explicitly restored. The run
record distinguishes restored results and settings captured at
computation from current controls. A session closing or a five-minute
limit stops its unfinished job. Development source launches need
pkgload; installed-package launches use the exact installed namespace
and verify their loaded definitions.

``` r

mssr_app()
```

## Checking an installation

[`mssr_selftest()`](https://cttir.github.io/mssrscopR/reference/mssr_selftest.md)
recomputes the bundled synthetic fixtures. They were produced by the
package’s engine definition, so this is a regression check of the
installation, not an independent validation:

``` r

st <- mssr_selftest()
st[, c("fixture_id", "max_abs_error", "passed")]
#>                           fixture_id max_abs_error passed
#> 1                       fx01_amp1_o1  5.551115e-16   TRUE
#> 2                fx02_amp1_o1_nonorm  0.000000e+00   TRUE
#> 3                  fx02_amp1_o1_norm  0.000000e+00   TRUE
#> 4                   fx03_constant_o2  0.000000e+00   TRUE
#> 5                       fx04_zero_o1  0.000000e+00   TRUE
#> 6                       fx05_amp1_o0  0.000000e+00   TRUE
#> 7                       fx05_amp1_o1  0.000000e+00   TRUE
#> 8                fx06_amp2_extent_o1  1.276756e-14   TRUE
#> 9              fx06_amp2_endpoint_o1  1.032507e-14   TRUE
#> 10               fx07_amp1_o3_nonorm  1.418136e-16   TRUE
#> 11 fx08_amp2_extent_o1_halfup_nomesh  1.065814e-13   TRUE
#> 12      fx09_amp3_endpoint_o2_nonorm  6.661338e-15   TRUE
#> 13               fx10_amp2_square_o1  2.042810e-14   TRUE
#> 14        fx11_amp1_square_o2_nonorm  8.560616e-17   TRUE
```

## Reproducible expert workflow

Choose FWHM from the acquisition PSF in input-pixel units. Record its
source and uncertainty; an image’s dimensions do not establish physical
calibration. A measured PSF is preferable to a theoretical one, which
describes an ideal system; the recorded PSF can be wider. Under noise a
too-small FWHM adds false peaks and a larger one weakens the separation
of close sources, so choose the larger plausible value when unsure. Only
the kernel half-size in `parameters$half_size` enters the computation,
so compare settings that change it. Fix preprocessing, channel
selection, frame boundaries and parameter-selection rules before
evaluating outcomes. Cropping changes the neighborhood context and
global normalizers, so a cropped reconstruction need not equal a crop of
the full-frame result. Background subtraction is a distinct
preprocessing decision.

Start with a low order and compare plausible acquisition-informed
settings. Orders above 3 are accepted for compatibility but produce a
qualification warning: the expanded independent reference suite found
sensitive high-order failures. The bounded passing domain is evidence
about the tested scenes, not a guarantee for an arbitrary noisy
acquisition. Review broad-object hollowing/splitting, missing dim
structures and blank/noise-only fields alongside favorable examples.

``` r

frame <- outer(1:13, 1:17, function(r, c) 0.05 + exp(-((r-7)^2+(c-9)^2)/8))
result <- mssr(frame, fwhm = 3, order = 1)
summary(result)
#> MSSR result summary: intensity_weighted_structure
#>   Grid:        input 13 x 17 -> output 13 x 17 (amp 1, extent grid)
#>   Parameters:  fwhm 3 px, order 1, kernel disk (half-size 2), rounding half_even
#>                intensity weighting TRUE, mesh FALSE
#>   Values:      range 0 to 1.05; zero fraction 0.805; negative fraction 0.000
#>   Diagnostics: defined; 0 undefined order step(s) skipped; 12 offsets
#>   Engine:      mssr_r_rev3, mssrscopR 0.2.0; result schema 1.0.0; evidence numerical_tool_only
#>   Not a quantitative intensity: measure on the original data.
mssr_estimate_resources(dim(frame), fwhm = 3)
#> $input_dim
#> [1] 13 17
#> 
#> $output_dim
#> [1] 13 17
#> 
#> $output_pixels
#> [1] 221
#> 
#> $half_size
#> [1] 2
#> 
#> $n_offsets
#> [1] 12
#> 
#> $estimated_work
#> [1] 2652
#> 
#> $estimated_peak_bytes
#> [1] 134272136
#> 
#> $model
#> [1] "whole_frame_buffers_v2"
#> 
#> $hard_limit
#> [1] FALSE
#> 
#> $limitation
#> [1] "Allocation estimate; retained objects and runtime can increase process RSS."
```

[`mssr_validate_result()`](https://cttir.github.io/mssrscopR/reference/mssr_validate_result.md)
checks a result’s internal contract.
[`mssr_write_result()`](https://cttir.github.io/mssrscopR/reference/mssr_result_io.md)
and
[`mssr_read_result()`](https://cttir.github.io/mssrscopR/reference/mssr_result_io.md)
use explicit paths, integrity hashes and exact binary values; optional
`digest` and `jsonlite` are needed for these operations. They do not
establish acquisition provenance. Never use reconstructed intensities as
calibrated measurements. Original-data measurements under a mask still
reflect selection bias: report retained coverage, compare with sensible
controls and inspect how small score changes alter the selected
population.

[`mssr_batch()`](https://cttir.github.io/mssrscopR/reference/mssr_batch.md)
processes a named list of independent whole frames with one worker. It
records failures and cancellations, checks completed results before
reuse and retains separate attempts. It checks cancellation between
frames. Its memory budget is a conservative estimate; use a separate
process-level limit when a hard memory cap is required. It does not
implement tiling or infer time, depth, wavelength, specimen identity or
physical units from an array.

## Save and replay an analysis

[`mssr_settings()`](https://cttir.github.io/mssrscopR/reference/mssr_settings.md)
validates the result and returns only callable computation settings,
including the grid. Passing `result$parameters` directly is not a replay
recipe: it includes a derived kernel half-size and omits the grid.
Settings are resolved values, so mesh compensation is recorded as off
when amplification is 1. Resource budgets are not retained settings;
choose them explicitly when recomputing.

The example below retains the original synthetic frame and mask context
in memory, then reads the exact result from a file. For a durable
analysis, keep the original frame in trusted storage and retain its
identity, preprocessing, channel/frame selection, acquisition
information and mask context alongside it. The `.mssr` file does not
contain those inputs. Here no acquisition calibration is available, and
FWHM is a chosen synthetic setting.

``` r

original <- frame
context <- list(
  preprocessing = "none; authored synthetic frame",
  region = outer(seq_len(nrow(original)), seq_len(ncol(original)),
                 function(r, c) r <= 10 & c >= 4),
  fraction = 0.2,
  seed = 23L
)
result <- mssr(original, fwhm = 3, amp = 2, order = 1,
               max_output_pixels = 5e7, max_memory_bytes = 1024^3)
mask <- mssr_mask(result, fraction = context$fraction,
                  region = context$region, seed = context$seed)
measurement <- mean(original[mask])

if (requireNamespace("digest", quietly = TRUE) &&
    requireNamespace("jsonlite", quietly = TRUE)) {
  path <- tempfile(fileext = ".mssr")
  mssr_write_result(result, path)
  restored <- mssr_read_result(path)
  stopifnot(identical(restored$engine$package_version,
                      as.character(packageVersion("mssrscopR"))))
  replay <- do.call(mssr, c(
    list(x = original, max_output_pixels = 5e7, max_memory_bytes = 1024^3),
    mssr_settings(restored)
  ))
  replay_mask <- mssr_mask(replay, fraction = context$fraction,
                           region = context$region, seed = context$seed)
  stopifnot(identical(replay$values, restored$values),
            identical(replay$transform, restored$transform),
            identical(replay_mask, mask),
            identical(mean(original[replay_mask]), measurement))
  unlink(path)
}
```

Preserve the package artifact and runtime environment with a durable
analysis, for example by retaining
[`sessionInfo()`](https://rdrr.io/r/utils/sessionInfo.html) output. The
helper refuses results from a different numerical engine and does not
migrate historical results. A legacy result schema with the current
engine can still supply validated settings. Matching engine and settings
is not a promise of identical arithmetic across package versions or
environments: verify values and the original-data measurement after
replay. The measurement remains subject to mask selection; successful
reproduction does not validate the scientific choice of mask.
