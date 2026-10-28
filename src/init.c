#include <stdlib.h>
#include <R.h>
#include <Rinternals.h>
#include <R_ext/Rdynload.h>

SEXP mssr_neighbourhood_c(SEXP x_, SEXP di_, SEXP dj_, SEXP hs_);

static const R_CallMethodDef call_methods[] = {
  {"mssr_neighbourhood_c", (DL_FUNC) &mssr_neighbourhood_c, 4},
  {NULL, NULL, 0}
};

void R_init_mssrscopR(DllInfo *dll) {
  R_registerRoutines(dll, NULL, call_methods, NULL, NULL);
  R_useDynamicSymbols(dll, FALSE);
  R_forceSymbols(dll, TRUE);
}
