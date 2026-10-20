# Check the engine against the bundled synthetic fixtures

Recomputes every bundled synthetic fixture and compares it with the
stored expected output. The fixtures are small non-square, impulse,
constant, zero, point-pair, ring and ramp images. The expected outputs
were produced by the accepted engine definition, so this is a regression
check of the installation, not an independent validation of the method
or of any application.

## Usage

``` r
mssr_selftest(tolerance = 1e-10)
```

## Arguments

- tolerance:

  Single non-negative number.

## Value

A data frame with one row per fixture (`fixture_id`, parameters,
`max_abs_error`, `passed`), with attribute `all_passed` (`TRUE` or
`FALSE`).

## Details

A fixture passes when its dimensions match and
`max(abs(got - expected)) <= tolerance * (1 + max(abs(expected)))`.

## Examples

``` r
st <- mssr_selftest()
attr(st, "all_passed")
#> [1] TRUE
```
