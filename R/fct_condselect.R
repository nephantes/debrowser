# R/fct_condselect.R
#
# Pure helpers for the comparison-selection wizard. No Shiny dependency.
# Tested in tests/testthat/test-condselect-helpers.R and
# tests/testthat/test-condselect-validation.R.

.CONTROL_REGEX <- paste0(
  "(?i)^(",
  paste(c(
    "control", "ctrl", "wt", "wildtype", "wild_type",
    "vehicle", "dmso", "untreated", "mock", "ref",
    "naive", "baseline", "0h", "day0"
  ), collapse = "|"),
  ")$"
)

#' Infer the control-side level for a 2-level metadata column.
#'
#' Matches each level (case-insensitive, anchored) against a small list of
#' reference-shaped words. If exactly one level matches, returns it. Otherwise
#' falls back to alphabetical order so the result is always deterministic.
#'
#' @param levels character vector of metadata-column levels (≥ 2 expected).
#' @return character(1) — the level chosen as control.
#' @noRd
infer_control_level <- function(levels) {
  matches <- grepl(.CONTROL_REGEX, levels, perl = TRUE)
  if (sum(matches) == 1) {
    return(levels[matches])
  }
  sort(levels)[1]
}
