# mssrscopR 0.1.0

* Input qualification rejects explicit numeric classes before arithmetic;
  finite intermediate overflow raises `mssrscopR_error_numerical`.
* Result consumers validate matrix dimensions, finiteness and grid metadata.
* Positive mask fractions always select at least one pixel; rounding only
  absorbs machine-precision noise near integer quotas. High-range amplified
  scores are averaged without overflowing into artificial ties.
* Additional synthetic contract regressions cover these boundaries. They
  establish software behavior, not segmentation accuracy or optical resolution.

* First functional version: single-frame Mean-Shift Super-Resolution (`mssr()`)
  with explicit result objects (role, grid transform, parameters, engine
  identity `mssr_r_rev2`, diagnostics).
* `mssr_coords()` returns output pixel-center coordinates in input-pixel units.
* `mssr_mask()` derives exact-count structural masks on the input grid with
  seeded tie-breaking and reports the share decided by tie-breaking.
* `mssr_selftest()` recomputes the bundled synthetic fixtures as a regression
  check of the installation.
* Defined results for degenerate input: flat frames return flagged zeros at
  every amplification, and undefined refinement steps (impulses on an exactly
  zero background) leave the map unchanged and are counted.
* Classed `cli` errors (`mssrscopR_error_*`) and warnings
  (`mssrscopR_warning_negative`); guards for output size, kernel size and
  total work.

# mssrscopR 0.0.0.9000

* Initial package skeleton.
