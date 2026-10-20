# Changelog

## mssrscopR 0.1.0

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
- Defined results for degenerate input: flat frames return flagged zeros
  at every amplification, and undefined refinement steps (impulses on an
  exactly zero background) leave the map unchanged and are counted.
- Classed `cli` errors (`mssrscopR_error_*`) and warnings
  (`mssrscopR_warning_negative`); guards for output size, kernel size
  and total work.

## mssrscopR 0.0.0.9000

- Initial package skeleton.
