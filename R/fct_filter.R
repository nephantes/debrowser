#' Filter low-count rows from a count matrix.
#'
#' @param counts Numeric matrix (genes x samples).
#' @param method One of "max", "mean", "cpm".
#' @param cutoff Numeric threshold; meaning depends on `method`.
#' @param min_samples For method="cpm": the row is kept if CPM > cutoff in
#'   at least `min_samples` samples. Defaults to `ncol(counts) - 1`.
#' @return Filtered count matrix (rows preserved by row order).
#' @examples
#' m <- matrix(c(1, 50, 100, 5, 80, 120,
#'               1,  2,   3, 1,  2,   3),
#'             nrow = 2, byrow = TRUE)
#' colnames(m) <- paste0("S", 1:6)
#' rownames(m) <- c("GeneA", "GeneB")
#' filter_low_counts(m, method = "max", cutoff = 10)
#' @export
filter_low_counts <- function(counts, method = "max", cutoff = 10,
                              min_samples = NULL) {
  de_assert_count_matrix(counts)
  filtd <- counts
  filtd[, colnames(filtd)] <- apply(filtd[, colnames(filtd)], 2, as.integer)

  switch(method,
    "max"  = subset(filtd, apply(filtd, 1, max, na.rm = TRUE) >= as.numeric(cutoff)),
    "mean" = subset(filtd, rowMeans(filtd, na.rm = TRUE) >= as.numeric(cutoff)),
    "cpm"  = {
      cpm <- edgeR::cpm(filtd)
      ns <- if (is.null(min_samples)) ncol(filtd) - 1L else as.integer(min_samples)
      subset(filtd, rowSums(cpm > as.numeric(cutoff), na.rm = TRUE) >= ns)
    },
    de_error(
      paste0("Unknown filter method: ", method),
      class = "unknown_filter_method"
    )
  )
}
