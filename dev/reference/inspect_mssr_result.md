# Inspect a structure-map result

Inspect a structure-map result

## Usage

``` r
# S3 method for class 'mssr_result'
summary(object, ...)

# S3 method for class 'mssr_result'
plot(x, ...)
```

## Arguments

- object, x:

  An `mssr_result`.

- ...:

  Further arguments. For plotting, passed to
  [`graphics::image()`](https://rdrr.io/r/graphics/image.html).

## Value

[`summary()`](https://rdrr.io/r/base/summary.html) returns a named list
with role, dimensions, range, diagnostics, parameters and version
identities. [`plot()`](https://rdrr.io/r/graphics/plot.default.html)
draws the stored map in input-pixel coordinates and invisibly returns
the result. It does not transform the stored values or infer physical
sampling.

## Examples

``` r
r <- mssr(matrix(1:20, 4, 5), fwhm = 2)
summary(r)
#> $role
#> [1] "intensity_weighted_structure"
#> 
#> $input_dim
#> [1] 4 5
#> 
#> $output_dim
#> [1] 4 5
#> 
#> $value_range
#> [1]  0 20
#> 
#> $parameters
#> $parameters$fwhm
#> [1] 2
#> 
#> $parameters$amp
#> [1] 1
#> 
#> $parameters$order
#> [1] 1
#> 
#> $parameters$intensity_normalize
#> [1] TRUE
#> 
#> $parameters$mesh
#> [1] FALSE
#> 
#> $parameters$kernel
#> [1] "disk"
#> 
#> $parameters$rounding
#> [1] "half_even"
#> 
#> $parameters$half_size
#> [1] 1
#> 
#> 
#> $diagnostics
#> $diagnostics$degenerate
#> [1] FALSE
#> 
#> $diagnostics$degenerate_reason
#> [1] NA
#> 
#> $diagnostics$order_steps_skipped
#> [1] 0
#> 
#> $diagnostics$zero_fraction
#> [1] 0.65
#> 
#> $diagnostics$negative_fraction
#> [1] 0
#> 
#> $diagnostics$n_offsets
#> [1] 4
#> 
#> $diagnostics$quantitative
#> [1] FALSE
#> 
#> $diagnostics$qualification_scope
#> [1] "bounded_synthetic_domain"
#> 
#> $diagnostics$high_order_unqualified
#> [1] FALSE
#> 
#> 
#> $engine
#> $engine$id
#> [1] "mssr_r_rev3"
#> 
#> $engine$package_version
#> [1] "0.1.0.9003"
#> 
#> $engine$method
#> [1] "Torres-Garcia et al. 2022, doi:10.1038/s41467-022-34693-9"
#> 
#> 
#> $schema_version
#> [1] "1.0.0"
#> 
#> $evidence
#> $evidence$status
#> [1] "numerical_tool_only"
#> 
#> $evidence$quantitative
#> [1] FALSE
#> 
#> 
plot(r)
```
