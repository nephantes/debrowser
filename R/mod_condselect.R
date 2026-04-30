# R/mod_condselect.R
#
# Comparison-Selection wizard module. Replaces the legacy
# debrowsercondselectServer / condSelectUI in R/condSelect.R.
# Pure helpers live in R/fct_condselect.R; the DE runner in
# R/prep_data_container.R.

#' Comparison-Selection wizard UI.
#'
#' @param id module namespace id.
#' @return a `de_card` containing the wizard's static skeleton; comparison
#'   panels are rendered dynamically by `condSelectServer` via
#'   `uiOutput("comparison_panels")`.
#' @export
condSelectUI <- function(id) {
  ns <- shiny::NS(id)
  de_card(
    title = "Comparison Selection",
    shiny::uiOutput(ns("comparison_panels")),
    shiny::fluidRow(
      shiny::column(
        12,
        actionButtonDE(ns("add_btn"), "Add another comparison",
                       styleclass = "primary"),
        actionButtonDE(ns("rm_btn"), "Remove last", styleclass = "primary"),
        getHelpButton("method",
                      "http://debrowser.readthedocs.io/en/master/deseq/deseq.html"),
        actionButtonDE(ns("startDE"), "Start DE", styleclass = "primary")
      )
    )
  )
}
