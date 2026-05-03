# R/mod_method_concordance.R
#
# Phase E11 — Method comparison sub-panel of the DE Analysis tab.
# Consumes the active comparison's (counts, metadata, columns, conds)
# reactives, runs DESeq2/edgeR/limma on demand, exposes the multi-
# method DE list as a returned reactive (so the Enrichment tab can
# reuse it for View C — cross-method NES heatmap).

#' UI for the Method comparison card.
#'
#' Renders an empty-state until the user clicks "Run comparison".
#'
#' @param id Module ID.
#' @return A `bslib::card` containing controls and result outputs.
#' @export
methodConcordanceUI <- function(id) {
  ns <- shiny::NS(id)
  shiny::tagList(
    bslib::card(
      bslib::card_header("Method comparison"),
      bslib::card_body(
        shiny::helpText(
          "Re-runs DESeq2, edgeR, and limma on the active comparison",
          "and compares overlapping DE genes. This is on demand —",
          "press the button below."
        ),
        shiny::fluidRow(
          shiny::column(3,
            shiny::numericInput(ns("padj"), "padj <=",
                                value = 0.05, min = 0, max = 1, step = 0.01)
          ),
          shiny::column(3,
            shiny::numericInput(ns("lfc"), "|log2FC| >=",
                                value = 0, min = 0, step = 0.1)
          ),
          shiny::column(6,
            shiny::actionButton(ns("run"), "Run comparison",
                                class = "btn-primary",
                                style = "margin-top: 25px;")
          )
        )
      )
    ),
    shiny::conditionalPanel(
      condition = sprintf("input['%s'] > 0", ns("run")),
      bslib::layout_column_wrap(
        width = 1 / 2,
        bslib::card(
          bslib::card_header("Overlap (UpSet)"),
          bslib::card_body(shiny::plotOutput(ns("upset"), height = "420px"))
        ),
        bslib::card(
          bslib::card_header("Pairwise log2FC scatter"),
          bslib::card_body(
            shiny::fluidRow(
              shiny::column(6, shiny::uiOutput(ns("scatter_method1_ui"))),
              shiny::column(6, shiny::uiOutput(ns("scatter_method2_ui")))
            ),
            shiny::plotOutput(ns("scatter"), height = "360px")
          )
        )
      ),
      bslib::card(
        bslib::card_header("Concordance summary"),
        bslib::card_body(DT::DTOutput(ns("summary")))
      )
    )
  )
}

#' Server for the Method comparison card.
#'
#' @param id Module ID.
#' @param counts_react Reactive yielding the count matrix (post-batch).
#' @param metadata_react Reactive yielding the sample metadata.
#' @param comparison_react Reactive yielding a list with components
#'   `cols` and `conds` for the active comparison (typically
#'   `comparison()` from `R/server.R`).
#' @return Reactive yielding the named list returned by
#'   [run_de_methods()] (or NULL pre-run). Caller can pass this into
#'   the Enrichment tab's cross-method GSEA pass.
#' @export
methodConcordanceServer <- function(id, counts_react, metadata_react,
                                    comparison_react) {
  shiny::moduleServer(id, function(input, output, session) {

    de_list <- shiny::eventReactive(input$run, {
      cmp <- comparison_react()
      shiny::req(cmp, cmp$cols, cmp$conds, counts_react())
      shiny::withProgress(
        message = "Running DESeq2 / edgeR / limma",
        value = 0.2,
        {
          run_de_methods(
            counts   = counts_react(),
            metadata = metadata_react(),
            columns  = cmp$cols,
            conds    = cmp$conds,
            methods  = c("DESeq2", "EdgeR", "Limma")
          )
        }
      )
    }, ignoreNULL = TRUE)

    output$upset <- shiny::renderPlot({
      d <- de_list()
      shiny::req(length(d) >= 2L)
      p <- plot_method_upset(d, padj_cutoff = input$padj,
                             lfc_cutoff = input$lfc)
      shiny::validate(shiny::need(
        !is.null(p),
        "Fewer than 2 methods produced a non-empty significant set at the chosen cutoffs. Loosen padj or |log2FC|."
      ))
      print(p)
    })

    output$scatter_method1_ui <- shiny::renderUI({
      d <- de_list()
      shiny::req(length(d) >= 2L)
      shiny::selectInput(session$ns("scatter_method1"), "x-axis method",
                         choices = names(d), selected = names(d)[1])
    })
    output$scatter_method2_ui <- shiny::renderUI({
      d <- de_list()
      shiny::req(length(d) >= 2L)
      shiny::selectInput(session$ns("scatter_method2"), "y-axis method",
                         choices = names(d),
                         selected = names(d)[min(2L, length(d))])
    })
    output$scatter <- shiny::renderPlot({
      d <- de_list()
      shiny::req(d, input$scatter_method1, input$scatter_method2)
      shiny::validate(shiny::need(
        input$scatter_method1 != input$scatter_method2,
        "Pick two different methods."
      ))
      plot_method_scatter(d, input$scatter_method1, input$scatter_method2)
    })

    output$summary <- DT::renderDT({
      d <- de_list()
      shiny::req(length(d) >= 2L)
      cs <- concordance_summary(d, padj_cutoff = input$padj,
                                lfc_cutoff = input$lfc)
      DT::datatable(
        cs,
        rownames = FALSE,
        options = list(pageLength = 10, dom = "t")
      ) |>
        DT::formatRound(c("jaccard", "spearman_lfc"), 3)
    })

    de_list
  })
}
