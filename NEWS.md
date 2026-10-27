# mssrscopR 0.1.0.9003

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
