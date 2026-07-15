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
#' @examples
#' comparisonConcordanceUI("demo")
#' @export
comparisonConcordanceUI <- function(id) {
  ns <- shiny::NS(id)
  shiny::tagList(
    de_card(
      "Comparison Concordance",
      shiny::helpText(
        "Compares your CondSelect comparisons against each other",
        "using the DE results that were already computed when you",
        "ran DE (each comparison uses whatever method you picked",
        "for it). Cutoffs below filter the significant-gene sets",
        "used for the UpSet plot and the concordance summary; the",
        "pairwise scatter shows log2FC across all common genes."
      ),
      bslib::layout_columns(
        col_widths = c(6, 6),
        shiny::numericInput(ns("padj"), "padj <=",
                            value = 0.05, min = 0, max = 1, step = 0.01),
        shiny::numericInput(ns("lfc"), "|log2FC| >=",
                            value = 0, min = 0, step = 0.1)
      )
    ),
    bslib::layout_columns(
      col_widths = c(6, 6),
      de_card(
        "DEGs per comparison (up / down)",
        shiny::plotOutput(ns("deg_bar"), height = "420px")
      ),
      de_card(
        "Pairwise DEG count heatmap",
        shiny::plotOutput(ns("deg_heatmap"), height = "420px")
      )
    ),
    bslib::layout_columns(
      col_widths = c(6, 6),
      de_card(
        "Overlap (UpSet)",
        shiny::plotOutput(ns("upset"), height = "420px")
      ),
      de_card(
        "Pairwise log2FC scatter",
        bslib::layout_columns(
          col_widths = c(6, 6),
          shiny::uiOutput(ns("scatter_x_ui")),
          shiny::uiOutput(ns("scatter_y_ui"))
        ),
        shiny::plotOutput(ns("scatter"), height = "360px")
      )
    ),
    de_card(
      "Concordance summary (pairwise)",
      DT::DTOutput(ns("summary"))
    ),
    # Phase E12.B: AI interpretation for concordance. Visibility
    # gated by parent (server.R checks credentials + >= 2 comparisons).
    de_card(
      "AI interpretation",
      shiny::conditionalPanel(
        condition = sprintf("output['%s'] === 'show'",
                            ns("ai_pathway_picker_visible")),
        shiny::selectInput(ns("reconcile_pathway"),
                           "Pathway to reconcile (optional)",
                           choices = c("(none)" = ""),
                           selected = "")
      ),
      debrowser::aiInterpretUI(
        ns("ai_concordance"),
        questions     = c("reconcile_enrichments", "suggest_followup",
                          "draft_methods"),
        payload_shape = "concordance"
      )
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
#' @param ai_settings_react Optional reactive yielding AI settings list
#'   (from `aiSettingsServer`). When NULL, no AI panel is mounted.
#' @param fgsea_pathways_react Optional reactive yielding the active
#'   fgsea pathway set (`names()` over the gene-set lookup). Drives
#'   the in-card pathway picker for `reconcile_enrichments`.
#' @param deterministic_methods_react Optional reactive yielding a
#'   chr(1) Methods paragraph (e.g. from `methods_paragraph()`).
#'   Consumed by the `draft_methods` preset.
#' @return invisible(NULL).
#' @examples
#' \donttest{
#'   de <- list(
#'     "Treat vs Ctrl" = data.frame(ID = paste0("G", 1:5),
#'       log2FoldChange = c(2, -1, 0, 3, -2),
#'       padj = c(0.01, 0.04, 0.5, 0.02, 0.03)),
#'     "Drug vs Vehicle" = data.frame(ID = paste0("G", 1:5),
#'       log2FoldChange = c(1.5, -0.8, 0.2, 2.1, -1.5),
#'       padj = c(0.02, 0.03, 0.6, 0.01, 0.04))
#'   )
#'   shiny::shinyApp(
#'     ui = comparisonConcordanceUI("cc"),
#'     server = function(input, output, session) {
#'       comparisonConcordanceServer("cc", shiny::reactive(de))
#'     }
#'   )
#' }
#' @export
comparisonConcordanceServer <- function(id, de_results_react,
                                        comparisons_react           = NULL,
                                        ai_settings_react           = NULL,
                                        fgsea_pathways_react        = NULL,
                                        deterministic_methods_react = NULL) {
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
      shiny::withProgress(message = "Drawing DEG bar plot", style = "notification", value = 0.1, {
        s <- direction_summary()
        shiny::validate(shiny::need(
          sum(s$n_sig) > 0L,
          "No significant genes at the chosen cutoffs. Loosen padj or |log2FC|."
        ))
        plot_de_direction_bar(s, subtitle = cutoff_subtitle())
      })
    })

    output$deg_heatmap <- shiny::renderPlot({
      shiny::withProgress(message = "Drawing pairwise DEG heatmap", style = "notification", value = 0.1, {
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
    })

    output$upset <- shiny::renderPlot({
      shiny::withProgress(message = "Drawing UpSet plot", style = "notification", value = 0.1, {
        d <- de_list()
        shiny::req(length(d) >= 2L)
        p <- plot_method_upset(d, padj_cutoff = input$padj,
                               lfc_cutoff = input$lfc)
        shiny::validate(shiny::need(
          !is.null(p),
          "Fewer than 2 comparisons produced a non-empty significant set at the chosen cutoffs. Loosen padj or |log2FC|."
        ))
        # UpSetR::upset() returns an `upset` list with no S4 show
        # method, so it must be rendered explicitly. methods::show()
        # delegates through UpSetR's print method and produces the
        # canonical UpSet output while avoiding BiocCheck's bare-print
        # heuristic.
        methods::show(p)
      })
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
      shiny::withProgress(message = "Drawing pairwise scatter", style = "notification", value = 0.1, {
        d <- de_list()
        shiny::req(d, input$scatter_x, input$scatter_y)
        shiny::validate(shiny::need(
          input$scatter_x != input$scatter_y,
          "Pick two different comparisons."
        ))
        plot_method_scatter(d, input$scatter_x, input$scatter_y)
      })
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

    # Phase E12.B: AI interpretation panel. Skip if no AI settings
    # reactive provided (older mounts that haven't been migrated).
    if (!is.null(ai_settings_react)) {

      # Pathways for the reconcile_enrichments picker: those significant
      # in >= 2 comparisons. Sourced from fgsea_pathways_react when
      # provided; empty otherwise.
      pathways_for_reconcile <- shiny::reactive({
        gmt <- if (is.null(fgsea_pathways_react)) NULL else
                 fgsea_pathways_react()
        if (is.null(gmt)) return(character(0))
        d <- de_list()
        if (length(d) < 2L) return(character(0))
        hits_per_pathway <- lapply(d, function(df) {
          tryCatch({
            r <- run_gsea(df, gmt)
            r$pathway[r$padj <= 0.05]
          }, error = function(e) character(0))
        })
        all_hits <- unlist(hits_per_pathway, use.names = FALSE)
        tab <- table(all_hits)
        names(tab)[tab >= 2L]
      })

      shiny::observe({
        choices <- pathways_for_reconcile()
        if (length(choices) == 0L) {
          shiny::updateSelectInput(session, "reconcile_pathway",
                                   choices = c("(none)" = ""),
                                   selected = "")
        } else {
          shiny::updateSelectInput(session, "reconcile_pathway",
                                   choices = c("(none)" = "", choices))
        }
      })

      output$ai_pathway_picker_visible <- shiny::reactive({
        if (length(pathways_for_reconcile()) > 0L) "show" else "hide"
      })
      shiny::outputOptions(output, "ai_pathway_picker_visible",
                           suspendWhenHidden = FALSE)

      # Local helper: collect NES + leading-edge for a SPECIFIC pathway
      # across every comparison in `de_list`. Returns a data.frame with
      # columns (comparison, NES, padj, leading_edge) and at least 1 row,
      # or NULL when fewer than 2 comparisons have the pathway scored.
      # Mirrors .collect_nes_across in server.R but is scoped per-module
      # to keep this file self-contained.
      .cc_collect_nes_for_pathway <- function(pathway_name, de_list, gmt) {
        if (is.null(pathway_name) || !nzchar(pathway_name)) return(NULL)
        if (length(de_list) < 2L || is.null(gmt)) return(NULL)
        rows <- lapply(names(de_list), function(cmp) {
          df <- tryCatch(run_gsea(de_list[[cmp]], gmt),
                         error = function(e) NULL)
          if (is.null(df) || nrow(df) == 0L) return(NULL)
          hit <- df[df$pathway == pathway_name, , drop = FALSE]
          if (nrow(hit) == 0L) return(NULL)
          le <- if ("leading_edge" %in% names(hit))
                  paste(hit$leading_edge[[1]], collapse = ", ")
                else ""
          data.frame(comparison   = cmp,
                     NES          = hit$NES[1],
                     padj         = hit$padj[1],
                     leading_edge = le,
                     stringsAsFactors = FALSE)
        })
        rows <- rows[!vapply(rows, is.null, logical(1))]
        if (length(rows) < 2L) return(NULL)
        do.call(rbind, rows)
      }

      ai_concordance_payload <- shiny::reactive({
        d <- de_list()
        if (length(d) < 2L) return(NULL)
        cs <- tryCatch(concordance_summary(d,
                                           padj_cutoff = input$padj,
                                           lfc_cutoff  = input$lfc),
                       error = function(e) data.frame())
        # Rename to user-facing labels (same as the summary table).
        if (nrow(cs) > 0L) {
          colnames(cs)[colnames(cs) == "method1"]   <- "comparison1"
          colnames(cs)[colnames(cs) == "method2"]   <- "comparison2"
          colnames(cs)[colnames(cs) == "n_method1"] <- "n_comparison1"
          colnames(cs)[colnames(cs) == "n_method2"] <- "n_comparison2"
        }
        out <- .build_concordance_payload(
          de_results_list   = d,
          concordance_table = cs,
          top_n             = 50L,
          cutoffs           = list(padj = input$padj, lfc = input$lfc)
        )
        # Attach the candidate pathway list for .applicable_questions.
        if (!is.null(out)) {
          out$pathways_for_reconcile <- pathways_for_reconcile()
          out$selected_pathway       <- input$reconcile_pathway

          # When the user has picked a pathway, populate the enrichment
          # slot the reconcile_enrichments slot builder expects.
          sel_pw <- input$reconcile_pathway
          if (!is.null(sel_pw) && nzchar(sel_pw)) {
            gmt <- if (is.null(fgsea_pathways_react)) NULL else
                     fgsea_pathways_react()
            nes_df <- .cc_collect_nes_for_pathway(sel_pw, d, gmt)
            if (!is.null(nes_df)) {
              out$enrichment <- list(term = sel_pw, nes_across = nes_df)
            }
          }
        }
        out
      })

      debrowser::aiInterpretServer(
        "ai_concordance",
        payload_react              = ai_concordance_payload,
        settings_react             = ai_settings_react,
        payload_shape              = "concordance",
        deterministic_methods_react = deterministic_methods_react
      )
    }

    invisible(NULL)
  })
}

# Private NULL-coalescing operator. Same definition lives in
# R/mod_enrichment_gmt.R (E2 era) - duplicated rather than exported
# to keep the module self-contained until R 4.4's native %||% becomes
# the package's minimum.
`%||%` <- function(a, b) if (is.null(a)) b else a
