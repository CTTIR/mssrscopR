# Single-frame Mean-Shift Super-Resolution

Computes the Mean-Shift Super-Resolution (MSSR) structure map of one 2D
frame (Torres-Garcia et al. 2022). The result is a structural map for
display, structure analysis or mask derivation. It is **not** a
quantitative intensity: MSSR is nonlinear, suppresses dim structures
next to bright ones and can hollow or split broad objects. Take
measurements from the original data (see
[`mssr_mask()`](https://cttir.github.io/mssrscopR/dev/reference/mssr_mask.md)).

## Usage

``` r
mssr(
  x,
  fwhm,
  amp = 1L,
  order = 1L,
  intensity_normalize = TRUE,
  mesh = TRUE,
  grid = c("extent", "endpoint"),
  kernel = c("disk", "square"),
  rounding = c("half_even", "half_up"),
  max_output_pixels = 5e+07,
  max_memory_bytes = NULL
)
```

## Arguments

- x:

  A plain integer or double matrix (rows = y, columns = x) with finite
  values and no explicit class. Input dimnames and other attributes are
  discarded; acquisition metadata are never inferred from attributes.

- fwhm:

  Full width at half maximum of the point-spread function, in **input
  pixels**. Required; there is no default because it is a property of
  the acquisition. Prefer a measured PSF: a theoretical value such as
  `0.51 * wavelength / NA` (emission wavelength, divided by the pixel
  size) describes an ideal widefield system, and aberrations, defocus
  and pixel size can widen the recorded PSF. Under noise an `fwhm` below
  the true PSF makes false peaks more likely, while a larger one gives a
  shallower dip between close sources; when unsure, choose the larger
  plausible value. Only the kernel half-size, `0.5 * fwhm * amp` rounded
  as set by `rounding` and at least 1 (recorded in
  `parameters$half_size`), enters the computation, so nearby values can
  give identical results.

- amp:

  Amplification factor (whole number from 1 to 64).

- order:

  MSSR order (whole number from 0 to 10). Orders above 3 are
  experimental: bounded high-precision checks found larger errors at
  order 10. They emit `mssrscopR_warning_unqualified_order`. Checks at
  orders 0 through 3 cover only the documented synthetic domain, not
  every input.

- intensity_normalize:

  If `TRUE` (the authors' default) the structure map is multiplied by
  the (amplified) input.

- mesh:

  Mesh compensation after amplification (only used if `amp > 1`).

- grid:

  `"extent"` (field-of-view-preserving, default) or `"endpoint"`
  (samples from the first to the last input pixel center, as the
  authors' code does; for comparison only).

- kernel:

  Neighborhood shape: `"disk"` (authors' R code) or `"square"` (authors'
  Python code).

- rounding:

  Rounding of the kernel half-size `0.5 * fwhm * amp`: `"half_even"` (R
  and Python default) or `"half_up"`.

- max_output_pixels:

  Upper limit on output pixels, checked before any computation.

- max_memory_bytes:

  Optional positive allocation-estimate ceiling. `NULL` leaves this
  guard disabled. This is not a hard process-memory cap; see
  [`mssr_estimate_resources()`](https://cttir.github.io/mssrscopR/dev/reference/mssr_estimate_resources.md).

## Value

An object of class `mssr_result`: a list with `values` (numeric matrix),
`role` (`"structure"` or `"intensity_weighted_structure"`), `transform`,
`parameters`, `engine` and `diagnostics`. `transform` holds `amp`,
`grid`, `input_dim`, `output_dim`, the first output pixel center and the
spacing (input-pixel units), and `field_of_view`: the input frame's
extent from pixel edge 0.5 to `n + 0.5`. Output samples cover it exactly
on the extent grid; on the endpoint grid they span only the first to the
last input pixel center. The input is not stored. `schema_version`
identifies the result contract separately from the numerical engine;
`input` records known axes and unknown calibration; `evidence`
identifies the numerical-only scope. Qualification diagnostics disclose
conservative high-order limits without assigning confidence.

## Details

**Geometry.** The output keeps the input orientation. With
`grid = "extent"` the amplified grid preserves the field of view: output
pixel centers lie at `(k - 0.5) / amp + 0.5` input pixels, so the
spacing is exactly `1 / amp`. Amplification adds samples, not
independent observations.

**Relation to the authors' code.** At `amp = 1` with
`intensity_normalize = FALSE`, tested non-degenerate examples agree with
the authors' single-frame R function after its final 90-degree rotation
is undone (`kernel = "disk"`) or their Python function
(`kernel = "square"`) within floating-point tolerance. Extreme numeric
ranges and undefined refinement steps can differ (see below). For
`amp > 1`, `mssr()` uses the supplement's cubic kernel (Keys cubic
convolution, a = -1/2). The authors' R script interpolates with akima's
Akima method and their Python script with a SciPy spline, and their R
mesh shifts asymmetrically, so the amplified input already differs
beyond rounding; MSSR's range normalization and refinement are nonlinear
and can enlarge such differences locally. Do not expect pixel-wise
agreement with their amplified maps, even with `grid = "endpoint"`,
which reproduces their sample positions. With the default
`intensity_normalize = TRUE` their R function multiplies the rotated map
by the unrotated input, so it agrees with `mssr()` only for frames that
a 90-degree rotation leaves unchanged (and fails for non-square frames).

**Several channels or bands.** `mssr()` processes one 2D frame. Applied
to each channel or band of multichannel or spectral data, it gives every
channel its own nonlinear structure map, scaled by that channel's
maxima. Intensity-weighted outputs (the default) are guaranteed to keep
the channels' intensity ratios only when one whole frame, background
included, is a scaled copy of another; a different background or another
object elsewhere in the frame can change the ratios, and the structure
maps (`intensity_normalize = FALSE`) of scaled copies are identical. So
do not compare channels, form ratios or indices, or assemble spectra
from the outputs; measure them on the original data.

**Degenerate input.** A flat frame, a frame whose amplified maximum is
not positive, a frame without any positive mean shift and a refinement
step that leaves no positive value (possible only with signed input)
return zeros with `diagnostics$degenerate = TRUE` and a
`degenerate_reason`. A refinement step (`order >= 1`) is undefined when
the mean-shift map already equals the normalized input, for example for
isolated impulses on an exactly zero background. Such a step leaves the
map unchanged, is counted in `diagnostics$order_steps_skipped` and gives
a warning of class `mssrscopR_warning_skipped_steps`: the result is not
the limit for slightly perturbed input, because any positive background
makes the step defined and changes the map. The authors' R function
returns `NaN` in all of these cases; their Python function returns
zeros, which equals `mssr()` for the degenerate frames but not for
skipped refinement steps.

**Negative values and background.** MSSR assumes non-negative
intensities. Negative input gives a warning of class
`mssrscopR_warning_negative`, and intensity-weighted output can then be
negative. Non-negative input is not free of offset effects either: the
order-0 structure map (`intensity_normalize = FALSE`) does not change
with a constant background, but every refinement step (`order >= 1`)
compares the map with the input divided by its maximum, which a
background changes, and intensity weighting multiplies by the input.
Subtracting a background is therefore a preprocessing choice that
changes the result; record it with the result. The range normalizer
adapts to the largest local difference at each pixel, so even
rounding-level ripple on an otherwise flat frame is stretched to full
contrast: only an exactly flat frame is degenerate.

**Numeric domain.** Input and numeric parameters must use plain integer
or double storage, without explicit classes. Convert calibrated or other
classed data deliberately before calling. The engine uses internal
power-of-two scaling, centered interpolation for non-negative input and
weighted local differences to limit overflow, underflow and
cancellation. A nonzero input lost during scaling or an overflowing
final result raises `mssrscopR_error_numerical`. Rounding already
present in the supplied data cannot be recovered. Intensity-weighted
output is rescaled to the original numeric units but remains
non-quantitative; subnormal output still has limited precision and can
round to zero.

**Cost.** Every order step uses image-wide maxima, so frames must be
processed whole. Time grows with the number of output pixels times the
number of neighborhood offsets (about `pi * h^2` for the disk kernel and
`(2 * h + 1)^2 - 1` for the square kernel, with half-size `h`, recorded
in `parameters$half_size`). Calls whose estimated work exceeds 1e10
operations, whose output exceeds `max_output_pixels`, or whose kernel
half-size exceeds 1000 pixels are refused before computing.

## References

Torres-Garcia E, Pinto-Camara R, Linares A, et al. Extending resolution
within a single imaging frame. *Nature Communications* 2022;13:7452.
[doi:10.1038/s41467-022-34693-9](https://doi.org/10.1038/s41467-022-34693-9)

## See also

[`mssr_coords()`](https://cttir.github.io/mssrscopR/dev/reference/mssr_coords.md),
[`mssr_mask()`](https://cttir.github.io/mssrscopR/dev/reference/mssr_mask.md),
[`mssr_selftest()`](https://cttir.github.io/mssrscopR/dev/reference/mssr_selftest.md)

## Examples

``` r
# Two point sources 3 pixels apart, blurred with FWHM 3 px.
g <- expand.grid(r = 1:21, c = 1:25)
spot <- function(r0, c0) exp(-((g$r - r0)^2 + (g$c - c0)^2) / (2 * (3 / 2.3548)^2))
x <- matrix(spot(11, 11) + spot(11, 14) + 0.05, 21, 25)
res <- mssr(x, fwhm = 3, amp = 2)
res
#> <mssr_result> intensity_weighted_structure
#>   input 21 x 25 -> output 42 x 50 (amp 2, extent grid)
#>   fwhm 3 px, order 1, kernel disk (half-size 3), mesh TRUE
#>   engine mssr_r_rev3; zero fraction 0.498
#>   Not a quantitative intensity: measure on the original data.
dim(as.matrix(res))
#> [1] 42 50
```
