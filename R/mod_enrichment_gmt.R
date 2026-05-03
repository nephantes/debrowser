# R/mod_enrichment_gmt.R
#
# Gene-set source picker for the Enrichment tab. E1 ships only the
# "Upload .gmt" branch; E2 will add "MSigDB" as a sibling option, plugging
# into the same reactive contract.

#' UI for the gene-set source picker (Enrichment-tab sidebar).
#'
#' @param id Module ID.
#' @return Shiny tagList for inclusion in a `bslib::accordion_panel`.
#' @export
enrichmentGmtUI <- function(id) {
  ns <- shiny::NS(id)
  shiny::tagList(
    shiny::selectizeInput(
      ns("gmt_source"), "Gene-set source:",
      choices = c("Upload .gmt" = "manual")
      # E2 will add: "MSigDB" = "msigdb"
    ),
    shiny::conditionalPanel(
      condition = sprintf("input['%s'] == 'manual'", ns("gmt_source")),
      shiny::fileInput(ns("manual_gmt"), ".gmt file:",
                       accept = c(".gmt", "text/plain"))
    )
  )
}

#' Server for the gene-set source picker.
#'
#' Returns a reactive that yields a named list of gene-symbol vectors —
#' the same shape \code{\link{gmt_to_pathways}} produces — or NULL until
#' the user has supplied a source.
#'
#' @param id Module ID.
#' @return Reactive expression yielding the parsed pathways list.
#' @export
enrichmentGmtServer <- function(id) {
  shiny::moduleServer(id, function(input, output, session) {
    shiny::reactive({
      shiny::req(input$gmt_source)
      if (input$gmt_source == "manual") {
        shiny::req(input$manual_gmt)
        gmt_to_pathways(input$manual_gmt$datapath)
      } else {
        NULL  # E2 plugs MSigDB here
      }
    })
  })
}
