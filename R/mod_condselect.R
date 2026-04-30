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

#' Comparison-Selection wizard server.
#'
#' @param id module namespace id (must match the id passed to `condSelectUI`).
#' @param data count matrix.
#' @param metadata sample-metadata data.frame; first column is the sample id.
#'
#' @return list with `n_comparisons`, `start_de`, `is_ready`, `comparisons_spec`.
#' @export
condSelectServer <- function(id, data = NULL, metadata = NULL) {
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
          testType = "LRT",       shrinkage = "None"
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
          "DESeq2" = shiny::tagList(
            shiny::selectInput(session$ns(iid("fitType")), "Fit type",
              c("parametric", "local", "mean"),
              selected = rv$method_params$fitType),
            shiny::selectInput(session$ns(iid("betaPrior")), "betaPrior",
              c(FALSE, TRUE),
              selected = rv$method_params$betaPrior),
            shiny::selectInput(session$ns(iid("testType")), "Test type",
              c("LRT", "Wald"),
              selected = rv$method_params$testType),
            shiny::selectInput(session$ns(iid("shrinkage")), "Shrinkage",
              c("None", "apeglm", "ashr", "normal"),
              selected = rv$method_params$shrinkage)
          ),
          "EdgeR" = shiny::tagList(
            shiny::selectInput(session$ns(iid("edgeR_normfact")), "Normalization",
              c("TMM", "RLE", "upperquartile", "none"),
              selected = rv$method_params$edgeR_normfact),
            shiny::textInput(session$ns(iid("dispersion")), "Dispersion",
              value = rv$method_params$dispersion),
            shiny::selectInput(session$ns(iid("edgeR_testType")), "Test type",
              c("exactTest", "glmLRT"),
              selected = rv$method_params$edgeR_testType)
          ),
          "Limma" = shiny::tagList(
            shiny::selectInput(session$ns(iid("limma_normfact")), "Normalization",
              c("TMM", "RLE", "upperquartile", "none"),
              selected = rv$method_params$limma_normfact),
            shiny::selectInput(session$ns(iid("limma_fitType")), "Fit type",
              c("ls", "robust"),
              selected = rv$method_params$limma_fitType),
            shiny::selectInput(session$ns(iid("normBetween")), "Norm. Bet. Arrays",
              c("none", "scale", "quantile", "cyclicloess",
                "Aquantile", "Gquantile", "Rquantile", "Tquantile"),
              selected = rv$method_params$normBetween)
          )
        )
        shiny::tagList(
          method_block,
          shiny::selectInput(session$ns(iid("covariates")),
            label = "Covariates",
            choices = cov_choices,
            selected = rv$covariates,
            multiple = TRUE),
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
                          testType = "LRT",       shrinkage = "None"),
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

    output$comparison_panels <- shiny::renderUI({
      n <- n_comparisons()
      if (n < 1L) return(NULL)
      shiny::tagList(
        lapply(seq_len(n), function(i) {
          comparisonCardUI(ns, i, comparisons[[as.character(i)]], data, metadata)
        })
      )
    })

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
    bslib::card_header(shiny::textOutput(iid("title"), inline = TRUE)),
    bslib::card_body(
      shiny::fluidRow(shiny::column(
        12,
        shiny::selectInput(iid("meta_column"),
          label = "Group by metadata column",
          choices = meta_choices,
          selected = if (is.na(rv$meta_column)) NA_character_ else rv$meta_column)
      )),
      shiny::fluidRow(
        shiny::column(5,
          shiny::div(class = "side-card",
            shiny::h6("Treatment"),
            shiny::uiOutput(iid("treatment_level_ui")),
            shiny::textInput(iid("treatment_label"),
              label = "Label", value = rv$treatment_label),
            shiny::selectInput(iid("treatment_samples"),
              label = "Samples", choices = sample_choices,
              selected = rv$treatment_samples, multiple = TRUE)
          )
        ),
        shiny::column(2,
          shiny::div(style = "text-align:center; padding-top:60px;",
            actionButtonDE(iid("swap"), "Swap", styleclass = "primary",
                           icon = shiny::icon("arrows-left-right"))
          )
        ),
        shiny::column(5,
          shiny::div(class = "side-card",
            shiny::h6("Control"),
            shiny::uiOutput(iid("control_level_ui")),
            shiny::textInput(iid("control_label"),
              label = "Label", value = rv$control_label),
            shiny::selectInput(iid("control_samples"),
              label = "Samples", choices = sample_choices,
              selected = rv$control_samples, multiple = TRUE)
          )
        )
      ),
      shiny::fluidRow(shiny::column(
        4,
        shiny::selectInput(iid("de_method"),
          label = "DE method",
          choices = c("DESeq2", "EdgeR", "Limma"),
          selected = rv$de_method)
      )),
      bslib::accordion(
        open = FALSE, multiple = FALSE,
        bslib::accordion_panel(
          title = "Advanced model settings",
          shiny::uiOutput(iid("advanced_ui"))
        )
      ),
      shiny::uiOutput(iid("validation_msgs"))
    )
  )
}
