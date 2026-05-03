# R/mod_comparison_concordance.R
#
# Phase E11 (post-redirect) - Comparison Concordance top-level tab.
#
# Consumes the per-comparison DE result tables already produced by
# CondSelect / Run DE (each comparison was run with whatever method
# the user picked there - DESeq2, edgeR, or limma). Renders UpSet of
# DE-gene overlap across comparisons + a pairwise log2FC scatter
# (comparison_A on x, comparison_B on y) + a pairwise concordance
# summary table.
#
# No DE re-running here: data comes straight from de_results_list()
# in R/server.R, which is the de-augmented data.frame stack from
# dc()[[i]]$init_data, named by comparison_labels(dc()).
#
# Visibility is governed by R/server.R: an observer on
# de_results_list() shows the tab when length >= 2, hides it
# otherwise (so users with one comparison don't see a useless tab).

#' UI for the Comparison Concordance top-level tab.
#'
#' @param id Module ID.
#' @return A `shiny::tagList` with a control card (padj / |log2FC|),
#'   an UpSet card, a pairwise scatter card with x/y comparison
#'   selectizes, and a concordance summary table card.
#' @export
comparisonConcordanceUI <- function(id) {
  ns <- shiny::NS(id)
  shiny::tagList(
    bslib::card(
      bslib::card_header("Comparison Concordance"),
      bslib::card_body(
        shiny::helpText(
          "Compares your CondSelect comparisons against each other",
          "using the DE results that were already computed when you",
          "ran DE (each comparison uses whatever method you picked",
          "for it). Cutoffs below filter the significant-gene sets",
          "used for the UpSet plot and the concordance summary; the",
          "pairwise scatter shows log2FC across all common genes."
        ),
        shiny::fluidRow(
          shiny::column(3,
            shiny::numericInput(ns("padj"), "padj <=",
                                value = 0.05, min = 0, max = 1, step = 0.01)
          ),
          shiny::column(3,
            shiny::numericInput(ns("lfc"), "|log2FC| >=",
                                value = 0, min = 0, step = 0.1)
          )
        )
      )
    ),
    bslib::layout_column_wrap(
      width = 1 / 2,
      bslib::card(
        bslib::card_header("DEGs per comparison (up / down)"),
        bslib::card_body(shiny::plotOutput(ns("deg_bar"), height = "420px"))
      ),
      bslib::card(
        bslib::card_header("Pairwise DEG count heatmap"),
        bslib::card_body(shiny::plotOutput(ns("deg_heatmap"), height = "420px"))
      )
    ),
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
            shiny::column(6, shiny::uiOutput(ns("scatter_x_ui"))),
            shiny::column(6, shiny::uiOutput(ns("scatter_y_ui")))
          ),
          shiny::plotOutput(ns("scatter"), height = "360px")
        )
      )
    ),
    bslib::card(
      bslib::card_header("Concordance summary (pairwise)"),
      bslib::card_body(DT::DTOutput(ns("summary")))
    )
  )
}

#' Server for the Comparison Concordance tab.
#'
#' @param id Module ID.
#' @param de_results_react Reactive yielding the named list of
#'   per-comparison DE result data.frames (typically `de_results_list`
#'   from `R/server.R`). Each element must contain `ID`,
#'   `log2FoldChange`, and `padj` columns; entries are keyed by
#'   `comparison_labels()` so colliding labels stay unique.
#' @param comparisons_react Reactive yielding the full comparison list
#'   (typically `dc()` from `R/server.R`); each entry should have
#'   `cond_names` so the pairwise DEG heatmap can label group axes.
#'   When NULL or missing cond_names, the heatmap card shows an
#'   empty-state.
#' @return invisible(NULL).
#' @export
comparisonConcordanceServer <- function(id, de_results_react,
                                        comparisons_react = NULL) {
  shiny::moduleServer(id, function(input, output, session) {

    # Coerce DE-augmented data.frames (which may use rownames as the
    # gene id and lack an explicit ID column) into the {ID,
    # log2FoldChange, padj} shape the helpers expect.
    de_list <- shiny::reactive({
      d <- de_results_react()
      if (is.null(d) || length(d) < 2L) return(NULL)
      lapply(d, function(df) {
        if (!"ID" %in% names(df)) df$ID <- rownames(df)
        df[, intersect(c("ID", "log2FoldChange", "padj"), names(df)),
           drop = FALSE]
      })
    })

    # Cutoff label reused as plot subtitle.
    cutoff_subtitle <- shiny::reactive({
      padj <- input$padj %||% 0.05
      lfc  <- input$lfc  %||% 0
      if (lfc > 0) {
        sprintf("Threshold: padj <= %g, |log2FC| >= %g", padj, lfc)
      } else {
        sprintf("Threshold: padj <= %g", padj)
      }
    })

    direction_summary <- shiny::reactive({
      d <- de_list()
      shiny::req(length(d) >= 2L)
      de_direction_summary(d, padj_cutoff = input$padj,
                           lfc_cutoff = input$lfc)
    })

    output$deg_bar <- shiny::renderPlot({
      s <- direction_summary()
      shiny::validate(shiny::need(
        sum(s$n_sig) > 0L,
        "No significant genes at the chosen cutoffs. Loosen padj or |log2FC|."
      ))
      plot_de_direction_bar(s, subtitle = cutoff_subtitle())
    })

    output$deg_heatmap <- shiny::renderPlot({
      s <- direction_summary()
      shiny::validate(shiny::need(
        !is.null(comparisons_react),
        "Pairwise DEG heatmap requires comparison metadata; the controller did not pass comparisons_react."
      ))
      comps <- comparisons_react()
      shiny::validate(shiny::need(
        length(comps) > 0L,
        "No comparisons available."
      ))
      plot_de_pairwise_heatmap(s, comps, subtitle = cutoff_subtitle())
    })

    output$upset <- shiny::renderPlot({
      d <- de_list()
      shiny::req(length(d) >= 2L)
      p <- plot_method_upset(d, padj_cutoff = input$padj,
                             lfc_cutoff = input$lfc)
      shiny::validate(shiny::need(
        !is.null(p),
        "Fewer than 2 comparisons produced a non-empty significant set at the chosen cutoffs. Loosen padj or |log2FC|."
      ))
      print(p)
    })

    output$scatter_x_ui <- shiny::renderUI({
      d <- de_list()
      shiny::req(length(d) >= 2L)
      shiny::selectInput(session$ns("scatter_x"), "x-axis comparison",
                         choices = names(d), selected = names(d)[1])
    })
    output$scatter_y_ui <- shiny::renderUI({
      d <- de_list()
      shiny::req(length(d) >= 2L)
      shiny::selectInput(session$ns("scatter_y"), "y-axis comparison",
                         choices = names(d),
                         selected = names(d)[min(2L, length(d))])
    })
    output$scatter <- shiny::renderPlot({
      d <- de_list()
      shiny::req(d, input$scatter_x, input$scatter_y)
      shiny::validate(shiny::need(
        input$scatter_x != input$scatter_y,
        "Pick two different comparisons."
      ))
      plot_method_scatter(d, input$scatter_x, input$scatter_y)
    })

    output$summary <- DT::renderDT({
      d <- de_list()
      shiny::req(length(d) >= 2L)
      cs <- concordance_summary(d, padj_cutoff = input$padj,
                                lfc_cutoff = input$lfc)
      # Rename method1/method2 to comparison1/comparison2 for clarity
      # in this tab's user-facing context (the helper is generic).
      colnames(cs)[colnames(cs) == "method1"]   <- "comparison1"
      colnames(cs)[colnames(cs) == "method2"]   <- "comparison2"
      colnames(cs)[colnames(cs) == "n_method1"] <- "n_comparison1"
      colnames(cs)[colnames(cs) == "n_method2"] <- "n_comparison2"
      DT::datatable(
        cs,
        rownames = FALSE,
        options  = list(pageLength = 10, dom = "t")
      ) |>
        DT::formatRound(c("jaccard", "spearman_lfc"), 3)
    })

    invisible(NULL)
  })
}

# Private NULL-coalescing operator. Same definition lives in
# R/mod_enrichment_gmt.R (E2 era) - duplicated rather than exported
# to keep the module self-contained until R 4.4's native %||% becomes
# the package's minimum.
`%||%` <- function(a, b) if (is.null(a)) b else a
