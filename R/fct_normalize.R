#' Normalize a count matrix.
#'
#' Pure function: takes a numeric matrix, returns a normalized numeric matrix.
#' Wraps `edgeR::calcNormFactors` + `edgeR::equalizeLibSizes` for
#' TMM/RLE/upper-quartile, DESeq2's median-of-ratios for `"MRN"`, identity
#' for `"none"`.
#'
#' @param counts Numeric matrix or data.frame (genes x samples).
#' @param method One of "TMM", "RLE", "upperquartile", "MRN", "none".
#' @return Normalized numeric matrix with the same shape and dimnames.
#' @export
normalize_counts <- function(counts, method = "TMM") {
  de_assert_count_matrix(counts)
  m <- counts
  m[is.na(m)] <- 0

  if (method == "none") {
    return(m)
  }
  if (method == "MRN") {
    columns <- colnames(m)
    coldata <- prepGroup(columns, columns)
    m[, columns] <- apply(m[, columns], 2, as.integer)
    dds <- DESeq2::DESeqDataSetFromMatrix(
      countData = as.matrix(m), colData = coldata, design = ~group
    )
    dds <- DESeq2::estimateSizeFactors(dds)
    return(DESeq2::counts(dds, normalized = TRUE))
  }
  norm_factors <- edgeR::calcNormFactors(m, method = method)
  edgeR::equalizeLibSizes(
    edgeR::DGEList(m, norm.factors = norm_factors)
  )$pseudo.counts
}
