# Package index

## Single-frame MSSR

Compute the structure map of one frame, place its pixels on the input
grid and derive masks for measuring the original data.

- [`mssr()`](https://cttir.github.io/mssrscopR/reference/mssr.md) :
  Single-frame Mean-Shift Super-Resolution
- [`mssr_coords()`](https://cttir.github.io/mssrscopR/reference/mssr_coords.md)
  : Output pixel-centre coordinates
- [`mssr_mask()`](https://cttir.github.io/mssrscopR/reference/mssr_mask.md)
  : Structural mask on the input grid

## Temporal statistics

Reduce the per-frame maps of a frame sequence pixel by pixel.

- [`mssr_temporal()`](https://cttir.github.io/mssrscopR/reference/mssr_temporal.md)
  [`mssr_stack()`](https://cttir.github.io/mssrscopR/reference/mssr_temporal.md)
  : Temporal statistics of per-frame MSSR maps

## Validation

Check the installation against the bundled fixtures, and validate,
summarise and plot results.

- [`mssr_selftest()`](https://cttir.github.io/mssrscopR/reference/mssr_selftest.md)
  : Check the engine against the bundled synthetic fixtures
- [`mssr_validate_result()`](https://cttir.github.io/mssrscopR/reference/mssr_validate_result.md)
  : Validate a complete result record
- [`summary(`*`<mssr_result>`*`)`](https://cttir.github.io/mssrscopR/reference/inspect_mssr_result.md)
  [`print(`*`<summary.mssr_result>`*`)`](https://cttir.github.io/mssrscopR/reference/inspect_mssr_result.md)
  [`plot(`*`<mssr_result>`*`)`](https://cttir.github.io/mssrscopR/reference/inspect_mssr_result.md)
  : Inspect a structure-map result

## Resources and result files

Plan memory and work, process batches of frames, store results exactly
and replay their settings.

- [`mssr_estimate_resources()`](https://cttir.github.io/mssrscopR/reference/mssr_estimate_resources.md)
  : Estimate whole-frame MSSR resources
- [`mssr_batch()`](https://cttir.github.io/mssrscopR/reference/mssr_batch.md)
  : Process and resume independent complete frames
- [`mssr_write_result()`](https://cttir.github.io/mssrscopR/reference/mssr_result_io.md)
  [`mssr_read_result()`](https://cttir.github.io/mssrscopR/reference/mssr_result_io.md)
  : Write and read an exact, bounded result record
- [`mssr_settings()`](https://cttir.github.io/mssrscopR/reference/mssr_settings.md)
  : Extract resolved computation settings from a result

## Interactive app

Explore parameters on synthetic examples or an uploaded frame.

- [`mssr_app()`](https://cttir.github.io/mssrscopR/reference/mssr_app.md)
  : Interactive MSSR explorer
