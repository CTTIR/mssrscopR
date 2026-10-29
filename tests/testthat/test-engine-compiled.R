# The compiled neighborhood passes must reproduce the R reference passes.
# Both form the same sums in the same order; the bound allows for compilers
# that fuse a multiply and add.
engine_pair <- function(x, s) {
  run <- function(implementation) {
    mssr_engine(x, s$amp, s$fwhm, s$order, s$int_norm, s$mesh, s$grid, s$kernel,
                s$rounding, implementation = implementation)
  }
  list(compiled = run("compiled"), reference = run("r"))
}

expect_engines_agree <- function(x, s) {
  e <- engine_pair(x, s)
  label <- paste(dim(x), collapse = "x")
  for (field in c("degenerate", "degenerate_reason", "order_steps_skipped", "half_size",
                  "n_offsets")) {
    expect_identical(e$compiled[[field]], e$reference[[field]], label = label)
  }
  expect_identical(dim(e$compiled$values), dim(e$reference$values))
  peak <- max(abs(e$reference$values))
  error <- if (peak > 0) max(abs(e$compiled$values - e$reference$values)) / peak else
    max(abs(e$compiled$values))
  expect_lte(error, 1e-12, label = paste(label, "normalized difference"))
}

test_that("compiled and R neighborhood passes agree on the parameter grid", {
  set.seed(20261028)
  frames <- list(
    random = matrix(stats::runif(9 * 7), 9, 7),
    spots = local({
      g <- expand.grid(r = 1:11, c = 1:8)
      m <- matrix(0.05 + exp(-((g$r - 5)^2 + (g$c - 4)^2) / 2) +
                    exp(-((g$r - 7)^2 + (g$c - 6)^2) / 2), 11, 8)
      m
    }),
    row = matrix(c(1, 3, 2, 8, 2, 1, 5), 1, 7),
    column = matrix(c(2, 9, 4, 1, 6), 5, 1),
    tiny = matrix(c(1, 4, 2, 3), 2, 2),
    thin = matrix(stats::runif(15), 3, 5)
  )
  settings <- expand.grid(kernel = c("disk", "square"), rounding = c("half_even", "half_up"),
                          grid = c("extent", "endpoint"), mesh = c(FALSE, TRUE),
                          int_norm = c(FALSE, TRUE), stringsAsFactors = FALSE)
  for (amp in 1:5) {
    for (order in 0:3) {
      for (i in seq_len(nrow(settings))) {
        s <- c(as.list(settings[i, ]), amp = amp, order = order, fwhm = 2.5)
        frame <- frames[[1L + (i + amp + order) %% length(frames)]]
        expect_engines_agree(frame, s)
      }
    }
  }
})

test_that("compiled passes agree at larger half-sizes and on degenerate frames", {
  set.seed(7)
  x <- matrix(stats::rpois(24 * 19, 20), 24, 19)
  for (fwhm in c(0.5, 3, 9)) {
    for (kernel in c("disk", "square")) {
      s <- list(amp = 2L, order = 1L, fwhm = fwhm, int_norm = TRUE, mesh = TRUE,
                grid = "extent", kernel = kernel, rounding = "half_even")
      expect_engines_agree(x, s)
    }
  }
  s <- list(amp = 1L, order = 2L, fwhm = 3, int_norm = TRUE, mesh = FALSE,
            grid = "extent", kernel = "disk", rounding = "half_even")
  expect_engines_agree(matrix(3, 4, 5), s)
  impulses <- matrix(0, 7, 7)
  impulses[2, 2] <- impulses[6, 5] <- 1
  expect_engines_agree(impulses, s)
  expect_engines_agree(matrix(1, 1, 1), s)
})

test_that("compiled passes return the reference sums exactly in shape and order", {
  set.seed(3)
  x <- matrix(stats::runif(6 * 4), 6, 4)
  offs <- mssr_offsets(2, "disk")
  a <- mssr_neighborhood(x, offs, 2, "compiled")
  b <- mssr_neighborhood(x, offs, 2, "r")
  expect_named(a, c("range_max", "weight_sum", "difference_sum"))
  for (field in names(b)) {
    expect_identical(dim(a[[field]]), dim(b[[field]]))
    expect_lte(max(abs(a[[field]] - b[[field]])), 1e-12 * max(1, max(abs(b[[field]]))))
  }
  # Integer storage reaches the compiled code as double.
  xi <- matrix(c(1L, 5L, 2L, 8L, 3L, 4L), 3, 2)
  expect_equal(mssr_neighborhood(xi, offs, 2, "compiled"),
               mssr_neighborhood(xi * 1, offs, 2, "r"), tolerance = 1e-12)
})

# Processes started in the background of a non-interactive shell inherit an
# ignored SIGINT, and then no child can be interrupted.
sigint_ignored <- function() {
  if (!file.exists("/proc/self/status")) return(FALSE)
  line <- grep("^SigIgn:", readLines("/proc/self/status"), value = TRUE)
  mask <- trimws(sub("^SigIgn:", "", line))
  bitwAnd(strtoi(substring(mask, nchar(mask) - 1L), 16L), 2L) != 0L
}

test_that("compiled passes can be interrupted", {
  skip_on_cran()
  skip_on_os("windows")
  skip_if_not_installed("callr")
  skip_if(sigint_ignored(), "SIGINT is ignored in this process")
  ns <- asNamespace("mssrscopR")
  root <- getNamespaceInfo(ns, "path")
  development <- exists(".__DEVTOOLS__", ns, inherits = FALSE)
  if (development) skip_if_not_installed("pkgload")
  ready <- tempfile("mssr-ready-")
  # A large frame at a big half-size runs for minutes unless the periodic
  # interrupt check stops it.
  p <- callr::r_bg(function(root, development, ready) {
    if (development) {
      pkgload::load_all(root, quiet = TRUE)
    } else {
      loadNamespace("mssrscopR", lib.loc = dirname(root))
    }
    ns <- asNamespace("mssrscopR")
    x <- matrix(stats::runif(1500 * 1500), 1500, 1500)
    offs <- get("mssr_offsets", ns)(40, "disk")
    file.create(ready)
    tryCatch({
      get("mssr_neighborhood", ns)(x, offs, 40, "compiled")
      "finished"
    }, interrupt = function(e) "interrupted")
  }, args = list(root = root, development = development, ready = ready),
  libpath = .libPaths())
  withr::defer(p$kill())
  waited <- 0
  while (!file.exists(ready) && p$is_alive() && waited < 120) {
    Sys.sleep(0.1)
    waited <- waited + 0.1
  }
  expect_true(file.exists(ready))
  Sys.sleep(0.5)
  p$interrupt()
  p$wait(30000)
  expect_false(p$is_alive())
  expect_identical(p$get_result(), "interrupted")
})

test_that("compiled sums round each product before adding it", {
  # (1 + 2^-27) * (1 - 2^-27) = 1 - 2^-54 rounds to 1, so adding -1 gives 0;
  # a fused multiply-add would keep the exact product and give -2^-54.
  x <- 1 + 2^-27
  y <- 1 - 2^-27
  expect_identical(x * y - 1, 0)
  expect_identical(.Call(mssr_add_product_c, -1, x, y), 0)
  expect_identical(.Call(mssr_add_product_c, 2, 3, 4), 14)
})

test_that("the compiled passes refuse invalid half-sizes", {
  x <- matrix(1, 3, 3)
  for (hs in list(0, -1, Inf, NaN, NA_real_)) {
    expect_error(.Call(mssr_neighborhood_c, x, 1L, 0L, hs), "positive and finite")
  }
})
