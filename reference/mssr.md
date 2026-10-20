# Single-frame Mean-Shift Super-Resolution

Computes the Mean-Shift Super-Resolution (MSSR) structure map of one 2D
frame (Torres-Garcia et al. 2022). The result is a structural map for
display, structure analysis or mask derivation. It is **not** a
quantitative intensity: MSSR is nonlinear, suppresses dim structures
next to bright ones and can hollow or split broad objects. Take
measurements from the original data (see
[`mssr_mask()`](https://cttir.github.io/mssrscopR/reference/mssr_mask.md)).

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
  max_output_pixels = 5e+07
)
```

## Arguments

- x:

  A plain integer or double matrix (rows = y, columns = x) with finite
  values and no explicit class.

- fwhm:

  Full width at half maximum of the point-spread function, in **input
  pixels**. Required; there is no default because it is a property of
  the acquisition.

- amp:

  Amplification factor (whole number from 1 to 64).

- order:

  MSSR order (whole number from 0 to 10).

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

## Value

An object of class `mssr_result`: a list with `values` (numeric matrix),
`role` (`"structure"` or `"intensity_weighted_structure"`), `transform`,
`parameters`, `engine` and `diagnostics`. `transform` holds `amp`,
`grid`, `input_dim`, `output_dim`, the first output pixel center and the
spacing (input-pixel units), and `field_of_view`: the input frame's
extent from pixel edge 0.5 to `n + 0.5`. Output samples cover it exactly
on the extent grid; on the endpoint grid they span only the first to the
last input pixel center. The input is not stored.

## Details

**Geometry.** The output keeps the input orientation. With
`grid = "extent"` the amplified grid preserves the field of view: output
pixel centers lie at `(k - 0.5) / amp + 0.5` input pixels, so the
spacing is exactly `1 / amp`. Amplification adds samples, not
independent observations.

**Relation to the authors' code.** At `amp = 1` with
`intensity_normalize = FALSE`, the output equals the authors'
single-frame R function after its final 90-degree rotation is undone
(`kernel = "disk"`) or their Python function (`kernel = "square"`),
wherever their code returns finite values, except for undefined
refinement steps (see below). For `amp > 1`, Keys cubic convolution is
used, which is not numerically identical to the authors' interpolation.
With the default `intensity_normalize = TRUE` their R function
multiplies the rotated map by the unrotated input, so it agrees with
`mssr()` only for frames that a 90-degree rotation leaves unchanged (and
fails for non-square frames).

**Degenerate input.** A flat frame, a frame whose amplified maximum is
not positive, and a frame without any positive mean shift return zeros
with `diagnostics$degenerate = TRUE` and a `degenerate_reason`. A
refinement step (`order >= 1`) is undefined when the mean-shift map
already equals the normalized input, for example for isolated impulses
on an exactly zero background. Such a step leaves the map unchanged, is
counted in `diagnostics$order_steps_skipped` and gives a warning of
class `mssrscopR_warning_skipped_steps`: the result is not the limit for
slightly perturbed input, because any positive background makes the step
defined and changes the map. The authors' R function returns `NaN` in
all of these cases; their Python function returns zeros, which equals
`mssr()` for the degenerate frames but not for skipped refinement steps.

**Negative values.** MSSR assumes non-negative intensities. With
negative input the structure map depends on the offset of the data and
intensity-weighted output can be negative, so a warning of class
`mssrscopR_warning_negative` is given.

**Numeric domain.** Input and numeric parameters must use plain integer
or double storage, without explicit classes. Convert calibrated or other
classed data deliberately before calling. Finite input can still
overflow intermediate arithmetic; this raises
`mssrscopR_error_numerical` rather than returning an invalid or
misleading zero map. Extreme underflow is not a calibrated intensity
regime; retain any input rescaling in provenance. A large constant
offset relative to the signal's variation (for example 1e12 added to
values that vary by 1) costs accuracy through cancellation; subtract
such offsets first.

**Cost.** Every order step uses image-wide maxima, so frames must be
processed whole. Time grows with the number of output pixels times the
number of neighborhood offsets (about `pi * h^2` for the disk kernel and
`(2 * h + 1)^2 - 1` for the square kernel, with half-size
`h = round(0.5 * fwhm * amp)`). Calls whose estimated work exceeds 1e10
operations, whose output exceeds `max_output_pixels`, or whose kernel
half-size exceeds 1000 pixels are refused before computing.

## References

Torres-Garcia E, Pinto-Camara R, Linares A, et al. Extending resolution
within a single imaging frame. *Nature Communications* 2022;13:7452.
[doi:10.1038/s41467-022-34693-9](https://doi.org/10.1038/s41467-022-34693-9)

## See also

[`mssr_coords()`](https://cttir.github.io/mssrscopR/reference/mssr_coords.md),
[`mssr_mask()`](https://cttir.github.io/mssrscopR/reference/mssr_mask.md),
[`mssr_selftest()`](https://cttir.github.io/mssrscopR/reference/mssr_selftest.md)

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
#>   engine mssr_r_rev2; zero fraction 0.490
#>   Not a quantitative intensity: measure on the original data.
dim(as.matrix(res))
#> [1] 42 50
```
