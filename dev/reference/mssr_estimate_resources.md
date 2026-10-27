# Estimate whole-frame MSSR resources

Reports a conservative allocation model before allocating an output
frame. The estimate includes a 192 MiB runtime allowance, 64 double
buffers per output pixel, five input buffers, and reflected-index/offset
storage. It is a planning guard, not a hard process-memory limit: R,
loaded packages, retained objects, garbage collection and the allocator
can change peak RSS. Calibration evidence covers the workload ladder
described in the package documentation; estimates outside that ladder
are extrapolations.

## Usage

``` r
mssr_estimate_resources(
  input_dim,
  fwhm,
  amp = 1L,
  kernel = c("disk", "square"),
  rounding = c("half_even", "half_up"),
  max_output_pixels = 5e+07
)
```

## Arguments

- input_dim:

  Two positive whole numbers: input rows and columns.

- fwhm, amp, kernel, rounding, max_output_pixels:

  As in
  [`mssr()`](https://cttir.github.io/mssrscopR/dev/reference/mssr.md).

## Value

A list with input/output dimensions, pixels, offsets, estimated work,
estimated peak bytes, model ID, and limitations.

## Examples

``` r
mssr_estimate_resources(c(128, 192), fwhm = 3, amp = 2)
#> $input_dim
#> [1] 128 192
#> 
#> $output_dim
#> [1] 256 384
#> 
#> $output_pixels
#> [1] 98304
#> 
#> $half_size
#> [1] 3
#> 
#> $n_offsets
#> [1] 28
#> 
#> $estimated_work
#> [1] 2752512
#> 
#> $estimated_peak_bytes
#> [1] 252678912
#> 
#> $model
#> [1] "whole_frame_buffers_v1"
#> 
#> $hard_limit
#> [1] FALSE
#> 
#> $limitation
#> [1] "Allocation estimate; retained objects and runtime can increase process RSS."
#> 
```
