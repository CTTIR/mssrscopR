# Output pixel-center coordinates

Coordinates of the output pixel centers of an
[`mssr()`](https://cttir.github.io/mssrscopR/reference/mssr.md) result,
in input-pixel units (input pixel centers at 1..n). Use them to overlay
results on the input grid; amplification adds samples, not independent
observations.

## Usage

``` r
mssr_coords(result)
```

## Arguments

- result:

  An `mssr_result`.

## Value

A list with numeric vectors `row` and `col`.

## Examples

``` r
r <- mssr(matrix(runif(20), 4, 5), fwhm = 2, amp = 2)
mssr_coords(r)$col
#>  [1] 0.75 1.25 1.75 2.25 2.75 3.25 3.75 4.25 4.75 5.25
```
