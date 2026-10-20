# Internal numerical kernel: engine definition "mssr_r_rev2".
#
# Single-frame Mean-Shift Super-Resolution (Torres-Garcia et al. 2022,
# doi:10.1038/s41467-022-34693-9), independently implemented. Relative to the
# authors' R script it keeps the input orientation (no rot90), supports
# non-square frames and interpolates with Keys cubic convolution on a
# field-of-view-preserving grid.
#
# rev2 differs from rev1 (the research handoff engine) only where rev1 was
# undefined or numerically unstable; both give identical results on all
# bundled fixtures:
#   - a flat frame (zero range) is flagged degenerate before amplification,
#     instead of amplifying interpolation rounding noise;
#   - a refinement step whose normalizer max(I5) is zero (the mean-shift map
#     already equals the normalized input, e.g. impulses on an exactly zero
#     background) leaves the map unchanged instead of zeroing it; such steps
#     are counted in the diagnostics.

# Kernel half-size; the authors' R and Python code round halves to even.
mssr_half_size <- function(fwhm, amp, rounding) {
  x <- 0.5 * fwhm * amp
  hs <- if (rounding == "half_even") round(x) else floor(x + 0.5)
  max(1, hs)
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

# Keys cubic convolution kernel, a = -0.5.
mssr_keys <- function(s, a = -0.5) {
  s <- abs(s)
  ifelse(s <= 1, (a + 2) * s^3 - (a + 3) * s^2 + 1,
         ifelse(s < 2, a * s^3 - 5 * a * s^2 + 8 * a * s - 4 * a, 0))
}

# Output sample positions in input-pixel units (input centers at 1..n).
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

# Interpolate along the rows of `img` with the four Keys taps per output
# position (memory proportional to the output, no dense matrix).
mssr_interp_rows <- function(img, amp, grid) {
  n <- nrow(img)
  u <- mssr_grid_positions(n, amp, grid)
  f <- floor(u)
  out <- matrix(0, length(u), ncol(img))
  for (off in -1:2) {
    j <- f + off
    out <- out + mssr_keys(u - j) * img[mssr_reflect(j, n), , drop = FALSE]
  }
  out
}

mssr_upsample <- function(img, amp, grid) {
  t(mssr_interp_rows(t(mssr_interp_rows(img, amp, grid)), amp, grid))
}

# Shift with cached reflected indices: result[i, j] = img[i + di, j + dj].
mssr_shifter <- function(nr, nc) {
  rows <- list()
  cols <- list()
  function(img, di, dj) {
    ki <- as.character(di)
    kj <- as.character(dj)
    if (is.null(rows[[ki]])) rows[[ki]] <<- mssr_reflect(seq_len(nr) + di, nr)
    if (is.null(cols[[kj]])) cols[[kj]] <<- mssr_reflect(seq_len(nc) + dj, nc)
    img[rows[[ki]], cols[[kj]], drop = FALSE]
  }
}

# Mesh compensation: mean of the image and four symmetric shifts.
mssr_mesh <- function(img, desp) {
  shift <- mssr_shifter(nrow(img), ncol(img))
  (img + shift(img, -desp, 0) + shift(img, desp, 0) +
     shift(img, 0, -desp) + shift(img, 0, desp)) / 5
}

# Block mean of an extent-grid image back to the input grid.
mssr_block_mean <- function(img, amp) {
  nr <- nrow(img) %/% amp
  nc <- ncol(img) %/% amp
  scale <- max(abs(img))
  if (scale > .Machine$double.xmax / amp^2) {
    img <- img / scale
  } else {
    scale <- 1
  }
  out <- matrix(0, nr, nc)
  for (a in seq_len(amp)) {
    for (b in seq_len(amp)) {
      rows <- seq(a, by = amp, length.out = nr)
      cols <- seq(b, by = amp, length.out = nc)
      out <- out + img[rows, cols, drop = FALSE]
    }
  }
  (out / amp^2) * scale
}

# Neighborhood offsets (i fastest, as in the reference definition).
mssr_offsets <- function(hs, kernel) {
  offs <- expand.grid(i = -hs:hs, j = -hs:hs)
  offs <- offs[!(offs$i == 0 & offs$j == 0), ]
  if (kernel == "disk") offs <- offs[sqrt(offs$i^2 + offs$j^2) <= hs, ]
  offs
}

# The operator. Inputs are already validated by mssr().
mssr_engine <- function(img, amp, fwhm, order, int_norm, mesh, grid, kernel, rounding,
                        call = NULL) {
  finite <- function(x) {
    if (any(!is.finite(x))) {
      mssr_abort("numerical", paste("MSSR arithmetic exceeded the finite numeric range.",
                                    "Use a documented input rescaling before retrying."), call)
    }
    invisible(NULL)
  }
  hs <- mssr_half_size(fwhm, amp, rounding)
  offs <- mssr_offsets(hs, kernel)
  result <- function(values, degenerate, reason = NA_character_, skipped = 0L) {
    finite(values)
    list(values = values, degenerate = degenerate, degenerate_reason = reason,
         half_size = hs, n_offsets = nrow(offs), order_steps_skipped = skipped)
  }
  zeros <- function() matrix(0, nrow(img) * amp, ncol(img) * amp)
  if (diff(range(img)) == 0) {
    return(result(zeros(), TRUE, "flat input"))
  }
  amplified <- if (amp > 1L) {
    up <- mssr_upsample(img, amp, grid)
    if (mesh) mssr_mesh(up, ceiling(amp / 2)) else up
  } else {
    img
  }
  finite(amplified)
  if (max(amplified) <= 0) {
    return(result(zeros(), TRUE, "non-positive maximum"))
  }
  shift <- mssr_shifter(nrow(amplified), ncol(amplified))
  # Pass 1: maximum absolute local difference (range normalizer).
  range_max <- NULL
  for (k in seq_len(nrow(offs))) {
    d <- abs(amplified - shift(amplified, offs$i[k], offs$j[k]))
    range_max <- if (is.null(range_max)) d else pmax(range_max, d)
  }
  finite(range_max)
  # Pass 2: spatial x range weights. Where range_max is zero every difference
  # is zero, so dividing by 1 there gives the defined ratio 0.
  divisor <- range_max
  divisor[range_max == 0] <- 1
  weight_sum <- value_sum <- matrix(0, nrow(amplified), ncol(amplified))
  for (k in seq_len(nrow(offs))) {
    x <- shift(amplified, offs$i[k], offs$j[k])
    ratio <- (amplified - x) / divisor
    w <- exp(-(offs$i[k]^2 + offs$j[k]^2) / hs^2) * exp(-ratio^2)
    weight_sum <- weight_sum + w
    value_sum <- value_sum + x * w
  }
  finite(value_sum)
  finite(weight_sum)
  mean_shift <- amplified - value_sum / weight_sum
  finite(mean_shift)
  mean_shift[mean_shift < 0] <- 0
  if (max(mean_shift) <= 0) {
    return(result(zeros(), TRUE, "zero mean-shift map"))
  }
  i3 <- mean_shift / max(mean_shift)
  x3 <- amplified / max(amplified)
  finite(x3)
  skipped <- 0L
  for (k in seq_len(order)) {
    i4 <- x3 - i3
    i5 <- max(i4) - i4
    finite(i5)
    if (max(i5) <= 0) {
      # Undefined step (i4 constant): keep the current map.
      skipped <- skipped + 1L
      next
    }
    i6 <- (i5 / max(i5)) * i3
    i7 <- if (max(i6) > 0) i6 / max(i6) else i6
    x3 <- i3
    i3 <- i7
  }
  result(if (int_norm) i3 * amplified else i3, FALSE, skipped = skipped)
}
