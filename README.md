# mssrscopR

Single-frame **Mean-Shift Super-Resolution (MSSR)** for R. MSSR was introduced by Torres-García et al. (2022, [doi:10.1038/s41467-022-34693-9](https://doi.org/10.1038/s41467-022-34693-9)).

`mssrscopR` is an independently written implementation of the published single-frame operator, with explicit geometry, defined behaviour for degenerate input, and a self-test against bundled synthetic fixtures. It is a research utility for **structure maps**, not a measurement tool.

## Installation

```r
# install.packages("pak")
pak::pak("CTTIR/mssrscopR")
```

## Example

```r
library(mssrscopR)

# Two blurred point sources 3 pixels apart (FWHM 3 px), on a faint background.
g <- expand.grid(r = 1:21, c = 1:25)
spot <- function(r0, c0) exp(-((g$r - r0)^2 + (g$c - c0)^2) / (2 * (3 / 2.3548)^2))
x <- matrix(spot(11, 11) + spot(11, 14) + 0.05, 21, 25)

res <- mssr(x, fwhm = 3, amp = 2)   # fwhm is in input pixels and has no default
res                                 # role, grid, parameters and diagnostics
coords <- mssr_coords(res)          # output pixel centres in input-pixel units

# Derive a mask from the structure map, but measure the ORIGINAL data.
m <- mssr_mask(mssr(x, fwhm = 3), fraction = 0.25)
mean(x[m])
attr(m, "tie_fraction")             # share of pixels tied at the threshold

# Confirm the installation reproduces the validated engine.
attr(mssr_selftest(), "all_passed")
```

## What it is, and what it is not

- **Output is a structure map.** `role` is `"structure"` or `"intensity_weighted_structure"`, and `diagnostics$quantitative` is always `FALSE`. MSSR is nonlinear: it suppresses dim structures next to bright ones, can hollow or split broad and touching objects, and turns noise into punctate texture. Measure intensities on the original data.
- **Amplification adds samples, not observations.** No gain in physical resolution is implied. With `grid = "extent"` (default) the amplified grid preserves the field of view, with output spacing exactly `1/amp`.
- **No application benefit is claimed.** The engine is validated algorithmically and on synthetic data. Any benefit for fluorescence, histology or hyperspectral analyses must be established for the data at hand.
- **Whole frames only.** Each order step uses image-wide maxima, so tiles are not equivalent to the whole frame.
- **Not implemented:** temporal summaries over frame stacks, tiled processing, readers for vendor formats.

## Relation to the authors' code

The authors distribute R, Python, MATLAB and ImageJ code at <https://github.com/adanog/MSSR>. `mssrscopR` does not contain or depend on it. At `amp = 1` its output equals the authors' single-frame R function once that function's final 90° rotation is undone with intensity normalisation off (for `kernel = "square"`: the authors' Python function). Deliberate differences:

- the input orientation is kept;
- non-square frames work;
- flat input returns zeros flagged `degenerate` instead of `NaN`;
- interpolation for `amp > 1` uses Keys cubic convolution on a field-of-view-preserving grid. It is therefore not numerically identical to the authors' interpolation.

## Citation

`citation("mssrscopR")` lists the method paper and this package. Please cite the method paper whenever you use MSSR.

## License

MIT. See [LICENSE.md](LICENSE.md).
