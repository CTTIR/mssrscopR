# Package index

## Single-frame MSSR

- [`mssr()`](https://cttir.github.io/mssrscopR/dev/reference/mssr.md) :
  Single-frame Mean-Shift Super-Resolution
- [`mssr_coords()`](https://cttir.github.io/mssrscopR/dev/reference/mssr_coords.md)
  : Output pixel-center coordinates
- [`mssr_mask()`](https://cttir.github.io/mssrscopR/dev/reference/mssr_mask.md)
  : Structural mask on the input grid

## Validation

- [`mssr_selftest()`](https://cttir.github.io/mssrscopR/dev/reference/mssr_selftest.md)
  : Check the engine against the bundled synthetic fixtures
- [`mssr_validate_result()`](https://cttir.github.io/mssrscopR/dev/reference/mssr_validate_result.md)
  : Validate a complete result record
- [`summary(`*`<mssr_result>`*`)`](https://cttir.github.io/mssrscopR/dev/reference/inspect_mssr_result.md)
  [`print(`*`<summary.mssr_result>`*`)`](https://cttir.github.io/mssrscopR/dev/reference/inspect_mssr_result.md)
  [`plot(`*`<mssr_result>`*`)`](https://cttir.github.io/mssrscopR/dev/reference/inspect_mssr_result.md)
  : Inspect a structure-map result

## Resources and result files

- [`mssr_estimate_resources()`](https://cttir.github.io/mssrscopR/dev/reference/mssr_estimate_resources.md)
  : Estimate whole-frame MSSR resources
- [`mssr_batch()`](https://cttir.github.io/mssrscopR/dev/reference/mssr_batch.md)
  : Process and resume independent complete frames
- [`mssr_write_result()`](https://cttir.github.io/mssrscopR/dev/reference/mssr_result_io.md)
  [`mssr_read_result()`](https://cttir.github.io/mssrscopR/dev/reference/mssr_result_io.md)
  : Write and read an exact, bounded result record
- [`mssr_settings()`](https://cttir.github.io/mssrscopR/dev/reference/mssr_settings.md)
  : Extract resolved computation settings from a result

## Interactive app

- [`mssr_app()`](https://cttir.github.io/mssrscopR/dev/reference/mssr_app.md)
  : Interactive MSSR explorer
