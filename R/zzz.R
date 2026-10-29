.onLoad <- function(libname, pkgname) {
  # Records the code this session loaded, for the app's background jobs. A
  # failure here must not prevent loading; jobs then snapshot on first use.
  mssr_loaded_code$files <- tryCatch(mssr_app_code_files(), error = function(e) NULL)
}
