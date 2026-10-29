# Estimate whole-frame MSSR resources

Reports a conservative allocation model before allocating an output
frame. The estimate includes a 128 MiB runtime allowance, 24 double
buffers per output pixel, six per input pixel, and reflected-index and
offset storage. It was calibrated on the peak resident memory of fresh R
processes on one Linux machine over a workload ladder of 65,536 to
16,777,216 output pixels (amplification 1 to 4, orders 0 to 3, mesh and
intensity weighting on and off, disk and square kernels), where it
exceeded every measured peak by 30 to 220 percent; the margin is
smallest for order 3 with mesh and weighting, and garbage-collection
timing changes peaks from run to run. It is a planning guard, not a hard
process-memory limit: other platforms, loaded packages, retained
objects, garbage collection and the allocator can change peak RSS, and
estimates outside that ladder are extrapolations.

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
#> [1] 154291456
#> 
#> $model
#> [1] "whole_frame_buffers_v2"
#> 
#> $hard_limit
#> [1] FALSE
#> 
#> $limitation
#> [1] "Allocation estimate; retained objects and runtime can increase process RSS."
#> 
```
