# Internal numerical kernel: engine definition "mssr_r_rev1".
#
# Single-frame Mean-Shift Super-Resolution (Torres-Garcia et al. 2022,
# doi:10.1038/s41467-022-34693-9), independently implemented. Relative to the
# authors' R script it keeps the input orientation (no rot90), supports
# non-square frames, defines flat neighbourhoods (zero local range) and
# all-zero mean-shift maps instead of producing 0/0, and interpolates with Keys
# cubic convolution on a field-of-view-preserving grid. The loop recomputes the
# shifted copies in a second pass instead of storing all of them; the order of
# operations matches the reference definition, so results are identical.

# Kernel half-size; the authors' R and Python code round halves to even.
mssr_half_size <- function(fwhm, amp, rounding) {
  x <- 0.5 * fwhm * amp
  hs <- if (rounding == "half_even") round(x) else floor(x + 0.5)
  max(1L, as.integer(hs))
}

# Symmetric (half-sample) reflection of 1-based indices into 1..n.
mssr_reflect <- function(idx, n) {
  if (n == 1L) {
    return(rep(1L, length(idx)))
  }
  p <- 2L * n
  m <- (idx - 1L) %% p
  as.integer(ifelse(m < n, m + 1L, p - m))
}

# result[i, j] = img[i + di, j + dj] with symmetric boundary.
mssr_shift <- function(img, di, dj) {
  img[mssr_reflect(seq_len(nrow(img)) + di, nrow(img)),
      mssr_reflect(seq_len(ncol(img)) + dj, ncol(img)), drop = FALSE]
}

# Keys cubic convolution kernel, a = -0.5.
mssr_keys <- function(s, a = -0.5) {
  s <- abs(s)
  ifelse(s <= 1, (a + 2) * s^3 - (a + 3) * s^2 + 1,
         ifelse(s < 2, a * s^3 - 5 * a * s^2 + 8 * a * s - 4 * a, 0))
}

# Output sample positions in input-pixel units (input centres at 1..n).
mssr_grid_positions <- function(n, amp, grid) {
  k <- seq_len(n * amp)
  if (grid == "extent") {
    (k - 0.5) / amp + 0.5
  } else if (n == 1L) {
    rep(1, length(k))
  } else {
    1 + (k - 1) * (n - 1) / (n * amp - 1)
  }
}

mssr_interp_matrix <- function(n, amp, grid) {
  u <- mssr_grid_positions(n, amp, grid)
  A <- matrix(0, length(u), n)
  f <- floor(u)
  for (off in -1:2) {
    j <- f + off
    w <- mssr_keys(u - j)
    jj <- mssr_reflect(j, n)
    for (r in seq_along(u)) A[r, jj[r]] <- A[r, jj[r]] + w[r]
  }
  A
}

mssr_upsample <- function(img, amp, grid) {
  mssr_interp_matrix(nrow(img), amp, grid) %*% img %*% t(mssr_interp_matrix(ncol(img), amp, grid))
}

# Mesh compensation: mean of the image and four symmetric shifts.
mssr_mesh <- function(img, desp) {
  (img + mssr_shift(img, -desp, 0) + mssr_shift(img, desp, 0) +
     mssr_shift(img, 0, -desp) + mssr_shift(img, 0, desp)) / 5
}

# Block mean of an extent-grid image back to the input grid.
mssr_block_mean <- function(img, amp) {
  nr <- nrow(img) %/% amp
  nc <- ncol(img) %/% amp
  out <- matrix(0, nr, nc)
  for (a in seq_len(amp)) for (b in seq_len(amp)) {
    out <- out + img[seq(a, by = amp, length.out = nr), seq(b, by = amp, length.out = nc), drop = FALSE]
  }
  out / amp^2
}

# The operator. Inputs are already validated by mssr().
mssr_engine <- function(img, amp, fwhm, order, int_norm, mesh, grid, kernel, rounding) {
  hs <- mssr_half_size(fwhm, amp, rounding)
  AMP <- if (amp > 1L) {
    up <- mssr_upsample(img, amp, grid)
    if (mesh) mssr_mesh(up, ceiling(amp / 2)) else up
  } else {
    img
  }
  offs <- expand.grid(i = -hs:hs, j = -hs:hs)
  offs <- offs[!(offs$i == 0 & offs$j == 0), ]
  if (kernel == "disk") offs <- offs[sqrt(offs$i^2 + offs$j^2) <= hs, ]
  # Pass 1: maximum absolute local difference (range normaliser).
  M <- NULL
  for (k in seq_len(nrow(offs))) {
    d <- abs(AMP - mssr_shift(AMP, offs$i[k], offs$j[k]))
    M <- if (is.null(M)) d else pmax(M, d)
  }
  # Pass 2: spatial x range weights; flat neighbourhoods get a zero ratio.
  wsum <- ysum <- matrix(0, nrow(AMP), ncol(AMP))
  for (k in seq_len(nrow(offs))) {
    x <- mssr_shift(AMP, offs$i[k], offs$j[k])
    ratio <- ifelse(M > 0, (AMP - x) / M, 0)
    w <- exp(-(offs$i[k]^2 + offs$j[k]^2) / hs^2) * exp(-ratio^2)
    wsum <- wsum + w
    ysum <- ysum + x * w
  }
  MS <- AMP - ysum / wsum
  MS[MS < 0] <- 0
  if (max(MS) <= 0 || max(AMP) <= 0) {
    return(list(values = matrix(0, nrow(AMP), ncol(AMP)), degenerate = TRUE, half_size = hs, n_offsets = nrow(offs)))
  }
  I3 <- MS / max(MS)
  x3 <- AMP / max(AMP)
  for (k in seq_len(order)) {
    I4 <- x3 - I3
    I5 <- max(I4) - I4
    I5 <- if (max(I5) > 0) I5 / max(I5) else I5
    I6 <- I5 * I3
    I7 <- if (max(I6) > 0) I6 / max(I6) else I6
    x3 <- I3
    I3 <- I7
  }
  list(values = if (int_norm) I3 * AMP else I3, degenerate = FALSE, half_size = hs, n_offsets = nrow(offs))
}
