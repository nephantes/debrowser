# R/fct_upload.R

#' Pure helpers for the Quick Start wizard (B2b).
#'
#' These are testthat-tested in isolation. The file has no `library()`
#' calls and no Shiny references — keep it that way.
#'
#' @keywords internal
#' @name fct_upload
NULL

#' Read up to `n` lines from a path that may be plain or gzipped.
#'
#' Strips a UTF-8 BOM if present on the first line.
#' @noRd
.read_head_lines <- function(path, n) {
  is_gz <- grepl("\\.gz$", path, ignore.case = TRUE)
  con <- if (is_gz) gzfile(path, "r") else file(path, "r")
  on.exit(close(con), add = TRUE)
  lines <- tryCatch(
    readLines(con, n = n, warn = FALSE, encoding = "UTF-8"),
    error = function(e) character(0)
  )
  if (length(lines) >= 1) {
    lines[1] <- sub("^\xef\xbb\xbf", "", lines[1], useBytes = TRUE)
  }
  lines
}

#' Score a candidate delimiter on a sample of lines.
#'
#' Splits each line on `sep`, takes the modal column count K, and
#' counts how many of columns 2..K have at least 80% numeric parse rate.
#' Treats comma as a possible decimal separator (European convention)
#' so that European-style "1,5" values count as numeric. This makes the
#' helper pick `;` for European CSVs without affecting US/UK files
#' (which have no commas inside numeric cells).
#'
#' @return integer score (number of "numeric" columns), or 0 if K < 2
#'   or the file has no usable rows.
#' @noRd
.score_separator <- function(lines, sep) {
  if (length(lines) < 2) return(0L)
  fields <- strsplit(lines, sep, fixed = TRUE)
  widths <- vapply(fields, length, integer(1))
  if (max(widths) < 2) return(0L)
  K <- as.integer(names(sort(table(widths), decreasing = TRUE))[1])
  if (is.na(K) || K < 2) return(0L)
  rows <- fields[widths == K]
  if (length(rows) < 2) return(0L)
  data_rows <- rows[-1]
  if (length(data_rows) == 0) return(0L)
  numeric_cols <- 0L
  for (j in seq.int(2L, K)) {
    vals <- vapply(data_rows, function(r) r[[j]], character(1))
    parsed <- suppressWarnings(as.numeric(sub(",", ".", vals, fixed = TRUE)))
    if (mean(!is.na(parsed)) >= 0.8) numeric_cols <- numeric_cols + 1L
  }
  numeric_cols
}

#' Auto-detect the field separator in a count-data file.
#'
#' Tries tab, comma, semicolon. Returns the highest-scoring delimiter
#' with score >= `min_score`, with the tie-break order tab > comma >
#' semicolon. Returns NA when no candidate clears the threshold.
#'
#' Decompresses `.gz` files and strips a leading UTF-8 BOM before
#' scoring. Excel files are not handled here — callers should branch
#' on extension before calling this.
#'
#' Counts files default to `min_score = 3` (3+ numeric columns is a strong
#' signal). Metadata files have only 1-2 numeric columns typically; pass
#' `min_score = 1` to keep the helper useful for them.
#'
#' @param path character, path to the file (may end in `.gz`).
#' @param sample_lines integer, number of lines to read for scoring.
#' @param min_score integer, minimum numeric-column count required to
#'   accept a candidate delimiter.
#' @return one of tab, comma, semicolon, or `NA_character_`.
#' @export
detect_separator <- function(path, sample_lines = 50L, min_score = 3L) {
  lines <- .read_head_lines(path, sample_lines)
  if (length(lines) < 2) return(NA_character_)
  candidates <- c("\t", ",", ";")
  scores <- vapply(candidates, function(s) .score_separator(lines, s), integer(1))
  best <- which.max(scores)
  if (length(best) == 0 || scores[best] < min_score) return(NA_character_)
  candidates[best]
}

#' Build a single-condition single-batch metadata data frame.
#'
#' Used as a fallback when the user uploads counts without metadata.
#' Downstream condSelect's existing "need >=2 conditions" validation
#' will surface the requirement when the user proceeds — no new
#' validation is added here.
#'
#' @param counts data frame whose column names are the sample IDs.
#' @return data frame with columns `Sample`, `Condition`, `Batch`.
#' @export
make_default_metadata <- function(counts) {
  samples <- colnames(counts)
  data.frame(
    Sample    = samples,
    Condition = if (length(samples)) "All" else character(0),
    Batch     = if (length(samples)) 1L else integer(0),
    stringsAsFactors = FALSE
  )
}

#' Validate a count-data upload file.
#'
#' Reads the file with the given separator and raises classed conditions
#' on validation failures. Designed for the upload observer to dispatch
#' on class via tryCatch.
#'
#' Raises:
#'   * `bad_separator`     — fewer than 3 columns after read (typically a
#'                           wrong-separator file).
#'   * `duplicate_gene_ids` — first column contains duplicate values; the
#'                           condition object carries field `dups`.
#'
#' Other I/O failures propagate as plain `simpleError` / `simpleWarning`
#' conditions; callers wrap with their own catch-all.
#'
#' @param path Path to the count file.
#' @param sep  Field separator string.
#' @return Invisibly returns `path` on success.
#' @keywords internal
validate_count_upload <- function(path, sep) {
  # header = FALSE (default) is intentional and matches legacy checkCountData:
  # the separator check fires when the parsed table has < 3 columns, which is
  # most reliable when the header row participates as a data row. The companion
  # validator validate_metadata_upload uses header = TRUE because metadata
  # column names are semantically required.
  data <- read.table(path, sep = sep)
  if (ncol(data) < 3) {
    de_error(
      sprintf("only %d column(s) detected in count file", ncol(data)),
      class = "bad_separator",
      n_cols = ncol(data)
    )
  }
  ids <- as.character(data[, 1])
  dups <- unique(ids[duplicated(ids, fromLast = TRUE) |
                       duplicated(ids, fromLast = FALSE)])
  if (length(dups) > 0) {
    de_error(
      sprintf("duplicate gene IDs in count file: %s",
              paste0(dups, collapse = ", ")),
      class = "duplicate_gene_ids",
      dups = dups
    )
  }
  invisible(path)
}
