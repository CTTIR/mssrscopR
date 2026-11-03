# Maintenance strategy and evidence — 3 November 2026

Base: public `CTTIR/mssrscopR` main
`abba017978abc51c377d18097ed9c6fd04bf65a5` (250 tracked files).
The original checkout remains at `5805643` with its existing uncommitted
branding/app changes; all 126 tracked/nonignored files, their hashes, Git diff
and status were preserved before creating the isolated audit worktree. No
excluded active session, private recording, or real microscopy acquisition is
used. No repository/ancestor AGENTS instructions were found.

## Purpose and baseline

The coherent release computes explicitly nonquantitative MSSR structure maps,
coordinates and masks for measuring original frames, temporal statistics of
per-frame maps, and a local Shiny explorer. Its existing distinction between
numerical qualification, physical resolution and application benefit remains.
The existing engine identity, scientific definitions, original fixtures and
method-concordance limitations are preserved. The prior qualification reports
76/76 bounded core cases and 96/98 full sampled cases; the two high-order
failures remain limitations, not targets for relaxed thresholds.

On the unchanged current source, 6,041 assertions pass with zero failures,
errors or warnings. Three tests skip on this macOS host because they require
Linux /proc memory measurements or the platform-specific interrupt probe.
The first evidence harness failed only while serializing a list-valued results
column to CSV; the saved test result was subsequently counted and exported
without rerunning or altering tests. Full package check is recorded separately.
All declared imports/suggests are available in the isolated R environment.

## Confirmed findings and priorities

| Priority | Evidence/location | User impact and repair |
|---|---|---|
| Essential | `temporal_reduce()` uses one exponent across every spatial pixel. Two separate impulse frames at1e-300 and1e300 return mean0 for the dim pixel instead of representable5e-301; a1e-150/1e150 pair returns variance0 instead of2.5e-301. Both raw and stored APIs reproduce it. | Silent loss in valid finite temporal output. Carry power-of-two exponents per pixel, retain the existing centered formulas/frame order, and test independent mean/variance/TPM/CV/SOFI oracles plus every execution path. Update the allocation model for extra buffers. |
| Essential | App CSV uses default `write.table()` formatting. A finite double.xmax value becomes `1.79769313486232e+308`, which reads as infinity. | Download/re-import corrupts valid values. Write sufficient roundtrip precision, retain table geometry and existing artifact semantics, and exercise actual downloaded bytes. |
| Everyday use | Signed input is supported with a warning, but profiles fix y limits to0..1.05 and skip normalization for nonpositive maxima. | Valid negative values are clipped and labels misstate scaling. Display the signed range and state each series' actual normalization convention. |
| Everyday use | Text reader silently drops `#` lines although its documented format is numbers-only. | A supplied row can disappear while import succeeds. Enforce the documented syntax explicitly, preserving supported numeric rectangular tables. |

Baseline probes are in external `evidence/mssrscopR/core-probes/` and `app/`.
The numerical counterexamples use public API-produced maps and independent
closed-form arithmetic; they do not alter objects to manufacture the failure.

## Milestones and acceptance

1. **Temporal numerical integrity.** Replace only the shared global exponent
   with per-pixel conditioning, keeping formulas, signed semantics and output
   schema unchanged. Ordinary-domain results and all frozen single-frame
   fixtures remain within their existing thresholds. Separate pixels with
   representable statistics must not erase each other. Stored, recomputed and
   `mssr_stack` paths agree; truly unrepresentable outputs retain explicit
   numerical errors. Update documented memory estimates conservatively for
   extra arrays and verify refusal before computation with tiny budgets.
2. **App input/display/output fidelity.** Exact finite CSV roundtrips preserve
   dimensions and axes. Signed profiles show all supplied values with truthful
   labels, and malformed/comment-bearing text input fails visibly. Preserve
   asynchronous ownership, stale-result invalidation and caller state. Add
   baseline-failing tests and verify actual isolated browser downloads.
3. **Independent validation and distribution.** Re-run affected/full tests,
   portable independent oracles and appropriate compiled/reference comparisons;
   obtain independent review of numerical representation and app behavior.
   Build/check the exact archive, install first-use paths, review final manual
   and site, retain honest coverage/lint/security evidence, and record hosted
   outcomes only after they occur. Preserve the dirty original. Normal pull,
   completed-source main publication and remote verification are authorized;
   no release/tag/submission or separate manual deployment is performed.

Per-pixel exponents add bounded output-sized working arrays. This costs memory
and some arithmetic, but avoids a new scientific definition or a blanket refusal
of finite representable results. The estimate remains a planning guard, not a
process RSS cap. The implementation will be benchmarked on ordinary small
frames to identify a material regression before acceptance.

Deferred: physical/biological validation, Fourier interpolation, out-of-core
computation, unqualified high-order accuracy, vendor adapters and segmentation
claims. No cosmetic restructuring or feature accumulation is part of this repair.

## Completion

The temporal repair preserves the single-frame engine (`mssr_r_rev3`), temporal
schema 1.1.0, statistical formulas, frame order and frozen fixtures. It also
refuses demonstrably lost nonzero intermediate products and averages. This is
a conservative floating-point safeguard, not exact arithmetic or a guarantee
against cancellation. Memory planning now uses `temporal_buffers_v4` and counts
eight additional output-sized work arrays; its values remain estimates, not RSS
limits. Linux-only RSS checks could not run on this Mac.

The CSV repair needed more than additional output digits: this platform's base
R decimal scanner can parse the canonical finite double maximum as infinity.
Validated decimal tokens therefore use the existing jsonlite dependency in
bounded chunks; supported hexadecimal input keeps its previous parser. Browser
downloads and re-uploads retain exact finite doubles, dimensions and axes.

The independent qualification kit had the same decimal-transport problem:
CSV parsing changed 22 of 98 binary input matrices on this host. Its new
little-endian binary64 sidecars preserve the exact inputs and expected rounded
outputs, while high-precision CSV remains available for inspection. No numerical
threshold, fixture, engine formula or known high-order failure was changed.

### Observed validation

Environment: ARM64 macOS 27.0.1, R 4.6.1, C compiler, Python with mpmath 1.3.0,
Pandoc/Quarto and TeX for full documentation. Libraries and evidence are isolated
from the original checkout. The final source archive is
`mssrscopR_0.2.0.9001.tar.gz`, 1,270,391 bytes, SHA-256
`8b14fa355646969528a6ba3516d286f4602fb693096dbed3cc6a4ba13204db68`.

| Check | Observed result |
|---|---|
| Full source suite, fresh R process | 6,117 assertions; zero failures, errors or warnings; three platform skips. |
| Exact archive, full `R CMD check --as-cran` | Zero errors, zero warnings, one incoming-feasibility NOTE; 6,116 installed assertions and the same three platform skips. Manual and vignettes built. |
| Same archive, imports/test-harness-only library | Zero errors, zero warnings, one NOTE; 5,386 assertions, 32 genuine optional-dependency skips and three platform skips. This lane explicitly used `--no-manual --ignore-vignettes` and disabled forced Suggests; the full lane covers those documents and optional paths. |
| Independent method calculations, exact installed archive | 153/153 checks: bounded amplification-one upstream Python agreement, direct 2,000-digit Decimal temporal formulas, execution-path agreement, raw means and conditioning refusal. |
| Portable high-precision qualification | 76/76 bounded core cases; 96/98 full sampled cases; 104/104 metamorphic checks; 9/9 injected mutations detected; 98/98 compiled/reference cases bit-identical; zero mask differences in 192 comparisons. The two existing order-10 failures remain. |
| Explorer | 377 focused assertions, 34 actual browser checks and 10 independent temporal/resource checks. CSV roundtrip, signed profiles, PNG/TIFF, malformed input, worker cancellation, session isolation, restore and installation self-test were exercised. |
| Documentation site | 29 pages and 1,069 local references; 58 desktop/mobile observations and six navigation/search/theme flows pass. All four scientific plot screenshots retain identical pixels across themes; alternative text is present. Code comment/output contrast measures 5.28:1 in light mode and 6.82:1 in dark mode. |
| Coverage and lint | 96.4983% line coverage against the unchanged 95% floor; repository and shared lint checks both zero. |
| Archive inspection | 210 source payloads byte-identical; DESCRIPTION differs only by build metadata; 11 generated documentation/build files. No Git metadata, planning records, coverage products or private recordings in the archive. |

The incoming NOTE includes the development version and new-submission status,
plus URLs not yet available at check time: the maintenance record before its
publication and the package's R-universe page before registry indexing. These
are recorded external publication/indexing conditions, not observed successful
URLs. The GitHub dependency-alert API returned an empty list; that is not a
comprehensive vulnerability assessment of every R dependency.

Actual site review also found that the inherited dark theme inverted scientific
figure colors and left transparent plot labels unreadable. A scoped stylesheet
retains each scientific image's colors and white plotting surface in both
themes; it leaves branding assets alone. All four plotted vignette chunks now
have descriptive alternative text. The same stylesheet corrects insufficient
contrast in code comments and printed output. The archive was rebuilt and checked after
these documentation changes; all 17 runtime source files are byte-identical to
the preceding qualified archive.

A preserved first source-test harness ran roxygen and tests in the same process;
pkgload's replaced native library path then caused the existing DLL-identity
test to fail. Running the unchanged suite in a fresh process passed, as did the
installed package and browser identity checks. The initial inexact-CSV oracle
and a JSON-observation rounding error are also retained separately from the
corrected, independently verified results.
The earlier purported minimal lane inherited the full-library wrapper and is
not evidence of dependency isolation. The final minimal lane sets both library
paths directly to the 24-package imports/test-harness closure; digest, png,
shiny and tiff are genuinely absent. Installation, self-test, a numerical example,
plotting and the explicit missing-explorer dependency error pass there.

### Cost and limits

On a synthetic 128 by 128 by 24 stack, five repeated reduction-only timings
had medians of 4 to 23 ms for mean, 7 to 35 ms for variance and 9 to 64 ms for
SOFI4 (baseline to repaired implementation). Outputs were bit-identical in all
three ordinary-domain cases. This measured overhead is accepted for explicit
numerical integrity; it does not establish large-stack throughput or peak RSS.

Orders above 3 remain experimental. The full sampled domain does not pass the
existing numerical criterion, and amplification-one comparisons do not establish
agreement with the authors' amplified algorithms. Physical resolution, biological
benefit, clinical use, real acquisition reproducibility and large-stack operating
limits remain outside this software qualification.

### First use and remaining release steps

Install R 4.1 or newer and a source-package C toolchain (Xcode Command Line Tools
on macOS, Rtools matching R on Windows, or a C compiler on Linux). In R:

```r
install.packages("pak")
pak::pak("CTTIR/mssrscopR")
library(mssrscopR)
check <- mssr_selftest()
stopifnot(isTRUE(attr(check, "all_passed")))
x <- matrix(0, 16, 16)
x[8, 8] <- 1
result <- mssr(x, fwhm = 2, order = 0)
plot(result)

# Optional explorer dependencies:
install.packages(c("shiny", "bslib", "jsonlite", "callr", "digest"))
mssr_app()
```

The exact archive's installation, README examples, manual and generated site
are reviewed separately in the retained audit evidence. Local software criteria
are met subject to the stated numerical/platform limits. Hosted CI and
R-universe indexing must be checked against the eventual published commit;
this record does not claim an unobserved CI result, CRAN acceptance, release tag
or physical validation. A formal release requires those external checks, a
deliberate release version and the maintainer's chosen submission process.


## Hosted diagnostic overflow follow-up

The published `9c07a8a` candidate failed the maximum-finite temporal regression
on Ubuntu release/devel and Windows in R-CMD-check run `41639759581`; coverage
run `41639760083` failed the same test. The pixel-wise input mean was finite,
but `mean()` used for a frame diagnostic returned infinity on those runtimes.
The existing stored-stack validator correctly refused that invalid diagnostic.
The prior macOS and Ubuntu R 4.1 results did not establish cross-platform success.

The fix retries only a nonfinite mean of finite, nonempty diagnostic inputs in
power-of-two scaled units. Every finite base-R mean remains unchanged. The same
helper covers field, trend and mesh averages; the pixel-wise reducer, statistical
formulas, original engine, stack validation and app are unchanged. It does not
reject a raw temporal scan merely because separate spatial pixels have widely
different magnitudes. The single-frame engine's existing spatial-range guard
remains in force.

An offline installed-package comparison on Linux x86-64 R 4.6.2, run in the
cached Docker image on this ARM Mac, reproduces six failures among twelve checks
on the published source and passes all twelve with the fix. The fixture includes
the original two-frame maximum-value case, direct/stored paths, independent
constant/trend/mesh formulas, mixed-scale inputs, caller preservation and refusal
of a deliberately corrupt diagnostic. The temporary container used one CPU,
768 MiB, no network or mounted host directories, and was stopped and removed.
This is local Linux-runtime evidence, not a Windows or hosted-CI result.

The initial independent probe also asked for a bit-exact raw mean of twenty
constant maximum-value frames. Both old and new reducers return one ULP below
the exact value on Mac and Linux, an existing sequential-summation rounding
limit. That initial result and its characterization are retained; no reducer,
threshold or existing test was weakened. The final exact reproduction uses the
original two-frame case. Finite base means can also retain ordinary cancellation
error; this diagnostic repair does not promise exact arithmetic.

The new exact archive is `mssrscopR_0.2.0.9001.tar.gz`, **1,271,427 bytes**, SHA-256
`d4990eded5f014891a5ba728aae5f0038c2760020b4066ba554a57291793778d`.
All 210 source payloads match; only standard DESCRIPTION metadata and eleven
generated documentation/build files are derived. No private recordings, Git
metadata, planning files or unsafe archive members are present.

- Full source suite: **6,149 assertions**, zero failures/errors/warnings and the
  same three platform skips; focused temporal precision suite: **71 assertions**.
- Exact archive, full `R CMD check --as-cran`: **0 errors, 0 warnings, 1 NOTE**;
  **6,148 installed assertions** and three platform skips.
- The same archive in the required-dependency/test-harness environment:
  **0 errors, 0 warnings, 1 NOTE**, **5,418 assertions**, 32 optional-dependency
  skips and three platform skips. This lane omits manual/vignettes and disables
  forced Suggests; the full lane covers them.
- Both incoming NOTE records contain new-submission status, development version
  `0.2.0.9001`, and the R-universe URL returning HTTP 404 at check time. No other
  NOTE, warning or error was observed.
- Coverage: **96.43697%**, above the unchanged 95% gate. Repository and shared
  blocking lint both report zero findings.
- A fresh exact-archive installation passes all twelve diagnostic/workflow checks
  and the fourteen-case installation self-test. Two independent bounded source
  reviews found no blocking issue.
- The updated manual remains twenty A4 pages. Only the added computation text
  and its following reflow change pages 17–19; independent visual review found
  no clipping, overlap or glyph issue, and all other semantic text is retained.

Detailed inputs, hashes, successful and superseded probes are retained under
`evidence/mssrscopR/hosted-diagnostic-mean`. The earlier archive and its app/site/
method qualification remain historical evidence; no app/site asset or method
formula changed in this follow-up. A fresh hosted run against the eventual fix
commit is still required; no unobserved hosted success or release is claimed.
