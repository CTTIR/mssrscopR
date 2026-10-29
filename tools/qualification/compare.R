# Synthetic-only comparison, metamorphic checks and mutation qualification.
args <- commandArgs(trailingOnly = TRUE)
stopifnot(length(args) %in% c(2L, 3L))
core_only <- length(args) == 3L && identical(args[3L], "--qualified-core")
if (length(args) == 3L && !core_only) stop("Unknown qualification scope option.")
out <- normalizePath(args[1], mustWork = TRUE)
package <- normalizePath(args[2], mustWork = TRUE)
pkgload::load_all(package, quiet = TRUE)
plan <- jsonlite::read_json(file.path(out, "plan.json"), simplifyVector = TRUE)
params <- c("fwhm", "amp", "order", "intensity_normalize", "mesh", "grid", "kernel", "rounding")
read_matrix <- function(path) as.matrix(utils::read.csv(path, header = FALSE))
read_case <- function(i) {
  c <- plan$cases[i, ]
  list(case = c, input = read_matrix(file.path(out, paste0(c$id, "_input.csv"))),
       expected = read_matrix(file.path(out, paste0(c$id, "_expected.csv"))),
       settings = as.list(c[params]))
}
capture_call <- function(fun, input, settings) {
  warnings <- character()
  value <- tryCatch(withCallingHandlers(do.call(fun, c(list(x = input), settings)),
    warning = function(w) {
      warnings <<- c(warnings, class(w)[1L]); invokeRestart("muffleWarning")
    }), error = identity)
  list(value = value, warning_classes = paste(unique(warnings), collapse = ";"))
}
error_score <- function(x, expected) {
  if (!identical(dim(x), dim(expected)) || any(!is.finite(x))) return(Inf)
  peak <- max(abs(expected))
  if (peak == 0) return(max(abs(x)))
  max(abs(x / peak - expected / peak))
}
rows <- masks <- list()
for (i in seq_len(nrow(plan$cases))) {
  c <- read_case(i)
  result <- capture_call(mssr, c$input, c$settings)
  failed <- inherits(result$value, "error")
  peak <- max(abs(c$expected))
  ulp <- if (peak > 0) 2 * (2^-1074 / peak) else 0
  tolerance <- plan$acceptance_normalized_max_error + ulp
  err <- if (failed) Inf else error_score(result$value$values, c$expected)
  mixed <- if (failed) FALSE else if (peak == 0) all(result$value$values == 0) else {
    all(abs(result$value$values / peak - c$expected / peak) <=
          1e-11 + 1e-11 * abs(c$expected / peak) + ulp)
  }
  rows[[i]] <- data.frame(case = c$case$id, scenario = c$case$scenario,
    normalized_max_error = err, tolerance = tolerance, mixed_pixel_rule_pass = mixed,
    passed = !failed && is.finite(err) && err <= tolerance && mixed,
    condition_class = if (failed) class(result$value)[1L] else "",
    warning_classes = result$warning_classes)
  if (!failed && (c$settings$amp == 1 || c$settings$grid == "extent")) {
    reference <- result$value
    reference$values <- c$expected
    for (fraction in c(0.1, 0.5, 0.9)) {
      # Wide quotas reach into ties by design here; the warning is not a finding.
      actual_mask <- suppressWarnings(mssr_mask(result$value, fraction = fraction, seed = 174L),
                                      classes = "mssrscopR_warning_mask_ties")
      reference_mask <- suppressWarnings(mssr_mask(reference, fraction = fraction, seed = 174L),
                                         classes = "mssrscopR_warning_mask_ties")
      scale <- max(abs(c$input))
      a_mean <- mean((c$input / if (scale > 0) scale else 1)[actual_mask])
      r_mean <- mean((c$input / if (scale > 0) scale else 1)[reference_mask])
      masks[[length(masks) + 1L]] <- data.frame(case = c$case$id,
        fraction = fraction, selected = sum(actual_mask), expected_quota = ceiling(fraction * length(c$input)),
        differing_selected_pixels = sum(actual_mask != reference_mask),
        jaccard = sum(actual_mask & reference_mask) / sum(actual_mask | reference_mask),
        normalized_original_measurement_change = a_mean - r_mean,
        tie_fraction = attr(actual_mask, "tie_fraction"), cut_relative = attr(actual_mask, "cut_relative"))
    }
  }
}
results <- do.call(rbind, rows)
utils::write.csv(results, file.path(out, "oracle_domain_results.csv"), row.names = FALSE)

# The compiled neighborhood passes against the retained R reference passes.
engine_case <- function(c, implementation) {
  s <- c$settings
  x <- matrix(as.double(c$input), nrow(c$input), ncol(c$input))
  tryCatch(mssr_engine(x, s$amp, s$fwhm, s$order, s$intensity_normalize, s$mesh,
                       s$grid, s$kernel, s$rounding, implementation = implementation),
           error = identity)
}
agreement <- do.call(rbind, lapply(seq_len(nrow(plan$cases)), function(i) {
  c <- read_case(i)
  a <- engine_case(c, "compiled")
  b <- engine_case(c, "r")
  both <- !inherits(a, "error") && !inherits(b, "error")
  difference <- if (!both) NA_real_ else {
    peak <- max(abs(b$values))
    if (peak > 0) max(abs(a$values - b$values)) / peak else max(abs(a$values))
  }
  data.frame(case = c$case$id, same_condition = inherits(a, "error") == inherits(b, "error"),
             identical_values = both && identical(a$values, b$values),
             normalized_difference = difference)
}))
utils::write.csv(agreement, file.path(out, "implementation_agreement.csv"), row.names = FALSE)
agreement_passed <- all(agreement$same_condition) &&
  all(is.na(agreement$normalized_difference) | agreement$normalized_difference <= 1e-12)
utils::write.csv(do.call(rbind, masks), file.path(out, "map_mask_measurement_sensitivity.csv"), row.names = FALSE)

# Independent geometric and homogeneity expectations, not output snapshots.
base <- matrix(c(1, 4, 2, 11, 3, 5, 6, 9, 4, 3, 10, 5), 3, 4)
settings <- expand.grid(amp = c(1L, 3L), order = c(0L, 3L),
                        kernel = c("disk", "square"), grid = c("extent", "endpoint"),
                        stringsAsFactors = FALSE)
meta <- list()
for (i in seq_len(nrow(settings))) {
  s <- as.list(settings[i, ])
  s$fwhm <- 2; s$intensity_normalize <- FALSE
  a <- do.call(mssr, c(list(x = base), s))
  variants <- list(transpose = list(input = t(base), expected = t(a$values)),
    row_reflection = list(input = base[nrow(base):1, ], expected = a$values[nrow(a$values):1, ]),
    col_reflection = list(input = base[, ncol(base):1], expected = a$values[, ncol(a$values):1]),
    binary_scaling = list(input = base * 2^500, expected = a$values))
  if (s$order == 0L) variants$zero_order_background <- list(input = base + 2^30, expected = a$values)
  for (name in names(variants)) {
    v <- variants[[name]]
    actual <- do.call(mssr, c(list(x = v$input), s))
    err <- error_score(actual$values, v$expected)
    meta[[length(meta) + 1L]] <- data.frame(case = i, property = name, error = err, passed = err <= 1e-11)
  }
  s$intensity_normalize <- TRUE
  weighted <- do.call(mssr, c(list(x = base), s))
  scaled <- do.call(mssr, c(list(x = base * 2^500), s))
  err <- error_score(scaled$values / 2^500, weighted$values)
  meta[[length(meta) + 1L]] <- data.frame(case = i, property = "weighted_homogeneity", error = err,
                                        passed = err <= 1e-11)
  co <- mssr_coords(a)
  independent_axis <- function(n) {
    if (s$grid == "extent") seq_len(n * s$amp) / s$amp + (0.5 - 0.5 / s$amp)
    else seq(1, n, length.out = n * s$amp)
  }
  err <- max(abs(co$row - independent_axis(nrow(base))), abs(co$col - independent_axis(ncol(base))))
  meta[[length(meta) + 1L]] <- data.frame(case = i, property = "coordinates", error = err, passed = err <= 1e-14)
}
metamorphic <- do.call(rbind, meta)
utils::write.csv(metamorphic, file.path(out, "metamorphic_results.csv"), row.names = FALSE)

# Mutants are isolated in private environments, never written into production.
engine_text <- readLines(file.path(package, "R", "engine.R"), warn = FALSE)
mutants <- c("orientation", "global_normalizer", "kernel_support", "grid", "rounding",
             "conditioning", "skipped_step", "weighting", "spatial_bandwidth")
mutation_rows <- list()
for (mutation in mutants) {
  env <- new.env(parent = asNamespace("mssrscopR"))
  src <- engine_text
  if (mutation == "global_normalizer") src <- sub("mean_shift / max(mean_shift)",
                                                 "mean_shift / mean(mean_shift)", src, fixed = TRUE)
  if (mutation == "conditioning") src <- sub("scale <- 2^exponent", "scale <- 1", src, fixed = TRUE)
  if (mutation == "skipped_step") src <- sub("skipped <- skipped + 1L",
                                              "i3[] <- 0; skipped <- skipped + 1L", src, fixed = TRUE)
  # The compiled passes cannot be edited at run time; this mutant changes the
  # spatial bandwidth they receive.
  if (mutation == "spatial_bandwidth") src <- sub("as.double(hs))", "as.double(2 * hs))", src,
                                                   fixed = TRUE)
  eval(parse(text = src), envir = env)
  sys.source(file.path(package, "R", "mssr.R"), envir = env)
  if (mutation == "kernel_support") {
    original <- env$mssr_offsets
    env$mssr_offsets <- local({ f <- original; function(hs, kernel) f(hs, "square") })
  }
  if (mutation == "grid") {
    original <- env$mssr_grid_positions
    env$mssr_grid_positions <- local({ f <- original; function(n, amp, grid) f(n, amp, "endpoint") })
  }
  if (mutation == "rounding") {
    env$mssr_half_size <- function(fwhm, amp, rounding) max(1, floor(0.5 * fwhm * amp + 0.5))
  }
  if (mutation %in% c("orientation", "weighting")) {
    original <- env$mssr_engine
    env$mssr_engine <- local({ f <- original; kind <- mutation
      function(img, amp, fwhm, order, int_norm, mesh, grid, kernel, rounding, call = NULL) {
        x <- f(img, amp, fwhm, order, if (kind == "weighting") FALSE else int_norm,
               mesh, grid, kernel, rounding, call)
        if (kind == "orientation") x$values <- x$values[nrow(x$values):1, , drop = FALSE]
        x
      }
    })
  }
  detected <- FALSE; detected_case <- ""; error <- NA_real_; condition <- ""
  for (i in which(results$passed)) {
    c <- read_case(i)
    actual <- capture_call(env$mssr, c$input, c$settings)$value
    failed <- inherits(actual, "error")
    error <- if (failed) Inf else error_score(actual$values, c$expected)
    peak <- max(abs(c$expected))
    tolerance <- 1e-11 + if (peak > 0) 2 * (2^-1074 / peak) else 0
    if (failed || !is.finite(error) || error > tolerance) {
      detected <- TRUE; detected_case <- c$case$id
      condition <- if (failed) class(actual)[1L] else "value_mismatch"
      break
    }
  }
  mutation_rows[[length(mutation_rows) + 1L]] <- data.frame(mutation = mutation, detected = detected,
    case = detected_case, error = error, disposition = if (detected) "detected" else "unexplained_escape",
    condition = condition)
}
mutations <- do.call(rbind, mutation_rows)
utils::write.csv(mutations, file.path(out, "mutation_disposition.csv"), row.names = FALSE)
writeLines(utils::capture.output(utils::sessionInfo()), file.path(out, "sessionInfo.txt"))
core <- plan$cases$order <= 3L
summary <- list(scope = if (core_only) "bounded_synthetic_core_orders_0_to_3" else "full_sampled_domain",
  full_sampled_domain_passed = all(results$passed),
  core_cases = sum(core), core_passed = sum(results$passed[core]),
  oracle_cases = nrow(results), oracle_passed = sum(results$passed),
  maximum_normalized_error = max(results$normalized_max_error),
  metamorphic_checks = nrow(metamorphic), metamorphic_passed = sum(metamorphic$passed),
  mutations = nrow(mutations), mutations_detected = sum(mutations$detected),
  implementation_cases = nrow(agreement),
  implementation_identical = sum(agreement$identical_values),
  implementation_max_difference = max(c(0, agreement$normalized_difference), na.rm = TRUE),
  implementation_agreement_passed = agreement_passed,
  mask_comparisons = length(masks),
  mask_comparisons_with_differences = sum(vapply(masks, function(x) x$differing_selected_pixels > 0, logical(1))))
jsonlite::write_json(summary, file.path(out, "summary.json"), pretty = TRUE, auto_unbox = TRUE, digits = NA)
print(summary)
stopifnot(all(results$passed[if (core_only) core else rep(TRUE, nrow(results))]),
          all(metamorphic$passed), all(mutations$detected), agreement_passed)
