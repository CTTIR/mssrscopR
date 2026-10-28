#' @keywords internal
"_PACKAGE"

# cli::cli_abort() and cli::cli_warn() need rlang, which cli only suggests.
#' @importFrom rlang abort
#' @useDynLib mssrscopR, .registration = TRUE
NULL
