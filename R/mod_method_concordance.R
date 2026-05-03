# R/mod_method_concordance.R
#
# Phase E11 - Method comparison sub-panel of the DE Analysis tab.
# Iterates every comparison set up in CondSelect, runs DESeq2/edgeR/
# limma per comparison on demand, and renders a stacked accordion
# (one panel per comparison) of UpSet + pairwise scatter + concordance
# summary. The returned reactive is a list of per-comparison de_lists
# keyed by comparison_labels(); the Enrichment tab's cross-method NES
# heatmap (View C) consumes the active-comparison slice.

#' UI for the Method comparison card.
#'
#' Renders an empty-state until the user clicks "Run comparison".
#'
#' @param id Module ID.
#' @return A `shiny::tagList` containing the control card and a
#'   per-comparison accordion that fills after the first Run click.
#' @export
methodConcordanceUI <- function(id) {
  ns <- shiny::NS(id)
  shiny::tagList(
    bslib::card(
      bslib::card_header("Method comparison"),
      bslib::card_body(
        shiny::helpText(
          "Re-runs DESeq2, edgeR, and limma on every comparison set up",
          "in CondSelect and renders one accordion panel per comparison",
          "with overlap (UpSet), pairwise log2FC scatter, and a",
          "concordance summary table. This is on demand - press the",
          "button below."
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
      shiny::uiOutput(ns("accordion"))
    )
  )
}

#' Server for the Method comparison card.
#'
#' Runs `run_de_methods()` for every comparison in `comparisons_react()`
#' on each Run click. Renders one accordion panel per comparison with
#' UpSet / pairwise scatter / summary cards. Returns a named list of
#' per-comparison de_lists for downstream consumers (Enrichment tab
#' cross-method NES heatmap reads the active-comparison slice).
#'
#' @param id Module ID.
#' @param counts_react Reactive yielding the count matrix (post-batch).
#' @param metadata_react Reactive yielding the sample metadata.
#' @param comparisons_react Reactive yielding the full list of
#'   comparison entries (typically `dc()` from `R/server.R`); each
#'   entry must have `cols`, `conds`, and (optionally) `cond_names`.
#' @return Reactive yielding a named list of per-comparison de_lists
#'   (each de_list itself is the named list returned by
#'   [run_de_methods()]). Names come from [comparison_labels()].
#'   Returns NULL pre-run.
#' @export
methodConcordanceServer <- function(id, counts_react, metadata_react,
                                    comparisons_react) {
  shiny::moduleServer(id, function(input, output, session) {

    de_lists <- shiny::eventReactive(input$run, {
      comps <- comparisons_react()
      shiny::req(length(comps) > 0L, counts_react())
      labels <- comparison_labels(comps)
      shiny::withProgress(
        message = "Running DESeq2 / edgeR / limma per comparison",
        value = 0.05,
        {
          out <- vector("list", length(comps))
          for (i in seq_along(comps)) {
            shiny::setProgress(value = i / length(comps),
                               detail = labels[i])
            cmp <- comps[[i]]
            if (is.null(cmp$cols) || is.null(cmp$conds)) {
              out[[i]] <- list()
              next
            }
            out[[i]] <- run_de_methods(
              counts   = counts_react(),
              metadata = metadata_react(),
              columns  = cmp$cols,
              conds    = cmp$conds,
              methods  = c("DESeq2", "EdgeR", "Limma")
            )
          }
          names(out) <- labels
          out
        }
      )
    }, ignoreNULL = TRUE)

    output$accordion <- shiny::renderUI({
      d <- de_lists()
      shiny::req(length(d) > 0L)
      panels <- lapply(seq_along(d), function(i) {
        nm <- names(d)[i]
        sfx <- paste0("_", i)
        bslib::accordion_panel(
          title = nm,
          bslib::layout_column_wrap(
            width = 1 / 2,
            bslib::card(
              bslib::card_header("Overlap (UpSet)"),
              bslib::card_body(
                shiny::plotOutput(session$ns(paste0("upset", sfx)),
                                  height = "420px")
              )
            ),
            bslib::card(
              bslib::card_header("Pairwise log2FC scatter"),
              bslib::card_body(
                shiny::fluidRow(
                  shiny::column(6, shiny::uiOutput(
                    session$ns(paste0("scatter_method1_ui", sfx))
                  )),
                  shiny::column(6, shiny::uiOutput(
                    session$ns(paste0("scatter_method2_ui", sfx))
                  ))
                ),
                shiny::plotOutput(session$ns(paste0("scatter", sfx)),
                                  height = "360px")
              )
            )
          ),
          bslib::card(
            bslib::card_header("Concordance summary"),
            bslib::card_body(DT::DTOutput(session$ns(paste0("summary", sfx))))
          )
        )
      })
      do.call(bslib::accordion,
              c(list(id = session$ns("comparison_accordion"),
                     open = names(d)[1]),
                panels))
    })

    # Wire per-panel outputs server-side. Re-runs on each Run click,
    # since de_lists() invalidates only when the user presses Run -
    # not when comparison labels are edited in CondSelect.
    shiny::observeEvent(de_lists(), {
      d <- de_lists()
      for (i in seq_along(d)) {
        local({
          ii <- i
          this_de <- d[[ii]]
          sfx <- paste0("_", ii)

          output[[paste0("upset", sfx)]] <- shiny::renderPlot({
            shiny::req(length(this_de) >= 2L)
            p <- plot_method_upset(this_de,
                                   padj_cutoff = input$padj,
                                   lfc_cutoff  = input$lfc)
            shiny::validate(shiny::need(
              !is.null(p),
              "Fewer than 2 methods produced a non-empty significant set at the chosen cutoffs. Loosen padj or |log2FC|."
            ))
            print(p)
          })

          output[[paste0("scatter_method1_ui", sfx)]] <- shiny::renderUI({
            shiny::req(length(this_de) >= 2L)
            shiny::selectInput(
              session$ns(paste0("scatter_method1", sfx)),
              "x-axis method",
              choices  = names(this_de),
              selected = names(this_de)[1]
            )
          })
          output[[paste0("scatter_method2_ui", sfx)]] <- shiny::renderUI({
            shiny::req(length(this_de) >= 2L)
            shiny::selectInput(
              session$ns(paste0("scatter_method2", sfx)),
              "y-axis method",
              choices  = names(this_de),
              selected = names(this_de)[min(2L, length(this_de))]
            )
          })
          output[[paste0("scatter", sfx)]] <- shiny::renderPlot({
            m1 <- input[[paste0("scatter_method1", sfx)]]
            m2 <- input[[paste0("scatter_method2", sfx)]]
            shiny::req(this_de, m1, m2)
            shiny::validate(shiny::need(
              m1 != m2,
              "Pick two different methods."
            ))
            plot_method_scatter(this_de, m1, m2)
          })

          output[[paste0("summary", sfx)]] <- DT::renderDT({
            shiny::req(length(this_de) >= 2L)
            cs <- concordance_summary(this_de,
                                      padj_cutoff = input$padj,
                                      lfc_cutoff  = input$lfc)
            DT::datatable(
              cs,
              rownames = FALSE,
              options  = list(pageLength = 10, dom = "t")
            ) |>
              DT::formatRound(c("jaccard", "spearman_lfc"), 3)
          })
        })
      }
    }, ignoreInit = TRUE)

    de_lists
  })
}
