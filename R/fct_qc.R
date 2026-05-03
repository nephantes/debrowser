#' Per-sample library depth summary.
#'
#' Computes column sums (sequencing depth) for a count matrix, optionally
#' annotates each sample with a group label from a metadata data.frame, and
#' flags outliers using a 2-sigma rule on the depth values.
#'
#' @param counts Numeric matrix or data.frame (rows = features,
#'   cols = samples).
#' @param meta Optional data.frame with at least a `samples` column matching
#'   `colnames(counts)` plus the column named in `group_col`. If NULL,
#'   `group` is `NA_character_` for every sample.
#' @param group_col Name of the column in `meta` to use as the group label.
#'   Ignored if `meta` is NULL.
#' @return data.frame with columns `sample`, `depth`, `group`,
#'   `is_outlier_2sd` (one row per sample, ordered as `colnames(counts)`).
#' @examples
#' m <- matrix(rpois(60, lambda = 10), nrow = 10,
#'             dimnames = list(NULL, paste0("s", 1:6)))
#' library_depth_summary(m)
#' @export
library_depth_summary <- function(counts, meta = NULL, group_col = NULL) {
  if (!is_count_matrix(counts)) {
    de_error(
      "counts must be a numeric matrix or data.frame with >= 1 column",
      class = "qc_input_error"
    )
  }
  if (is.data.frame(counts)) counts <- as.matrix(counts)

  samples <- colnames(counts)
  if (is.null(samples)) samples <- paste0("V", seq_len(ncol(counts)))
  depth <- colSums(counts)

  group <- rep(NA_character_, length(samples))
  if (!is.null(meta) && !is.null(group_col)) {
    if (!is.data.frame(meta)) {
      de_error("meta must be a data.frame", class = "qc_input_error")
    }
    if (!"samples" %in% colnames(meta)) {
      de_error(
        "meta must have a 'samples' column matching colnames(counts)",
        class = "qc_input_error"
      )
    }
    if (!group_col %in% colnames(meta)) {
      de_error(
        sprintf("meta has no column named '%s'", group_col),
        class = "qc_input_error"
      )
    }
    if (nrow(meta) != ncol(counts)) {
      de_error(
        sprintf(
          "meta has %d rows but counts has %d columns",
          nrow(meta), ncol(counts)
        ),
        class = "qc_input_error"
      )
    }
    idx <- match(samples, meta$samples)
    if (anyNA(idx)) {
      de_error(
        "not all colnames(counts) found in meta$samples",
        class = "qc_input_error"
      )
    }
    group <- as.character(meta[[group_col]][idx])
  }

  data.frame(
    sample = samples,
    depth = as.numeric(depth),
    group = group,
    is_outlier_2sd = flag_outliers_2sd(as.numeric(depth)),
    stringsAsFactors = FALSE
  )
}

#' Per-sample gene detection rate.
#'
#' Counts the number of features with values strictly greater than
#' `threshold` per sample and reports detection percentage.
#'
#' @param counts Numeric matrix or data.frame (rows = features,
#'   cols = samples).
#' @param threshold Detection threshold (default 0). A feature is "detected"
#'   in a sample iff its value is strictly greater than `threshold`.
#' @return data.frame with columns `sample`, `n_detected`, `total_features`,
#'   `detection_pct` (one row per sample).
#' @examples
#' m <- matrix(c(0, 0, 5, 5, 0, 5), nrow = 3,
#'             dimnames = list(NULL, c("a", "b")))
#' detection_rate(m)
#' @export
detection_rate <- function(counts, threshold = 0) {
  if (!is_count_matrix(counts)) {
    de_error(
      "counts must be a numeric matrix or data.frame with >= 1 column",
      class = "qc_input_error"
    )
  }
  if (is.data.frame(counts)) counts <- as.matrix(counts)

  samples <- colnames(counts)
  if (is.null(samples)) samples <- paste0("V", seq_len(ncol(counts)))
  total <- nrow(counts)
  n_detected <- colSums(counts > threshold)
  pct <- if (total > 0L) 100 * n_detected / total else rep(0, length(samples))

  data.frame(
    sample = samples,
    n_detected = as.numeric(n_detected),
    total_features = total,
    detection_pct = as.numeric(pct),
    stringsAsFactors = FALSE
  )
}

#' Per-sample mitochondrial-transcript percentage.
#'
#' Identifies mitochondrial-genome rows by matching `rownames(counts)` against
#' a curated list of MT gene symbols across the common naming conventions:
#' human HGNC (`MT-ND1`, `MT-CO1`), mouse MGI (`mt-Nd1`, `mt-Co1`), the
#' dash-stripped Ensembl-style variants (`MTND1`, `mtNd1`), and the
#' prefix-stripped suffixes (`ND1`, `Nd1`). Avoids false positives like
#' `Mtor`, `Mthfr`, `Atp6v0a1` by anchoring to the exact suffix set.
#'
#' Returns each sample's mitochondrial count, total count, and MT percentage.
#'
#' @param counts Numeric matrix or data.frame (rows = features,
#'   cols = samples).
#' @param pattern Optional regex to override the default matcher. If NULL
#'   (the default), the curated MT symbol list is used.
#' @return data.frame with columns `sample`, `mt_count`, `total`, `mt_pct`.
#'   Zero rows if no rownames match.
#' @examples
#' m <- matrix(c(1, 2, 0, 4, 5, 0), nrow = 3,
#'             dimnames = list(c("MT-ND1", "ACTB", "GAPDH"), c("a", "b")))
#' mt_pct_per_sample(m)
#' # mouse MGI (with or without the dash) also matches:
#' m2 <- matrix(c(3, 0, 7, 0), nrow = 2,
#'              dimnames = list(c("mt-Nd1", "Actb"), c("a", "b")))
#' mt_pct_per_sample(m2)
#' @export
mt_pct_per_sample <- function(counts, pattern = NULL) {
  if (is.null(pattern)) pattern <- mt_default_pattern()
  if (!is_count_matrix(counts)) {
    de_error(
      "counts must be a numeric matrix or data.frame with >= 1 column",
      class = "qc_input_error"
    )
  }
  if (is.data.frame(counts)) counts <- as.matrix(counts)

  rn <- rownames(counts)
  mt_rows <- if (is.null(rn)) logical(0) else grepl(pattern, rn)

  if (!any(mt_rows)) {
    return(data.frame(
      sample = character(0),
      mt_count = numeric(0),
      total = numeric(0),
      mt_pct = numeric(0),
      stringsAsFactors = FALSE
    ))
  }

  samples <- colnames(counts)
  if (is.null(samples)) samples <- paste0("V", seq_len(ncol(counts)))
  mt_count <- colSums(counts[mt_rows, , drop = FALSE])
  total <- colSums(counts)
  mt_pct <- ifelse(total > 0, 100 * mt_count / total, 0)

  data.frame(
    sample = samples,
    mt_count = as.numeric(mt_count),
    total = as.numeric(total),
    mt_pct = as.numeric(mt_pct),
    stringsAsFactors = FALSE
  )
}

#' Sample-to-sample distance matrix from variance-stabilized counts.
#'
#' Applies DESeq2's variance-stabilizing transformation
#' (\code{\link[DESeq2]{vst}} when `nrow(counts) >= 30`, otherwise
#' \code{\link[DESeq2]{varianceStabilizingTransformation}}) and computes
#' euclidean distances between samples on the transformed scale. Falls back
#' to `log2(counts + 1)` if vst fails (e.g., all-zero rows).
#'
#' @param counts Numeric matrix or data.frame (rows = features,
#'   cols = samples).
#' @return Symmetric numeric matrix of size
#'   `ncol(counts) x ncol(counts)`, diagonal = 0, dimnames =
#'   `colnames(counts)` on both axes.
#' @examples
#' \donttest{
#' m <- matrix(rpois(600, lambda = 10), nrow = 100,
#'             dimnames = list(NULL, paste0("s", 1:6)))
#' d <- sample_distance_matrix(m)
#' isSymmetric(d)
#' }
#' @importFrom DESeq2 vst varianceStabilizingTransformation
#' @export
sample_distance_matrix <- function(counts) {
  if (!is_count_matrix(counts)) {
    de_error(
      "counts must be a numeric matrix or data.frame with >= 1 column",
      class = "qc_input_error"
    )
  }
  if (is.data.frame(counts)) counts <- as.matrix(counts)

  storage.mode(counts) <- "integer"

  transformed <- tryCatch({
    if (nrow(counts) >= 30L) {
      DESeq2::vst(counts, blind = TRUE)
    } else {
      DESeq2::varianceStabilizingTransformation(counts, blind = TRUE)
    }
  }, error = function(e) {
    log2(counts + 1)
  })

  d <- as.matrix(stats::dist(t(transformed)))
  diag(d) <- 0
  dimnames(d) <- list(colnames(counts), colnames(counts))
  d
}

#' Flag values further than 2 standard deviations from the mean.
#'
#' Pure helper used by \code{\link{library_depth_summary}}. NA values map
#' to FALSE in the output. Returns all FALSE if `length(x) < 2` or if the
#' standard deviation is zero.
#'
#' @param x Numeric vector.
#' @return Logical vector the same length as `x`. TRUE iff
#'   `abs(x - mean(x, na.rm = TRUE)) > 2 * sd(x, na.rm = TRUE)`.
#' @examples
#' flag_outliers_2sd(c(1, 1, 1, 1, 1, 10))
#' flag_outliers_2sd(c(1, 1, 1, 1))           # zero variance -> all FALSE
#' flag_outliers_2sd(c(NA, 1, 1, 1, 10))      # NA position -> FALSE
#' @export
flag_outliers_2sd <- function(x) {
  if (length(x) < 2L) return(rep(FALSE, length(x)))
  m <- mean(x, na.rm = TRUE)
  s <- stats::sd(x, na.rm = TRUE)
  if (!is.finite(s) || s == 0) return(rep(FALSE, length(x)))
  out <- abs(x - m) > 2 * s
  out[is.na(out)] <- FALSE
  out
}

# Internal: regex matching mitochondrial gene symbols across the common
# naming conventions. Anchored to a curated suffix set so we never trip on
# nuclear genes whose names happen to start with "MT" or "Mt" (Mtor, Mthfr,
# Atp6v0a1, etc.).
#
# Suffixes covered (case-insensitive in spirit, listed both cases):
#   - 13 protein-coding mtDNA genes:
#       human: ND1..ND6, ND4L, CYTB/CYB, CO1..CO3, COX1..COX3, ATP6, ATP8
#       mouse: Nd1..Nd6, Nd4l, Cytb,     Co1..Co3,             Atp6, Atp8
#   - 2 mt-rRNAs: RNR1, RNR2 / Rnr1, Rnr2
# Prefix forms accepted: "MT-", "Mt-", "mt-" (canonical), "MT_", "Mt_", "mt_"
# (rare), "MT", "Mt", "mt" (Ensembl no-dash, e.g. MTND1 / mtNd1), or no
# prefix at all (`ND1`, `Nd1`).
#' @noRd
mt_default_pattern <- function() {
  human_suffix <- c(
    "ND1", "ND2", "ND3", "ND4", "ND4L", "ND5", "ND6",
    "CYTB", "CYB",
    "CO1", "CO2", "CO3",
    "COX1", "COX2", "COX3",
    "ATP6", "ATP8",
    "RNR1", "RNR2"
  )
  mouse_suffix <- c(
    "Nd1", "Nd2", "Nd3", "Nd4", "Nd4l", "Nd5", "Nd6",
    "Cytb", "Cyb",
    "Co1", "Co2", "Co3",
    "Atp6", "Atp8",
    "Rnr1", "Rnr2"
  )
  suffix <- paste(c(human_suffix, mouse_suffix), collapse = "|")
  paste0("^(MT[-_]?|Mt[-_]?|mt[-_]?)?(", suffix, ")$")
}

#' Per-sample size-factor vs. library-size summary.
#'
#' Pulls the size factors that DESeq2 estimated for the comparison and the
#' raw library sizes from the same `DESeqDataSet`, returned in a tidy
#' data.frame plus `sf_scaled`/`lib_scaled` columns rescaled to [0,1] for
#' a side-by-side bar comparison. Spearman's rho between size factor and
#' library size is attached as `attr(out, "spearman_rho")`; values close
#' to 1 confirm DESeq2 picked up depth differences without unexpected
#' per-sample composition shifts.
#'
#' @param dds A fitted `DESeqDataSet`.
#' @return data.frame with columns `sample`, `size_factor`, `library_size`,
#'   `sf_scaled`, `lib_scaled`. Attribute `spearman_rho` holds the rank
#'   correlation between size factor and library size (NA for n < 2).
#' @examples
#' \dontrun{
#' size_factor_library_summary(dds)
#' }
#' @importFrom DESeq2 sizeFactors counts
#' @export
size_factor_library_summary <- function(dds) {
  if (is.null(dds)) {
    de_error(
      "dds must be a fitted DESeqDataSet, not NULL",
      class = "qc_input_error"
    )
  }
  sf <- DESeq2::sizeFactors(dds)
  if (is.null(sf)) {
    de_error(
      "dds has no estimated size factors",
      class = "qc_input_error"
    )
  }
  cnt <- DESeq2::counts(dds)
  lib <- colSums(cnt)
  rho <- if (length(sf) >= 2L) {
    suppressWarnings(stats::cor(sf, lib, method = "spearman"))
  } else {
    NA_real_
  }
  sf_max <- max(sf, na.rm = TRUE)
  lib_max <- max(lib, na.rm = TRUE)
  out <- data.frame(
    sample = if (is.null(names(sf))) colnames(cnt) else names(sf),
    size_factor = unname(sf),
    library_size = unname(lib),
    sf_scaled = if (is.finite(sf_max) && sf_max > 0) unname(sf) / sf_max else unname(sf),
    lib_scaled = if (is.finite(lib_max) && lib_max > 0) unname(lib) / lib_max else unname(lib),
    stringsAsFactors = FALSE
  )
  attr(out, "spearman_rho") <- rho
  out
}

#' Per-sample Cook's distance outlier counts.
#'
#' Counts how many genes in each sample have a Cook's distance above a
#' threshold; samples with disproportionately many high-Cook genes drove
#' DE calls more than their share and may warrant a downstream re-check.
#' Default threshold is the canonical DESeq2 vignette cut,
#' `4 / (n_samples - n_params)`, where `n_params` is the column count of
#' `model.matrix(design(dds), colData(dds))`. The chosen threshold is
#' attached as `attr(out, "threshold")`.
#'
#' @param dds A fitted `DESeqDataSet`. Must carry the `cooks` assay (i.e.
#'   `DESeq()` was run); otherwise raises `qc_input_error`.
#' @param threshold Optional numeric Cook's-distance cut. NULL (default)
#'   uses the DESeq2 vignette cut.
#' @return data.frame with columns `sample`, `n_high_cooks`, `total_genes`,
#'   `high_cooks_pct`. The active threshold is attached as
#'   `attr(out, "threshold")`.
#' @examples
#' \dontrun{
#' cooks_outlier_summary(dds)
#' }
#' @importFrom SummarizedExperiment assays colData
#' @importFrom DESeq2 design
#' @export
cooks_outlier_summary <- function(dds, threshold = NULL) {
  if (is.null(dds)) {
    de_error(
      "dds must be a fitted DESeqDataSet, not NULL",
      class = "qc_input_error"
    )
  }
  cooks_mat <- SummarizedExperiment::assays(dds)[["cooks"]]
  if (is.null(cooks_mat)) {
    de_error(
      "dds has no 'cooks' assay (was DESeq() called?)",
      class = "qc_input_error"
    )
  }
  n_samples <- ncol(cooks_mat)
  total_genes <- nrow(cooks_mat)
  if (is.null(threshold)) {
    coldat <- as.data.frame(SummarizedExperiment::colData(dds))
    n_params <- tryCatch(
      ncol(stats::model.matrix(DESeq2::design(dds), data = coldat)),
      error = function(e) 1L
    )
    denom <- n_samples - n_params
    if (!is.finite(denom) || denom <= 0L) denom <- 1L
    threshold <- 4 / denom
  }
  n_high <- colSums(cooks_mat > threshold, na.rm = TRUE)
  out <- data.frame(
    sample = colnames(cooks_mat),
    n_high_cooks = unname(n_high),
    total_genes = total_genes,
    high_cooks_pct = if (total_genes > 0L) {
      100 * unname(n_high) / total_genes
    } else {
      rep(0, n_samples)
    },
    stringsAsFactors = FALSE
  )
  attr(out, "threshold") <- threshold
  out
}

#' Subset a count matrix to a user-selected column list.
#'
#' Mirrors the QC sidebar's column-selector contract: NULL `selected`
#' (the pre-render state) returns `counts` unchanged; otherwise keeps
#' only the columns whose name is in `selected`. Empty intersection
#' returns a zero-column matrix (matches \code{getSelectedCols} on an
#' empty selection).
#'
#' @param counts Numeric matrix or data.frame, or NULL.
#' @param selected Character vector of sample names to keep, or NULL.
#' @return The subset matrix (or `counts` unchanged if `selected` is
#'   NULL); NULL passes through.
#' @examples
#' m <- matrix(1:6, nrow = 2,
#'             dimnames = list(NULL, c("a", "b", "c")))
#' qc_keep_cols(m, c("a", "c"))
#' qc_keep_cols(m, NULL)  # unchanged
#' @export
qc_keep_cols <- function(counts, selected = NULL) {
  if (is.null(counts)) return(NULL)
  if (is.null(selected)) return(counts)
  keep <- intersect(colnames(counts), selected)
  counts[, keep, drop = FALSE]
}

#' Subset a sample-metadata data.frame by a user-selected column list.
#'
#' Companion to \code{\link{qc_keep_cols}}: keeps the rows of `meta`
#' whose `samples` column matches `selected`. NULL `selected` returns
#' `meta` unchanged. NULL `meta` passes through. If `meta` has no
#' `samples` column, returns it unchanged.
#'
#' @param meta data.frame with a `samples` column, or NULL.
#' @param selected Character vector of sample names to keep, or NULL.
#' @return The subset data.frame, or `meta` unchanged when there is
#'   nothing to do; NULL passes through.
#' @examples
#' m <- data.frame(samples = c("a", "b", "c"), x = 1:3)
#' qc_keep_meta_rows(m, c("a", "c"))
#' @export
qc_keep_meta_rows <- function(meta, selected = NULL) {
  if (is.null(meta)) return(NULL)
  if (is.null(selected)) return(meta)
  if (!"samples" %in% colnames(meta)) return(meta)
  meta[meta$samples %in% selected, , drop = FALSE]
}

# Internal: TRUE iff x is a matrix or data.frame with >= 1 column and all
# numeric content.
#' @noRd
is_count_matrix <- function(x) {
  if (is.matrix(x)) {
    return(ncol(x) >= 1L && is.numeric(x))
  }
  if (is.data.frame(x)) {
    return(ncol(x) >= 1L && all(vapply(x, is.numeric, logical(1))))
  }
  FALSE
}
