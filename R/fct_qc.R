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
#' Identifies rows whose rownames match `pattern` (default catches the common
#' human/mouse MT- prefixes) and reports each sample's MT count, total
#' count, and MT percentage.
#'
#' @param counts Numeric matrix or data.frame (rows = features,
#'   cols = samples).
#' @param pattern Regex applied to `rownames(counts)`.
#' @return data.frame with columns `sample`, `mt_count`, `total`, `mt_pct`.
#'   Zero rows if no rownames match `pattern`.
#' @examples
#' m <- matrix(c(1, 2, 0, 4, 5, 0), nrow = 3,
#'             dimnames = list(c("MT-X", "ACTB", "GAPDH"), c("a", "b")))
#' mt_pct_per_sample(m)
#' @export
mt_pct_per_sample <- function(counts, pattern = "^(MT-|mt-|Mt-)") {
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
