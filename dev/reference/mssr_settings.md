# Extract resolved computation settings from a result

Validates a result and returns arguments that can be passed to
[`mssr()`](https://cttir.github.io/mssrscopR/dev/reference/mssr.md) with
the retained original input. The grid is included explicitly; derived
kernel sizes and resource limits are not computation settings returned
here.

## Usage

``` r
mssr_settings(result)
```

## Arguments

- result:

  A result returned by
  [`mssr()`](https://cttir.github.io/mssrscopR/dev/reference/mssr.md) or
  [`mssr_read_result()`](https://cttir.github.io/mssrscopR/dev/reference/mssr_result_io.md).

## Value

A named list containing `fwhm`, `amp`, `order`, `intensity_normalize`,
`mesh`, `grid`, `kernel` and `rounding`.

## Details

These are resolved settings, not the original call. For example, `mesh`
is `FALSE` when amplification is 1 because it had no effect. Records
from a different numerical engine are refused: this helper does not
migrate historical engines. A legacy result schema is accepted when its
engine matches and its stored contract validates.

Retain the original input, preprocessing and channel/frame selection,
acquisition information, and mask region, fraction and seed separately.
Result files do not contain them. Set resource budgets explicitly when
recomputing. Preserve the package and runtime environment, check engine
identity, and compare recomputed values; matching settings alone do not
guarantee identical arithmetic across environments or versions. This
function needs no optional packages and does not modify the result.

## Examples

``` r
x <- matrix(seq_len(35), 5, 7)
result <- mssr(x, fwhm = 2.5, amp = 2, grid = "endpoint")
replay <- do.call(mssr, c(list(x = x, max_memory_bytes = 1024^3),
                          mssr_settings(result)))
identical(replay$values, result$values)
#> [1] TRUE
```
