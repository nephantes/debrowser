# R/mod_enrichment_nes_heatmap.R
#
# NES heatmap card for the Enrichment tab. Consumes a long-format
# data.frame produced by nes_heatmap_data(); reusable for E11's
# cross-method NES heatmap without modification.

#' UI for the NES heatmap card.
#'
#' Renders only when [enrichmentServer] passes more than one comparison's
#' GSEA results.
#'
#' @param id Module ID.
#' @return A `bslib::card`.
#' @export
enrichmentNesHeatmapUI <- function(id) {
  ns <- shiny::NS(id)
  bslib::card(
    bslib::card_header("NES heatmap"),
    bslib::card_body(
      shiny::plotOutput(ns("heatmap"), height = "500px"),
      shiny::fluidRow(
        shiny::column(
          3,
          shiny::checkboxInput(ns("flip_axis"), "Invert axes", FALSE)
        ),
        shiny::column(
          3,
          shiny::checkboxInput(ns("sig_only"), "Significant only", TRUE)
        ),
        shiny::column(
          3,
          shiny::numericInput(ns("sig_threshold"), "padj cutoff", 0.05,
                              min = 0, max = 1, step = 0.01)
        )
      )
    )
  )
}

#' Server for the NES heatmap card.
#'
#' @param id Module ID.
#' @param results_by_comparison Reactive yielding a named list of
#'   \code{\link{run_gsea}} outputs (one per comparison).
#' @return invisible(NULL).
#' @export
enrichmentNesHeatmapServer <- function(id, results_by_comparison) {
  shiny::moduleServer(id, function(input, output, session) {
    output$heatmap <- shiny::renderPlot({
      res <- results_by_comparison()
      shiny::req(length(res) >= 1L)
      long <- nes_heatmap_data(
        res,
        sig_only      = input$sig_only,
        sig_threshold = input$sig_threshold
      )
      shiny::validate(shiny::need(
        nrow(long) > 0,
        "No pathways meet the significance cutoff."
      ))

      x_var <- if (input$flip_axis) "pathway"    else "comparison"
      y_var <- if (input$flip_axis) "comparison" else "pathway"
      long$Label <- ifelse(long$padj < 0.001, "***",
                    ifelse(long$padj < 0.01,  "**",
                    ifelse(long$padj < 0.05,  "*",  "")))

      ggplot2::ggplot(
        long,
        ggplot2::aes(x = .data[[x_var]],
                     y = .data[[y_var]],
                     fill = NES,
                     label = Label)
      ) +
        ggplot2::geom_tile() +
        ggplot2::geom_text(size = 3, vjust = 0.77) +
        ggplot2::scale_fill_gradient2(
          low = "steelblue", mid = "grey96", high = "firebrick"
        ) +
        ggplot2::theme_classic() +
        ggplot2::theme(
          axis.text.x = ggplot2::element_text(angle = 90, hjust = 0),
          axis.title  = ggplot2::element_blank()
        )
    })
  })
  invisible(NULL)
}
