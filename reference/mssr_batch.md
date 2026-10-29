# Process and resume independent complete frames

Processes an explicitly named list of matrices sequentially. Each frame
uses the same settings and the public
[`mssr()`](https://cttir.github.io/mssrscopR/reference/mssr.md)
function. Completed files are reused only after input/settings identity,
SHA-256 and result readback checks. Changed input or settings creates a
new identity and preserves prior output. Failed frames remain in the
returned table. No data are downloaded or sent.

## Usage

``` r
mssr_batch(
  frames,
  output_dir,
  settings,
  resume = TRUE,
  max_memory_bytes = 2 * 1024^3,
  max_result_bytes = 256 * 1024^2,
  cancel = NULL
)
```

## Arguments

- frames:

  A nonempty named list of plain numeric matrices. Names are unique
  opaque IDs containing only letters, digits, underscore or hyphen.

- output_dir:

  Explicit directory for result files and recovery records.

- settings:

  Named list of
  [`mssr()`](https://cttir.github.io/mssrscopR/reference/mssr.md)
  arguments, including `fwhm`; `x` and `max_memory_bytes` are supplied
  by the runner and cannot be overridden.

- resume:

  Reuse matching, verified completed results.

- max_memory_bytes:

  Positive estimated-memory budget; default 2 GiB. A frame runs only if
  its
  [`mssr_estimate_resources()`](https://cttir.github.io/mssrscopR/reference/mssr_estimate_resources.md)
  estimate plus the size of all input frames held in `frames` fits
  within it.

- max_result_bytes:

  Positive serialized-result limit; default 256 MiB.

- cancel:

  Optional function with no arguments returning a single logical. `TRUE`
  marks remaining frames cancelled without running them.

## Value

A data frame with one row per input: ID, status, reuse flag, output
path, elapsed seconds and message. Individual JSON records retain
warnings, identities, completion state and hashes. Complete results use
`.mssr` files.

## Details

Requires optional packages `digest` and `jsonlite`, as do result files.
A directory lock prevents simultaneous writers. A lock left by a
terminated process must be reviewed and removed manually once its owner
has stopped. Cancellation is checked between frames; it does not
interrupt a numerical call already in progress. An interrupted output is
retained and a new attempt receives a distinct filename. Keep this
output directory local and trusted; hashes establish consistency, not
authenticity.

All input matrices are already resident in memory. The budget adds their
storage to the per-frame allocation estimate; it is not an OS memory
cap. `workers` is deliberately absent: parallel processing remains
unqualified.
