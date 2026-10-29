# Structural mask on the input grid

Selects exactly `ceiling(fraction * n)` pixels of a region with the
highest MSSR values, on the **input** grid (amplified results are
averaged back over each input pixel's children; this needs
`grid = "extent"`). Pixels tied at the cut are chosen by a seeded random
permutation, without changing the caller's random-number state or
depending on its [`RNGkind()`](https://rdrr.io/r/base/Random.html).
Floating-point noise within eight machine epsilons relative to the quota
is snapped to a positive integer before rounding up. Every positive
fraction selects at least one pixel. Flat maps can yield masks chosen
entirely by ties; such masks are not detected foreground or cell
instances.

## Usage

``` r
mssr_mask(result, fraction, region = NULL, seed = 1L)
```

## Arguments

- result:

  An `mssr_result`.

- fraction:

  Fraction of the region to keep, in (0, 1\]. Required: a suitable share
  depends on how much of the map is positive, which differs from frame
  to frame, so there is no default.

- region:

  Optional logical matrix with the input dimensions; defaults to the
  whole frame.

- seed:

  Whole number used for tie-breaking.

## Value

A logical matrix (input dimensions) with attributes `coverage` (selected
share of the region), `tie_fraction`, `cut_relative` (0 when no score in
the region is positive) and `n_region`.

## Details

Use the mask to measure the **original** data, e.g. `mean(x[mask])`. A
mask changes which pixels are measured; it does not make MSSR values
quantitative, and selecting pixels by MSSR is not known to improve any
downstream analysis. MSSR maps often contain many exact zeros, so check
`tie_fraction`: it is the share of the selected pixels that were decided
by random tie-breaking (0 when the cut falls between distinct values;
only exact ties count). Also check `cut_relative`, the lowest selected
score divided by the highest score in the region. Interpolation and
rounding leave many tiny positive values (often below 1e-6 of the
maximum) where MSSR found no structure; they rank above exact zeros
without counting as ties, so a small `cut_relative` means the mask
reaches beyond the structure. A warning of class
`mssrscopR_warning_mask_ties` is given when tie-breaking chose more than
half of the selected pixels or `cut_relative` is at most 1e-6; the mask
is still returned. A `fraction` near the share of positive map values,
or a `region`, avoids it. Both mask and coordinate consumers reject
nonfinite values or inconsistent grid metadata. This checks the stored
matrix/grid contract, not authenticity of the image, parameters or
review status.

## Examples

``` r
x <- matrix(runif(400), 20, 20)
r <- mssr(x, fwhm = 3)
mean(as.matrix(r) > 0)  # share of pixels with any structure
#> [1] 0.51
m <- mssr_mask(r, fraction = 0.1)
attr(m, "tie_fraction")
#> [1] 0
attr(m, "cut_relative")
#> [1] 0.3015393
mean(x[m])
#> [1] 0.9283137
```
