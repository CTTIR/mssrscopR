## README URL correction (24 November 2026)

The reserved Zenodo DOI is now shown as plain text, without a DOI link or
badge. R's URL extraction confirms that the README no longer exposes the
unpublished DOI as a URL. The DOI-related findings below describe earlier
checks, before this correction; the reservation has not been published.

## Submission

This is a new submission.

## R CMD check results

0 errors | 0 warnings | 1 note

* checking CRAN incoming feasibility ... NOTE
  Maintainer: 'R. Heller <raban.heller@uni-ulm.de>'

  New submission

  Found the following (possibly) invalid URLs:
    URL: https://doi.org/10.5281/zenodo.24426376
      From: README.md
      Status: 404
      Message: Not Found

  This is a first submission. The DOI in the README badge is reserved on
  Zenodo for this release and resolves once its record is published.

## Test environments

* local: macOS 27.0.1 (aarch64-apple-darwin), R 4.6.1,
  `R CMD check --as-cran` on the built tarball with the remote incoming
  checks, including the PDF manual (TinyTeX) and the HTML manual validation
  (HTML Tidy 5.8.0).
* GitHub Actions (r-lib/actions v2, `--as-cran`): ubuntu-latest (R devel,
  release, oldrel-1 and the declared minimum R 4.1.0), macos-latest
  (R release), windows-latest (R release).
* win-builder (R-devel and R-release) and R-hub: to be run by the maintainer
  before submission.

## Reverse dependencies

There are no reverse dependencies; this is a new package.

## Notes

* The neighborhood passes run in a small C routine registered with
  `R_registerRoutines()`; the R reference implementation is kept and the tests
  check that both agree, and that the engine agrees with a direct
  transcription of the published equations.
* Examples, tests and vignettes use bundled or generated synthetic data, need
  no network access and write only to `tempdir()`. The package code is
  single-threaded. Some tests start short-lived background R processes (via
  'callr') for the explorer's job handling and stop them afterwards.
* The optional 'shiny' explorer (Suggests) is launched only in interactive
  sessions; its server logic is tested without a browser.
* Possibly flagged words in the Description are correct technical terms or
  names: 'MSSR' (mean-shift super-resolution), 'SOFI' (super-resolution
  optical fluctuation imaging), 'cumulants', and the author names
  'Torres-Garcia' and 'Dertinger'.
