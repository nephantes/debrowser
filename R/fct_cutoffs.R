#' Default DE significance cutoffs.
#'
#' Single source of truth for the values that populate the DE cutoff
#' inputs and the prepDataForQA() fallback.
#'
#' @return Named list with components: padj, log2fc, gopvalue.
#' @export
default_cutoffs <- function() {
  list(padj = 0.01, log2fc = 1, gopvalue = 0.01)
}

#' Cutoff preset table.
#'
#' Each row defines a one-click preset for the Strict / Standard
#' button bar. log2fc is shared across presets by design -- only
#' padj differs.
#'
#' @return data.frame with columns: name, label, padj, log2fc.
#' @export
cutoff_presets <- function() {
  data.frame(
    name   = c("strict", "standard"),
    label  = c("Strict (0.01)", "Standard (0.05)"),
    padj   = c(0.01, 0.05),
    log2fc = c(1,    1),
    stringsAsFactors = FALSE
  )
}

#' Identify which preset a (padj, log2fc) pair matches.
#'
#' Uses a small numeric tolerance because numericInput round-trips
#' floats via JSON and exact equality occasionally fails.
#'
#' @param padj,log2fc Numeric scalars from the cutoff inputs.
#' @param tol Match tolerance.
#' @return Character scalar ("strict" | "standard") or NA_character_
#'   if either input is invalid or no preset matches.
#' @export
match_preset <- function(padj, log2fc, tol = 1e-9) {
  if (!is_finite_scalar(padj) || !is_finite_scalar(log2fc)) {
    return(NA_character_)
  }
  presets <- cutoff_presets()
  hit <- which(
    abs(presets$padj   - padj)   < tol &
    abs(presets$log2fc - log2fc) < tol
  )
  if (length(hit) == 1L) presets$name[hit] else NA_character_
}

#' Convert |log2FC| cutoff to fold-change cutoff.
#' @param x Numeric |log2FC| cutoff.
#' @return Fold-change cutoff (2^x).
#' @export
log2fc_to_fold <- function(x) 2^x

#' Convert fold-change cutoff to |log2FC|.
#' @param x Numeric fold-change cutoff.
#' @return |log2FC| cutoff (log2(x)).
#' @export
fold_to_log2fc <- function(x) log2(x)

# Internal: length-1, finite, non-NA, numeric.
is_finite_scalar <- function(x) {
  is.numeric(x) && length(x) == 1L && is.finite(x)
}

#' Install Shiny observers that synchronise a preset-button input
#' with the (padj, log2fc_cutoff) numeric inputs.
#'
#' Two observers are installed on the supplied session:
#' (1) a click on the `cutoff_preset` radio group fills the two
#'     numeric inputs with that preset's values;
#' (2) a manual edit on either numeric input clears the preset
#'     highlight if the resulting (padj, log2fc) pair no longer
#'     matches any preset (or selects the matching preset if it
#'     happens to match one exactly).
#'
#' The observers guard against echoing each other via an
#' `isolate()` + `!identical()` check on the current radio-group
#' selection. Both use `ignoreInit = TRUE` to avoid the page-load
#' click cascade.
#'
#' @param input,session A Shiny input/session pair (either the
#'   top-level session for the global widget, or a moduleServer
#'   session for the namespaced widget).
#' @return Invisible NULL; observers are installed as a side effect.
#' @export
install_cutoff_preset_observers <- function(input, session) {
  observeEvent(input$cutoff_preset, ignoreInit = TRUE, {
    presets <- cutoff_presets()
    row <- presets[presets$name == input$cutoff_preset, ]
    if (nrow(row) == 1L) {
      updateNumericInput(session, "padj",          value = row$padj)
      updateNumericInput(session, "log2fc_cutoff", value = row$log2fc)
    }
  })

  observeEvent(c(input$padj, input$log2fc_cutoff), ignoreInit = TRUE, {
    matched <- match_preset(input$padj, input$log2fc_cutoff)
    current <- isolate(input$cutoff_preset)
    desired <- if (is.na(matched)) character(0) else matched
    if (!identical(current, desired)) {
      shinyWidgets::updateRadioGroupButtons(
        session, "cutoff_preset", selected = desired
      )
    }
  })

  invisible(NULL)
}
