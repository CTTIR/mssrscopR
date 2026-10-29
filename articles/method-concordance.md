# Method concordance

![mssrscopR logo](figures/logo.svg)![mssrscopR
logo](figures/logo-dark.svg)

The official supplementary methods for Torres-García et al. (2022) were
reviewed against engine `mssr_r_rev3` on 24 October 2026 and re-checked
against the article, the supplement and the pinned R and Python scripts
on 27 October 2026. This comparison documents the defined single-frame
operator and its differences from the authors’ code. The MATLAB code and
the Fiji plugin were not compared for the single-frame operator. The
temporal definitions (29 October 2026) were checked against
Supplementary Table S2 and all four author implementations; the MATLAB
code and the Fiji plugin were read for them, not run.

Sources:

- [Original article, DOI
  10.1038/s41467-022-34693-9](https://www.nature.com/articles/s41467-022-34693-9).
- [Official supplementary
  information](https://media.springernature.com/full/springer-static/esm/art%3A10.1038%2Fs41467-022-34693-9/MediaObjects/41467_2022_34693_MOESM1_ESM.pdf),
  69 pages; SHA-256
  `a48d05079a4f32fa7fe1748f6937f27308a43ba0e452aabb9841229bc85583e2`.
- [Author implementation revision
  77b20b1](https://github.com/adanog/MSSR/tree/77b20b16269487f8c3d2333e52e08f31a676b108),
  including the R and Python scripts and user manual.

## Single-frame correspondence

| Operation | Published location | Rev3 correspondence and boundary |
|----|----|----|
| Neighbourhood | S17, p.8; Fig. S8, p.18 | The default punctured disk follows the spatial support. Radius is `max(1, round(amp*fwhm/2))`, using half-even rounding by default. The named square option follows the Python backend’s different support. |
| Local weights and mean shift | S25–S29, pp.9–10; S48, p.17 | Adaptive range-normalized Gaussian weights; centre minus weighted neighbour mean, with negatives clipped. Rev3 evaluates the equivalent weighted sum of local differences to reduce cancellation. |
| Cubic interpolation | S50–S51, p.26 | Published `c=1/2` is exactly the separable Keys kernel `a=-1/2`, and S50 is the separable product that rev3 implements. Grid alignment and repeated half-sample reflection are package conventions; the authors’ backends differ (below). |
| Mesh compensation | Note 6.1.2, pp.27–28 | Average of the image and four symmetric axial shifts. Rev3 specifies `ceil(amp/2)` and reflected edges, correcting the upstream R shift asymmetry. |
| Refinement | Note 5.1.2/Fig. S11, p.21; article Fig. 2a | Subtraction, complement, normalization and current-map multiplication agree for finite nondegenerate steps; each further order starts from the previous map, as the article’s Fig. 2a legend and both scripts describe. Frame-wide maxima make independently normalized tiles different from a whole-frame computation. |
| Output weighting | Note 11.4, p.60 | Optional multiplication of the normalized structure map by the amplified input. Rev3 preserves orientation, correcting the R script’s rotation/multiplication mismatch. Weighted values remain nonquantitative. |

S51 cites Keys’s cubic convolution and a two-dimensional cubic
convolution ([Reichenbach and Geng
2003](https://doi.org/10.1109/TIP.2003.814248)); the latter develops a
nonseparable kernel, but S50 is the separable product. The authors’
scripts interpolate with neither: the R script calls akima’s
`bicubic.grid` (revised Akima method), and the Python script calls
SciPy’s `interp2d`, so its default bicubic path (`ftI = False`) fails on
SciPy 1.14 and later. Both sample endpoint-aligned positions, which
`grid = "endpoint"` reproduces; the default `grid = "extent"` preserves
the field of view. With the R script’s asymmetric mesh shifts as well,
the amplified input already differs beyond rounding, and MSSR’s range
normalization and refinement are nonlinear and can enlarge such
differences locally. Pixel-wise agreement with the authors’ amplified
maps is therefore not expected.

Supplementary Note 6 and the Python script also offer Fourier
interpolation, which the article recommends for temporal analysis;
mssrscopR does not implement it. The paper also describes scaling
zero-order output to the original maximum (p.17), which differs from
optional pixelwise weighting. Rev3 fixes its two output roles
explicitly. Flat-input results, zero-range handling, skipped undefined
refinement, arithmetic conditioning and resource refusals are documented
implementation extensions. Quota masks are a separate package feature.

## Numerical and scientific limits

The source review does not expand numerical qualification: 76 cases at
orders 0–3 pass within the sampled synthetic domain; two of the wider 98
cases fail at order 10. Orders above 3 retain an explicit warning.
Passing cases do not prove accuracy for every input, parameter
combination or derived mask.

The Gaussian theorem’s displayed derivative in S33 omits
weight-derivative terms despite the weights’ intensity dependence. This
review does not supply a proof for the full adaptive operator or assert
that the theorem’s conclusion is false. Physical calibration, measured
PSFs, resolution gain and application benefit remain separate
requirements.

## Temporal statistics

[`mssr_temporal()`](https://cttir.github.io/mssrscopR/reference/mssr_temporal.md)
applies the pixel-wise temporal functions of Supplementary Note 5.2 and
Table S2 (p.25) to a stack of per-frame MSSR maps, as in article Fig.
7a. Per pixel, `x_1, ..., x_M` are the maps’ values, `x̄` their mean and
`δx_t = x_t − x̄`.

| Statistic | Table S2 | mssrscopR | Authors’ code |
|----|----|----|----|
| Mean | `(1/M) Σ x_i` | the same | plain average in all four tools |
| Var | `(1/M) Σ (x_i − x̄)²` | population variance | Python `1/M`; R, MATLAB and Fiji `1/(M − 1)` |
| TPM | `(1/M) Σ (x_i x_j)²`, with `j` undefined | `(Σ_t x_t)² = M² · Mean²` | `(Σ_t x_t)²` in all four tools |
| CV | `Var / Mean` | literally `Var / Mean`, 0 where the mean is 0 | Fiji only: sample variance divided by the mean |
| SOFI2, SOFI3 | `⟨δx_i δx_{i+1}⟩`, `⟨δx_i δx_{i+1} δx_{i+2}⟩` | lagged, signed deviations, averaged over the frames where every lag exists | Python, MATLAB: absolute deviations at zero lag; Fiji: absolute deviations, lags wrapping around |
| SOFI4 | lagged fourth-order product minus the three pair-product terms | the same, every term averaged over the same `M − 3` frames | Python, MATLAB: absolute value of `⟨δx⁴⟩ − 3⟨δx²⟩²` on absolute deviations at zero lag; Fiji: absolute value of the table form on absolute deviations, lags wrapping around |

Notes:

- **SOFI.** The table’s SOFI rows are the lagged auto-cumulants of the
  SOFI reference it cites (Dertinger et al. 2009, PNAS 106:22287).
  Because of the lags, noise that is independent from frame to frame
  does not enter their expectation. The authors’ Python and MATLAB
  functions form every product from one frame (zero lag) and average
  from frame `k` on, so their order 2 is the variance without the first
  frame. Absolute deviations, used by all three tools, keep a positive
  contribution of independent noise even at a lag, and their orders 3
  and 4 are no longer cumulants. These are different statistics, not
  rounding differences, so the tools’ “SOFI” outputs do not match
  [`mssr_temporal()`](https://cttir.github.io/mssrscopR/reference/mssr_temporal.md)
  by design. Orders 3 and 4 change sign with the emitters’ duty cycle;
  `sign = "absolute"` returns the absolute value.
- **TPM.** Every tool squares the frame sum, so mssrscopR does the same.
  For non-negative maps it is a monotone function of the mean and adds
  nothing to it; the help says so. The Fiji batch TPM plugin for more
  than 100 frames is not registered in the plugin’s menu configuration.
- **Variance and CV.** The table’s variance divides by `M`, and its “CV”
  is `Var / Mean`, an index of dispersion rather than the standard
  deviation divided by the mean; mssrscopR follows the table. The R
  script also has a different missing-data policy.
- **Interpolation.** The article’s Discussion and Supplementary Note
  6.2.1 recommend Fourier interpolation for temporal analysis, because
  the bicubic mesh-like artifact appears in temporal statistics (Note
  6.1.1, Fig. S16, the variance of a noise stack with the period of the
  amplification). The figure legends of the temporal results do not
  state which interpolation was used. mssrscopR amplifies with the
  supplement’s cubic kernel and mesh compensation; Fourier interpolation
  is not implemented, and `diagnostics$mesh_index` reports the remaining
  sub-pixel grid on signal-free input pixels of the
  field-of-view-preserving grid.

The package tests compare the reduction with values derived by hand for
constant, alternating and periodic stacks and with an explicit-loop
implementation, check its offset, scale, time-reversal and pixel-order
properties, and check that the stored and recomputed computation paths
give the same values. These checks establish the definitions, not a
resolution gain or any behaviour on real fluctuation data. Wavelength,
depth and lifetime-delay axes cannot be substituted for time. Note 10.7
(p.54) explicitly leaves a full anisotropic 3D extension for further
development.

The article’s open-access licence and the user guide’s plugin-specific
public-domain statement do not resolve every upstream script or
dependency’s redistribution terms. No upstream implementation or source
payload is included in this qualification kit.
