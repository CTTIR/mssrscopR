# mssrscopR: Single-Frame Mean-Shift Super-Resolution Structure Maps

Computes the single-frame Mean-Shift Super-Resolution ('MSSR') structure
map of Torres-Garcia et al. (2022)
[doi:10.1038/s41467-022-34693-9](https://doi.org/10.1038/s41467-022-34693-9)
with an independently written implementation that keeps the input
orientation, accepts non-square frames and defines the result for flat
input. Provides output-grid coordinates, structural masks for measuring
the original data, pixel-wise temporal statistics of the per-frame maps
of an image sequence (mean, variance and lagged SOFI cumulants as
defined in the article's supplement), a self-test against bundled
synthetic fixtures and an interactive 'shiny' app for exploring
parameters. Results are structural maps, not quantitative intensities;
no gain in physical resolution or benefit for any application is
implied.

## See also

Useful links:

- <https://github.com/CTTIR/mssrscopR>

- <https://cttir.github.io/mssrscopR/>

- Report bugs at <https://github.com/CTTIR/mssrscopR/issues>

## Author

**Maintainer**: R. Heller <raban.heller@uni-ulm.de>
([ORCID](https://orcid.org/0000-0001-8006-9742)) \[copyright holder\]

Authors:

- R. Heller <raban.heller@uni-ulm.de>
  ([ORCID](https://orcid.org/0000-0001-8006-9742)) \[copyright holder\]
