# Classed conditions via cli. Every error inherits from "mssrscopR_error" and
# every warning from "mssrscopR_warning", so callers can handle all package
# conditions, or a specific subclass, with tryCatch(). Exported functions pass
# their own call so messages name the function the user called. Messages are
# built with sprintf() and passed through cli with braces escaped, so values
# are never interpreted as glue expressions.
cli_text_escape <- function(x) gsub("}", "}}", gsub("{", "{{", x, fixed = TRUE), fixed = TRUE)

mssr_abort <- function(subclass, message, call = NULL) {
  cli::cli_abort(cli_text_escape(message),
                 class = c(paste0("mssrscopR_error_", subclass), "mssrscopR_error"),
                 call = call)
}

mssr_warn <- function(subclass, message) {
  cli::cli_warn(cli_text_escape(message),
                class = c(paste0("mssrscopR_warning_", subclass), "mssrscopR_warning"))
}

# Scalar argument checks used by the exported functions.
plain_real <- function(x) {
  typeof(x) %in% c("integer", "double") && !is.object(x)
}

check_whole <- function(x, name, lower, upper = Inf, call = NULL) {
  ok <- plain_real(x) && length(x) == 1L && is.finite(x) &&
    x == round(x) && x >= lower && x <= upper
  if (!ok) {
    msg <- sprintf("`%s` must be a single whole number between %s and %s.", name, lower, upper)
    mssr_abort("parameter", msg, call)
  }
  as.integer(x)
}

check_positive <- function(x, name, call = NULL, allow_zero = FALSE) {
  ok <- plain_real(x) && length(x) == 1L && is.finite(x) && (x > 0 || (allow_zero && x == 0))
  if (!ok) {
    kind <- if (allow_zero) "non-negative" else "positive"
    mssr_abort("parameter", sprintf("`%s` must be a single %s number.", name, kind), call)
  }
  x
}

check_flag <- function(x, name, call = NULL) {
  if (!is.logical(x) || length(x) != 1L || is.na(x)) {
    mssr_abort("parameter", sprintf("`%s` must be TRUE or FALSE.", name), call)
  }
  x
}

check_matrix <- function(x, call = NULL) {
  if (is.data.frame(x)) {
    mssr_abort("input", "`x` must be a numeric matrix, not a data frame.", call)
  }
  if (!is.null(dim(x)) && length(dim(x)) > 2L) {
    msg <- sprintf("`x` has %d dimensions; process one 2D frame at a time (no axis is inferred).",
                   length(dim(x)))
    mssr_abort("input", msg, call)
  }
  if (!is.matrix(x) || !plain_real(x)) {
    mssr_abort("input", paste("`x` must be a plain integer or double matrix, without an",
                              "explicit class, with rows = y and columns = x."), call)
  }
  if (nrow(x) < 1L || ncol(x) < 1L) {
    mssr_abort("input", "`x` must have at least one row and one column.", call)
  }
  if (any(!is.finite(x))) {
    mssr_abort("nonfinite",
               "`x` contains NA, NaN or infinite values; MSSR is undefined for them.", call)
  }
  storage.mode(x) <- "double"
  dimnames(x) <- NULL
  x
}

check_result <- function(result, call = NULL) {
  fail <- function() {
    mssr_abort("input", "`result` must contain a finite matrix and a consistent MSSR grid.", call)
  }
  if (!inherits(result, "mssr_result") || !is.list(result) ||
        anyDuplicated(names(result))) {
    fail()
  }
  v <- result[["values"]]
  tr <- result[["transform"]]
  if (!is.matrix(v) || !plain_real(v) || any(dim(v) < 1L) ||
        any(!is.finite(v)) || !is.list(tr) || is.object(tr) ||
        anyDuplicated(names(tr))) {
    fail()
  }
  vector_ok <- function(x, n) {
    plain_real(x) && is.null(dim(x)) && length(x) == n && all(is.finite(x))
  }
  dims <- tr[["input_dim"]]
  amp <- tr[["amp"]]
  grid <- tr[["grid"]]
  if (!vector_ok(dims, 2L) || any(dims < 1 | dims != round(dims)) ||
        !vector_ok(amp, 1L) || amp < 1 || amp > 64 || amp != round(amp) ||
        !is.character(grid) || is.object(grid) || length(grid) != 1L ||
        is.na(grid) || !grid %in% c("extent", "endpoint")) {
    fail()
  }
  out <- tr[["output_dim"]]
  if (!vector_ok(out, 2L) || any(out != dim(v)) ||
        any(as.double(dims) * amp != dim(v)) ||
        (grid == "endpoint" && amp > 1L && min(dims) < 2L)) {
    fail()
  }
  same <- function(x, expected) {
    vector_ok(x, length(expected)) && all(x == expected)
  }
  first <- if (grid == "extent") rep(0.5 / amp + 0.5, 2L) else c(1, 1)
  spacing <- if (grid == "extent") {
    rep(1 / amp, 2L)
  } else {
    ifelse(dims > 1, (dims - 1) / (dims * amp - 1), 1)
  }
  extent <- c(0.5, dims[1] + 0.5, 0.5, dims[2] + 0.5)
  if (!same(tr[["first_center"]], first) || !same(tr[["spacing"]], spacing) ||
        !same(tr[["field_of_view"]], extent)) {
    fail()
  }
  invisible(result)
}
