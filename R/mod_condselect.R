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
#' @examples
#' condSelectUI("demo")
#' @export
condSelectUI <- function(id) {
  ns <- shiny::NS(id)
  shiny::tagList(
    # B3.25 -- Sticky workbar at the top of the Comparison page so the
    # primary "Start DE" CTA is always visible. Add/Remove are also
    # reachable here without scrolling. Help icon on the far right.
    shiny::tags$div(
      class = "de-cs-workbar",
      shiny::tags$div(class = "de-cs-workbar-left",
        shiny::tags$span(class = "de-cs-workbar-hint",
                         "Define your contrast(s), then start DE.")),
      shiny::tags$div(class = "spacer", style = "flex:1"),
      shiny::tags$div(class = "de-cs-workbar-actions",
        actionButtonDE(ns("rm_btn"), "Remove last", styleclass = "primary"),
        actionButtonDE(ns("add_btn"), "Add comparison",
                       styleclass = "primary"),
        actionButtonDE(ns("startDE"), "Start DE", styleclass = "primary")
      )
    ),
    de_card(
      title = "Comparison Selection",
      shiny::uiOutput(ns("comparison_panels")),
      # B3.25 -- also keep the bottom buttons (some users will scroll
      # down to use them); they stay rendered so server-side bindings
      # don't break, but the workbar above carries the primary CTA.
      shiny::fluidRow(
        shiny::column(
          12,
          shiny::tags$div(
            class = "de-cs-bottom-actions",
            getHelpButton("method",
                          "http://debrowser.readthedocs.io/en/master/deseq/deseq.html")
          )
        )
      )
    )
  )
}

#' Comparison-Selection wizard server.
#'
#' @param id module namespace id (must match the id passed to `condSelectUI`).
#' @param data count matrix.
#' @param metadata sample-metadata data.frame; first column is the sample id.
#' @param initial_spec Optional saved comparisons_spec to populate the
#'   wizard with on mount. When the module is created during an active
#'   bookmark restore, the module's own `onRestore` hook handles this;
#'   when the module is created LATER (e.g. by the D2.5 DE auto-replay
#'   state machine in deServer, after the active-restore window has
#'   closed), pass the captured spec here so the per-comparison
#'   reactiveValues and UI cards reflect the restored state.
#' @return list with `n_comparisons`, `start_de`, `is_ready`, `comparisons_spec`.
#' @examples
#' \donttest{
#'   counts <- matrix(as.integer(c(100, 200, 10, 12, 40, 60)),
#'                    nrow = 2,
#'                    dimnames = list(c("G1", "G2"), paste0("S", 1:3)))
#'   meta <- data.frame(Sample = paste0("S", 1:3),
#'                      Condition = c("Ctrl", "Ctrl", "Treat"))
#'   shiny::shinyApp(
#'     ui = condSelectUI("cs"),
#'     server = function(input, output, session) {
#'       condSelectServer("cs", data = counts, metadata = meta)
#'     }
#'   )
#' }
#' @export
condSelectServer <- function(id, data = NULL, metadata = NULL,
                             initial_spec = NULL) {
  if (is.null(data)) return(NULL)

  shiny::moduleServer(id, function(input, output, session) {
    ns <- session$ns
    `%||%` <- function(a, b) if (is.null(a)) b else a

    # Per-comparison state lives in this list; each entry is a reactiveValues
    # holding the comparison spec components. Indexed by comparison id (1..N).
    comparisons <- shiny::reactiveValues()

    # Counter; mirror of length(reactiveValuesToList(comparisons)).
    n_comparisons <- shiny::reactiveVal(0L)

    # --- Helpers (closures over `data`, `metadata`, `session`) ------------

    new_comparison <- function(idx) {
      sn <- colnames(data)
      halves <- halve_sample_names(sn)
      labels <- default_side_labels(NA_character_, NA_character_, NA_character_)
      comparisons[[as.character(idx)]] <- shiny::reactiveValues(
        meta_column       = NA_character_,
        treatment_level   = NA_character_,
        control_level     = NA_character_,
        treatment_samples = halves$treatment,
        control_samples   = halves$control,
        treatment_label   = unname(labels["treatment"]),
        control_label     = unname(labels["control"]),
        de_method         = "DESeq2",
        method_params     = list(
          fitType = "parametric", betaPrior = FALSE,
          testType = "LRT",       shrinkage = "apeglm"
        ),
        covariates        = character(0)
      )
    }

    rm_comparison <- function(idx) {
      comparisons[[as.character(idx)]] <- NULL
    }

    snapshot_spec <- function(rv) {
      list(
        meta_column       = rv$meta_column,
        treatment_level   = rv$treatment_level,
        control_level     = rv$control_level,
        treatment_samples = rv$treatment_samples,
        control_samples   = rv$control_samples,
        treatment_label   = rv$treatment_label,
        control_label     = rv$control_label,
        de_method         = rv$de_method,
        method_params     = rv$method_params,
        covariates        = rv$covariates
      )
    }

    # --- Per-comparison observer factory ---------------------------------
    #
    # Bind widgets for comparison `i` to its rv and to the per-comparison
    # output slots. Each comparison gets a fresh set of observers when
    # its rv is added; observers from removed comparisons persist but
    # become harmless (their inputs vanish from the namespace).

    install_card_observers <- function(i) {
      iid <- function(name) paste0(name, "_", i)

      # Card title (bound to the labels).
      output[[iid("title")]] <- shiny::renderText({
        rv <- comparisons[[as.character(i)]]
        if (is.null(rv)) return("")
        paste0("Comparison ", i, ": ",
               rv$treatment_label, " vs ", rv$control_label)
      })

      # Side labels.
      shiny::observeEvent(input[[iid("treatment_label")]], {
        rv <- comparisons[[as.character(i)]]; if (is.null(rv)) return()
        rv$treatment_label <- input[[iid("treatment_label")]]
      }, ignoreInit = TRUE)
      shiny::observeEvent(input[[iid("control_label")]], {
        rv <- comparisons[[as.character(i)]]; if (is.null(rv)) return()
        rv$control_label <- input[[iid("control_label")]]
      }, ignoreInit = TRUE)

      # Side sample pickers.
      shiny::observeEvent(input[[iid("treatment_samples")]], {
        rv <- comparisons[[as.character(i)]]; if (is.null(rv)) return()
        rv$treatment_samples <- input[[iid("treatment_samples")]] %||% character(0)
      }, ignoreInit = TRUE, ignoreNULL = FALSE)
      shiny::observeEvent(input[[iid("control_samples")]], {
        rv <- comparisons[[as.character(i)]]; if (is.null(rv)) return()
        rv$control_samples <- input[[iid("control_samples")]] %||% character(0)
      }, ignoreInit = TRUE, ignoreNULL = FALSE)

      # DE method.
      shiny::observeEvent(input[[iid("de_method")]], {
        rv <- comparisons[[as.character(i)]]; if (is.null(rv)) return()
        rv$de_method <- input[[iid("de_method")]]
      }, ignoreInit = TRUE)

      # Meta column toggle (manual <-> meta).
      shiny::observeEvent(input[[iid("meta_column")]], {
        rv <- comparisons[[as.character(i)]]; if (is.null(rv)) return()
        v <- input[[iid("meta_column")]]
        rv$meta_column <- if (is.null(v) || identical(v, "NA") || is.na(v)) {
          NA_character_
        } else {
          v
        }
      }, ignoreInit = TRUE, ignoreNULL = FALSE)

      # Level pickers -- rendered only when meta_column is not NA.
      output[[iid("treatment_level_ui")]] <- shiny::renderUI({
        rv <- comparisons[[as.character(i)]]
        if (is.null(rv) || is.na(rv$meta_column)) return(NULL)
        col <- metadata[[rv$meta_column]]
        if (is.factor(col)) col <- as.character(col)
        levels_present <- unique(col)
        levels_present <- levels_present[!is.na(levels_present) & nzchar(levels_present)]
        shiny::selectInput(session$ns(iid("treatment_level")),
          label = "Level",
          choices = levels_present,
          selected = rv$treatment_level)
      })
      output[[iid("control_level_ui")]] <- shiny::renderUI({
        rv <- comparisons[[as.character(i)]]
        if (is.null(rv) || is.na(rv$meta_column)) return(NULL)
        col <- metadata[[rv$meta_column]]
        if (is.factor(col)) col <- as.character(col)
        levels_present <- unique(col)
        levels_present <- levels_present[!is.na(levels_present) & nzchar(levels_present)]
        shiny::selectInput(session$ns(iid("control_level")),
          label = "Level",
          choices = levels_present,
          selected = rv$control_level)
      })

      # When meta_column changes, auto-assign default levels and refresh
      # sample lists + labels.
      shiny::observeEvent(comparisons[[as.character(i)]]$meta_column, {
        rv <- comparisons[[as.character(i)]]; if (is.null(rv)) return()
        sample_col <- find_sample_column(metadata, colnames(data))
        if (is.na(rv$meta_column)) {
          # Manual mode.
          halves <- halve_sample_names(colnames(data))
          rv$treatment_level   <- NA_character_
          rv$control_level     <- NA_character_
          rv$treatment_samples <- halves$treatment
          rv$control_samples   <- halves$control
          labels <- default_side_labels(NA_character_, NA_character_, NA_character_)
        } else {
          col <- metadata[[rv$meta_column]]
          if (is.factor(col)) col <- as.character(col)
          levels_present <- unique(col)
          levels_present <- levels_present[!is.na(levels_present) & nzchar(levels_present)]
          if (length(levels_present) >= 2L && !is.na(sample_col)) {
            rv$control_level   <- infer_control_level(levels_present)
            rv$treatment_level <- setdiff(levels_present, rv$control_level)[1]
            rv$treatment_samples <- metadata[[sample_col]][col == rv$treatment_level]
            rv$control_samples   <- metadata[[sample_col]][col == rv$control_level]
            labels <- default_side_labels(rv$meta_column,
              rv$treatment_level, rv$control_level)
          } else {
            labels <- default_side_labels(NA_character_, NA_character_, NA_character_)
          }
        }
        rv$treatment_label <- unname(labels["treatment"])
        rv$control_label   <- unname(labels["control"])
        # Reflect in widgets.
        shiny::updateTextInput(session, iid("treatment_label"), value = rv$treatment_label)
        shiny::updateTextInput(session, iid("control_label"),   value = rv$control_label)
        shiny::updateSelectInput(session, iid("treatment_samples"),
          choices = colnames(data), selected = rv$treatment_samples)
        shiny::updateSelectInput(session, iid("control_samples"),
          choices = colnames(data), selected = rv$control_samples)
      })

      # When the user changes a level picker, refill that side's samples.
      shiny::observeEvent(input[[iid("treatment_level")]], {
        rv <- comparisons[[as.character(i)]]; if (is.null(rv)) return()
        if (is.na(rv$meta_column)) return()
        sample_col <- find_sample_column(metadata, colnames(data))
        if (is.na(sample_col)) return()
        rv$treatment_level <- input[[iid("treatment_level")]]
        col <- metadata[[rv$meta_column]]
        if (is.factor(col)) col <- as.character(col)
        rv$treatment_samples <- metadata[[sample_col]][col == rv$treatment_level]
        rv$treatment_label <- rv$treatment_level
        shiny::updateTextInput(session, iid("treatment_label"), value = rv$treatment_label)
        shiny::updateSelectInput(session, iid("treatment_samples"),
          selected = rv$treatment_samples)
      }, ignoreInit = TRUE)

      shiny::observeEvent(input[[iid("control_level")]], {
        rv <- comparisons[[as.character(i)]]; if (is.null(rv)) return()
        if (is.na(rv$meta_column)) return()
        sample_col <- find_sample_column(metadata, colnames(data))
        if (is.na(sample_col)) return()
        rv$control_level <- input[[iid("control_level")]]
        col <- metadata[[rv$meta_column]]
        if (is.factor(col)) col <- as.character(col)
        rv$control_samples <- metadata[[sample_col]][col == rv$control_level]
        rv$control_label <- rv$control_level
        shiny::updateTextInput(session, iid("control_label"), value = rv$control_label)
        shiny::updateSelectInput(session, iid("control_samples"),
          selected = rv$control_samples)
      }, ignoreInit = TRUE)

      # Swap button -- flips treatment <-> control across labels, levels,
      # and sample lists.
      shiny::observeEvent(input[[iid("swap")]], {
        rv <- comparisons[[as.character(i)]]; if (is.null(rv)) return()
        new_t_label <- rv$control_label;    new_c_label <- rv$treatment_label
        new_t_lvl   <- rv$control_level;    new_c_lvl   <- rv$treatment_level
        new_t_smp   <- rv$control_samples;  new_c_smp   <- rv$treatment_samples
        rv$treatment_label   <- new_t_label
        rv$control_label     <- new_c_label
        rv$treatment_level   <- new_t_lvl
        rv$control_level     <- new_c_lvl
        rv$treatment_samples <- new_t_smp
        rv$control_samples   <- new_c_smp
        shiny::updateTextInput(session, iid("treatment_label"), value = rv$treatment_label)
        shiny::updateTextInput(session, iid("control_label"),   value = rv$control_label)
        shiny::updateSelectInput(session, iid("treatment_samples"), selected = rv$treatment_samples)
        shiny::updateSelectInput(session, iid("control_samples"),   selected = rv$control_samples)
      })

      # Advanced model settings UI: per-method params + covariates.
      output[[iid("advanced_ui")]] <- shiny::renderUI({
        rv <- comparisons[[as.character(i)]]; if (is.null(rv)) return(NULL)
        method <- rv$de_method
        cov_choices <- if (!is.null(metadata) && ncol(metadata) > 1L) {
          colnames(metadata)[-1]
        } else {
          character(0)
        }
        method_block <- switch(method,
          "DESeq2" = shiny::fluidRow(
            shiny::column(3, shiny::selectInput(session$ns(iid("fitType")),
              "Fit type", c("parametric", "local", "mean"),
              selected = rv$method_params$fitType, width = "100%")),
            shiny::column(3, shiny::selectInput(session$ns(iid("betaPrior")),
              "betaPrior", c(FALSE, TRUE),
              selected = rv$method_params$betaPrior, width = "100%")),
            shiny::column(3, shiny::selectInput(session$ns(iid("testType")),
              "Test type", c("LRT", "Wald"),
              selected = rv$method_params$testType, width = "100%")),
            shiny::column(3, shiny::selectInput(session$ns(iid("shrinkage")),
              "Shrinkage", c("None", "apeglm", "ashr", "normal"),
              selected = rv$method_params$shrinkage, width = "100%"))
          ),
          "EdgeR" = shiny::fluidRow(
            shiny::column(4, shiny::selectInput(session$ns(iid("edgeR_normfact")),
              "Normalization", c("TMM", "RLE", "upperquartile", "none"),
              selected = rv$method_params$edgeR_normfact, width = "100%")),
            shiny::column(4, shiny::textInput(session$ns(iid("dispersion")),
              "Dispersion", value = rv$method_params$dispersion, width = "100%")),
            shiny::column(4, shiny::selectInput(session$ns(iid("edgeR_testType")),
              "Test type", c("exactTest", "glmLRT"),
              selected = rv$method_params$edgeR_testType, width = "100%"))
          ),
          "Limma" = shiny::fluidRow(
            shiny::column(4, shiny::selectInput(session$ns(iid("limma_normfact")),
              "Normalization", c("TMM", "RLE", "upperquartile", "none"),
              selected = rv$method_params$limma_normfact, width = "100%")),
            shiny::column(4, shiny::selectInput(session$ns(iid("limma_fitType")),
              "Fit type", c("ls", "robust"),
              selected = rv$method_params$limma_fitType, width = "100%")),
            shiny::column(4, shiny::selectInput(session$ns(iid("normBetween")),
              "Norm. Bet. Arrays",
              c("none", "scale", "quantile", "cyclicloess",
                "Aquantile", "Gquantile", "Rquantile", "Tquantile"),
              selected = rv$method_params$normBetween, width = "100%"))
          )
        )
        shiny::tagList(
          method_block,
          shiny::selectInput(session$ns(iid("covariates")),
            label = "Covariates",
            choices = cov_choices,
            selected = rv$covariates,
            multiple = TRUE,
            width = "100%"),
          shiny::uiOutput(session$ns(iid("covariate_msgs")))
        )
      })

      # Method-params observers -- write back into rv$method_params.
      shiny::observe({
        rv <- comparisons[[as.character(i)]]; if (is.null(rv)) return()
        m <- rv$de_method
        if (m == "DESeq2") {
          if (!is.null(input[[iid("fitType")]]))
            rv$method_params$fitType <- input[[iid("fitType")]]
          if (!is.null(input[[iid("betaPrior")]]))
            rv$method_params$betaPrior <- as.logical(input[[iid("betaPrior")]])
          if (!is.null(input[[iid("testType")]]))
            rv$method_params$testType <- input[[iid("testType")]]
          if (!is.null(input[[iid("shrinkage")]]))
            rv$method_params$shrinkage <- input[[iid("shrinkage")]]
        } else if (m == "EdgeR") {
          if (!is.null(input[[iid("edgeR_normfact")]]))
            rv$method_params$edgeR_normfact <- input[[iid("edgeR_normfact")]]
          if (!is.null(input[[iid("dispersion")]]))
            rv$method_params$dispersion <- input[[iid("dispersion")]]
          if (!is.null(input[[iid("edgeR_testType")]]))
            rv$method_params$edgeR_testType <- input[[iid("edgeR_testType")]]
        } else if (m == "Limma") {
          if (!is.null(input[[iid("limma_normfact")]]))
            rv$method_params$limma_normfact <- input[[iid("limma_normfact")]]
          if (!is.null(input[[iid("limma_fitType")]]))
            rv$method_params$limma_fitType <- input[[iid("limma_fitType")]]
          if (!is.null(input[[iid("normBetween")]]))
            rv$method_params$normBetween <- input[[iid("normBetween")]]
        }
      })

      # When the method changes, reset method_params to that method's
      # defaults so we don't carry stale fields from another method.
      shiny::observeEvent(input[[iid("de_method")]], {
        rv <- comparisons[[as.character(i)]]; if (is.null(rv)) return()
        m <- input[[iid("de_method")]]
        rv$method_params <- switch(m,
          "DESeq2" = list(fitType = "parametric", betaPrior = FALSE,
                          testType = "LRT",       shrinkage = "apeglm"),
          "EdgeR"  = list(edgeR_normfact = "TMM", dispersion = "0",
                          edgeR_testType = "exactTest"),
          "Limma"  = list(limma_normfact = "TMM", limma_fitType = "ls",
                          normBetween = "none")
        )
      }, ignoreInit = TRUE)

      # Covariates.
      shiny::observeEvent(input[[iid("covariates")]], {
        rv <- comparisons[[as.character(i)]]; if (is.null(rv)) return()
        rv$covariates <- input[[iid("covariates")]] %||% character(0)
      }, ignoreInit = TRUE, ignoreNULL = FALSE)

      # Validation messages -- card footer (all errors + warnings).
      output[[iid("validation_msgs")]] <- shiny::renderUI({
        rv <- comparisons[[as.character(i)]]; if (is.null(rv)) return(NULL)
        records <- validate_comparison(snapshot_spec(rv), metadata)
        bad <- Filter(function(r) !r$ok, records)
        if (length(bad) == 0L) return(NULL)
        shiny::tagList(lapply(bad, function(r) {
          cls <- if (r$severity == "error") "text-danger" else "text-warning"
          shiny::tags$div(class = cls,
            shiny::icon(if (r$severity == "error") "circle-exclamation" else "triangle-exclamation"),
            " ", r$message
          )
        }))
      })

      # Validation messages -- covariate widget area only.
      output[[iid("covariate_msgs")]] <- shiny::renderUI({
        rv <- comparisons[[as.character(i)]]; if (is.null(rv)) return(NULL)
        records <- validate_comparison(snapshot_spec(rv), metadata)
        cov_recs <- Filter(
          function(r) startsWith(r$field, "covariate_") && !r$ok,
          records
        )
        if (length(cov_recs) == 0L) return(NULL)
        shiny::tagList(lapply(cov_recs, function(r) {
          shiny::tags$div(class = "text-warning small",
            shiny::icon("triangle-exclamation"), " ", r$message)
        }))
      })
    }

    # --- Initialize first comparison + its observers ---------------------

    new_comparison(1L)
    n_comparisons(1L)
    install_card_observers(1L)

    # D2.5 fix: spec-application helper. Used by BOTH the module's own
    # onRestore (active-restore window) AND the `initial_spec` constructor
    # path (post-restore, e.g. DE auto-replay in deServer that mounts this
    # module after Shiny's restore phase has already finished). Both paths
    # need to: (1) replace card 1's empty NA rv with the saved values,
    # (2) install card 2..N observers, (3) sync n_comparisons.
    #
    # Idempotent under "double init" caveats:
    # - card 1 observers were ALREADY installed by `install_card_observers(1L)`
    #   above; we MUST NOT re-install them here, or the renderUI for
    #   per-card UI elements duplicates and you get "duplicate input ID"
    #   warnings + a wedged card render.
    apply_spec <- function(saved) {
      restored <- tryCatch(
        restore_comparisons_spec(saved),
        error = function(e) NULL
      )
      if (length(restored) == 0L) return()
      for (key in names(restored)) {
        comparisons[[key]] <- shiny::reactiveValues()
        for (fld in names(restored[[key]])) {
          comparisons[[key]][[fld]] <- restored[[key]][[fld]]
        }
        i <- as.integer(key)
        if (is.na(i)) next
        if (i > 1L) install_card_observers(i)
      }
      n_comparisons(length(restored))
    }

    # If the caller passed `initial_spec` (auto-replay path), apply it
    # immediately. This runs at module mount time, BEFORE the first
    # reactive flush, so the comparison cards render with the restored
    # values on first paint instead of flashing the empty initial state.
    if (!is.null(initial_spec) && length(initial_spec) > 0L) {
      apply_spec(initial_spec)
    }

    # --- Add / remove observers ------------------------------------------

    shiny::observeEvent(input$add_btn, {
      idx <- n_comparisons() + 1L
      new_comparison(idx)
      n_comparisons(idx)
      install_card_observers(idx)
    })

    shiny::observeEvent(input$rm_btn, {
      idx <- n_comparisons()
      if (idx > 1L) {
        rm_comparison(idx)
        n_comparisons(idx - 1L)
      }
    })

    # --- Render comparison panels ----------------------------------------

    # B3.27 -- Currently-selected comparison tab. Tracked in a reactiveVal
    # so that re-renders (rare, only on add/remove) can preserve the
    # active tab -- and so we can auto-switch to the freshly-added one.
    current_tab <- shiny::reactiveVal(NULL)
    shiny::observeEvent(input$comp_tabs, {
      current_tab(input$comp_tabs)
    }, ignoreInit = TRUE)

    output$comparison_panels <- shiny::renderUI({
      # Only n_comparisons() (add/remove) should re-trigger this UI.
      # Everything else lives behind isolate() so typing in a label
      # input doesn't blow away the whole tabset and reset to tab #1.
      n <- n_comparisons()
      if (n < 1L) return(NULL)
      shiny::isolate({
        # B3.26 -- When more than one comparison exists, render them as
        # navigable TABS instead of stacking vertically. Single comparison:
        # render directly (no tab chrome) so the page stays clean.
        if (n == 1L) {
          return(comparisonCardUI(ns, 1L,
                                  comparisons[["1"]], data, metadata))
        }
        panels <- lapply(seq_len(n), function(i) {
          bslib::nav_panel(
            title = paste("Comparison", i),
            value = paste0("comp_", i),
            comparisonCardUI(ns, i, comparisons[[as.character(i)]], data, metadata)
          )
        })
        # Preserve the user's active tab across re-renders. If the saved
        # tab no longer exists (rm_btn), fall back to the last tab.
        sel <- current_tab()
        valid_values <- paste0("comp_", seq_len(n))
        if (is.null(sel) || !sel %in% valid_values) {
          sel <- paste0("comp_", n)   # default to most recently added
        }
        tabs <- do.call(
          bslib::navset_underline,
          c(panels, list(id = ns("comp_tabs"), selected = sel))
        )
        shiny::tags$div(class = "de-comparison-tabs", tabs)
      })
    })

    # When the user clicks "Add comparison", auto-switch to the new tab
    # so they land on it instead of staying on Comparison 1.
    shiny::observeEvent(input$add_btn, {
      current_tab(paste0("comp_", n_comparisons()))
    }, ignoreInit = TRUE)

    # --- Public reactives ------------------------------------------------

    comparisons_spec <- shiny::reactive({
      n <- n_comparisons()
      lapply(seq_len(n), function(i) {
        snapshot_spec(comparisons[[as.character(i)]])
      })
    })

    is_ready <- shiny::reactive({
      specs <- comparisons_spec()
      if (length(specs) == 0L) return(FALSE)
      records <- lapply(specs, validate_comparison, metadata = metadata)
      all(vapply(records, function(rs) {
        !any(vapply(rs, function(r) r$severity == "error", logical(1)))
      }, logical(1)))
    })

    # Toggle Start DE button enabled/disabled.
    shiny::observe({
      shinyjs::toggleState(id = "startDE", condition = is_ready())
    })

    # D2.3: bookmark-side save of the structured comparisons_spec.
    # Restore is intentionally NOT wired here -- the comparisons rv is a
    # reactiveValues-of-reactiveValues structure that's tricky to
    # recreate from a flat spec. D2.4 adds the live restore logic that
    # walks the saved spec and replays the per-comparison add flow.
    # For D2.3, the spec is saved so D2.4 has data to work with; the
    # user manually re-selects samples on restore.
    shiny::onBookmark(function(state) {
      spec <- tryCatch(comparisons_spec(),
                       error = function(e) NULL,
                       warning = function(w) NULL)
      if (!is.null(spec) && length(spec) > 0L) {
        state$values$cs <- list(comparisons_spec = spec)
      }
    })

    # D2.4: live restore. Walks the saved spec into the per-comparison
    # reactiveValues structure and registers card observers so the UI
    # cards re-render. Built on top of D2.3's save-side hook above.
    # D2.5 refactor: shares the apply_spec helper above with the
    # initial_spec constructor path so both pathways behave identically.
    shiny::onRestore(function(state) {
      apply_spec(state$values$cs$comparisons_spec)
    })

    list(
      n_comparisons    = n_comparisons,
      start_de         = shiny::reactive(input$startDE),
      is_ready         = is_ready,
      comparisons_spec = comparisons_spec
    )
  })
}

# Per-comparison card UI. Renders the manual-path widgets directly and
# uses uiOutput slots for level pickers (shown when meta_column is set),
# advanced model settings, and validation messages -- all populated by
# observers in `install_card_observers()`.
comparisonCardUI <- function(ns, i, rv, data, metadata) {
  if (is.null(rv)) return(NULL)
  iid <- function(name) ns(paste0(name, "_", i))
  sample_choices <- colnames(data)
  meta_choices <- if (!is.null(metadata) && ncol(metadata) > 1L) {
    c("None -- pick samples manually" = NA_character_,
      stats::setNames(colnames(metadata)[-1], colnames(metadata)[-1]))
  } else {
    c("None -- pick samples manually" = NA_character_)
  }

  bslib::card(
    class = "de-comparison",
    bslib::card_header(shiny::textOutput(iid("title"), inline = TRUE)),
    bslib::card_body(
      bslib::card(
        class = "de-subcard",
        bslib::card_header("Sample grouping"),
        bslib::card_body(
          shiny::selectInput(iid("meta_column"),
            label = "Group by metadata column",
            choices = meta_choices,
            selected = if (is.na(rv$meta_column)) NA_character_ else rv$meta_column,
            width = "100%")
        )
      ),
      shiny::fluidRow(
        shiny::column(5,
          bslib::card(
            class = "de-subcard",
            bslib::card_header("Treatment"),
            bslib::card_body(
              shiny::uiOutput(iid("treatment_level_ui")),
              shiny::textInput(iid("treatment_label"),
                label = "Label", value = rv$treatment_label, width = "100%"),
              shiny::selectInput(iid("treatment_samples"),
                label = "Samples", choices = sample_choices,
                selected = rv$treatment_samples, multiple = TRUE, width = "100%")
            )
          )
        ),
        shiny::column(2,
          shiny::div(class = "de-swap-wrap",
            actionButtonDE(iid("swap"), "Swap", styleclass = "primary",
                           icon = shiny::icon("right-left"))
          )
        ),
        shiny::column(5,
          bslib::card(
            class = "de-subcard",
            bslib::card_header("Control"),
            bslib::card_body(
              shiny::uiOutput(iid("control_level_ui")),
              shiny::textInput(iid("control_label"),
                label = "Label", value = rv$control_label, width = "100%"),
              shiny::selectInput(iid("control_samples"),
                label = "Samples", choices = sample_choices,
                selected = rv$control_samples, multiple = TRUE, width = "100%")
            )
          )
        )
      ),
      bslib::card(
        class = "de-subcard",
        bslib::card_header("Differential expression model"),
        bslib::card_body(
          shiny::fluidRow(shiny::column(
            6,
            shiny::selectInput(iid("de_method"),
              label = "DE method",
              choices = c("DESeq2", "EdgeR", "Limma"),
              selected = rv$de_method, width = "100%")
          )),
          bslib::accordion(
            open = FALSE, multiple = FALSE,
            bslib::accordion_panel(
              title = "Advanced model settings",
              shiny::uiOutput(iid("advanced_ui"))
            )
          )
        )
      ),
      shiny::uiOutput(iid("validation_msgs"))
    )
  )
}
