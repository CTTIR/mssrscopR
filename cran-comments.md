## Submission

This is a new submission.

## R CMD check results

0 errors | 0 warnings | 1 note

* checking CRAN incoming feasibility ... NOTE
  Maintainer: 'R. Heller <raban.heller@uni-ulm.de>'
  New submission

  This is the expected note for a first submission.

## Test environments

* local: macOS 27.0.1 (aarch64-apple-darwin), R 4.6.1,
  `R CMD check --as-cran` on the built tarball, including the PDF manual
  (TinyTeX, TeX Live 2026) and the HTML manual validation (HTML Tidy 5.8.0).
* GitHub Actions (r-lib/actions v2, `--as-cran`): ubuntu-latest (R devel,
  release, oldrel-1 and the declared minimum R 4.1.0), macos-latest
  (R release), windows-latest (R release).

## Notes

* The neighborhood passes run in a small C routine registered with
  `R_registerRoutines()`; the R reference implementation is kept and the tests
  check that both agree.
* Examples, tests and vignettes use bundled or generated synthetic data, need
  no network access and write only to `tempdir()`.
* The optional 'shiny' explorer (Suggests) is launched only in interactive
  sessions; its server logic is tested without a browser.
* Possibly flagged words in the Description are correct technical terms:
  'cumulants' and 'SOFI' (super-resolution optical fluctuation imaging).
