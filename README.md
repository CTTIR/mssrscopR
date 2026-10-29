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

> **Status: 0.1.0.9004, development candidate.** At amplification 1 with intensity
> normalization off, comparisons with the authors' single-frame R code (disk
> kernel, rotation undone) and Python code (square kernel) agree on the tested
> non-degenerate examples. Engine `mssr_r_rev3` improves numerical stability;
> the unchanged bundled synthetic fixtures guard against regressions. Its benefit for
> fluorescence, histology or hyperspectral analyses has not been established.

The method concordance in `vignette("method-concordance")` maps the official
supplementary equations to the engine and records implementation differences,
unresolved temporal definitions and qualification boundaries
([Markdown source](https://github.com/CTTIR/mssrscopR/blob/main/tools/qualification/METHOD_CONCORDANCE.md)).

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
  integer amplification 1–64 on a field-of-view-preserving grid. This is the
  accepted syntax; independent qualification covers a bounded subset, and
  orders above 3 are experimental.
- Defined results for degenerate input (flat frames, impulses on an exactly
  zero background), reported in the diagnostics.
- Structural masks with exact coverage for measurements on the original data.
- Input validation with classed errors and warnings, resource guards, and an
  installation self-test.

**Out of scope**

- Temporal MSSR summaries over frame stacks (mean, variance, TPM).
- Tiled or out-of-core processing: every order step uses image-wide maxima.
- General-purpose file readers, physical calibration, and claims of resolution gain,
  intensity fidelity or diagnostic value.

## Where it sits in CTTIR

```
2D frame from any reader (one channel / one band at a time; results of
different channels need not keep their intensity ratios)
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
| `mssr_mask(result, fraction, region = NULL, seed = 1)` | logical mask on the input grid with `coverage`, `tie_fraction`, `n_region` |
| `mssr_selftest(tolerance = 1e-10)` | fixture errors, with attribute `all_passed` |
| `mssr_app(max_upload_mb = 50, ...)` | interactive Shiny explorer (needs shiny, bslib, jsonlite, callr and digest): synthetic examples or an uploaded frame, maps on shared input-pixel axes, profiles, masks measured on the input, self-test, downloads |

`fwhm` is the point-spread-function width in **input pixels** and has no
default. Errors inherit from `mssrscopR_error` (subclasses `_input`,
`_nonfinite`, `_parameter`, `_resource`, `_unsupported`, `_numerical`,
`_dependency`); negative input gives a `mssrscopR_warning_negative` warning,
because MSSR assumes non-negative intensities, and undefined refinement steps
give a `mssrscopR_warning_skipped_steps` warning.

Use plain integer or double inputs; explicitly classed numeric objects must be
converted deliberately. The engine scales internally and accumulates local
differences to reduce overflow, underflow and cancellation. It reports a numerical
error if scaling loses a nonzero input or the final output overflows. Very small
intensity-weighted outputs remain subject to subnormal rounding, including zero.
This cannot recover precision already lost in the supplied frame.

A constant background changes the result, also for non-negative input: the
order-0 structure map does not depend on it, but every refinement step
(`order >= 1`) compares the map with the input divided by its maximum, and
intensity weighting multiplies by the input. Subtracting a background is
therefore a preprocessing choice that changes the map; record it with the
result. The range normalizer adapts to the largest local difference, so even
rounding-level ripple on an otherwise flat frame is stretched to full contrast.

Coordinate and mask consumers check finite values and consistent grid metadata;
they do not authenticate image provenance. Positive mask fractions select at
least one pixel. `tie_fraction` is the share of the selected pixels that random
tie-breaking among equal scores (usually exact zeros) decided, and
`cut_relative` the lowest selected score divided by the highest. A large
`tie_fraction` or a `cut_relative` near 0 means the mask reaches beyond the
structure that MSSR found, and `mssr_mask()` warns; choose a smaller `fraction`
or a `region`. A quota mask is not a cell segmentation.

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

# A structural mask on the input grid. Only a few percent of this map is
# positive, so keep a smaller share than that.
r1 <- mssr(x, fwhm = 3)
mean(as.matrix(r1) > 0)          # share of pixels with any structure
m <- mssr_mask(r1, fraction = 0.03)
mean(x[m])                       # measured on the original frame
attr(m, "tie_fraction")          # 0: no pixel was chosen by tie-breaking
attr(m, "cut_relative")          # lowest kept score relative to the highest

attr(mssr_selftest(), "all_passed")

# Explore parameters interactively (needs shiny, bslib, jsonlite, callr and digest):
# mssr_app()
```

## Relation to the authors' code

The authors distribute R, Python, MATLAB and ImageJ code at
<https://github.com/adanog/MSSR>. `mssrscopR` is an independent implementation
and contains none of it. At amplification 1 with intensity normalization off,
comparisons agree on tested non-degenerate examples with the authors' single-frame
R function once its final rotation is undone, and with `kernel = "square"` their
Python function. This is a bounded numerical comparison, not a guarantee for
every finite input: the revised engine avoids numerical failures of the direct
arithmetic at extreme intensity ranges. For flat frames and for impulses on
an exactly zero background their R function returns `NaN` and their Python
function returns zeros; `mssrscopR` returns flagged zeros for flat frames and
keeps the map, counting the skipped step, for impulses. With intensity
normalization on, their R function multiplies the rotated map by the unrotated
input, so it matches `mssr()` only for frames that a 90-degree rotation leaves
unchanged (and fails for non-square frames). Their R mesh compensation shifts
asymmetrically (by `desp + 1` one way and `desp` the other); `mssrscopR` uses
the symmetric shifts of their Python code. Amplification uses Keys cubic convolution on a
field-of-view-preserving grid, so output for `amp > 1` differs from the
authors' interpolation, also with `grid = "endpoint"`, which reproduces their
sample positions: pixel-wise agreement is not expected.

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

## Inspect, preserve and resume results

The development interface adds `summary()`, `plot()` and
`mssr_validate_result()` for result inspection. Results carry a separate schema
version, engine/package identity and an explicit evidence scope. Unknown
acquisition calibration stays unknown; arbitrary matrix attributes are not
copied into outputs.

```r
x <- matrix(seq_len(120), 10, 12)
r <- mssr(x, fwhm = 3, order = 1, max_memory_bytes = 1024^3)
summary(r)
mssr_validate_result(r)
mssr_estimate_resources(dim(x), fwhm = 3)

# Optional packages digest and jsonlite are needed only for file exchange/batches.
# Paths are explicit and output replacement is refused by default.
# mssr_write_result(r, "frame.mssr")
# restored <- mssr_read_result("frame.mssr")
# run <- mssr_batch(list(frame_a = x, frame_b = t(x)), "batch-output",
#                   settings = list(fwhm = 3, order = 1))
```

Result files preserve exact binary64 values with SHA-256 integrity checks and
bounded, non-executable metadata parsing. Readback establishes consistency,
not source authenticity or biological validity. Batch processing is sequential:
complete frames, verified reuse, retained failed/cancelled rows and separate
attempt files. Cancellation takes effect between frames. The returned table's
`run_record` attribute identifies the durable invocation summary.

The allocation model was calibrated on the peak RSS of fresh R processes on
one Linux machine over 65,536–16,777,216 output pixels (amplification 1–4,
orders 0–3, mesh and weighting on and off, both kernels), where it exceeded
every measured peak by 30–220 %, least for order 3 with mesh and weighting. It
includes a 128 MiB runtime allowance. Garbage collection, larger workloads,
other platforms and retained objects can change RSS; this is not an OS memory
cap.

### Recompute a saved result

`mssr_settings()` validates a result and returns the eight resolved computation
arguments, including its grid. Use it instead of passing `result$parameters`
directly: that field includes the derived `half_size` and omits the grid.
Resolved settings describe what ran; for example, mesh compensation is recorded
as off at amplification 1. Resource budgets must be set explicitly for replay.

```r
# Continue from x and r above; keep the original input separately.
if (requireNamespace("digest", quietly = TRUE) &&
    requireNamespace("jsonlite", quietly = TRUE)) {
  path <- tempfile(fileext = ".mssr")
  mssr_write_result(r, path)
  restored <- mssr_read_result(path)
  stopifnot(identical(restored$engine$package_version,
                      as.character(packageVersion("mssrscopR"))))
  replay <- do.call(mssr, c(
    list(x = x, max_output_pixels = 5e7, max_memory_bytes = 1024^3),
    mssr_settings(restored)
  ))
  stopifnot(identical(replay$values, restored$values),
            identical(replay$transform, restored$transform))
  unlink(path)
}
```

This demonstration retains the original input in memory. For a durable analysis,
preserve it in trusted storage together with its identity, preprocessing,
channel/frame selection, acquisition information, and mask region, fraction and
seed. These are not stored in the `.mssr` result. Preserve the package artifact
and runtime environment too. `mssr_settings()` refuses records from other
numerical engines; it does not migrate them. Matching engine/settings alone
does not guarantee identical arithmetic across package versions or environments,
so compare the recomputed values as above. See the vignette for a worked example
that also reproduces the original-data measurement.

## Numerical qualification boundary

The portable kit in `tools/qualification/` evaluates independent high-precision
references and keeps failing cases visible. The current bounded core contains
76 passing cases at orders 0–3; this does not establish accuracy for every
possible input or parameter combination. Across the wider 98-case sample,
two order-10 cases exceed the unchanged tolerance. Small perturbations can be
strongly amplified by repeated nonlinear refinement. Orders above 3 therefore
produce an explicit qualification warning and remain experimental.

A small map difference does not guarantee an identical mask: near a cutoff,
score perturbations can change selected pixels and measurements made on the
original frame. A fixed retained fraction is a quota, not a detector threshold,
probability or confidence score. Always inspect retained coverage, cutoff ties,
parameter sensitivity and the consequences for the original-data measurement.


## Background app computation

The app runs one owned background R job per session. **Cancel computation** stops
that job; pending, failed or cancelled work cannot be downloaded. **Restore
previous completed result** recovers the prior input, settings and mask with an
explicit restored-state label. Controls edited while a job runs do not change
its captured inputs. Current mask controls can update a normally completed
result; restored results retain their previous mask settings.

Jobs stop when the session closes or after five minutes. They inherit CPU
constraints and use one numerical thread. The app verifies package files and
loaded function definitions in the child, preventing an unnoticed switch to an
older installed version. Development-source launches additionally need pkgload;
installed packages do not. Dependencies are never installed automatically.


The app's Run record uses schema 1.1.0 and includes SHA-256 identities for the
uploaded file bytes and decoded frame. It retains neither the filename nor the
local path. Keep the source file separately: these hashes establish content
identity, not authenticity or acquisition provenance. You can compare the raw
file hash with `digest::digest(file = "your-frame.csv", algo = "sha256", serialize = FALSE)`.

The decoded-frame format `mssr-input-binary64-v1` hashes this concatenation:
the ASCII tag `mssr-input-binary64-v1` followed by a newline, two little-endian
signed 32-bit integers (row count, then column count), and all finite samples
as little-endian IEEE-754 binary64 values in column-major order. Matrix
attributes are excluded. Equal decoded frames from different file encodings
have the same frame hash, while their uploaded-file hashes can differ.


## Branding

Editable R sources and regeneration instructions are in
[tools/branding](https://github.com/CTTIR/mssrscopR/tree/main/tools/branding).
