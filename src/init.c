#include <stdlib.h>
#include <R.h>
#include <Rinternals.h>
#include <R_ext/Rdynload.h>

SEXP mssr_neighborhood_c(SEXP x_, SEXP di_, SEXP dj_, SEXP hs_);
SEXP mssr_add_product_c(SEXP sum_, SEXP x_, SEXP y_);

static const R_CallMethodDef call_methods[] = {
  {"mssr_neighborhood_c", (DL_FUNC) &mssr_neighborhood_c, 4},
  {"mssr_add_product_c", (DL_FUNC) &mssr_add_product_c, 3},
  {NULL, NULL, 0}
};

void R_init_mssrscopR(DllInfo *dll) {
  R_registerRoutines(dll, NULL, call_methods, NULL, NULL);
  R_useDynamicSymbols(dll, FALSE);
  R_forceSymbols(dll, TRUE);
}
