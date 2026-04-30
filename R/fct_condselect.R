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

#' Compute initial side labels for a comparison.
#'
#' Returns a named character(2) `c(treatment = ..., control = ...)`. When
#' a metadata column with two non-NA levels is supplied, the level names are
#' used directly. Otherwise falls back to the literal "Treatment" / "Control".
#'
#' @noRd
default_side_labels <- function(meta_column, treatment_level, control_level) {
  if (!is.na(meta_column) && !is.na(treatment_level) && !is.na(control_level)) {
    return(c(treatment = treatment_level, control = control_level))
  }
  c(treatment = "Treatment", control = "Control")
}

#' Halve a sample-name vector into default treatment / control halves.
#'
#' Replaces the legacy `getSampleNames(cnames, part)` and fixes its `1:0`
#' index-reversal quirk at length 1. The first half (length floor(n/2)) is
#' assigned to treatment, the rest to control. At n = 1 treatment is empty
#' and control gets the single sample.
#'
#' @param sample_names character vector of column names from the count matrix.
#' @return list with components `treatment` and `control`, or NULL on NULL input.
#' @noRd
halve_sample_names <- function(sample_names) {
  if (is.null(sample_names)) return(NULL)
  n <- length(sample_names)
  if (n == 0L) return(list(treatment = character(0), control = character(0)))
  cut <- floor(n / 2L)
  list(
    treatment = if (cut >= 1L) sample_names[seq_len(cut)] else character(0),
    control   = if (cut + 1L <= n) sample_names[(cut + 1L):n] else character(0)
  )
}
