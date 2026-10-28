# Method concordance

![mssrscopR logo](figures/logo.svg)![mssrscopR
logo](figures/logo-dark.svg)

The official supplementary methods for Torres-García et al. (2022) were
reviewed against engine `mssr_r_rev3` on 24 October 2026 and re-checked
against the article, the supplement and the pinned R and Python scripts
on 27 October 2026. This comparison documents the defined single-frame
operator and its differences from the authors’ code. The MATLAB code and
the Fiji plugin were not compared.

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
interpolation, which the article uses for temporal analysis; mssrscopR
does not implement it. The paper also describes scaling zero-order
output to the original maximum (p.17), which differs from optional
pixelwise weighting. Rev3 fixes its two output roles explicitly.
Flat-input results, zero-range handling, skipped undefined refinement,
arithmetic conditioning and resource refusals are documented
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

## Temporal and dimensional restrictions

Temporal functions remain unsupported. Table S2 (p.25) and the pinned
scripts contain material differences:

- TPM has an unspecified `j` index in the table; both scripts compute
  the square of the frame sum.
- The table uses population variance; the R script uses sample variance
  and a different missing-data policy. The table labels `Var/Mean` as
  CV.
- The displayed SOFI formulas use signed, distinct-lag products. The
  Python implementation instead uses absolute deviations, and its
  shifted slices are re-aligned so that all factors come from one frame:
  orders 2 and 3 average `|δx_k|²` and `|δx_k|³`, and order 4 returns
  `|⟨|δx|⁴⟩ − 3⟨|δx|²⟩²|`.

Any future temporal operator needs a resolved formula and independent
qualification on genuine repeated-time data. Wavelength, depth and
lifetime-delay axes cannot be substituted for time. Note 10.7 (p.54)
explicitly leaves a full anisotropic 3D extension for further
development.

The article’s open-access licence and the user guide’s plugin-specific
public-domain statement do not resolve every upstream script or
dependency’s redistribution terms. No upstream implementation or source
payload is included in this qualification kit.
