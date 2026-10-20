# mssrscopR 0.1.0

* First functional version: single-frame Mean-Shift Super-Resolution (`mssr()`)
  with explicit result objects (role, grid transform, parameters, engine
  identity `mssr_r_rev1`, diagnostics).
* `mssr_coords()` returns output pixel-centre coordinates in input-pixel units.
* `mssr_mask()` derives exact-coverage structural masks on the input grid with
  seeded tie-breaking, for measuring the original data.
* `mssr_selftest()` checks the installation against bundled synthetic fixtures.
* Input checks with classed errors (`mssrscopR_error_*`); flat input returns
  zeros flagged as degenerate.

# mssrscopR 0.0.0.9000

* Initial package skeleton.
