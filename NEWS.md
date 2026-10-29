# mssrscopR 0.1.0.9004

* Breaking change: `mssr_mask()` has no default `fraction` any more. The former
  default of 0.5 selected exact zeros on typical maps and so mostly gave masks
  decided by tie-breaking; callers now choose the share, ideally below the
  share of positive map values.
* The two neighborhood passes of engine `mssr_r_rev3` (range normalizer and
  weighted mean shift) now run in compiled C code. They form the same sums in
  the same order as before, so results are unchanged: the R passes are kept as
  an internal reference, and the tests and the qualification kit compare the
  two. No offset stack is held in memory, so peak memory falls, and frames run
  about 2 to 4 times faster; the gain grows with the neighborhood size, and the
  remaining time is mostly the weight's exponential. The computation stays
  single-threaded and can still be interrupted. The engine identity is
  unchanged; the package version identifies the implementation.
* A refinement step that leaves no positive value (possible only with signed
  input) now returns a degenerate result with reason `"zero refinement map"`
  instead of an unflagged all-zero map.
* The app's background jobs are checked against the code the R session loaded:
  package files (in development checkouts including the C sources), function
  definitions and the loaded native library. A file edited after the package
  was loaded is refused, also before the first job.
* `mssr_mask()` warns (class `mssrscopR_warning_mask_ties`) when tie-breaking
  chose more than half of the selected pixels or the lowest selected score is
  at most 1e-6 of the highest, that is, when the mask reaches beyond the
  structure the map shows. The README, vignette and help examples now use a
  share below the positive part of the map and explain `tie_fraction` and
  `cut_relative`. The app keeps its own inline message for this case.
* `mssr_estimate_resources()` uses a model recalibrated on the compiled engine
  (`whole_frame_buffers_v2`): it was two to eight times too high and now
  exceeds measured peak memory by 20 to 40 percent on the calibration ladder.
  The default budget of `mssr_batch()` is now 2 GiB, so ordinary 1024 x 1024
  frames at amplification 2 are no longer refused.
* `summary()` of a result prints a short report; the returned list keeps its
  fields and gains the output grid.
* Documented plainly that maps of order 1 and higher change with a constant
  background even for non-negative input, so background subtraction must be
  recorded, and that rounding-level ripple on an otherwise flat frame is
  stretched to full contrast.
* Added tests for corrupted result metadata, the batch record of a frame that
  fails after it started, and package files changing before an app job loads
  them, and a result file written by 0.1.0.9003 that must still read, validate
  and replay.

# mssrscopR 0.1.0.9003

* Standardize the named v5 package logo across README, documentation pages
  and available application headers, with matching light and dark artwork.

* Added validated callable settings for reproducible result replay, including
  the output grid and explicit refusal of historical engine definitions.
* Run records now identify uploaded bytes and decoded matrix content with
  SHA-256 hashes while excluding source filenames and paths.
* Figure downloads retain interpretation, computed settings and run identity.
  Download actions are unavailable until their result or mask is ready.
* Notification dismissal restores keyboard focus, and Browse has a visible
  focus indicator in both themes.
* Corrected the vignette and app: MSSR can separate sources that the pixels show
  merged (at amp 2, two peaks for sources 2.6 px apart with FWHM 3 px, where the
  input pixels show one maximum), with the peaks closer together than the
  sources. Documented that a rod three FWHM long becomes two peaks near its ends,
  and that under noise single sources and short rods can break up, more so with
  an `fwhm` below the true PSF.
* Documented that channels or bands processed one at a time are guaranteed to
  keep their intensity ratios only when one whole frame is a scaled copy of
  another (intensity-weighted output), so ratios, indices and spectra belong to
  the original data (help, vignette example, app, tests), and that filled
  objects are hollowed and should be segmented on the original data.
* Added guidance on `fwhm`: prefer a measured PSF, since a theoretical value
  describes an ideal system; under noise a too-small `fwhm` adds false peaks and
  a larger one weakens the separation of close sources, so when unsure choose
  the larger plausible value. Only the kernel half-size enters the computation.
* Re-checked the method concordance against the article, the supplement and the
  authors' R and Python scripts. The concordance now names their interpolation
  backends, the Fourier interpolation option that mssrscopR does not implement,
  and the zero-lag products of the Python SOFI functions. `?mssr` and the README
  now say that amplified maps are not expected to agree pixel-wise with the
  authors' code, even with `grid = "endpoint"`, which reproduces their sample
  positions.

# mssrscopR 0.1.0.9002

* Reviewed the official supplementary methods and documented equation-to-code
  concordance, including the published cubic kernel, symmetric mesh scheme and
  unresolved temporal definitions. Numerical engine equations, regression
  values and scientific claims are unchanged.
* Expanded synthetic TIFF coverage for LZW, Deflate and PackBits across supported
  sample types and storage layouts. Invalid strip/tile extents are now refused
  before decoding.
* Replaced app sliders with native numeric controls and improved document
  semantics, keyboard focus, summary reflow and status/hover contrast.

# mssrscopR 0.1.0.9001

* Added versioned result inspection, strict validation and bounded binary result
  exchange with SHA-256 checks, exact numeric readback and no implicit overwrite.
* Added a calibrated allocation estimate, opt-in memory guard and sequential
  complete-frame batches with verified reuse, retained failures and recovery.
* Expanded independent numerical qualification. Orders above 3 now warn that
  they are outside the bounded qualified core; two order-10 cases fail the
  unchanged tolerance. The engine equations and frozen fixtures are unchanged.
* TIFF metadata traversal is bounded. Packed 12-bit, non-top-left orientation
  and other unqualified layouts are refused before pixel decoding. Application
  state, exports, keyboard access and textual diagnostics are more explicit.
* Arbitrary source matrix attributes are removed so identifying metadata do not
  silently propagate into computed values.

# mssrscopR 0.1.0.9000

* Engine `mssr_r_rev3` uses internal power-of-two scaling, centered interpolation
  and weighted local differences to reduce overflow, underflow and cancellation.
  Existing expected fixture values are unchanged. Background subtraction is
  still a distinct preprocessing choice; higher-order MSSR is not invariant to
  additive background.
* Image uploads preserve single-row and single-column channel dimensions,
  report decoder failures with classed errors, and check decoded dimensions
  before reading PNG pixels or a selected TIFF page. TIFF page selection needs
  tiff >= 0.1-8. Run records include the mask's relative cutoff diagnostic.
  Multichannel planar-separate TIFFs are refused because the underlying reader
  can silently corrupt them; explicit volumetric TIFFs are outside the 2D scope.

# mssrscopR 0.1.0

* Input qualification rejects explicit numeric classes before arithmetic;
  finite intermediate overflow raises `mssrscopR_error_numerical`.
* Result consumers validate matrix dimensions, finiteness and grid metadata.
* Positive mask fractions always select at least one pixel; rounding only
  absorbs machine-precision noise near integer quotas. High-range amplified
  scores are averaged without overflowing into artificial ties.
* Additional synthetic contract regressions cover these boundaries. They
  establish software behavior, not segmentation accuracy or optical resolution.
* `mssr_mask()` reports `cut_relative` (lowest selected score / highest score):
  interpolation and rounding leave tiny positive scores that rank above exact
  zeros without counting as ties, so a small value shows that the mask reaches
  beyond the structure. Tie-breaking no longer depends on the caller's
  `RNGkind()`.
* Undefined refinement steps now also give a
  `mssrscopR_warning_skipped_steps` warning: the result is not the limit for
  slightly perturbed input.
* `grid`, `kernel` and `rounding` are checked with classed
  `mssrscopR_error_parameter` errors and need exact values.
* Four more fixtures (asymmetric frames at amp 2 and 3 on both grids, half-up
  rounding, `mesh = FALSE`, the square kernel) let `mssr_selftest()` detect
  orientation and option errors at amp > 1.
* `rlang` is imported, because `cli`'s condition functions need it.
* Documentation states the relation to the authors' R and Python code exactly
  (intensity normalization, skipped steps, mesh shifts) and the title no
  longer claims validation.

* First functional version: single-frame Mean-Shift Super-Resolution (`mssr()`)
  with explicit result objects (role, grid transform, parameters, engine
  identity `mssr_r_rev2`, diagnostics).
* `mssr_coords()` returns output pixel-center coordinates in input-pixel units.
* `mssr_mask()` derives exact-count structural masks on the input grid with
  seeded tie-breaking and reports the share decided by tie-breaking.
* `mssr_selftest()` recomputes the bundled synthetic fixtures as a regression
  check of the installation.
* `mssr_app()` opens an interactive Shiny explorer: synthetic examples or an
  uploaded frame (text, PNG, TIFF), input and structure map on shared
  input-pixel axes, line profiles, masks measured on the input, the self-test,
  and downloads of the map, the mask, a figure and a run record. It calls the
  exported functions and adds no processing of its own.
* Defined results for degenerate input: flat frames return flagged zeros at
  every amplification, and undefined refinement steps (impulses on an exactly
  zero background) leave the map unchanged and are counted.
* Classed `cli` errors (`mssrscopR_error_*`) and warnings
  (`mssrscopR_warning_negative`); guards for output size, kernel size and
  total work.

# mssrscopR 0.0.0.9000

* Initial package skeleton.
