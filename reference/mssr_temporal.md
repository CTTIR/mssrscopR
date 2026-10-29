# Temporal statistics of per-frame MSSR maps

Computes single-frame MSSR
([`mssr()`](https://cttir.github.io/mssrscopR/reference/mssr.md)) for
every frame of an image sequence and reduces the stack of maps pixel by
pixel with one temporal statistic, as in the temporal MSSR (t-MSSR) of
Torres-Garcia et al. (2022, Fig. 7a and Supplementary Note 5.2). The
output is a temporal statistic of nonlinear structure maps: it is not a
quantitative intensity, and no gain in resolution is implied (see
**Interpretation**). `mssr_stack()` stores the per-frame maps so that
several statistics can be computed without recomputing MSSR.

## Usage

``` r
mssr_temporal(
  x,
  statistic,
  fwhm,
  amp = 1L,
  order = 1L,
  intensity_normalize = TRUE,
  mesh = TRUE,
  grid = c("extent", "endpoint"),
  kernel = c("disk", "square"),
  rounding = c("half_even", "half_up"),
  frames = NULL,
  sign = c("signed", "absolute"),
  background = NULL,
  max_output_pixels = 5e+07,
  max_memory_bytes = NULL
)

mssr_stack(
  x,
  fwhm,
  amp = 1L,
  order = 1L,
  intensity_normalize = TRUE,
  mesh = TRUE,
  grid = c("extent", "endpoint"),
  kernel = c("disk", "square"),
  rounding = c("half_even", "half_up"),
  frames = NULL,
  max_output_pixels = 5e+07,
  max_memory_bytes = NULL
)
```

## Arguments

- x:

  Either a plain numeric array with dimensions rows x columns x frames
  (rows = y, columns = x) and finite values, or an `mssr_stack` from
  `mssr_stack()`. For an `mssr_stack`, the per-frame arguments (`fwhm`
  to `rounding` and `max_output_pixels`) must not be given; the stored
  maps already fix them.

- statistic:

  One of `"mean"`, `"var"`, `"tpm"`, `"cv"`, `"sofi2"`, `"sofi3"` or
  `"sofi4"`. Required: none of them is a safe default.

- fwhm, amp, order, intensity_normalize, mesh, grid, kernel, rounding,
  max_output_pixels:

  Per-frame MSSR settings, exactly as in
  [`mssr()`](https://cttir.github.io/mssrscopR/reference/mssr.md).
  `fwhm` is required for raw frames.

- frames:

  Optional contiguous, increasing frame indices; the lags need
  consecutive frames. Defaults to all frames.

- sign:

  For `"sofi2"`, `"sofi3"` and `"sofi4"`: `"signed"` (default) returns
  the cumulant, `"absolute"` its absolute value. Other statistics accept
  only `"signed"`.

- background:

  Optional logical matrix on the input grid that marks signal-free
  pixels for `diagnostics$mesh_index`. By default these are the pixels
  whose raw temporal mean is below the median of that mean. Because the
  mesh index is formed only with `amp > 1` on the extent grid, giving
  `background` otherwise is an error.

- max_memory_bytes:

  Optional positive allocation-estimate budget (see **Computation**).
  This is not a hard process-memory cap. For an `mssr_stack`, whose maps
  already exist, it limits the reduction's buffers.

## Value

`mssr_temporal()` returns an `mssr_result` (result schema 1.1.0) with
`role` `"temporal_<statistic>"`, `values` on the amplified grid and the
same `transform` as
[`mssr()`](https://cttir.github.io/mssrscopR/reference/mssr.md).
`parameters` holds the per-frame MSSR settings plus `statistic`,
`frames` (the number of frames used), `first_frame` (the first frame's
index in the original input), `sign` (`"not_applicable"` for statistics
other than SOFI) and `definition`. `diagnostics` counts
`degenerate_frames`, `warning_frames` and `order_steps_skipped` over the
frames, and gives `zero_fraction`, `negative_fraction`, `mesh_index`,
`mesh_region`, `trend` and the computation `path`. `mssr_stack()`
returns an object of class `mssr_stack`: `values` (an array of the
per-frame maps), `transform`, `parameters` (with `frames` and
`first_frame`), `engine`, `diagnostics` (a data frame with one row per
frame, including the raw frame's mean `input_mean`) and `input_mean`
(the raw temporal mean on the input grid).

`diagnostics$mesh_index` measures the sub-pixel grid on signal-free
input pixels only, because where structure is present the index mixes
structure and grid. Each such input pixel contributes its whole
`amp x amp` block of output pixels; the index is the range of the mean
over the `amp x amp` sub-pixel phases, divided by the absolute mean of
these blocks. For the SOFI statistics it is computed on the absolute
values, because signed cumulants average to about zero where there is no
signal. It is formed only on the default `grid = "extent"`, where every
input pixel holds each phase exactly once; on the endpoint grid the
phases drift across the field.

`mesh_region` names the pixels used: `"below_median"`, the pixels whose
raw temporal mean over the selected frames lies strictly below its
median; `"below_median_stack"`, the same rule for a frame subset of an
`mssr_stack`, whose stored raw mean covers all of its frames, so the
index can differ from that of the raw frames; `"background"`, a supplied
mask; or `"not_computed"` for `amp = 1` and the endpoint grid.
`mesh_pixels` counts the input pixels used. `mesh_index` is `NULL` when
no index is computed, when no pixel qualifies (for example when more
than half of the pixels share the lowest raw mean, so that none lies
below the median; supply `background` then), or when the mean of the
blocks is 0.

`diagnostics$trend` is the mean of the raw frames over the whole field
in the last tenth of the selected frames divided by that in the first
tenth (at least one frame each); `NULL` when the first is 0. It is
reported for every statistic and corrects nothing.

## Details

**Definitions.** Per output pixel, `x_1, ..., x_M` are the values of the
`M` selected frames' MSSR maps, `m` is their mean and `d_t = x_t - m`.
Following Supplementary Table S2:

|  |  |  |
|----|----|----|
| `statistic` | Value | Minimum `M` |
| `"mean"` | `m` | 1 |
| `"var"` | `(1/M) sum(d_t^2)` | 2 |
| `"tpm"` | `(sum(x_t))^2` | 1 |
| `"cv"` | `var / m`, and 0 where `m = 0` | 2 |
| `"sofi2"` | `(1/(M-1)) sum_{t=1}^{M-1} d_t d_{t+1}` | 2 |
| `"sofi3"` | `(1/(M-2)) sum_{t=1}^{M-2} d_t d_{t+1} d_{t+2}` | 3 |
| `"sofi4"` | `A(0,1,2,3) - A(0,1)A(2,3) - A(0,2)A(1,3) - A(0,3)A(1,2)` | 4 |

For `"sofi4"`, `A(L)` is the average over `t = 1, ..., M - 3` of the
product of `d_{t+l}` for the lags `l` in `L`; all its terms use the same
frames.

- `"var"` is the population variance; the sample variance is larger by
  `M / (M - 1)`.

- `"tpm"` equals `M^2 * mean^2`. For non-negative maps it is a monotone
  function of the mean and shows nothing that `"mean"` does not; it is
  offered because every implementation by the authors computes it.

- `"cv"` is the supplement's "CV", literally `Var / Mean`: an index of
  dispersion, not the standard deviation divided by the mean. It takes
  the sign of the mean, so it is negative where the mean is negative
  (signed input). It is 0 where the mean, formed in the scaled range
  described under **Computation**, is exactly 0; where the mean is tiny
  compared with the variance the ratio becomes very large, and a ratio
  beyond the numeric range is refused.

- `"sofi2"` to `"sofi4"` are lagged auto-cumulants of signed deviations.
  Noise that is independent from frame to frame does not enter their
  expectation. Orders 3 and 4 change sign with the emitters' duty cycle,
  so displays usually need `sign = "absolute"`.

The "SOFI" outputs of the authors' Python, MATLAB and Fiji tools are
other statistics, so they do not match these values by design. The
Python and MATLAB tools use absolute deviations at zero lag, which makes
their order 2 the variance without the first frame. The Fiji plugin uses
absolute deviations with lags that wrap around the ends of the
acquisition. Their variance divides by `M - 1` except in the Python
tool. See
[`vignette("method-concordance")`](https://cttir.github.io/mssrscopR/articles/method-concordance.md).

**Interpretation.** `"var"`, `"cv"` and the SOFI statistics depend on
how the emitters blink and on the noise, and every map is a nonlinear
function of its frame. Treat the outputs as visual aids:

- Variance, `"cv"` and SOFI of per-frame MSSR maps, and higher MSSR
  orders, can show two maxima where there is a single emitter.

- When emitters are rarely on and dim, MSSR of nearly empty frames adds
  maxima to every statistic.

- With `amp > 1`, signal-free regions show a sub-pixel grid with the
  period `amp`; `diagnostics$mesh_index` reports its size there (see
  **Value**).

- The article recommends Fourier interpolation for temporal analysis.
  The package amplifies with the supplement's cubic kernel and mesh
  compensation instead; Fourier interpolation is not implemented.

No drift, bleaching or background correction is applied. `"var"`, `"cv"`
and the SOFI statistics treat slow intensity trends (bleaching, drift,
focus changes) as fluctuation, so a large trend inflates them. Correct
the frames first, and record what was done; `diagnostics$trend` reports
the ratio of the raw intensity at the end and at the start of the
selected frames.

**Computation.** Every statistic is formed from centered deviations in
frame order, in a power-of-two scaled range so that products of up to
four deviations stay representable. The scaling is undone at the end; a
value that would exceed the numeric range, or a nonzero value that would
fall below the smallest representable magnitude, raises
`mssrscopR_error_numerical`, and very small results keep only subnormal
precision. `"mean"` and `"tpm"` need one pass over the frames. The
others need the mean first and then a second pass. The per-frame maps
are stored for it when they fit (`diagnostics$path` `"stored"`), else
every frame's MSSR is computed again (`"recompute"`), which doubles the
time. Both paths give the same values. With `max_memory_bytes = NULL`
the maps are stored when they take at most 2 GiB, counted with the
estimate's 100 percent margin for stored maps; with a budget, they are
stored when the estimate fits it, and a call whose recompute path does
not fit is refused.
[`mssr_estimate_resources()`](https://cttir.github.io/mssrscopR/reference/mssr_estimate_resources.md)
reports both estimates; they are checked before any frame is read. The
input array is read one frame at a time and never copied as a whole.
`mssr_stack()` stores every map: without `max_memory_bytes` it refuses
(with `mssrscopR_error_resource`) maps that would take more than 2 GiB
with that margin.

Each frame must satisfy the checks of
[`mssr()`](https://cttir.github.io/mssrscopR/reference/mssr.md); errors
name the frame. Warnings of the frames'
[`mssr()`](https://cttir.github.io/mssrscopR/reference/mssr.md) calls
(negative values, skipped refinement steps) are collected and given once
per class, with the number of frames concerned. A call-level
`mssrscopR_warning_unqualified_order` is given for orders above 3.

## References

Torres-Garcia E, Pinto-Camara R, Linares A, et al. Extending resolution
within a single imaging frame. *Nature Communications* 2022;13:7452.
[doi:10.1038/s41467-022-34693-9](https://doi.org/10.1038/s41467-022-34693-9)

Dertinger T, Colyer R, Iyer G, Weiss S, Enderlein J. Fast,
background-free, 3D super-resolution optical fluctuation imaging (SOFI).
*PNAS* 2009;106:22287-22292.
[doi:10.1073/pnas.0907866106](https://doi.org/10.1073/pnas.0907866106)

## See also

[`mssr()`](https://cttir.github.io/mssrscopR/reference/mssr.md),
[`mssr_estimate_resources()`](https://cttir.github.io/mssrscopR/reference/mssr_estimate_resources.md),
[`vignette("temporal")`](https://cttir.github.io/mssrscopR/articles/temporal.md)

## Examples

``` r
# Two blinking emitters, 40 frames, Poisson noise (synthetic).
set.seed(1)
g <- expand.grid(r = 1:16, c = 1:16)
spot <- function(r0, c0) exp(-((g$r - r0)^2 + (g$c - c0)^2) / (2 * (3 / 2.3548)^2))
x <- array(0, c(16, 16, 40))
for (t in 1:40) {
  on <- stats::runif(2) < 0.4
  x[, , t] <- stats::rpois(256, 20 * (on[1] * spot(8, 7) + on[2] * spot(8, 10)) + 2)
}
s <- mssr_stack(x, fwhm = 3)
v <- mssr_temporal(s, "var")
v
#> <mssr_result> temporal_var
#>   input 16 x 16 -> output 16 x 16 (amp 1, extent grid)
#>   var of 40 frame(s) (frames 1 to 40)
#>   per frame: fwhm 3 px, order 1, kernel disk (half-size 2)
#>   0 degenerate frame(s), 0 frame(s) with warnings; path stack
#>   trend (last / first tenth of frames) 0.997; no mesh index (amp 1 or endpoint grid)
#>   Temporal statistic of nonlinear structure maps, not a quantitative intensity.
m <- mssr_temporal(s, "mean")
all.equal(mssr_temporal(s, "tpm")$values, 40^2 * m$values^2)
#> [1] TRUE
```
