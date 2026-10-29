# Applies the temporal reduction directly to a stack of values, without MSSR.
reduce_stack <- function(a, statistic) {
  frame <- function(t, pass) {
    f <- a[, , t]
    dim(f) <- dim(a)[1:2]
    f
  }
  temporal_reduce(frame, dim(a)[3], statistic)
}

# One series per pixel, repeated over a 1 x 2 frame.
series_stack <- function(v) array(rep(v, each = 2L), c(1L, 2L, length(v)))

# Slow reference: explicit loops over pixels and time, from Table S2.
reference_statistic <- function(a, statistic) {
  out <- matrix(0, dim(a)[1], dim(a)[2])
  n <- dim(a)[3]
  for (i in seq_len(dim(a)[1])) {
    for (j in seq_len(dim(a)[2])) {
      x <- a[i, j, ]
      m <- sum(x) / n
      d <- x - m
      lag_mean <- function(lags, k) {
        s <- 0
        for (t in seq_len(k)) s <- s + prod(d[t + lags])
        s / k
      }
      out[i, j] <- switch(statistic,
        mean = m,
        var = sum(d^2) / n,
        tpm = sum(x)^2,
        cv = if (m == 0) 0 else (sum(d^2) / n) / m,
        sofi2 = lag_mean(0:1, n - 1),
        sofi3 = lag_mean(0:2, n - 2),
        sofi4 = lag_mean(0:3, n - 3) - lag_mean(0:1, n - 3) * lag_mean(2:3, n - 3) -
          lag_mean(c(0, 2), n - 3) * lag_mean(c(1, 3), n - 3) -
          lag_mean(c(0, 3), n - 3) * lag_mean(1:2, n - 3)
      )
    }
  }
  out
}

blinking_frames <- function(n_frames = 24L, seed = 1L, size = 14L) {
  withr::with_seed(seed, {
    g <- expand.grid(r = seq_len(size), c = seq_len(size))
    spot <- function(r0, c0) exp(-((g$r - r0)^2 + (g$c - c0)^2) / (2 * (3 / 2.3548)^2))
    x <- array(0, c(size, size, n_frames))
    for (t in seq_len(n_frames)) {
      on <- stats::runif(2) < 0.5
      mu <- 30 * (on[1] * spot(7, 6) + on[2] * spot(7, 9)) + 3
      x[, , t] <- stats::rpois(size^2, mu)
    }
    x
  })
}

test_that("constant, alternating and periodic stacks give the derived values", {
  const <- series_stack(rep(2.5, 6))
  expected <- c(mean = 2.5, var = 0, tpm = 15^2, cv = 0, sofi2 = 0, sofi3 = 0, sofi4 = 0)
  for (s in names(expected)) expect_equal(reduce_stack(const, s)[1, ], rep(expected[[s]], 2))
  a <- 3
  b <- 0.5
  alt <- series_stack(a + b * (-1)^(1:8))
  expected <- c(mean = a, var = b^2, tpm = (8 * a)^2, cv = b^2 / a, sofi2 = -b^2, sofi3 = 0,
                sofi4 = -2 * b^4)
  for (s in names(expected)) expect_equal(reduce_stack(alt, s)[1, ], rep(expected[[s]], 2))
  per <- series_stack(rep(c(0, 0, 3), 3))
  expected <- c(mean = 1, var = 2, tpm = 81, cv = 2, sofi2 = -7 / 8, sofi3 = 2)
  for (s in names(expected)) expect_equal(reduce_stack(per, s)[1, ], rep(expected[[s]], 2))
})

test_that("the reduction agrees with an explicit-loop reference", {
  withr::with_seed(11, {
    for (n in c(4L, 7L, 50L)) {
      a <- array(stats::rexp(3 * 4 * n), c(3, 4, n))
      for (s in temporal_statistics) {
        got <- reduce_stack(a, s)
        want <- reference_statistic(a, s)
        expect_lte(max(abs(got - want)), 1e-12 * max(abs(want), 1e-300))
      }
    }
  })
})

test_that("offsets, scaling, time reversal and pixel order behave as defined", {
  withr::with_seed(5, {
    a <- array(stats::rexp(4 * 5 * 9), c(4, 5, 9))
  })
  shifted <- a + 7.25
  for (s in c("var", "sofi2", "sofi3", "sofi4")) {
    expect_equal(reduce_stack(shifted, s), reduce_stack(a, s), tolerance = 1e-9)
  }
  degree <- c(mean = 1, var = 2, tpm = 2, cv = 1, sofi2 = 2, sofi3 = 3, sofi4 = 4)
  for (s in temporal_statistics) {
    # Power-of-two scaling is exact; other factors scale to rounding.
    expect_identical(reduce_stack(a * 2^-20, s), reduce_stack(a, s) * 2^(-20 * degree[[s]]))
    expect_equal(reduce_stack(a * 3.7, s), reduce_stack(a, s) * 3.7^degree[[s]],
                 tolerance = 1e-12)
  }
  reversed <- a[, , rev(seq_len(dim(a)[3]))]
  for (s in c("var", "sofi2", "sofi3", "sofi4")) {
    expect_equal(reduce_stack(reversed, s), reduce_stack(a, s), tolerance = 1e-12)
  }
  rows <- c(3, 1, 4, 2)
  cols <- c(5, 2, 1, 4, 3)
  for (s in temporal_statistics) {
    expect_identical(reduce_stack(a[rows, cols, ], s), reduce_stack(a, s)[rows, cols])
  }
})

test_that("extreme magnitudes stay representable or are refused", {
  plain <- series_stack(c(1, 3, 2, 5, 4))
  big <- plain * 2^1000
  expect_identical(reduce_stack(big, "mean"), reduce_stack(plain, "mean") * 2^1000)
  expect_identical(reduce_stack(plain * 2^500, "sofi2"), reduce_stack(plain, "sofi2") * 2^1000)
  expect_error(reduce_stack(big, "var"), class = "mssrscopR_error_numerical")
  tiny <- series_stack(c(1, 3, 2, 5) * 2^-1000)
  expect_identical(reduce_stack(tiny, "mean"), reduce_stack(series_stack(c(1, 3, 2, 5)),
                                                            "mean") * 2^-1000)
  zero <- series_stack(rep(0, 5))
  for (s in temporal_statistics) expect_identical(reduce_stack(zero, s), matrix(0, 1, 2))
})

test_that("stored, recomputed and stack paths agree and mean matches per-frame MSSR", {
  x <- blinking_frames()
  stored <- mssr_temporal(x, "sofi2", fwhm = 3, amp = 2)
  budget <- mssr_estimate_resources(dim(x)[1:2], fwhm = 3, amp = 2, frames = dim(x)[3],
                                    statistic = "sofi2")$recompute_peak_bytes
  recomputed <- mssr_temporal(x, "sofi2", fwhm = 3, amp = 2, max_memory_bytes = budget)
  stack <- mssr_stack(x, fwhm = 3, amp = 2)
  from_stack <- mssr_temporal(stack, "sofi2")
  expect_identical(stored$diagnostics$path, "stored")
  expect_identical(recomputed$diagnostics$path, "recompute")
  expect_identical(from_stack$diagnostics$path, "stack")
  expect_identical(recomputed$values, stored$values)
  expect_identical(from_stack$values, stored$values)
  expect_identical(from_stack$diagnostics$mesh_index, stored$diagnostics$mesh_index)
  expect_identical(from_stack$diagnostics$trend, stored$diagnostics$trend)
  mean_map <- mssr_temporal(x, "mean", fwhm = 3, amp = 2)
  expect_identical(mean_map$diagnostics$path, "single_pass")
  per_frame <- lapply(seq_len(dim(x)[3]), function(t) mssr(x[, , t], fwhm = 3, amp = 2)$values)
  expect_equal(mean_map$values, Reduce(`+`, per_frame) / dim(x)[3], tolerance = 1e-14)
  expect_equal(mssr_temporal(stack, "tpm")$values, dim(x)[3]^2 * mean_map$values^2,
               tolerance = 1e-12)
  expect_identical(dim(stack$values), c(28L, 28L, 24L))
  expect_identical(stack$values[, , 3], mssr(x[, , 3], fwhm = 3, amp = 2)$values)
})

test_that("frame selection, sign and the result record are consistent", {
  x <- blinking_frames(12L)
  part <- mssr_temporal(x, "var", fwhm = 3, frames = 4:9)
  expect_identical(part$values, mssr_temporal(x[, , 4:9], "var", fwhm = 3)$values)
  expect_identical(part$parameters$first_frame, 4L)
  expect_identical(part$parameters$frames, 6L)
  stack <- mssr_stack(x, fwhm = 3, frames = 3:12)
  expect_identical(mssr_temporal(stack, "var", frames = 2:7)$values, part$values)
  expect_identical(mssr_temporal(stack, "var", frames = 2:7)$parameters$first_frame, 4L)
  signed <- mssr_temporal(x, "sofi3", fwhm = 3)
  absolute <- mssr_temporal(x, "sofi3", fwhm = 3, sign = "absolute")
  expect_identical(absolute$values, abs(signed$values))
  expect_identical(signed$parameters$sign, "signed")
  expect_identical(part$parameters$sign, "not_applicable")
  expect_identical(part$role, "temporal_var")
  expect_identical(part$schema_version, "1.1.0")
  expect_identical(part$parameters$definition, "table_s2_lagged")
  expect_null(part$diagnostics$mesh_index)
  expect_true("mesh_index" %in% names(part$diagnostics))
  expect_identical(part$diagnostics$mesh_region, "not_computed")
  amplified <- mssr_temporal(x, "mean", fwhm = 3, amp = 2)
  expect_true(is.double(amplified$diagnostics$mesh_index))
  expect_gte(amplified$diagnostics$mesh_index, 0)
  expect_identical(amplified$diagnostics$mesh_region, "below_median")
  everywhere <- matrix(TRUE, 14, 14)
  masked <- mssr_temporal(x, "mean", fwhm = 3, amp = 2, background = everywhere)
  expect_identical(masked$diagnostics$mesh_region, "background")
  expect_identical(masked$values, amplified$values)
  blocks <- masked$values
  phases <- vapply(1:4, function(k) {
    mean(blocks[seq(1 + (k - 1) %/% 2, 28, by = 2), seq(1 + (k - 1) %% 2, 28, by = 2)])
  }, numeric(1))
  expect_equal(masked$diagnostics$mesh_index, (max(phases) - min(phases)) / abs(mean(blocks)),
               tolerance = 1e-12)
  for (s in temporal_statistics) {
    r <- mssr_temporal(x, s, fwhm = 3)
    expect_identical(mssr_validate_result(r), r)
  }
  replay <- do.call(mssr_temporal, c(list(x = x), mssr_settings(part)))
  expect_identical(replay$values, part$values)
  replay <- do.call(mssr_temporal, c(list(x = x), mssr_settings(absolute)))
  expect_identical(replay$values, absolute$values)
  expect_output(print(part), "var of 6 frame")
  expect_output(print(summary(absolute)), "sign absolute")
  expect_output(print(stack), "10 frames")
})

test_that("temporal records survive writing and reading", {
  skip_if_not_installed("digest")
  skip_if_not_installed("jsonlite")
  x <- blinking_frames(8L)
  results <- list(
    mssr_temporal(x, "cv", fwhm = 3),
    mssr_temporal(x, "sofi4", fwhm = 3, amp = 2, sign = "absolute")
  )
  for (r in results) {
    path <- tempfile(fileext = ".mssr")
    withr::defer(unlink(path))
    mssr_write_result(r, path)
    expect_identical(mssr_read_result(path), r)
  }
})

test_that("validation refuses inconsistent temporal records", {
  x <- blinking_frames(8L)
  r <- mssr_temporal(x, "sofi2", fwhm = 3, amp = 2)
  changes <- list(
    function(z) {
      z$role <- "temporal_var"
      z
    },
    function(z) {
      z$parameters$statistic <- "sofi5"
      z
    },
    function(z) {
      z$parameters$sign <- "not_applicable"
      z
    },
    function(z) {
      z$parameters$frames <- 1L
      z
    },
    function(z) {
      z$parameters$definition <- "zero_lag"
      z
    },
    function(z) {
      z$diagnostics$mesh_index <- -1
      z
    },
    function(z) {
      z$diagnostics$mesh_region <- "not_computed"
      z
    },
    function(z) {
      z$diagnostics$trend <- "falling"
      z
    },
    function(z) {
      z$diagnostics$path <- "cached"
      z
    },
    function(z) {
      z$diagnostics$degenerate_frames <- 9L
      z
    },
    function(z) {
      z$schema_version <- "1.0.0"
      z
    },
    function(z) {
      z$diagnostics$quantitative <- TRUE
      z
    },
    function(z) {
      z$parameters$first_frame <- 0L
      z
    }
  )
  for (change in changes) expect_error(mssr_validate_result(change(r)), class = "mssrscopR_error")
  m <- mssr_temporal(x, "mean", fwhm = 3)
  m$parameters$sign <- "signed"
  expect_error(mssr_validate_result(m), class = "mssrscopR_error_result")
  a <- mssr_temporal(x, "sofi3", fwhm = 3, sign = "absolute")
  a$values[1, 1] <- -1
  expect_error(mssr_validate_result(a), class = "mssrscopR_error_result")
  single <- mssr(x[, , 1], fwhm = 3)
  single$schema_version <- "1.1.0"
  expect_error(mssr_validate_result(single), class = "mssrscopR_error_result")
})

test_that("inputs and arguments are refused with documented classes", {
  x <- blinking_frames(6L)
  expect_error(mssr_temporal(x, fwhm = 3), class = "mssrscopR_error_parameter")
  expect_error(mssr_temporal(x, "median", fwhm = 3), class = "mssrscopR_error_parameter")
  expect_error(mssr_temporal(x, "var"), class = "mssrscopR_error_parameter")
  expect_error(mssr_temporal(x[, , 1], "var", fwhm = 3), class = "mssrscopR_error_input")
  expect_error(mssr_temporal(as.data.frame(x[, , 1]), "var", fwhm = 3),
               class = "mssrscopR_error_input")
  bad <- x
  bad[2, 2, 5] <- NA
  expect_error(mssr_temporal(bad, "var", fwhm = 3), "Frame 5", class = "mssrscopR_error_nonfinite")
  expect_error(mssr_temporal(x, "sofi4", fwhm = 3, frames = 1:3), class = "mssrscopR_error_input")
  expect_error(mssr_temporal(x, "var", fwhm = 3, frames = c(1, 3)),
               class = "mssrscopR_error_parameter")
  expect_error(mssr_temporal(x, "var", fwhm = 3, frames = 5:7), class = "mssrscopR_error_parameter")
  expect_error(mssr_temporal(x, "mean", fwhm = 3, sign = "absolute"),
               class = "mssrscopR_error_parameter")
  expect_error(mssr_temporal(x, "var", fwhm = 3, max_memory_bytes = 1024),
               class = "mssrscopR_error_resource")
  expect_error(mssr_stack(x, fwhm = 3, max_memory_bytes = 1024), class = "mssrscopR_error_resource")
  stack <- mssr_stack(x, fwhm = 3)
  expect_error(mssr_temporal(stack, "var", fwhm = 3), "fwhm", class = "mssrscopR_error_parameter")
  expect_error(mssr_temporal(stack, "var", amp = 2), class = "mssrscopR_error_parameter")
  broken <- stack
  broken$values[1, 1, 1] <- Inf
  expect_error(mssr_temporal(broken, "var"), class = "mssrscopR_error_input")
  broken <- stack
  broken$parameters$half_size <- 9
  expect_error(mssr_temporal(broken, "var"), class = "mssrscopR_error")
  broken <- stack
  broken$diagnostics <- broken$diagnostics[-1, ]
  expect_error(mssr_temporal(broken, "var"), class = "mssrscopR_error_input")
  broken <- stack
  broken$input_mean <- broken$input_mean[-1, ]
  expect_error(mssr_temporal(broken, "var"), class = "mssrscopR_error_input")
  expect_error(mssr_temporal(x, "var", fwhm = 3, amp = 2, background = matrix(TRUE, 2, 2)),
               class = "mssrscopR_error_parameter")
  expect_error(mssr_temporal(x, "var", fwhm = 3, amp = 2, background = matrix(FALSE, 14, 14)),
               class = "mssrscopR_error_parameter")
  everywhere <- matrix(TRUE, 14, 14)
  expect_error(mssr_temporal(x, "var", fwhm = 3, background = everywhere), "amp > 1",
               class = "mssrscopR_error_parameter")
  expect_error(mssr_temporal(x, "var", fwhm = 3, amp = 2, grid = "endpoint",
                             background = everywhere), class = "mssrscopR_error_parameter")
  expect_error(mssr_temporal(stack, "var", background = everywhere),
               class = "mssrscopR_error_parameter")
  expect_error(mssr_temporal(unclass(stack), "var"), class = "mssrscopR_error_input")
  frame_error <- x
  frame_error[, , 3] <- 0
  frame_error[1, 1, 3] <- 2^1023
  frame_error[1, 2, 3] <- 2^-1074
  expect_error(mssr_temporal(frame_error, "var", fwhm = 3), "Frame 3",
               class = "mssrscopR_error_numerical")
})

test_that("frame warnings are collected and given once per class", {
  x <- blinking_frames(5L) - 4
  warnings <- character()
  withCallingHandlers(
    r <- mssr_temporal(x, "var", fwhm = 3),
    warning = function(w) {
      warnings <<- c(warnings, class(w)[1])
      invokeRestart("muffleWarning")
    }
  )
  expect_identical(warnings, "mssrscopR_warning_negative")
  expect_identical(r$diagnostics$warning_frames, 5L)
  impulses <- array(0, c(9, 9, 4))
  impulses[5, 5, ] <- 1
  impulses[2, 2, 2] <- 1
  expect_warning(s <- mssr_temporal(impulses, "mean", fwhm = 2, order = 2),
                 class = "mssrscopR_warning_skipped_steps")
  expect_gt(s$diagnostics$order_steps_skipped, 0L)
  expect_warning(mssr_temporal(blinking_frames(3L), "mean", fwhm = 3, order = 4),
                 class = "mssrscopR_warning_unqualified_order")
  flat <- array(1, c(6, 6, 3))
  d <- mssr_temporal(flat, "mean", fwhm = 2)
  expect_identical(d$diagnostics$degenerate_frames, 3L)
  expect_true(all(d$values == 0))
})

test_that("temporal resource estimates extend the single-frame model", {
  base <- mssr_estimate_resources(c(32, 40), fwhm = 3, amp = 2)
  est <- mssr_estimate_resources(c(32, 40), fwhm = 3, amp = 2, frames = 10, statistic = "sofi4")
  expect_identical(est[names(base)], base)
  expect_identical(est$stack_bytes, 8 * base$output_pixels * 10)
  expect_gt(est$stored_peak_bytes, est$recompute_peak_bytes)
  expect_identical(est$recompute_work, 2 * est$stored_work)
  expect_identical(est$temporal_model, "temporal_buffers_v2")
  mean_est <- mssr_estimate_resources(c(32, 40), fwhm = 3, amp = 2, frames = 10,
                                      statistic = "mean")
  expect_identical(mean_est$recompute_work, mean_est$stored_work)
  expect_error(mssr_estimate_resources(c(32, 40), fwhm = 3, frames = 10),
               class = "mssrscopR_error_parameter")
  expect_error(mssr_estimate_resources(c(32, 40), fwhm = 3, frames = 0, statistic = "var"),
               class = "mssrscopR_error_parameter")
})

test_that("the trend diagnostic compares the last and first tenth of the raw frames", {
  fading <- array(0, c(8, 8, 20))
  for (t in 1:20) fading[, , t] <- (21 - t) * (1 + outer(1:8, 1:8) / 64)
  r <- mssr_temporal(fading, "mean", fwhm = 2)
  expect_equal(r$diagnostics$trend, mean(c(2, 1)) / mean(c(20, 19)), tolerance = 1e-14)
  steady <- mssr_temporal(blinking_frames(30L), "var", fwhm = 3)
  expect_true(is.double(steady$diagnostics$trend))
  short <- mssr_temporal(fading[, , 1:3], "mean", fwhm = 2)
  expect_equal(short$diagnostics$trend, 18 / 20, tolerance = 1e-14)
  zeros <- array(0, c(6, 6, 4))
  zeros[, , 4] <- 1
  expect_null(mssr_temporal(zeros, "mean", fwhm = 2)$diagnostics$trend)
})

test_that("remaining argument and stack checks are classed", {
  x <- blinking_frames(4L, size = 8L)
  expect_error(mssr_stack(x), class = "mssrscopR_error_parameter")
  expect_error(mssr_temporal(array(0, c(2, 2, 0)), "mean", fwhm = 2),
               class = "mssrscopR_error_input")
  expect_error(mssr_temporal(array(1, c(1, 5, 3)), "mean", fwhm = 2, amp = 2, grid = "endpoint"),
               class = "mssrscopR_error_unsupported")
  square <- mssr_temporal(x, "var", fwhm = 3, kernel = "square")
  expect_identical(mssr_validate_result(square), square)
  expect_identical(square$diagnostics$n_offsets,
                   as.integer((2 * square$parameters$half_size + 1)^2 - 1))
  flat <- mssr_temporal(array(2, c(8, 8, 3)), "mean", fwhm = 2, amp = 2)
  expect_null(flat$diagnostics$mesh_index)
  expect_identical(flat$diagnostics$mesh_region, "below_median")
  stack <- mssr_stack(x, fwhm = 3)
  extra <- stack
  extra$note <- "added"
  expect_error(mssr_temporal(extra, "var"), class = "mssrscopR_error_input")
  missing_field <- stack
  missing_field$parameters$first_frame <- NULL
  expect_error(mssr_temporal(missing_field, "var"), class = "mssrscopR_error_input")
  engine <- stack
  engine$engine$id <- NA_character_
  expect_error(mssr_temporal(engine, "var"), class = "mssrscopR_error_input")
})

test_that("signed series give signed CV, zero-mean CV 0, and refuse underflow", {
  neg <- series_stack(c(-3, -1, -2, -4))
  expect_equal(reduce_stack(neg, "mean")[1, ], rep(-2.5, 2))
  expect_equal(reduce_stack(neg, "var")[1, ], rep(1.25, 2))
  expect_equal(reduce_stack(neg, "cv")[1, ], rep(-0.5, 2))
  expect_identical(reduce_stack(series_stack(c(-1, 1, -1, 1)), "cv"), matrix(0, 1, 2))
  expect_error(reduce_stack(series_stack(c(1, 3, 2, 5) * 2^-300), "sofi4"),
               class = "mssrscopR_error_numerical")
  expect_error(reduce_stack(series_stack(c(1, 3, 2) * 2^-600), "var"),
               class = "mssrscopR_error_numerical")
})

test_that("every statistic agrees across the stored, recomputed and stack paths", {
  x <- blinking_frames(10L, size = 10L)
  stack <- mssr_stack(x, fwhm = 3, amp = 2)
  for (s in temporal_statistics) {
    est <- mssr_estimate_resources(c(10, 10), fwhm = 3, amp = 2, frames = 10, statistic = s)
    stored <- mssr_temporal(x, s, fwhm = 3, amp = 2)
    recomputed <- mssr_temporal(x, s, fwhm = 3, amp = 2,
                                max_memory_bytes = est$recompute_peak_bytes)
    from_stack <- mssr_temporal(stack, s)
    for (r in list(recomputed, from_stack)) {
      expect_identical(r$values, stored$values, label = s)
      expect_identical(r$diagnostics[c("mesh_index", "mesh_region", "mesh_pixels", "trend")],
                       stored$diagnostics[c("mesh_index", "mesh_region", "mesh_pixels", "trend")],
                       label = s)
    }
  }
})

test_that("a stack's frame subset records its own mesh region", {
  x <- blinking_frames(12L, size = 10L)
  raw <- mssr_temporal(x, "var", fwhm = 3, amp = 2, frames = 3:10)
  whole <- mssr_temporal(mssr_stack(x, fwhm = 3, amp = 2), "var", frames = 3:10)
  part <- mssr_temporal(mssr_stack(x, fwhm = 3, amp = 2, frames = 3:10), "var")
  expect_identical(whole$values, raw$values)
  expect_identical(raw$diagnostics$mesh_region, "below_median")
  expect_identical(whole$diagnostics$mesh_region, "below_median_stack")
  expect_identical(part$diagnostics$mesh_region, "below_median")
  expect_identical(part$diagnostics$mesh_index, raw$diagnostics$mesh_index)
  expect_identical(part$parameters$first_frame, 3L)
  expect_identical(whole$parameters$first_frame, 3L)
})

test_that("the endpoint grid and SOFI statistics get the documented mesh treatment", {
  x <- blinking_frames(6L, size = 10L)
  ends <- mssr_temporal(x, "mean", fwhm = 3, amp = 2, grid = "endpoint")
  expect_null(ends$diagnostics$mesh_index)
  expect_identical(ends$diagnostics$mesh_region, "not_computed")
  expect_identical(ends$diagnostics$mesh_pixels, 0L)
  frames <- lapply(1:6, function(t) mssr(x[, , t], fwhm = 3, amp = 2, grid = "endpoint")$values)
  expect_equal(ends$values, Reduce(`+`, frames) / 6, tolerance = 1e-14)
  expect_identical(mssr_validate_result(ends), ends)
  forged <- ends
  forged$diagnostics$mesh_region <- "below_median"
  expect_error(mssr_validate_result(forged), class = "mssrscopR_error_result")
  everywhere <- matrix(TRUE, 10, 10)
  k <- mssr_temporal(x, "sofi2", fwhm = 3, amp = 2, background = everywhere)
  a <- abs(k$values)
  phases <- vapply(1:4, function(i) {
    mean(a[seq(1 + (i - 1) %/% 2, 20, by = 2), seq(1 + (i - 1) %% 2, 20, by = 2)])
  }, numeric(1))
  expect_equal(k$diagnostics$mesh_index, (max(phases) - min(phases)) / mean(a), tolerance = 1e-12)
  expect_identical(k$diagnostics$mesh_pixels, 100L)
  expect_output(print(ends), "amp 1 or endpoint grid")
  flat <- mssr_temporal(array(2, c(10, 10, 3)), "mean", fwhm = 2, amp = 2)
  expect_output(print(flat), "supply `background`")
})

test_that("stacks are capped by default and checked for counts and engines", {
  big <- array(0, c(16, 16, 300))
  expect_error(mssr_stack(big, fwhm = 1, amp = 64), "2 GiB", class = "mssrscopR_error_resource")
  x <- blinking_frames(5L, size = 8L)
  stack <- mssr_stack(x, fwhm = 3)
  expect_error(mssr_temporal(stack, "var", max_memory_bytes = 64),
               class = "mssrscopR_error_resource")
  expect_identical(mssr_temporal(stack, "var", max_memory_bytes = 1024^3)$values,
                   mssr_temporal(stack, "var")$values)
  bad <- stack
  bad$diagnostics$order_steps_skipped[2] <- -1
  expect_error(mssr_temporal(bad, "var"), class = "mssrscopR_error_input")
  bad <- stack
  bad$engine$id <- "other_engine"
  expect_error(mssr_temporal(bad, "var"), class = "mssrscopR_error_input")
  bad <- stack
  bad$parameters$first_frame <- .Machine$integer.max
  expect_error(mssr_temporal(bad, "var"), class = "mssrscopR_error_input")
  expect_output(print(bad), "2147483647 to 2147483651")
})

test_that("variance and TPM records must not be negative", {
  x <- blinking_frames(5L, size = 8L)
  for (s in c("var", "tpm")) {
    r <- mssr_temporal(x, s, fwhm = 3)
    r$values[1, 1] <- -1
    r$diagnostics$negative_fraction <- mean(r$values < 0)
    r$diagnostics$zero_fraction <- mean(r$values == 0)
    expect_error(mssr_validate_result(r), class = "mssrscopR_error_result")
  }
})

test_that("raw frames are read without copying the input array", {
  skip_if_not(capabilities("profmem"), "tracemem needs memory profiling")
  x <- blinking_frames(6L, size = 10L)
  storage.mode(x) <- "integer"
  tracemem(x)
  copies <- utils::capture.output({
    r <- mssr_temporal(x, "var", fwhm = 3, frames = 2:6)
    s <- mssr_stack(x, fwhm = 3)
  })
  untracemem(x)
  expect_length(copies, 0L)
  expect_identical(r$values, mssr_temporal(x + 0, "var", fwhm = 3, frames = 2:6)$values)
  bad <- x
  bad[1, 1, 1] <- NA
  expect_identical(mssr_temporal(bad, "var", fwhm = 3, frames = 2:6)$values, r$values)
})

test_that("the temporal estimate bounds measured peak memory on a small ladder", {
  skip_on_cran()
  skip_on_covr()
  skip_if_not_installed("callr")
  skip_if_not(file.exists("/proc/self/status"), "peak RSS is read from /proc")
  ns <- asNamespace("mssrscopR")
  root <- getNamespaceInfo(ns, "path")
  development <- exists(".__DEVTOOLS__", ns, inherits = FALSE)
  if (development) skip_if_not_installed("pkgload")
  ladder <- list(
    c(n = 192, frames = 60, amp = 1, store = 1),
    c(n = 128, frames = 30, amp = 2, store = 0)
  )
  for (step in ladder) {
    estimate <- mssr_estimate_resources(rep(step[["n"]], 2), fwhm = 3, amp = step[["amp"]],
                                        frames = step[["frames"]], statistic = "var")
    budget <- if (step[["store"]] == 1) NULL else estimate$recompute_peak_bytes
    measured <- callr::r(function(root, development, step, budget) {
      if (development) {
        pkgload::load_all(root, quiet = TRUE)
      } else {
        loadNamespace("mssrscopR", lib.loc = dirname(root))
      }
      ns <- asNamespace("mssrscopR")
      set.seed(1)
      x <- array(stats::rpois(step[["n"]]^2 * step[["frames"]], 20) + 0,
                 c(step[["n"]], step[["n"]], step[["frames"]]))
      get("mssr_temporal", ns)(x, "var", fwhm = 3, amp = step[["amp"]],
                               max_memory_bytes = budget)
      status <- readLines("/proc/self/status")
      as.numeric(sub("^VmHWM:\\s+([0-9]+) kB$", "\\1", grep("^VmHWM", status, value = TRUE))) * 1024
    }, args = list(root = root, development = development, step = step, budget = budget),
    libpath = .libPaths())
    # The child also holds its input array, which the estimate does not count.
    input <- 8 * step[["n"]]^2 * step[["frames"]]
    peak <- if (step[["store"]] == 1) estimate$stored_peak_bytes else estimate$recompute_peak_bytes
    planned <- peak + input
    label <- paste(step, collapse = "/")
    slack <- if (identical(Sys.getenv("MSSRSCOPR_STRICT_MEMORY_TEST"), "true")) 1 else 1.25
    if (development) slack <- slack * 1.5
    expect_lte(measured, planned * slack, label = label)
    expect_lte(planned, 4 * measured, label = label)
  }
})

test_that("input names and attributes never reach stacks or results", {
  x <- blinking_frames(6L, size = 10L)
  named <- x
  dimnames(named) <- list(paste0("r", 1:10), paste0("c", 1:10), paste0("t", 1:6))
  attr(named, "acquisition") <- "private/path/scan-07"
  raw <- mssr_temporal(named, "var", fwhm = 3, amp = 2)
  expect_identical(attributes(raw$values), list(dim = c(20L, 20L)))
  expect_identical(raw$values, mssr_temporal(x, "var", fwhm = 3, amp = 2)$values)
  stack <- mssr_stack(named, fwhm = 3, amp = 2, frames = 2:6)
  expect_identical(attributes(stack$input_mean), list(dim = c(10L, 10L)))
  expect_identical(attributes(stack$values), list(dim = c(20L, 20L, 5L)))
  expect_false(any(grepl("private", unlist(lapply(unclass(stack), format)))))
  from_stack <- mssr_temporal(stack, "var")
  expect_identical(from_stack$values,
                   mssr_temporal(x, "var", fwhm = 3, amp = 2, frames = 2:6)$values)
  expect_identical(mssr_validate_result(from_stack), from_stack)
  thin <- array(blinking_frames(4L, size = 6L)[1, , ], c(1, 6, 4))
  dimnames(thin) <- list("only", NULL, NULL)
  expect_identical(attributes(mssr_stack(thin, fwhm = 2)$input_mean), list(dim = c(1L, 6L)))
})

test_that("the stored maps are filled in place, without a copy per frame", {
  skip_if_not(capabilities("profmem"), "Rprofmem needs memory profiling")
  x <- blinking_frames(40L, size = 24L)
  stack_bytes <- 8 * (48 * 48) * 40
  large_allocations <- function(expr) {
    log <- tempfile()
    withr::defer(unlink(log))
    utils::Rprofmem(log, threshold = stack_bytes / 2)
    force(expr)
    utils::Rprofmem(NULL)
    sizes <- suppressWarnings(as.numeric(sub(" *:.*", "", readLines(log))))
    sum(sizes >= stack_bytes, na.rm = TRUE)
  }
  expect_identical(large_allocations(mssr_stack(x, fwhm = 3, amp = 2)), 1L)
  expect_identical(large_allocations(mssr_temporal(x, "var", fwhm = 3, amp = 2)), 1L)
})
