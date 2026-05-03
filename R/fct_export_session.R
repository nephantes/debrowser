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

#' Build the structured block list consumed by emit_r_script() / emit_rmd().
#'
#' Pure transformation from a plain-list `state` snapshot (collected by
#' the Shiny export module on download click) into a structured block list:
#' `list(meta, load, filter, batch, de, enrichment)`. Each `de` entry is one
#' comparison; `enrichment` is NULL when the user has not loaded gene sets.
#'
#' The transformation adds two fields per `de` block that the emitters need
#' but the snapshot doesn't carry: `cond_codes` (the `Cond1/Cond2` paired
#' codes that the live app's `prep_comparison_inputs()` builds from the
#' comparison's 1-based slot) and `safe_label` (the sanitized comparison
#' label used as a TSV filename component).
#'
#' @param state Plain list with components `meta, load, filter, batch,
#'   comparisons, enrichment` (see spec section "State snapshot shape").
#' @return list with components `meta, load, filter, batch, de, enrichment`.
#' @keywords internal
#' @noRd
build_session_blocks <- function(state) {
  de_blocks <- lapply(seq_along(state$comparisons), function(i) {
    cmp <- state$comparisons[[i]]
    safe_treat   <- sanitize_label(cmp$treatment_label)
    safe_control <- sanitize_label(cmp$control_label)
    c(cmp, list(
      cond_codes = c(paste0("Cond", 2L * i - 1L),
                     paste0("Cond", 2L * i)),
      safe_label = paste0(safe_treat, "_vs_", safe_control)
    ))
  })
  # Dedupe collisions: when two comparisons produce the same safe_label,
  # later ones get _2, _3, ... suffixes. Same intent as the live-app
  # comparison_labels() helper from R/fct_method_concordance.R but operating
  # on the filename-safe form.
  labels <- vapply(de_blocks, function(b) b$safe_label, character(1))
  for (j in seq_along(labels)) {
    if (sum(labels[seq_len(j)] == labels[j]) > 1L) {
      n <- sum(labels[seq_len(j)] == labels[j])
      de_blocks[[j]]$safe_label <- paste0(labels[j], "_", n)
    }
  }
  list(
    meta       = state$meta,
    load       = state$load,
    filter     = state$filter,
    batch      = state$batch,
    de         = de_blocks,
    enrichment = state$enrichment
  )
}
