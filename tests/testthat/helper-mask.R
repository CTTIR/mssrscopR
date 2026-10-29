# Masks that reach into ties or near-zero scores on purpose, in tests of other
# properties; the warning itself is tested in test-mask.R.
mask_quietly <- function(...) {
  withCallingHandlers(mssr_mask(...), mssrscopR_warning_mask_ties = function(w) {
    invokeRestart("muffleWarning")
  })
}
