# Portable numerical qualification

This optional developer kit evaluates independently specified synthetic frames.
It is not a biological benchmark or a production dependency. No upstream source
code, reference image, patient data, network call, or workstation path is used.
The scalar Python equations are independently implemented under the package
license. mpmath 1.3.0 is a separately installed BSD dependency, not vendored.

Run from any checkout with Python 3, mpmath 1.3.0, R and the package's test/developer
dependencies available:

```
python3 tools/qualification/oracle.py /explicit/output/directory
Rscript tools/qualification/compare.R /explicit/output/directory .
```

The output directory is explicit and should be a new run. The generator records
its seed, options, precision and tolerance before evaluations. It performs scalar
weighted absolute-intensity calculations with 16-tap interpolation and repeated
reflection, unlike the R engine's conditioned local-difference vectorization.
Inputs are lifted from their exact binary64 values. Expected CSV values contain
60 significant decimal digits. Output reductions are over complete frames.

The bounded design covers six scene families, both grids and kernels, both
rounding rules, mesh and weighting choices, amplification 1–4, orders 0/1/3/10,
rounding boundaries, extreme binary scales and exceptional geometries. A small
amplification-8 case extends sampling coverage. This is a documented sample of
the accepted parameter domain, not an exhaustive or universal accuracy proof.
No claim is made for all amplification values through 64 or all within-frame
contrasts. See the generated records and conditioning report for actual results.

The 1e-11 normalized-map threshold is retained from the prior numerical audit.
A mixed absolute/relative pixel rule and explicit two-ULP subnormal allowance
are also checked. Precision convergence must be below 1e-70. Floating-point
input rounding is part of the input and cannot be undone by an oracle.

The comparison script preserves every failure, performs independent metamorphic
checks and mask/measurement sensitivity assessments, and reports mutations
separately. Mask identity is not inferred from numerical-map tolerance.

## Recorded limitation and restricted exit criterion

The first execution found 96/98 passing oracle cases; two paired-source
amplification 4/mesh/order 10 cases exceed the unchanged tolerance. Focused
follow-up found failures starting at order 6 or 7. High-precision one-ULP input
probes confirm large cumulative sensitivity of high-order refinement. The
production policy warns above order 3; no accuracy guarantee is inferred for
all possible inputs at lower orders.

The default comparison command therefore deliberately exits nonzero for this
full sampled domain. To check only the explicitly bounded synthetic core
(order<=3), while still retaining all failures in the output tables, run:

```
Rscript tools/qualification/compare.R /explicit/output/directory . --qualified-core
```

That flag changes the final exit criterion only. It does not loosen tolerances,
remove cases, change result values, or turn the full-domain summary into a pass.
Mutation detection uses baseline-passing cases, so a pre-existing error cannot
count as detection of a new mutation. All generated synthetic arrays are
numerical tests, not experimentally observed microscopy images.
