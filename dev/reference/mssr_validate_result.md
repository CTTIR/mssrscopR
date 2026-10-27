# Validate a complete result record

Checks values, geometry, settings, engine identity and diagnostic
consistency. This establishes the stored contract, not image
authenticity, numerical recomputation, scientific validation or a
calibrated confidence estimate. Coordinate and mask functions retain
their narrower matrix/grid validation.

## Usage

``` r
mssr_validate_result(result)
```

## Arguments

- result:

  A result returned by
  [`mssr()`](https://cttir.github.io/mssrscopR/dev/reference/mssr.md).

## Value

The validated result invisibly, unchanged.

## Details

Results without a schema field are treated as legacy records; they must
still have the original six documented fields. Their engine identity is
retained. Schema 1.0.0 adds explicit unknown input calibration and a
separate evidence status. Unknown schema versions and unexpected fields
are refused.

## Examples

``` r
r <- mssr(matrix(1:20, 4, 5), fwhm = 2)
mssr_validate_result(r)
```
