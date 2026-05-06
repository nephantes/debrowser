# R/fct_condselect_restore.R
#
# Pure helper consumed by mod_condselect's onRestore (D2.4 Task 4).
# Walks a saved comparisons spec (the structure produced by the
# comparisons_spec() reactive, captured by the module's onBookmark in
# D2.3 Task 7) and returns a named list of plain-list entries.
#
# The module-side wrapper then re-promotes each entry to a
# reactiveValues so the existing card observers see a familiar shape.
# Keeping the rv promotion outside this helper makes the helper
# unit-testable without a Shiny session.

#' Convert a saved comparisons spec to a plain-list structure ready for
#' reactiveValues promotion.
#'
#' @param spec A list of per-comparison entries, each a named list
#'   with up to 10 fields. NULL or empty returns `list()`.
#' @return A named list keyed by `"1"`, `"2"`, ... matching the
#'   one-based-string convention used by `mod_condselect`'s
#'   `comparisons[[as.character(idx)]]`.
#' @keywords internal
#' @noRd
restore_comparisons_spec <- function(spec) {
  if (is.null(spec) || length(spec) == 0L) return(list())

  default_method_params <- list(
    fitType   = "parametric",
    betaPrior = FALSE,
    testType  = "LRT",
    shrinkage = "apeglm"
  )

  entry_with_defaults <- function(e) {
    if (is.null(e)) e <- list()
    list(
      meta_column       = e$meta_column %||% NA_character_,
      treatment_level   = e$treatment_level %||% NA_character_,
      control_level     = e$control_level %||% NA_character_,
      treatment_samples = e$treatment_samples %||% character(0),
      control_samples   = e$control_samples %||% character(0),
      treatment_label   = e$treatment_label %||% "treatment",
      control_label     = e$control_label %||% "control",
      de_method         = e$de_method %||% "DESeq2",
      method_params     = e$method_params %||% default_method_params,
      covariates        = e$covariates %||% character(0)
    )
  }

  out <- lapply(spec, entry_with_defaults)
  names(out) <- as.character(seq_along(out))
  out
}
