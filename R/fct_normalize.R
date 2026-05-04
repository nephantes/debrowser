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
#' @examples
#' m <- matrix(as.integer(c(100, 200, 150, 80, 250, 130,
#'                          40,  60,  55, 30,  70,  45)),
#'             nrow = 2, byrow = TRUE)
#' colnames(m) <- paste0("S", 1:6)
#' rownames(m) <- c("Gene1", "Gene2")
#' normalize_counts(m, method = "TMM")
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

#' Apply batch-effect correction.
#'
#' Pure function — no Shiny dependency. Accepts batch / treatment column
#' names directly instead of pulling from a reactive `input` object.
#'
#' @param counts Numeric matrix (genes x samples).
#' @param metadata data.frame; first column is sample id.
#' @param method One of "none", "Combat", "CombatSeq", "Harman".
#' @param batch_col Name of the batch column in `metadata`.
#' @param treatment_col Name of the treatment column in `metadata`. May be
#'   NULL or "None" — only required for Harman.
#' @return Corrected count matrix.
#' @examples
#' m <- matrix(as.integer(c(100, 200, 150, 80, 250, 130,
#'                          40,  60,  55, 30,  70,  45)),
#'             nrow = 2, byrow = TRUE)
#' colnames(m) <- paste0("S", 1:6)
#' rownames(m) <- c("Gene1", "Gene2")
#' # method = "none" returns the matrix unchanged
#' apply_batch_correction(m, metadata = NULL, method = "none")
#' @export
apply_batch_correction <- function(counts, metadata, method = "none",
                                   batch_col = NULL, treatment_col = NULL) {
  de_assert_count_matrix(counts)
  if (method == "none") {
    return(counts)
  }

  if (is.null(batch_col) || !batch_col %in% colnames(metadata)) {
    de_error(
      paste0("metadata has no column '", batch_col, "'"),
      class = "missing_batch_col"
    )
  }

  switch(method,
    "Combat"    = combat_correct(counts, metadata, batch_col, treatment_col, seq = FALSE),
    "CombatSeq" = combat_correct(counts, metadata, batch_col, treatment_col, seq = TRUE),
    "Harman"    = harman_correct(counts, metadata, batch_col, treatment_col),
    de_error(
      paste0("Unknown batch correction method: ", method),
      class = "unknown_batch_method"
    )
  )
}

#' @keywords internal
combat_correct <- function(counts, metadata, batch_col, treatment_col,
                           seq = FALSE) {
  batch <- metadata[, batch_col]
  columns <- colnames(counts)
  datacor <- data.frame(counts[, columns])
  datacor[, columns] <- apply(
    datacor[, columns], 2,
    function(x) as.integer(x) + runif(1, 0, 0.01)
  )

  has_treatment <- !is.null(treatment_col) && treatment_col != "None" &&
    treatment_col %in% colnames(metadata)

  if (has_treatment) {
    treatment <- metadata[, treatment_col]
    meta <- data.frame(cbind(columns, treatment, batch))
    modcombat <- model.matrix(~ as.factor(treatment), data = meta)
    res <- if (seq) {
      sva::ComBat_seq(
        counts = as.matrix(datacor),
        covar_mod = modcombat, batch = batch
      )
    } else {
      sva::ComBat(
        dat = as.matrix(datacor),
        mod = modcombat, batch = batch
      )
    }
  } else {
    res <- if (seq) {
      sva::ComBat_seq(counts = as.matrix(datacor), batch = batch)
    } else {
      sva::ComBat(dat = as.matrix(datacor), batch = batch)
    }
  }

  out <- res
  out[out < 0] <- 0
  out[, columns] <- apply(out[, columns], 2, as.integer)
  out
}

#' @keywords internal
harman_correct <- function(counts, metadata, batch_col, treatment_col) {
  if (is.null(treatment_col) || treatment_col == "None") {
    de_error(
      "Harman requires a treatment column",
      class = "missing_treatment_col"
    )
  }
  require_pkg("Harman", feature = "Harman batch correction")
  batch_info <- data.frame(metadata[, c(treatment_col, batch_col)])
  rownames(batch_info) <- rownames(metadata)
  colnames(batch_info) <- c("treatment", "batch")

  res <- Harman::harman(counts,
    expt = batch_info$treatment,
    batch = batch_info$batch, limit = 0.95
  )
  out <- Harman::reconstructData(res)
  out[out < 0] <- 0
  out
}
