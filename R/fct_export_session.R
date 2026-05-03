# R/fct_export_session.R
#
# Pure helpers for reproducible session export (R script + RMarkdown report).
# Tested in tests/testthat/test-fct-export-session.R.

#' Sanitize a comparison label for use in a filename.
#'
#' Replaces every character that is not alphanumeric, dot, underscore, or
#' hyphen with a single underscore. Used by the export emitters when building
#' per-comparison TSV filenames so that labels like "treated vs control" or
#' "high dose / low dose" produce safe paths.
#'
#' @param label character(1).
#' @return character(1).
#' @keywords internal
#' @noRd
sanitize_label <- function(label) {
  gsub("[^A-Za-z0-9._-]", "_", label)
}
