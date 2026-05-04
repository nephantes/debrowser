# R/mod_enrichment.R
#
# Main Enrichment tab module (Phase E1). Lives next to the existing GO
# Term tab. E2 will fold GO Term in here as the ORA mode; E11 adds the
# "Compare methods" mode.

# Internal: pick the gene-id column name in a DE table. DEBrowser's
# legacy `addDataCols()` output uses "ID"; the gsea-explorer reference
# uses "gene". Accept either — fall back to NULL and let run_gsea raise
# a classed error.
#' @noRd
.enrichment_id_col <- function(de) {
  if ("ID"   %in% names(de)) return("ID")
  if ("gene" %in% names(de)) return("gene")
  NA_character_
}

#' UI for the Enrichment tab.
#'
#' Lives next to the existing GO Term tab. E2 will fold GO Term into here
#' as the ORA mode; E11 adds the "Compare methods" mode.
#'
#' @param id Module ID.
#' @return A `bslib::layout_sidebar` tagList.
#' @examples
#' enrichmentUI("demo")
#' @export
enrichmentUI <- function(id) {
  ns <- shiny::NS(id)
  bslib::layout_sidebar(
    sidebar = bslib::sidebar(
      width = 280,
      bslib::accordion(
        id   = ns("acc"),
        open = c("Method", "Gene sets"),
        bslib::accordion_panel(
          "Method", icon = shiny::icon("flask"),
          shiny::selectizeInput(ns("method"), NULL,
                                choices = c("GSEA" = "gsea"))
        ),
        bslib::accordion_panel(
          "Gene sets", icon = shiny::icon("dna"),
          enrichmentGmtUI(ns("gmt"))
        ),
        bslib::accordion_panel(
          "Advanced", icon = shiny::icon("gear"),
          shiny::numericInput(ns("min_size"), "Min set size", 15,
                              min = 1, step = 1),
          shiny::numericInput(ns("max_size"), "Max set size", 500,
                              min = 1, step = 1),
          shiny::numericInput(ns("n_perm"),   "Permutations", 1000,
                              min = 100, step = 100),
          shiny::numericInput(ns("seed"),     "Seed", 1, step = 1)
        )
      )
    ),
    bslib::layout_column_wrap(
      width = 1 / 2,
      bslib::card(
        bslib::card_header("Results"),
        bslib::card_body(
          DT::DTOutput(ns("results_table")),
          shiny::downloadButton(ns("download_results"), "Download")
        )
      ),
      bslib::card(
        bslib::card_header("Enrichment plot"),
        bslib::card_body(shiny::plotOutput(ns("enrichment_plot")))
      )
    ),
    bslib::card(
      bslib::card_header("Leading edge"),
      bslib::card_body(shiny::textOutput(ns("leading_edge")))
    ),
    shiny::conditionalPanel(
      condition = sprintf("output['%s'] == true", ns("show_heatmap")),
      enrichmentNesHeatmapUI(ns("nes_heatmap"))
    )
  )
}

#' Server for the Enrichment tab.
#'
#' @param id Module ID.
#' @param de_results Reactive yielding either:
#'   - a single data.frame with columns `ID` (or `gene`),
#'     `log2FoldChange`, `padj` (one comparison), or
#'   - a named list of such data.frames (multi-comparison; enables
#'     the NES heatmap).
#' @return invisible(NULL).
#' @examples
#' \donttest{
#'   de <- data.frame(ID = paste0("G", 1:5),
#'                    log2FoldChange = c(2, -1, 0, 3, -2),
#'                    padj = c(0.01, 0.04, 0.5, 0.02, 0.03))
#'   shiny::shinyApp(
#'     ui = enrichmentUI("e1"),
#'     server = function(input, output, session) {
#'       enrichmentServer("e1", shiny::reactive(de))
#'     }
#'   )
#' }
#' @export
enrichmentServer <- function(id, de_results) {
  shiny::moduleServer(id, function(input, output, session) {
    .gmt     <- enrichmentGmtServer("gmt")
    pathways <- .gmt$pathways

    de_list <- shiny::reactive({
      x <- de_results()
      shiny::req(x)
      if (is.data.frame(x)) list(comparison_1 = x) else x
    })

    gsea_results_by_comparison <- shiny::reactive({
      shiny::req(pathways(), de_list())
      lapply(de_list(), function(df) {
        id_col <- .enrichment_id_col(df)
        run_gsea(df, pathways = pathways(),
                 min_size = input$min_size, max_size = input$max_size,
                 n_perm   = input$n_perm,   seed     = input$seed,
                 id_col   = id_col)
      })
    })

    output$show_heatmap <- shiny::reactive(length(de_list()) >= 2L)
    shiny::outputOptions(output, "show_heatmap", suspendWhenHidden = FALSE)

    enrichmentNesHeatmapServer("nes_heatmap", gsea_results_by_comparison)

    primary_result <- shiny::reactive({
      r <- gsea_results_by_comparison()
      shiny::req(length(r) >= 1L)
      r[[1]]
    })

    output$results_table <- DT::renderDT({
      df <- primary_result()
      DT::datatable(
        df[, c("pathway", "size", "NES", "padj")],
        rownames  = FALSE,
        selection = list(mode = "single", selected = 1),
        filter    = "top",
        options   = list(pageLength = 10)
      ) |>
        DT::formatRound("NES", 4) |>
        DT::formatSignif("padj", 4)
    })

    output$download_results <- shiny::downloadHandler(
      filename = function() "gsea_results.tsv",
      content  = function(file) {
        df <- primary_result()
        df$leading_edge <- vapply(df$leading_edge, paste, character(1),
                                  collapse = ";")
        utils::write.table(df, file = file, sep = "\t",
                           quote = FALSE, row.names = FALSE)
      }
    )

    selected_pw <- shiny::reactive({
      sel <- input$results_table_rows_selected
      shiny::req(length(sel) == 1L)
      primary_result()$pathway[sel]
    })

    output$enrichment_plot <- shiny::renderPlot({
      shiny::req(selected_pw(), pathways(), de_list())
      df <- de_list()[[1]]
      id_col <- .enrichment_id_col(df)
      stats <- df$log2FoldChange
      names(stats) <- as.character(df[[id_col]])
      stats <- sort(stats[is.finite(stats)], decreasing = TRUE)
      fgsea::plotEnrichment(pathways()[[selected_pw()]], stats) +
        ggplot2::labs(title = selected_pw())
    })

    output$leading_edge <- shiny::renderText({
      sel <- input$results_table_rows_selected
      shiny::req(length(sel) == 1L)
      paste(primary_result()$leading_edge[[sel]], collapse = ", ")
    })
  })
  invisible(NULL)
}
