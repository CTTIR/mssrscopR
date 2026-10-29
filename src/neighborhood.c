/*
 * Neighborhood passes of engine definition "mssr_r_rev3" (see R/engine.R).
 *
 * For every output pixel p and neighborhood offset k, delta = x[p] - x[p + k]
 * with symmetric (half-sample) reflection at the frame edges. Pass 1 takes the
 * largest |delta| over all offsets (the adaptive range normalizer); pass 2
 * accumulates the spatial x range weights and the weighted differences. Both
 * passes visit the offsets in the order supplied and accumulate each pixel in
 * that order, as the R reference loop does, so the sums are formed in the same
 * sequence. Products are kept in separate statements so that a compiler that
 * contracts only within an expression does not fuse them into multiply-adds.
 *
 * No offset stack is materialized: memory is three output-sized buffers plus
 * reflected index tables of (2 * h + 1) * (rows + columns) integers.
 */
#include <math.h>
#include <R.h>
#include <Rinternals.h>

/* 0-based half-sample reflection of t into 0..n-1 (n >= 1). */
static int reflect(int t, int n) {
  if (n == 1) return 0;
  int p = 2 * n;
  int m = t % p;
  if (m < 0) m += p;
  return m < n ? m : p - m - 1;
}

/* table[(v + h) * n + i] = reflect(i + v, n) for v in -h..h. */
static int *reflect_table(int n, int h) {
  int width = 2 * h + 1;
  int *table = (int *) R_alloc((size_t) width * (size_t) n, sizeof(int));
  for (int v = -h; v <= h; v++) {
    int *row = table + (size_t) (v + h) * (size_t) n;
    for (int i = 0; i < n; i++) row[i] = reflect(i + v, n);
  }
  return table;
}

SEXP mssr_neighborhood_c(SEXP x_, SEXP di_, SEXP dj_, SEXP hs_) {
  SEXP dim = Rf_getAttrib(x_, R_DimSymbol);
  if (!Rf_isReal(x_) || Rf_length(dim) != 2) Rf_error("x must be a double matrix");
  if (!Rf_isInteger(di_) || !Rf_isInteger(dj_) || Rf_length(di_) != Rf_length(dj_)) {
    Rf_error("offsets must be integer vectors of equal length");
  }
  if (!Rf_isReal(hs_) || Rf_length(hs_) != 1) Rf_error("hs must be a double scalar");
  const int nr = INTEGER(dim)[0];
  const int nc = INTEGER(dim)[1];
  const R_xlen_t n = (R_xlen_t) nr * (R_xlen_t) nc;
  const int nk = Rf_length(di_);
  const int *di = INTEGER(di_);
  const int *dj = INTEGER(dj_);
  const double hs = REAL(hs_)[0];
  const double *x = REAL(x_);

  int h = 0;
  for (int k = 0; k < nk; k++) {
    if (di[k] == NA_INTEGER || dj[k] == NA_INTEGER) Rf_error("offsets must not be NA");
    int a = di[k] < 0 ? -di[k] : di[k];
    int b = dj[k] < 0 ? -dj[k] : dj[k];
    if (a > h) h = a;
    if (b > h) h = b;
  }
  const int *rows = reflect_table(nr, h);
  const int *cols = reflect_table(nc, h);

  SEXP range_max_ = PROTECT(Rf_allocMatrix(REALSXP, nr, nc));
  SEXP weight_sum_ = PROTECT(Rf_allocMatrix(REALSXP, nr, nc));
  SEXP difference_sum_ = PROTECT(Rf_allocMatrix(REALSXP, nr, nc));
  double *range_max = REAL(range_max_);
  double *weight_sum = REAL(weight_sum_);
  double *difference_sum = REAL(difference_sum_);
  for (R_xlen_t p = 0; p < n; p++) {
    range_max[p] = 0.0;
    weight_sum[p] = 0.0;
    difference_sum[p] = 0.0;
  }

  /* Pass 1: maximum absolute local difference. */
  for (int k = 0; k < nk; k++) {
    const int *row = rows + (size_t) (di[k] + h) * (size_t) nr;
    const int *col = cols + (size_t) (dj[k] + h) * (size_t) nc;
    for (int j = 0; j < nc; j++) {
      if ((j & 63) == 0) R_CheckUserInterrupt();
      const double *center = x + (R_xlen_t) j * nr;
      const double *shifted = x + (R_xlen_t) col[j] * nr;
      double *out = range_max + (R_xlen_t) j * nr;
      for (int i = 0; i < nr; i++) {
        double d = fabs(center[i] - shifted[row[i]]);
        if (d > out[i]) out[i] = d;
      }
    }
  }

  /* Pass 2: spatial x range weights; a zero normalizer divides by 1, where
   * every difference is zero and the ratio is the defined value 0. */
  const double hs2 = hs * hs;
  for (int k = 0; k < nk; k++) {
    const int *row = rows + (size_t) (di[k] + h) * (size_t) nr;
    const int *col = cols + (size_t) (dj[k] + h) * (size_t) nc;
    const double radius2 = (double) di[k] * (double) di[k] + (double) dj[k] * (double) dj[k];
    const double spatial = exp(-radius2 / hs2);
    for (int j = 0; j < nc; j++) {
      if ((j & 63) == 0) R_CheckUserInterrupt();
      const double *center = x + (R_xlen_t) j * nr;
      const double *shifted = x + (R_xlen_t) col[j] * nr;
      const double *norm = range_max + (R_xlen_t) j * nr;
      double *wsum = weight_sum + (R_xlen_t) j * nr;
      double *dsum = difference_sum + (R_xlen_t) j * nr;
      for (int i = 0; i < nr; i++) {
        double delta = center[i] - shifted[row[i]];
        double divisor = norm[i] == 0.0 ? 1.0 : norm[i];
        double ratio = delta / divisor;
        double ratio2 = ratio * ratio;
        double range = exp(-ratio2);
        double w = spatial * range;
        wsum[i] = wsum[i] + w;
        double product = delta * w;
        dsum[i] = dsum[i] + product;
      }
    }
  }

  SEXP out = PROTECT(Rf_allocVector(VECSXP, 3));
  SET_VECTOR_ELT(out, 0, range_max_);
  SET_VECTOR_ELT(out, 1, weight_sum_);
  SET_VECTOR_ELT(out, 2, difference_sum_);
  SEXP names = PROTECT(Rf_allocVector(STRSXP, 3));
  SET_STRING_ELT(names, 0, Rf_mkChar("range_max"));
  SET_STRING_ELT(names, 1, Rf_mkChar("weight_sum"));
  SET_STRING_ELT(names, 2, Rf_mkChar("difference_sum"));
  Rf_setAttrib(out, R_NamesSymbol, names);
  UNPROTECT(5);
  return out;
}
