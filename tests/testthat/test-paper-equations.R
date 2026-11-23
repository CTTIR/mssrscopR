# An independent, per-pixel transcription of the single-frame operator from
# the Supplementary Information of Torres-Garcia et al. (2022),
# doi:10.1038/s41467-022-34693-9, at amplification 1 with the disk kernel:
#   - neighborhood 0 < ||offset|| <= h_s, h_s = FWHM / 2 (Eq. S17, p.8;
#     p.18 and Fig. S8),
#   - weights g(||offset / h_s||^2) * g(((y0 - yn) / h_r)^2) with g(t) = exp(-t)
#     and the adaptive range bandwidth h_r = max |y0 - yn| (Eqs. S21, S22, S25,
#     pp.8-9; p.17),
#   - MS = sum(g * yn) / sum(g) - y0 (Eq. S26, p.9), MSSR^0 = -MS with negative
#     values set to zero, normalized to 1 (Eq. S48, p.17),
#   - higher orders: Diff = I - MSSR, its complement normalized, weighted by
#     the current map and normalized (Note 5.1.2 and Fig. S11, p.21),
#   - intensity normalization: pixel-wise product with the input (p.60).
# Edges use the package's half-sample reflection, which the paper leaves open.
paper_mssr <- function(img, fwhm, order, weighted) {
  hs <- max(1, round(fwhm / 2))
  nr <- nrow(img)
  nc <- ncol(img)
  reflect <- function(i, n) {
    m <- (i - 1) %% (2 * n)
    if (m < n) m + 1 else 2 * n - m
  }
  offsets <- expand.grid(i = -hs:hs, j = -hs:hs)
  offsets <- offsets[!(offsets$i == 0 & offsets$j == 0) &
                       sqrt(offsets$i^2 + offsets$j^2) <= hs, ]
  ms <- matrix(0, nr, nc)
  for (r in seq_len(nr)) {
    for (c in seq_len(nc)) {
      yn <- vapply(seq_len(nrow(offsets)), function(k) {
        img[reflect(r + offsets$i[k], nr), reflect(c + offsets$j[k], nc)]
      }, numeric(1))
      hr <- max(abs(img[r, c] - yn))
      if (hr == 0) hr <- 1
      g <- exp(-(offsets$i^2 + offsets$j^2) / hs^2) * exp(-((img[r, c] - yn) / hr)^2)
      ms[r, c] <- sum(g * yn) / sum(g) - img[r, c]
    }
  }
  map <- pmax(-ms, 0)
  map <- map / max(map)
  previous <- img / max(img)
  for (k in seq_len(order)) {
    diff <- previous - map
    complement <- max(diff) - diff
    refined <- complement / max(complement) * map
    previous <- map
    map <- refined / max(refined)
  }
  if (weighted) map * img else map
}

test_that("mssr() agrees with a direct transcription of the published equations", {
  withr::local_seed(20261123)
  img <- matrix(stats::runif(13 * 9), 13, 9) +
    outer(1:13, 1:9, function(r, c) exp(-((r - 6)^2 + (c - 4)^2) / 3))
  for (order in 0:3) {
    for (weighted in c(FALSE, TRUE)) {
      expected <- paper_mssr(img, fwhm = 3, order = order, weighted = weighted)
      actual <- as.matrix(mssr(img, fwhm = 3, order = order, intensity_normalize = weighted))
      expect_lte(max(abs(actual - expected)) / max(abs(expected)), 1e-12,
                 label = sprintf("order %d, weighted %s", order, weighted))
    }
  }
})

test_that("mssr() commutes with transposing and flipping the frame", {
  withr::local_seed(20261124)
  img <- matrix(stats::runif(11 * 8), 11, 8)
  for (amp in 1:3) {
    for (kernel in c("disk", "square")) {
      map <- function(x) as.matrix(mssr(x, fwhm = 3, amp = amp, kernel = kernel))
      reference <- map(img)
      scale <- max(abs(reference))
      expect_lte(max(abs(map(t(img)) - t(reference))) / scale, 1e-12)
      flipped <- map(img[rev(seq_len(nrow(img))), ])
      expect_lte(max(abs(flipped - reference[rev(seq_len(nrow(reference))), ])) / scale, 1e-12)
    }
  }
})
