# mssrscopR <picture class="cttir-readme-logo"><source class="cttir-logo-dark-source" media="(prefers-color-scheme: dark)" srcset="man/figures/logo-with-name-dark.png" /><img src="man/figures/logo-with-name.png" align="right" alt="mssrscopR logo" width="120" height="139" /></picture>

<!-- badges: start -->
[![Lifecycle: experimental](https://img.shields.io/badge/lifecycle-experimental-orange.svg)](https://lifecycle.r-lib.org/articles/stages.html#experimental)
[![R-CMD-check](https://github.com/CTTIR/mssrscopR/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/CTTIR/mssrscopR/actions/workflows/R-CMD-check.yaml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
<!-- badges: end -->

`mssrscopR` computes single-frame Mean-Shift Super-Resolution (MSSR;
Torres-García et al. 2022) structure maps in R. Geometry is explicit, degenerate
input has a defined result, and a self-test can check any installation.

- **Compute:** `mssr()` returns the MSSR structure map of one 2D frame, with its
  role, grid transform, parameters and diagnostics.
- **Locate:** `mssr_coords()` places output pixels in input-pixel coordinates.
- **Select:** `mssr_mask()` derives a structural mask on the input grid for
  measuring the **original** data, and reports how much of it tie-breaking
  decided.
- **Verify:** `mssr_selftest()` recomputes bundled synthetic fixtures.

> **Status: 0.1.0, experimental.** At amplification 1 with intensity
> normalization off, the engine matches the authors' single-frame R code (disk
> kernel, rotation undone) and Python code (square kernel) wherever their output
> is finite, apart from undefined refinement steps; the bundled synthetic
> fixtures guard against regressions. Its benefit for
> fluorescence, histology or hyperspectral analyses has not been established.

## Why

MSSR is easy to run and easy to misread:

- **The authors' R script returns a rotated image.** It fails on non-square
  frames and returns `NaN` for flat input.
- **"Amplification" is ambiguous.** It adds samples, not observations, and
  common interpolation grids shift the field of view.
- **The output looks like an image of intensities, but it is not one.** MSSR is
  nonlinear: dim structures next to bright ones are suppressed, and broad or
  touching objects can be hollowed or split.

`mssrscopR` makes each of these explicit: outputs keep the input orientation,
coordinates and the field of view are returned with the result, and every result
is labeled as a non-quantitative structure map.

## Scope

**In scope**

- Single-frame MSSR of finite 2D numeric matrices of any shape, orders 0–10,
  integer amplification 1–64 on a field-of-view-preserving grid.
- Defined results for degenerate input (flat frames, impulses on an exactly
  zero background), reported in the diagnostics.
- Structural masks with exact coverage for measurements on the original data.
- Input validation with classed errors and warnings, resource guards, and an
  installation self-test.

**Out of scope**

- Temporal MSSR summaries over frame stacks (mean, variance, TPM).
- Tiled or out-of-core processing: every order step uses image-wide maxima.
- File readers, physical calibration, and claims of resolution gain,
  intensity fidelity or diagnostic value.

## Where it sits in CTTIR

```
2D frame from any reader (one channel / one band at a time)
      │
      ▼
mssrscopR::mssr()  →  structure map + coordinates + diagnostics
      │
      ▼
mssrscopR::mssr_mask()  →  mask on the input grid
      │
      ▼
measurements on the ORIGINAL frame (your analysis code)
```

There are no adapters to other CTTIR packages yet. Use with hyperspectral cubes
or segmentation workflows has not been validated.

## Interface

| Function | Returns |
|---|---|
| `mssr(x, fwhm, amp = 1, order = 1, ...)` | `mssr_result`: `values`, `role`, `transform`, `parameters`, `engine`, `diagnostics` |
| `mssr_coords(result)` | output pixel-center coordinates (`row`, `col`) in input-pixel units |
| `mssr_mask(result, fraction = 0.5, region = NULL, seed = 1)` | logical mask on the input grid with `coverage`, `tie_fraction`, `n_region` |
| `mssr_selftest(tolerance = 1e-10)` | fixture errors, with attribute `all_passed` |
| `mssr_app(max_upload_mb = 50, ...)` | interactive Shiny explorer (needs shiny, bslib and jsonlite): synthetic examples or an uploaded frame, maps on shared input-pixel axes, profiles, masks measured on the input, self-test, downloads |

`fwhm` is the point-spread-function width in **input pixels** and has no
default. Errors inherit from `mssrscopR_error` (subclasses `_input`,
`_nonfinite`, `_parameter`, `_resource`, `_unsupported`, `_numerical`,
`_dependency`); negative input gives a `mssrscopR_warning_negative` warning,
because MSSR assumes non-negative intensities, and undefined refinement steps
give a `mssrscopR_warning_skipped_steps` warning.

Use plain integer or double inputs; explicitly classed numeric objects must be
converted deliberately. Intermediate overflow raises a numerical error.
Coordinate and mask consumers check finite values and consistent grid metadata;
they do not authenticate image provenance. Positive mask fractions select at
least one pixel, but flat maps may yield entirely tie-selected masks. A quota
mask is not a cell segmentation.

## Installation

``` r
# install.packages("pak")
pak::pak("CTTIR/mssrscopR")
```

## Quick start

``` r
library(mssrscopR)

# Two blurred point sources 3 pixels apart (FWHM 3 px) on a faint background:
# a shallow dip in the input that MSSR deepens.
g <- expand.grid(r = 1:21, c = 1:25)
spot <- function(r0, c0) exp(-((g$r - r0)^2 + (g$c - c0)^2) / (2 * (3 / 2.3548)^2))
x <- matrix(spot(11, 11) + spot(11, 14) + 0.05, 21, 25)

res <- mssr(x, fwhm = 3, amp = 2)
res
mssr_coords(res)$col[1:4]

m <- mssr_mask(mssr(x, fwhm = 3), fraction = 0.25)
mean(x[m])                       # measured on the original frame
attr(m, "tie_fraction")

attr(mssr_selftest(), "all_passed")

# Explore parameters interactively (needs shiny, bslib and jsonlite):
# mssr_app()
```

## Relation to the authors' code

The authors distribute R, Python, MATLAB and ImageJ code at
<https://github.com/adanog/MSSR>. `mssrscopR` is an independent implementation
and contains none of it. At amplification 1 with intensity normalization off,
its output equals the authors' single-frame R function once that function's
final rotation is undone, and with `kernel = "square"` their Python function,
wherever their code returns finite values. For flat frames and for impulses on
an exactly zero background their R function returns `NaN` and their Python
function returns zeros; `mssrscopR` returns flagged zeros for flat frames and
keeps the map, counting the skipped step, for impulses. With intensity
normalization on, their R function multiplies the rotated map by the unrotated
input, so it matches `mssr()` only for frames that a 90-degree rotation leaves
unchanged (and fails for non-square frames). Their R mesh compensation shifts
asymmetrically (by `desp + 1` one way and `desp` the other); `mssrscopR` uses
the symmetric shifts of their Python code. Amplification uses Keys cubic convolution on a
field-of-view-preserving grid, so output for `amp > 1` differs from the
authors' interpolation.

## Citation

Please cite the method paper whenever you use MSSR; `citation("mssrscopR")`
lists it together with the package.

> Torres-García E, Pinto-Cámara R, Linares A, et al. Extending resolution within
> a single imaging frame. *Nature Communications* 2022;13:7452.
> <https://doi.org/10.1038/s41467-022-34693-9>

## Contributing

Follows the [CTTIR contributing guide](https://github.com/CTTIR/.github/blob/main/CONTRIBUTING.md).

## License

MIT

## Use of LLM tools

Where applicable, LLM tools were used for narrowly defined, non-authorial tasks:
copyediting, prose refinement, Markdown/LaTeX formatting, boilerplate scaffolding
(such as CI configurations and build scripts), and code refactoring. Tools included
[Chat AI](https://kisski.gwdg.de/leistungen/2-02-llm-service/), the KISSKI
(GWDG) service, and self-hosted **Mistral Small (24B, Apache-2.0)** served through
a local **vLLM architecture** on an Ubuntu Linux workstation with Intel
processors and NVIDIA GPUs. The self-hosted model ran locally, with no data sent
to third parties.

All scientific claims, methodological choices, analyses, interpretations and
conclusions remain the authors' own. Where applicable, LLM-generated material
must be reviewed and revised before inclusion, and references must be verified
against their DOI, arXiv ID or ISBN.

Local software setup: vLLM with Python/PyTorch, plus R and RStudio.

## Branding

Editable R sources and regeneration instructions are in
[tools/branding](https://github.com/CTTIR/mssrscopR/tree/main/tools/branding).
