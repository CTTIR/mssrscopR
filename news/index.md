# Changelog

## mssrscopR 0.1.0

- Input qualification rejects explicit numeric classes before
  arithmetic; finite intermediate overflow raises
  `mssrscopR_error_numerical`.

- Result consumers validate matrix dimensions, finiteness and grid
  metadata.

- Positive mask fractions always select at least one pixel; rounding
  only absorbs machine-precision noise near integer quotas. High-range
  amplified scores are averaged without overflowing into artificial
  ties.

- Additional synthetic contract regressions cover these boundaries. They
  establish software behavior, not segmentation accuracy or optical
  resolution.

- [`mssr_mask()`](https://cttir.github.io/mssrscopR/reference/mssr_mask.md)
  reports `cut_relative` (lowest selected score / highest score):
  interpolation and rounding leave tiny positive scores that rank above
  exact zeros without counting as ties, so a small value shows that the
  mask reaches beyond the structure. Tie-breaking no longer depends on
  the caller’s [`RNGkind()`](https://rdrr.io/r/base/Random.html).

- Undefined refinement steps now also give a
  `mssrscopR_warning_skipped_steps` warning: the result is not the limit
  for slightly perturbed input.

- `grid`, `kernel` and `rounding` are checked with classed
  `mssrscopR_error_parameter` errors and need exact values.

- Four more fixtures (asymmetric frames at amp 2 and 3 on both grids,
  half-up rounding, `mesh = FALSE`, the square kernel) let
  [`mssr_selftest()`](https://cttir.github.io/mssrscopR/reference/mssr_selftest.md)
  detect orientation and option errors at amp \> 1.

- `rlang` is imported, because `cli`’s condition functions need it.

- Documentation states the relation to the authors’ R and Python code
  exactly (intensity normalization, skipped steps, mesh shifts) and the
  title no longer claims validation.

- First functional version: single-frame Mean-Shift Super-Resolution
  ([`mssr()`](https://cttir.github.io/mssrscopR/reference/mssr.md)) with
  explicit result objects (role, grid transform, parameters, engine
  identity `mssr_r_rev2`, diagnostics).

- [`mssr_coords()`](https://cttir.github.io/mssrscopR/reference/mssr_coords.md)
  returns output pixel-center coordinates in input-pixel units.

- [`mssr_mask()`](https://cttir.github.io/mssrscopR/reference/mssr_mask.md)
  derives exact-count structural masks on the input grid with seeded
  tie-breaking and reports the share decided by tie-breaking.

- [`mssr_selftest()`](https://cttir.github.io/mssrscopR/reference/mssr_selftest.md)
  recomputes the bundled synthetic fixtures as a regression check of the
  installation.

- [`mssr_app()`](https://cttir.github.io/mssrscopR/reference/mssr_app.md)
  opens an interactive Shiny explorer: synthetic examples or an uploaded
  frame (text, PNG, TIFF), input and structure map on shared input-pixel
  axes, line profiles, masks measured on the input, the self-test, and
  downloads of the map, the mask, a figure and a run record. It calls
  the exported functions and adds no processing of its own.

- Defined results for degenerate input: flat frames return flagged zeros
  at every amplification, and undefined refinement steps (impulses on an
  exactly zero background) leave the map unchanged and are counted.

- Classed `cli` errors (`mssrscopR_error_*`) and warnings
  (`mssrscopR_warning_negative`); guards for output size, kernel size
  and total work.

## mssrscopR 0.0.0.9000

- Initial package skeleton.
