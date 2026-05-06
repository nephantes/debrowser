#' deServer
#'
#' Sets up shinyServer to be able to run DEBrowser interactively.
#'
#' @note \code{deServer}
#' @param input, input params from UI
#' @param output, output params to UI
#' @param session, session variable
#' @return the panel for main plots;
#'
#' @examples
#' deServer
#'
#' @export
#' @importFrom shiny actionButton actionLink addResourcePath column conditionalPanel downloadButton downloadHandler eventReactive fileInput fluidPage helpText isolate mainPanel need numericInput observe observeEvent outputOptions parseQueryString plotOutput radioButtons reactive reactiveValues renderPlot renderUI runApp selectInput shinyApp shinyServer shinyUI sidebarLayout sidebarPanel sliderInput stopApp tabPanel tabsetPanel textInput textOutput titlePanel uiOutput tags HTML h4 img icon updateNumericInput updateTabsetPanel updateTextInput validate wellPanel checkboxInput br p checkboxGroupInput onRestore reactiveValuesToList renderText onBookmark onBookmarked updateQueryString enableBookmarking htmlOutput onRestored NS reactiveVal withProgress tableOutput selectizeInput fluidRow div renderPrint renderImage verbatimTextOutput imageOutput renderTable incProgress a h3 strong h2 withMathJax updateCheckboxInput showNotification updateSelectInput moduleServer showModal modalDialog modalButton tagList req span updateRadioButtons setBookmarkExclude
#' @importFrom shinyjs show hide enable disable useShinyjs extendShinyjs js inlineCSS onclick
#' @importFrom DT datatable dataTableOutput renderDataTable formatStyle styleInterval formatRound
#' @importFrom ggplot2 aes geom_bar geom_point ggplot labs scale_x_discrete scale_y_discrete ylab autoplot theme_minimal theme geom_density geom_text element_blank margin facet_grid
#' @importFrom plotly renderPlotly plotlyOutput plot_ly add_bars event_data hide_legend %>% group_by ggplotly config
#' @importFrom gplots heatmap.2 redblue bluered
#' @importFrom igraph layout.kamada.kawai
#' @importFrom grDevices dev.off pdf colorRampPalette
#' @importFrom graphics barplot hist pairs par rect text plot
#' @importFrom stats aggregate as.dist cor cor.test dist hclust kmeans na.omit prcomp var sd model.matrix p.adjust runif cov mahalanobis quantile as.dendrogram density as.formula coef
#' @importFrom utils read.csv read.table write.table update.packages download.file read.delim data install.packages packageDescription installed.packages modifyList
#' @importMethodsFrom AnnotationDbi as.data.frame as.list colnames exists sample subset head mappedkeys ncol nrow subset keys mapIds select
#' @importMethodsFrom GenomicRanges as.factor setdiff
#' @importMethodsFrom IRanges as.matrix "colnames<-" mean nchar paste rownames toupper unique which as.matrix lapply "rownames<-" gsub
#' @importMethodsFrom S4Vectors eval grep grepl levels sapply t
#' @importMethodsFrom SummarizedExperiment cbind order rbind
#' @importFrom jsonlite fromJSON
#' @importFrom methods new is
#' @importFrom stringi stri_rand_strings
#' @importFrom annotate geneSymbols
#' @importFrom reshape2 melt
#' @importFrom clusterProfiler compareCluster enrichKEGG enrichGO gseGO bitr
#' @importFrom DESeq2 DESeq DESeqDataSetFromMatrix results estimateSizeFactors counts lfcShrink
#' @importFrom edgeR calcNormFactors equalizeLibSizes DGEList glmLRT exactTest estimateCommonDisp glmFit topTags
#' @importFrom limma lmFit voom eBayes topTable
#' @importFrom sva ComBat
#' @importFrom RCurl getURL
#' @import org.Hs.eg.db
#' @import shinyBS
#' @import colourpicker
#' @import RColorBrewer
#' @import heatmaply

deServer <- function(input, output, session) {
  options(warn = -1)

  # D2.3: server-side bookmarking. Bookmark dirs live under data_dir()
  # so they share the Docker volume mount with the upload cache and
  # users.sqlite (see Section 6 of the D2 spec). enableBookmarking is
  # called inside deServer so it activates per-session — Shiny
  # supports both module-level and app-level activation.
  ensure_data_dir()
  shiny::enableBookmarking("server")
  options(shiny.bookmarkStore =
            file.path(data_dir(), "shiny_bookmarks"))

  # SECURITY-CRITICAL: never put AI keys / file-input handles /
  # button counters into bookmark state. setBookmarkExclude is the
  # primary mechanism; redact_for_bookmark() in R/fct_bookmark_state.R
  # is the defense-in-depth pass.
  setBookmarkExclude(c(
    # AI namespace — entire E12.A inputs surface. Audited against
    # actual ns() IDs in mod_ai_settings.R + mod_ai_interpret.R.
    "ai_settings-enabled", "ai_settings-provider",
    "ai_settings-model", "ai_settings-api_key",
    "ai_settings-default_privacy", "ai_settings-save_settings",
    "ai_settings-test_provider", "ai_settings-refresh_models",
    "ai_settings-open_ai_modal",
    "ai_enrichment-ask", "ai_enrichment-question",
    "ai_enrichment-privacy", "ai_enrichment-top_n",
    # File-input handles (datapaths are per-session-tmp)
    "load-countdata", "load-metadata",
    "fgsea_gmt-manual_gmt",
    # Action-button counters (would re-fire side effects on restore).
    # Module-namespaced IDs first; deServer top-level IDs after.
    "load-uploadFile", "load-demo", "load-demo2",
    "lcf-submitLCF", "batcheffect-submitBatchEffect",
    "fgsea_gmt-msigdb_load",
    "cs-startDE", "cs-add_btn", "cs-rm_btn",
    "startDE", "Filter", "Batch", "goDE",
    "goDEFromFilter", "goMain", "goQCplots",
    "goQCplotsFromFilter", "resetsamples",
    "startGO"
  ))

  onBookmark(function(state) {
    # Stamp the package version so onRestore can do a compat check.
    state$values$debrowser_version <-
      as.character(utils::packageVersion("debrowser"))
    # Resolve and stamp the user_id so onBookmarked can insert the
    # ownership row even if the auth chain re-resolves later.
    state$values$user_id <- current_user(session)
  })

  onBookmarked(function(url) {
    # state_id is the last path segment of the bookmark URL.
    # Shiny constructs URLs like:
    #   <base>?_state_id_=<id>
    state_id <- sub(".*_state_id_=", "", url)
    if (!nzchar(state_id) || state_id == url) {
      # URL has no _state_id_ — nothing to track. Surface anyway.
      showNotification(paste("Bookmark URL:", url),
                       duration = NULL, type = "message")
      return()
    }
    user_id <- current_user(session)
    if (is.na(user_id) || is.null(user_id)) user_id <- "local"
    con <- tryCatch(user_db_connect(), error = function(e) NULL)
    if (!is.null(con)) {
      on.exit(DBI::dbDisconnect(con), add = TRUE)
      # Idempotent: re-bookmarking with the same content yields a
      # different state_id, so this is always an INSERT not an UPSERT.
      # Use tryCatch because the user row may not exist yet in
      # non-hosted mode (we only insert "local" lazily when bookmarked).
      tryCatch(
        user_db_bookmark_insert(con, state_id, user_id,
                                visibility = "private",
                                label = NA_character_),
        error = function(e) {
          # Auto-provision the implicit user row, then retry.
          # The FK from bookmarks.user_id requires a users row.
          tryCatch({
            user_db_create_user(con, user_id,
                                kind = if (identical(user_id, "local"))
                                         "local" else "header")
          }, error = function(e2) NULL)
          tryCatch(user_db_bookmark_insert(con, state_id, user_id,
                                           visibility = "private",
                                           label = NA_character_),
                   error = function(e3) NULL)
        }
      )
    }
    showModal(modalDialog(
      title = "Bookmark created",
      build_share_modal_ui(url, can_toggle = FALSE),
      easyClose = TRUE,
      footer = modalButton("Close")
    ))
  })

  onRestore(function(state) {
    # Authorization gate. Unknown / private-non-owner bookmarks
    # raise `bookmark_denied`; surface and abort.
    url_query <- shiny::parseQueryString(
      session$clientData$url_search %||% "")
    state_id <- url_query[["_state_id_"]]
    if (is.null(state_id) || !nzchar(state_id)) return(invisible())
    viewer <- current_user(session)
    if (is.na(viewer)) viewer <- NULL
    con <- tryCatch(user_db_connect(), error = function(e) NULL)
    if (!is.null(con)) {
      on.exit(DBI::dbDisconnect(con), add = TRUE)
      tryCatch(
        bookmark_authorize(con, state_id, viewer),
        bookmark_denied = function(cond) {
          showModal(modalDialog(
            title = "Bookmark not accessible",
            tagList(
              div(class = "alert alert-warning",
                  cond$message),
              div("Ask the owner to share the link or enable ",
                  tags$em("Shared via link"), " mode.")
            ),
            easyClose = TRUE,
            footer = modalButton("OK")
          ))
          # Hard-stop restore by clearing state values so downstream
          # observers see no useful state.
          state$values <- list()
          state$input  <- list()
          return()
        }
      )
    }

    # Version compatibility check.
    saved <- state$values$debrowser_version
    current <- as.character(utils::packageVersion("debrowser"))
    compat <- is_safe_to_restore(saved, current)
    if (!identical(compat, "safe")) {
      showModal(modalDialog(
        title = if (compat == "warn") "Bookmark from a different minor version"
                else "Bookmark from a different major version",
        tagList(
          div(class = "alert alert-warning",
              sprintf("This bookmark was made with debrowser %s; you're running %s.",
                      saved %||% "(unknown)", current)),
          div("The session will still attempt to restore. Some panels may behave unexpectedly.")
        ),
        easyClose = TRUE,
        footer = modalButton("OK")
      ))
    }

    # Defense-in-depth redaction. setBookmarkExclude SHOULD have
    # already removed AI inputs; this strips anything that slipped
    # through (e.g. a future module that forgot to exclude its key).
    state$values <- redact_for_bookmark(state$values)
    state$input  <- redact_for_bookmark(state$input)
  })

  onRestored(function(state) {
    # No-op for D2.3. D2.4 (account UI) will use this to re-select
    # the bookmarked tab.
  })

  shiny::observeEvent(input$bookmark_share, {
    session$doBookmark()
  })

  tryCatch(
    {
      if (!interactive()) {
        options(
          shiny.maxRequestSize = 30 * 1024^2,
          shiny.fullstacktrace = FALSE, shiny.trace = FALSE,
          shiny.autoreload = TRUE, warn = -1
        )
      }
      # To hide the panels from 1 to 4 and only show Data Prep
      togglePanels(0, c(0), session)

      choicecounter <- reactiveValues(nc = 0)

      # B2a: progress reactiveValues drives the wizard pill / Data Prep tab
      # icon decoration. Tab visibility is still managed by togglePanels()
      # in R/uifuncs.R; this is icon state only.
      # State enum per key: pending | done | locked | skipped | "" (blank)
      progress <- reactiveValues(
        upload     = "pending",
        filter     = "locked",
        batch      = "skipped",   # batch is optional; default to skipped
        condselect = "locked",
        de         = "locked"
      )

      # Broadcast every progress field on any change. Also derives the
      # Data Prep outer tab's "data_prep" key (done iff DE is done).
      observe({
        update_progress(session, "upload",     progress$upload)
        update_progress(session, "filter",     progress$filter)
        update_progress(session, "batch",      progress$batch)
        update_progress(session, "condselect", progress$condselect)
        update_progress(session, "de",         progress$de)
        update_progress(
          session, "data_prep",
          if (progress$de == "done") "done" else ""
        )
      })

      output$programtitle <- renderUI({
        togglePanels(0, c(0), session)
        getProgramTitle(session)
      })

      updata <- reactiveVal()
      filtd <- reactiveVal()
      batch <- reactiveVal()
      sel <- reactiveVal()
      dc <- reactiveVal()
      compsel <- reactive({
        cp <- 1
        if (!is.null(input$compselect_dataprep)) {
          cp <- input$compselect_dataprep
        }
        cp
      })

      # B1.16: wizard reveal moved entirely to UI-side conditionalPanels
      # in R/ui.R (sidebar's Data Prep section). Each step's actionLink is
      # wrapped in a conditionalPanel keyed on input.<trigger> > 0, so the
      # actionButton click counts (which never decrement) give us natural
      # high-water-mark reveal without server observers.
      #
      # Sidebar nav: 6 actionLinks in the Data Prep section call
      # nav_select on the navset_hidden(id="DataPrep") body.
      observeEvent(input$nav_DataPrep_Intro, {
        bslib::nav_select("DataPrep", "Intro", session = session)
      }, ignoreInit = TRUE)
      observeEvent(input$nav_DataPrep_Upload, {
        bslib::nav_select("DataPrep", "Upload", session = session)
      }, ignoreInit = TRUE)
      observeEvent(input$nav_DataPrep_Filter, {
        bslib::nav_select("DataPrep", "Filter", session = session)
      }, ignoreInit = TRUE)
      observeEvent(input$nav_DataPrep_BatchEffect, {
        bslib::nav_select("DataPrep", "BatchEffect", session = session)
      }, ignoreInit = TRUE)
      observeEvent(input$nav_DataPrep_CondSelect, {
        bslib::nav_select("DataPrep", "CondSelect", session = session)
      }, ignoreInit = TRUE)
      observeEvent(input$nav_DataPrep_DEAnalysis, {
        bslib::nav_select("DataPrep", "DEAnalysis", session = session)
      }, ignoreInit = TRUE)

      # Auto-advance the wizard when the user clicks a Submit/Start
      # button. (Previously these observers also called nav_show/nav_hide
      # on the now-replaced navset_pill_list; with navset_hidden those
      # are no-ops.) startDE / cs-startDE -- both ids exist post-A4ac.
      observeEvent(input$startDE, {
        bslib::nav_select("DataPrep", "DEAnalysis", session = session)
      }, ignoreInit = TRUE)
      observeEvent(input[["cs-startDE"]], {
        bslib::nav_select("DataPrep", "DEAnalysis", session = session)
      }, ignoreInit = TRUE)

      observe({
        updata(debrowserdataload("load", "Filter"))
        bslib::nav_select("DataPrep", "Upload", session = session)

        # B2a: when counts arrive, mark upload done and unlock filter.
        # Also auto-show the QC tab (panel2) so users can inspect raw
        # QC plots without first running DE.
        observeEvent(updata()$load(), {
          if (!is.null(updata()$load())) {
            progress$upload     <- "done"
            progress$filter     <- "pending"
            # B2a.12: re-upload mid-session -- reset downstream pills so
            # stale "done" decorations from a prior run don't carry over
            # onto the new dataset.
            progress$batch      <- "skipped"
            progress$condselect <- "locked"
            progress$de         <- "locked"
            bslib::nav_show("methodtabs", target = "panel2", session = session)
          }
        }, ignoreInit = TRUE)

        observeEvent(input$Filter, {
          if (!is.null(updata()$load())) {
            bslib::nav_select("DataPrep", "Filter", session = session)
            filtd(debrowserlowcountfilter("lcf", updata()$load()))
            # B2a: filter clicked -> mark filter done; unlock batch.
            progress$filter <- "done"
            progress$batch  <- "pending"
          }
        })
        observeEvent(input$Batch, {
          if (!is.null(filtd()$filter())) {
            bslib::nav_select("DataPrep", "BatchEffect", session = session)
            batch(debrowserbatcheffect("batcheffect", filtd()$filter()))
            # B2a: batch step entered -> mark batch done; unlock condselect.
            progress$batch      <- "done"
            progress$condselect <- "pending"
          }
        })

        observeEvent(input$goDEFromFilter, {
          if (is.null(batch())) batch(setBatch(filtd()))
          bslib::nav_select("DataPrep", "CondSelect", session = session)
          sel(condSelectServer(
            "cs",
            batch()$BatchEffect()$count, batch()$BatchEffect()$meta
          ))
          choicecounter$nc <- sel()$n_comparisons()
          # B2a: skipping past Filter+Batch -- mark them done/skipped.
          if (progress$filter != "done") progress$filter <- "done"
          if (progress$batch  == "pending" || progress$batch == "locked") {
            progress$batch <- "skipped"
          }
          progress$condselect <- "pending"
        })
        observeEvent(input$goDE, {
          bslib::nav_select("DataPrep", "CondSelect", session = session)
          sel(condSelectServer(
            "cs",
            batch()$BatchEffect()$count, batch()$BatchEffect()$meta
          ))
          choicecounter$nc <- sel()$n_comparisons()
          # B2a: condselect step entered.
          progress$condselect <- "pending"
        })
        observeEvent(req(sel())$start_de(), {
          if (is.null(batch()$BatchEffect()$count)) return()
          # Guard against double-clicks: a second click while
          # prepDataContainer is still running would reassign dc()
          # mid-render and intermittently leave the scatter plot blank.
          # on.exit() ensures the button isn't left stuck disabled if
          # anything below errors out.
          shinyjs::disable("cs-startDE")
          on.exit(shinyjs::enable("cs-startDE"), add = TRUE)
          # B2a: mark condselect done at this point (the user has
          # clicked start-de, which is the natural exit from the cs step).
          progress$condselect <- "done"
          progress$de         <- "pending"
          # Re-lock plot/GO/Table tabs while DE runs (existing behavior).
          togglePanels(0, c(0, 2), session)
          # B2.5: prepDataContainer rewritten to take a structured
          # comparisons_spec instead of reaching into the module's input
          # rv. We still call it at the parent session so the inner
          # debrowserdeanalysis modules bind to the top-level "DEResultsN"
          # ids that getDEResultsUI() renders.
          dc_res <- prepDataContainer(
            batch()$BatchEffect()$count,
            batch()$BatchEffect()$meta,
            sel()$comparisons_spec()
          )
          if (is.null(dc_res)) return()
          dc(dc_res)
          bslib::nav_select("DataPrep", "DEAnalysis", session = session)
          buttonValues$startDE <- TRUE
          buttonValues$goQCplots <- FALSE
          hideObj(c(
            "load-uploadFile", "load-demo",
            "load-demo2", "goQCplots", "goQCplotsFromFilter"
          ))
          # B2a: DE finished -- mark done, unlock all outer tabs, and
          # auto-navigate to Main Plots (panel1). The existing goMain
          # observer is preserved for back-navigation but no longer
          # required for the golden path.
          progress$de <- "done"
          togglePanels(1, c(0, 1, 2, 3, 4), session)
        })

        observeEvent(input$goMain, {
          bslib::nav_select("methodtabs", "panel1", session = session)
          togglePanels(0, c(0, 1, 2, 3, 4), session)
        })

        output$compselectUI <- renderUI({
          if (!is.null(sel()) && !is.null(sel()$n_comparisons())) {
            getCompSelection("compselect_dataprep", sel()$n_comparisons())
          }
        })

        install_cutoff_preset_observers(input, session)

        cutoff_servers_registered <- reactiveValues()
        output$cutOffUI <- renderUI({
          cutOffSelectionUI(paste0("DEResults", compsel()))
        })
        observeEvent(compsel(), {
          id <- paste0("DEResults", compsel())
          if (is.null(cutoff_servers_registered[[id]])) {
            cutOffSelectionServer(id)
            cutoff_servers_registered[[id]] <- TRUE
          }
        }, ignoreNULL = TRUE)
        # Sidebar uiOutputs live inside the "DEFilter" submenu in ui.R.
        # When that submenu is collapsed, Shiny's default suspend-when-
        # hidden behavior drops the renderUI on the floor and the controls
        # never populate. Force the outputs to stay alive so the moment
        # the user clicks DEFilter to expand, the cutoff + comparison
        # widgets are already rendered.
        outputOptions(output, "cutOffUI", suspendWhenHidden = FALSE)
        outputOptions(output, "compselectUI", suspendWhenHidden = FALSE)
        output$deresUI <- renderUI({
          column(12, getDEResultsUI(paste0("DEResults", compsel())))
        })
      })
      output$mainpanel <- renderUI({
        getMainPanel()
      })
      output$qcpanel <- renderUI({
        getQCPanel(input)
      })
      output$gopanel <- renderUI({
        getGoPanel()
      })
      output$cutoffSelection <- renderUI({
        nc <- 1
        if (!is.null(choicecounter$nc)) nc <- choicecounter$nc
        getCutOffSelection(nc)
      })
      output$downloadSection <- renderUI({
        choices <- c("most-varied", "alldetected")
        if (buttonValues$startDE) {
          choices <- c(
            "up+down", "up", "down",
            "comparisons", "alldetected",
            "most-varied", "selected"
          )
        }
        choices <- c(choices, "searched")
        getDownloadSection(choices)
      })

      output$leftMenu <- renderUI({
        getLeftMenu(input)
      })
      output$loading <- renderUI({
        getLoadingMsg()
      })
      output$logo <- renderUI({
        getLogo()
      })
      output$startup <- renderUI({
        getStartupMsg()
      })
      output$afterload <- renderUI({
        getAfterLoadMsg()
      })
      output$mainmsgs <- renderUI({
        if (is.null(condmsg())) {
          getStartPlotsMsg()
        } else {
          condmsg()
        }
      })
      buttonValues <- reactiveValues(
        goQCplots = FALSE, goDE = FALSE,
        startDE = FALSE
      )
      output$dataready <- reactive({
        query <- parseQueryString(session$clientData$url_search)
        jsonobj <- query$jsonobject
        if (!is.null(jsonobj) && (is.null(updata()) || is.null(updata()$load()))) {
          return(NULL)
        }
        hide(id = "loading-debrowser", anim = TRUE, animType = "fade")
        return(!is.null(init_data()))
      })
      outputOptions(output, "dataready",
        suspendWhenHidden = FALSE
      )

      observeEvent(input$resetsamples, {
        buttonValues$startDE <- FALSE
        showObj(c("goQCplots", "goDE"))
        hideObj(c("cs-add_btn", "cs-rm_btn", "cs-startDE"))
        choicecounter$nc <- 0
      })

      observe({
        if (!is.null(sel())) {
          choicecounter$nc <- sel()$n_comparisons()
        }
      })
      observeEvent(input$goQCplotsFromFilter, {
        if (is.null(batch())) batch(setBatch(filtd()))
        buttonValues$startDE <- FALSE
        buttonValues$goQCplots <- TRUE
        # B2a.12: once DE has run, keep all unlocked tabs visible
        # rather than re-hiding Main Plots + GO Term.
        if (isTRUE(progress$de == "done")) {
          togglePanels(2, c(0, 1, 2, 3, 4), session)
        } else {
          togglePanels(2, c(0, 2, 4), session)
        }
      })
      observeEvent(input$goQCplots, {
        buttonValues$startDE <- FALSE
        buttonValues$goQCplots <- TRUE
        # B2a.12: same post-DE preservation as goQCplotsFromFilter above.
        if (isTRUE(progress$de == "done")) {
          togglePanels(2, c(0, 1, 2, 3, 4), session)
        } else {
          togglePanels(2, c(0, 2, 4), session)
        }
      })
      comparison <- reactive({
        compselect <- 1
        if (!is.null(input$compselect)) {
          compselect <- as.integer(input$compselect)
        }
        dc()[[compselect]]
      })
      conds <- reactive({
        comparison()$conds
      })
      cols <- reactive({
        comparison()$cols
      })
      cond_names <- reactive({
        comparison()$cond_names
      })

      init_data <- reactive({
        if (buttonValues$startDE && !is.null(comparison()$init_data)) {
          comparison()$init_data
        } else if (!is.null(batch())) {
          batch()$BatchEffect()$count
        }
      })
      # E4.5: fitted DESeqDataSet for the active comparison. NULL for
      # non-DESeq2 methods or pre-DE; QC cards 5-7 (Dispersion / SizeFactors /
      # Cook's) handle that as an empty-state alert.
      post_de_dds <- reactive({
        cmp <- comparison()
        if (is.null(cmp)) return(NULL)
        cmp$dds
      })
      # E1: per-comparison DE result tables for the Enrichment tab. NULL
      # pre-DE so the tab's req() chain blocks rendering until DE has run.
      # Names come from comparison_labels(dc()) which produces
      # "<treatment> vs <control>" with " (N)" suffixes on collisions.
      de_results_list <- reactive({
        if (!isTRUE(buttonValues$startDE) || is.null(dc())) return(NULL)
        comps <- dc()
        all_labels <- comparison_labels(comps)
        out <- lapply(comps, function(x) x$init_data)
        keep <- !vapply(out, is.null, logical(1))
        out <- out[keep]
        if (length(out) == 0L) return(NULL)
        names(out) <- all_labels[keep]
        out
      })

      # E11 (post-redirect): Comparison Concordance top-level tab.
      # Pure consumer of de_results_list - no DE re-running. Visibility
      # is governed by the observer immediately below: the tab is
      # hidden at startup and shown only when there are 2+ comparisons.
      comparisonConcordanceServer(
        "comparison_concordance",
        de_results_react  = de_results_list,
        comparisons_react = dc
      )
      bslib::nav_hide("methodtabs", target = "panel_cc",
                      session = session)
      observe({
        d <- de_results_list()
        if (!is.null(d) && length(d) >= 2L) {
          bslib::nav_show("methodtabs", target = "panel_cc",
                          session = session)
        } else {
          bslib::nav_hide("methodtabs", target = "panel_cc",
                          session = session)
        }
      })

      # E2.5: fgsea-based GSEA inside the consolidated Enrichment tab
      # (panel3, formerly GO Term). Sidebar's GMT/MSigDB picker is
      # mounted here; a startGO + goplot=='fgseaGSEA' combo triggers a
      # run_gsea() pass per comparison.
      .fgsea_gmt        <- enrichmentGmtServer("fgsea_gmt")
      fgsea_pathways    <- .fgsea_gmt$pathways
      fgsea_gmt_state   <- .fgsea_gmt$state    # consumed by export module (Task 10)

      # E3: snapshot the analytical state on demand. Read on download click only;
      # nothing else depends on this reactive, so it does not invalidate other
      # computations. Returns NULL until DE has run.
      state_react <- shiny::reactive({
        if (!isTRUE(buttonValues$startDE) || is.null(dc())) return(NULL)

        count_mat <- batch()$BatchEffect()$count

        # filter inputs live in the lcf module's namespace
        lcf_input <- function(name) session$input[[paste0("lcf-", name)]]
        filter_method <- lcf_input("lcfmethod") %||% "Max"
        filter_cutoff <- switch(filter_method,
          "Max"  = as.numeric(lcf_input("maxCutoff")  %||% 10),
          "Mean" = as.numeric(lcf_input("meanCutoff") %||% 10),
          "CPM"  = as.numeric(lcf_input("CPMCutoff")  %||% 1)
        )
        filter_min_samples <- if (identical(filter_method, "CPM")) {
          as.integer(lcf_input("numSample") %||% (ncol(count_mat) - 1L))
        } else {
          NA_integer_
        }

        batch_input <- function(name) session$input[[paste0("batcheffect-", name)]]
        batch_method <- batch_input("batchmethod") %||% "none"
        batch_col    <- batch_input("batch")
        treat_col    <- batch_input("treatment")

        comps_spec <- if (!is.null(sel())) sel()$comparisons_spec() else list()

        comparisons <- lapply(seq_along(dc()), function(i) {
          cmp_spec <- if (i <= length(comps_spec)) comps_spec[[i]] else list()
          init <- dc()[[i]]$init_data
          sig_thresh_padj <- 0.05
          sig_thresh_lfc  <- 1
          n_sig <- if (!is.null(init) && all(c("padj", "log2FoldChange") %in% colnames(init))) {
            sum(!is.na(init$padj) & init$padj < sig_thresh_padj &
                abs(init$log2FoldChange) > sig_thresh_lfc)
          } else NA_integer_
          list(
            treatment_label   = cmp_spec$treatment_label   %||% "treatment",
            control_label     = cmp_spec$control_label     %||% "control",
            treatment_samples = cmp_spec$treatment_samples %||% character(0),
            control_samples   = cmp_spec$control_samples   %||% character(0),
            de_method         = cmp_spec$de_method         %||% "DESeq2",
            method_params     = cmp_spec$method_params     %||% list(),
            covariates        = cmp_spec$covariates        %||% character(0),
            n_features_in     = nrow(count_mat),
            n_sig_at_padj0.05_lfc1 = as.integer(n_sig)
          )
        })

        enrichment_state <- if (exists("fgsea_gmt_state", inherits = FALSE)) {
          fgsea_gmt_state()
        } else NULL

        list(
          meta = list(
            debrowser_version = utils::packageVersion("debrowser"),
            r_version         = R.version.string,
            timestamp         = Sys.time(),
            session_info      = utils::capture.output(utils::sessionInfo())
          ),
          load = list(
            source       = updata()$load()$data_source %||% NA_character_,
            counts_path  = NA_character_,   # original upload name not preserved through
            meta_path    = NA_character_,   # the load module today; minor, can refine later
            n_features   = nrow(count_mat),
            n_samples    = ncol(count_mat)
          ),
          filter = list(
            method         = filter_method,
            cutoff         = filter_cutoff,
            min_samples    = filter_min_samples,
            n_features_in  = nrow(updata()$load()$count),
            n_features_out = nrow(count_mat)
          ),
          batch = list(
            method           = batch_method,
            batch_column     = if (is.null(batch_col) || identical(batch_col, "None")) NA_character_ else batch_col,
            treatment_column = if (is.null(treat_col) || identical(treat_col, "None")) NA_character_ else treat_col
          ),
          comparisons = comparisons,
          enrichment  = enrichment_state,
          # E3.B: full filtered+batch-corrected matrix (all detected genes,
          # all samples) and the sample metadata table -- consumed by the
          # Sample Info / QC / PCA / All2All sections of the rich report.
          full_counts = count_mat,
          metadata    = batch()$BatchEffect()$meta
        )
      })

      exportMenuServer("export", state_react)

      # Phase E12.A: Settings dropdown wiring. Returns a reactive
      # yielding the current settings list, consumed by gates below.
      ai_settings <- debrowser::aiSettingsServer("ai_settings")

      .fgsea_id_col <- function(de) {
        if ("ID"   %in% names(de)) return("ID")
        if ("gene" %in% names(de)) return("gene")
        NA_character_
      }
      fgsea_results_by_comparison <- eventReactive(input$startGO, {
        req(input$goplot == "fgseaGSEA")
        if (is.null(fgsea_pathways())) {
          de_notify_warning(
            "Load gene sets first. Pick a source (.gmt upload or MSigDB) and click \"Load gene sets\" before Submit."
          )
          return(NULL)
        }
        if (is.null(de_results_list())) {
          de_notify_warning(
            "Run a DE analysis before requesting GSEA on its results."
          )
          return(NULL)
        }
        # Pre-flight: how many DE genes match the loaded pathway
        # universe? Mouse pathways vs. human DE (or vice versa) is the
        # classic species-mismatch trap -- fgsea returns 0 rows and the
        # user is left with a blank table. Catch it here and tell them
        # exactly what to fix.
        primary_de <- de_results_list()[[1]]
        primary_id_col <- .fgsea_id_col(primary_de)
        if (!is.na(primary_id_col)) {
          de_genes <- unique(as.character(primary_de[[primary_id_col]]))
          de_genes <- de_genes[nzchar(de_genes)]
          pw_universe <- unique(unlist(fgsea_pathways(),
                                       use.names = FALSE))
          n_overlap <- length(intersect(de_genes, pw_universe))
          overlap_pct <- if (length(de_genes) > 0L) {
            100 * n_overlap / length(de_genes)
          } else {
            0
          }
          if (n_overlap < input$fgsea_min_size) {
            de_notify_warning(sprintf(
              paste0(
                "Only %d of your %d DE genes (%.1f%%) match symbols in ",
                "the loaded gene sets. The most common cause is a ",
                "species mismatch (e.g. mouse gene sets loaded but ",
                "human DE input -- symbols are case-sensitive: PGK1 ",
                "won't match Pgk1). Reload MSigDB with the species ",
                "matching your DE genes, or upload a .gmt that uses ",
                "the same symbol convention."
              ),
              n_overlap, length(de_genes), overlap_pct
            ))
            return(NULL)
          }
        }
        results <- withProgress(message = "Running GSEA (fgsea)", value = 0.3, {
          lapply(de_results_list(), function(df) {
            run_gsea(df, pathways = fgsea_pathways(),
                     min_size = input$fgsea_min_size,
                     max_size = input$fgsea_max_size,
                     n_perm   = input$fgsea_n_perm,
                     seed     = input$fgsea_seed,
                     id_col   = .fgsea_id_col(df))
          })
        })
        # Even with overlap, every pathway might be filtered out by
        # min/max size -- surface that too instead of leaving the user
        # with a blank table and no clue.
        n_rows <- vapply(results, function(x) {
          if (is.data.frame(x)) nrow(x) else 0L
        }, integer(1))
        if (all(n_rows == 0L)) {
          de_notify_info(
            "GSEA finished but no pathways passed the size filters. Try lowering 'Min set size' or pick a collection with smaller pathways (e.g. Hallmark)."
          )
        }
        results
      }, ignoreNULL = TRUE)

      output$fgsea_show_heatmap <- reactive({
        length(fgsea_results_by_comparison()) >= 2L
      })
      outputOptions(output, "fgsea_show_heatmap",
                    suspendWhenHidden = FALSE)

      enrichmentNesHeatmapServer("fgsea_nes_heatmap",
                                 fgsea_results_by_comparison)

      fgsea_primary_result <- reactive({
        r <- fgsea_results_by_comparison()
        req(length(r) >= 1L)
        r[[1]]
      })

      output$fgsea_results_table <- DT::renderDT({
        df <- fgsea_primary_result()
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

      output$fgsea_download_results <- downloadHandler(
        filename = function() "gsea_results.tsv",
        content  = function(file) {
          df <- fgsea_primary_result()
          df$leading_edge <- vapply(df$leading_edge, paste, character(1),
                                    collapse = ";")
          utils::write.table(df, file = file, sep = "\t",
                             quote = FALSE, row.names = FALSE)
        }
      )

      fgsea_selected_pw <- reactive({
        sel <- input$fgsea_results_table_rows_selected
        df  <- fgsea_primary_result()
        req(length(sel) == 1L, nrow(df) >= sel)
        df$pathway[sel]
      })

      output$fgsea_enrichment_plot <- renderPlot({
        req(fgsea_selected_pw(), fgsea_pathways(), de_results_list())
        df <- de_results_list()[[1]]
        id_col <- .fgsea_id_col(df)
        stats <- df$log2FoldChange
        names(stats) <- as.character(df[[id_col]])
        stats <- sort(stats[is.finite(stats)], decreasing = TRUE)
        fgsea::plotEnrichment(fgsea_pathways()[[fgsea_selected_pw()]],
                              stats) +
          ggplot2::labs(title = fgsea_selected_pw())
      })

      output$fgsea_leading_edge <- renderText({
        sel <- input$fgsea_results_table_rows_selected
        df  <- fgsea_primary_result()
        req(length(sel) == 1L, nrow(df) >= sel,
            "leading_edge" %in% names(df))
        paste(df$leading_edge[[sel]], collapse = ", ")
      })

      # Phase E12.A: AI panel payload reactive. Produces the gene list
      # (leading edge of the currently-selected pathway), per-gene stats
      # from the primary DE result, and the enrichment context. NULL when
      # no pathway is selected -- panel disables Ask in that case.
      ai_enrichment_payload <- reactive({
        sel <- input$fgsea_results_table_rows_selected
        req(length(sel) == 1L)
        df <- fgsea_primary_result()
        # DT keeps the old selection across re-renders, so a row index
        # may temporarily point past the new result's nrow. Guard against
        # that -- and against a missing leading_edge column -- so the AI
        # panel reactive doesn't crash the whole tab with subscript
        # errors.
        req(is.data.frame(df), nrow(df) >= sel,
            "leading_edge" %in% names(df))
        pw_row     <- df[sel, , drop = FALSE]
        leading    <- df$leading_edge[[sel]]
        if (is.null(leading)) leading <- character(0)
        primary_de <- de_results_list()
        if (is.null(primary_de) || length(primary_de) == 0L) return(NULL)
        primary_de <- primary_de[[1]]
        id_col     <- .fgsea_id_col(primary_de)
        stats_df   <- if (is.na(id_col) || length(leading) == 0L) NULL else {
          keep <- as.character(primary_de[[id_col]]) %in% leading
          data.frame(
            gene_id        = as.character(primary_de[[id_col]][keep]),
            log2FoldChange = primary_de$log2FoldChange[keep],
            padj           = primary_de$padj[keep],
            stringsAsFactors = FALSE
          )
        }
        list(
          genes      = leading,
          stats      = stats_df,
          enrichment = list(
            term      = pw_row$pathway,
            pvalue    = pw_row$padj,
            n_overlap = length(leading)
          )
        )
      })

      # Phase E12.A: gate the AI card visibility from JS-side
      # (conditionalPanel reads output$ai_panel_visibility).
      output$ai_panel_visibility <- reactive({
        s <- ai_settings()
        if (.has_required_credentials(s)) "show" else "hide"
      })
      outputOptions(output, "ai_panel_visibility", suspendWhenHidden = FALSE)

      debrowser::aiInterpretServer("ai_enrichment",
                                   payload_react = ai_enrichment_payload,
                                   settings_react = ai_settings)

      filt_data <- reactive({
        if (!is.null(init_data()) && !is.null(comparison()) && !is.null(input$padj)) {
          applyFilters(init_data(), cols(), conds(), input)
        }
      })

      selectedQCHeat <- reactiveVal()
      observe({
        if ((!is.null(input$genenames) && input$interactive == TRUE) ||
          (!is.null(input$genesetarea) && input$genesetarea != "")) {
          tmpDat <- init_data()
          if (!is.null(filt_data())) {
            tmpDat <- filt_data()
          }
          genenames <- ""
          if (!is.null(input$genenames)) {
            genenames <- input$genenames
          } else {
            tmpDat <- getSearchData(tmpDat, input)
            genenames <- paste(rownames(tmpDat), collapse = ",")
          }
        }
        if (!is.null(input$qcplot) && !is.null(normdat())) {
          if (input$qcplot == "all2all") {
            debrowserall2all("all2all", normdat(), input$cex)
          } else if (input$qcplot == "pca") {
            debrowserpcaplot("qcpca", normdat(), batch()$BatchEffect()$meta)
          } else if (input$qcplot == "heatmap") {
            selectedQCHeat(debrowserheatmap("heatmapQC", normdat()))
          } else if (input$qcplot == "IQR") {
            debrowserIQRplot("IQR", removeExtraCols(df_select()))
            debrowserIQRplot("normIQR", normdat())
          } else if (input$qcplot == "Density") {
            debrowserdensityplot("density", removeExtraCols(df_select()))
            debrowserdensityplot("normdensity", normdat())
          } else if (input$qcplot == "libraryDepth") {
            raw <- updata()$load()
            debrowserqclibrarydepth("libraryDepth",
              qc_keep_cols(raw$count, input$col_list),
              qc_keep_meta_rows(raw$meta, input$col_list),
              "treatment")
          } else if (input$qcplot == "detectionRate") {
            debrowserqcdetectionrate("detectionRate",
              qc_keep_cols(updata()$load()$count, input$col_list))
          } else if (input$qcplot == "mtPct") {
            debrowserqcmtpct("mtPct",
              qc_keep_cols(updata()$load()$count, input$col_list))
          } else if (input$qcplot == "sampleDist") {
            debrowserqcsampledist("sampleDist",
              qc_keep_cols(batch()$BatchEffect()$count, input$col_list))
          } else if (input$qcplot == "dispersion") {
            # Dispersion is a gene-level property of the fit; column
            # selection has no meaningful effect, so we always render the
            # full plot.
            debrowserqcdispersion("dispersion", post_de_dds())
          } else if (input$qcplot == "sizeFactors") {
            debrowserqcsizefactors("sizeFactors", post_de_dds(),
              selected_samples = input$col_list)
          } else if (input$qcplot == "cooks") {
            debrowserqccooks("cooks", post_de_dds(),
              selected_samples = input$col_list)
          }
        }
      })
      condmsg <- reactiveVal()
      selectedMain <- reactiveVal()
      observe({
        if (!is.null(filt_data())) {
          condmsg(getCondMsg(
            dc(), input,
            cols(), conds()
          ))
          selectedMain(debrowsermainplot("main", filt_data(), cond_names()))
        }
      })
      selectedHeat <- reactiveVal()
      observe({
        if (!is.null(selectedMain()) && !is.null(selectedMain()$selGenes())) {
          withProgress(message = "Creating plot", style = "notification", value = 0.1, {
            selectedHeat(debrowserheatmap("heatmap", filt_data()[selectedMain()$selGenes(), cols()]))
          })
        }
      })

      selgenename <- reactiveVal()
      observe({
        if (!is.null(selectedMain()) && !is.null(selectedMain()$shgClicked()) &&
          selectedMain()$shgClicked() != "") {
          selgenename(selectedMain()$shgClicked())
          if (!is.null(selectedHeat()) && !is.null(selectedHeat()$shgClicked()) &&
            selectedHeat()$shgClicked() != "") {
            js$resetInputParam("heatmap-hoveredgenenameclick")
          }
        }
      })
      observe({
        if (!is.null(selectedHeat()) && !is.null(selectedHeat()$shgClicked()) &&
          selectedHeat()$shgClicked() != "") {
          selgenename(selectedHeat()$shgClicked())
        }
      })

      observe({
        if (!is.null(selgenename()) && selgenename() != "") {
          withProgress(message = "Creating Bar/Box plots", style = "notification", value = 0.1, {
            debrowserbarmainplot("barmain", filt_data(),
              cols(), conds(), cond_names(), selgenename()
            )
            debrowserboxmainplot("boxmain", filt_data(),
              cols(), conds(), cond_names(), selgenename()
            )
          })
        }
      })

      normdat <- reactive({
        if (!is.null(init_data()) && !is.null(datasetInput())) {
          dat <- init_data()
          norm <- c()
          if (!is.null(cols())) {
            norm <- removeExtraCols(datasetInput())
          } else {
            norm <- getNormalizedMatrix(dat, input$norm_method)
          }
          getSelectedCols(norm, datasetInput(), input)
        }
      })

      df_select <- reactive({
        if (!is.null(init_data()) && !is.null(datasetInput())) {
          getSelectedCols(init_data(), datasetInput(), input)
        }
      })

      output$columnSelForQC <- renderUI({
        existing_cols <- colnames(removeExtraCols(datasetInput()))
        wellPanel(
          id = "tPanel",
          style = "overflow-y:scroll; max-height: 300px",
          checkboxGroupInput("col_list", "Select col to include:",
            existing_cols,
            selected = existing_cols
          )
        )
      })

      selectedData <- reactive({
        dat <- isolate(filt_data())
        ret <- c()
        if (input$selectedplot == "Main Plot" && !is.null(selectedMain())) {
          ret <- dat[selectedMain()$selGenes(), ]
        } else if (input$selectedplot == "Main Heatmap" && !is.null(selectedHeat())) {
          ret <- dat[selectedHeat()$selGenes(), ]
        } else if (input$selectedplot == "QC Heatmap" && !is.null(selectedQCHeat())) {
          ret <- dat[selectedQCHeat()$selGenes(), ]
        }
        ret
      })

      datForTables <- reactive({
        getDataForTables(
          input, normdat(),
          filt_data(), selectedData(),
          getMostVaried(), mergedComp()
        )
      })

      inputGOstart <- reactive({
        if (input$startGO) {
          withProgress(message = "GO Started", detail = "interactive", value = 0, {
            dat <- datForTables()
            getGOPlots(dat[[1]], isolate(getGSEARes()), input)
          })
        }
      })

      getGSEARes <- reactive({
        if (input$goplot == "GSEA") {
          dat <- datForTables()
          gopval <- as.numeric(input$gopvalue)
          getGSEA(dat[[1]],
            pvalueCutoff = gopval,
            org = input$organism, sortfield = input$sortfield
          )
        }
      })

      observeEvent(input$startGO, {
        inputGOstart()
      })

      output$GOPlots1 <- renderPlot({
        if (!is.null(inputGOstart()$p) && input$startGO) {
          if (input$goplot == "GSEA" && !is.null(input$gotable_rows_selected)) {
            require_pkg("enrichplot", feature = "GSEA plot")
            pid <- input$gotable_rows_selected
            p <- enrichplot::gseaplot(inputGOstart()$enrich_p,
              by = "all",
              title = inputGOstart()$enrich_p$Description[pid[1]],
              geneSetID = pid[1]
            )
            return(p)
          }
          return(inputGOstart()$p)
        }
      })
      observeEvent(input$KeggPathway, {
        if (is.null(input$gotable_rows_selected)) {
          showModal(modalDialog(
            title = "KEGG Pathway",
            size = "l",
            easyClose = TRUE,
            footer = modalButton("Close"),
            div(
              class = "alert alert-info de-modal-empty mb-0",
              "Please select a category in the GO/KEGG table to be able to see the pathway diagram."
            )
          ))
          return()
        }
        showModal(modalDialog(
          title = "KEGG Pathway",
          size = "l",
          easyClose = TRUE,
          footer = modalButton("Close"),
          tags$div(
            style = "display:block;overflow-y:auto;overflow-x:auto;",
            imageOutput("KEGGPlot")
          )
        ))
      })

      observeEvent(input$GeneTableButton, {
        if (is.null(input$gotable_rows_selected)) {
          showModal(modalDialog(
            title = "Genes in the category",
            size = "l",
            easyClose = TRUE,
            footer = modalButton("Close"),
            div(
              class = "alert alert-info de-modal-empty mb-0",
              "Please select a category in the GO/KEGG table to be able to see the gene list."
            )
          ))
          return()
        }
        showModal(modalDialog(
          title = "Genes in the category",
          size = "l",
          easyClose = TRUE,
          footer = modalButton("Close"),
          tags$div(
            style = "display:block;overflow-y:auto;overflow-x:auto;",
            wellPanel(DT::dataTableOutput("GOGeneTable"))
          )
        ))
      })

      output$KEGGPlot <- renderImage(
        {
          shiny::validate(need(
            !is.null(input$gotable_rows_selected),
            "Please select a category in the GO/KEGG table tab to be able to see the pathway diagram."
          ))

          withProgress(message = "KEGG Started", detail = "interactive", value = 0, {
            i <- input$gotable_rows_selected

            pid <- inputGOstart()$table$ID[i]

            drawKEGG(input, datForTables(), pid)
            list(
              src = paste0(pid, ".b.2layer.png"),
              contentType = "image/png"
            )
          })
        },
        deleteFile = TRUE
      )

      getGOCatGenes <- reactive({
        if (is.null(input$gotable_rows_selected)) {
          return(NULL)
        }
        org <- input$organism
        dat <- tabledat()
        if (is.null(dat)) {
          return(NULL)
        }
        i <- input$gotable_rows_selected
        if (input$goplot == "GSEA") {
          genes <- inputGOstart()$enrich_p$core_enrichment[i]
        } else {
          genes <- inputGOstart()$enrich_p$geneID[i]
        }

        genedata <- getEntrezTable(
          genes,
          dat[[1]], org
        )
        # `dat[[1]] <- NULL` would *remove* the data slot from the list
        # (shifting indices); coerce to an empty 0-row data frame so the
        # downstream renderer still has a data.frame to display.
        if (is.null(genedata)) {
          genedata <- dat[[1]][integer(0), , drop = FALSE]
        }
        dat[[1]] <- genedata
        dat
      })
      output$GOGeneTable <- DT::renderDataTable({
        shiny::validate(need(
          !is.null(input$gotable_rows_selected),
          "Please select a category in the GO/KEGG table to be able to see the gene list."
        ))
        dat <- getGOCatGenes()
        if (!is.null(dat)) {
          DT::datatable(dat[[1]],
            extensions = "Buttons",
            options = list(
              server = TRUE,
              dom = "Blfrtip",
              buttons =
                list("copy", list(
                  extend = "collection",
                  buttons = c("csv", "excel", "pdf"),
                  text = "Download"
                )), # end of buttons customization
              lengthMenu = list(
                c(10, 25, 50, 100),
                c("10", "25", "50", "100")
              ),
              pageLength = 25, paging = TRUE, searching = TRUE
            )
          ) %>%
            getTableStyle(input, dat[[2]], dat[[3]], buttonValues$startDE)
        }
      })

      output$getColumnsForTables <- renderUI({
        if (is.null(table_col_names())) {
          return(NULL)
        }
        selected_list <- table_col_names()
        if (!is.null(input$table_col_list) &&
          all(input$table_col_list %in% colnames(tabledat()[[1]]))) {
          selected_list <- input$table_col_list
        }
        colsForTable <- list(
          wellPanel(
            id = "tPanel",
            style = "overflow-y:scroll; max-height: 200px",
            checkboxGroupInput("table_col_list", "Select col to include:",
              table_col_names(),
              selected = selected_list
            )
          )
        )
        return(colsForTable)
      })
      table_col_names <- reactive({
        if (is.null(tabledat())) {
          return(NULL)
        }
        colnames(tabledat()[[1]])
      })
      tabledat <- reactive({
        dat <- datForTables()
        if (is.null(dat)) {
          return(NULL)
        }
        if (nrow(dat[[1]]) < 1) {
          return(NULL)
        }
        dat2 <- removeCols(c("ID", "x", "y", "Legend", "Size"), dat[[1]])

        pcols <- c(
          names(dat2)[grep("^padj", names(dat2))],
          names(dat2)[grep("pvalue", names(dat2))]
        )
        if (!is.null(pcols) && length(pcols) > 1) {
          dat2[, pcols] <- apply(
            dat2[, pcols], 2,
            function(x) format(as.numeric(x), scientific = TRUE, digits = 3)
          )
        } else {
          dat2[, pcols] <- format(as.numeric(dat2[, pcols]),
            scientific = TRUE, digits = 3
          )
        }
        rcols <- names(dat2)[!(names(dat2) %in% pcols)]
        if (!is.null(rcols) && length(rcols) > 1) {
          dat2[, rcols] <- apply(
            dat2[, rcols], 2,
            function(x) round(as.numeric(x), digits = 2)
          )
        } else {
          dat2[, rcols] <- round(as.numeric(dat2[, rcols]), digits = 2)
        }

        dat[[1]] <- dat2
        return(dat)
      })
      output$tables <- DT::renderDataTable({
        dat <- tabledat()
        if (is.null(dat) || is.null(table_col_names()) ||
          is.null(input$table_col_list) || length(input$table_col_list) < 1) {
          return(NULL)
        }
        if (!all(input$table_col_list %in% colnames(dat[[1]]), na.rm = FALSE)) {
          return(NULL)
        }
        # if (!dat[[2]] %in% input$table_col_list)
        #    dat[[2]] <- ""
        # if (!dat[[3]] %in% input$table_col_list)
        #    dat[[3]] <- ""

        datDT <- DT::datatable(dat[[1]][, input$table_col_list],
          extensions = "Buttons",
          options = list(
            server = TRUE,
            dom = "Blfrtip",
            buttons =
              list("copy", list(
                extend = "collection",
                buttons = c("csv", "excel", "pdf"),
                text = "Download"
              )), # end of buttons customization
            lengthMenu = list(
              c(10, 25, 50, 100),
              c("10", "25", "50", "100")
            ),
            pageLength = 25, paging = TRUE, searching = TRUE
          )
        ) %>%
          getTableStyle(input, dat[[2]], dat[[3]], buttonValues$startDE)
        return(datDT)
      })
      getMostVaried <- reactive({
        dat <- init_data()
        if (!is.null(cols())) {
          dat <- init_data()[, cols()]
        }
        getMostVariedList(dat, colnames(dat), input)
      })
      output$gotable <- DT::renderDataTable({
        if (!is.null(inputGOstart()$table)) {
          DT::datatable(inputGOstart()$table,
            rownames = FALSE,
            extensions = "Buttons",
            options = list(
              server = TRUE,
              dom = "Blfrtip",
              buttons =
                list("copy", list(
                  extend = "collection",
                  buttons = c("csv", "excel", "pdf"),
                  text = "Download"
                )), # end of buttons customization
              lengthMenu = list(
                c(10, 25, 50, 100),
                c("10", "25", "50", "100")
              ),
              pageLength = 25, paging = TRUE, searching = TRUE
            )
          )
        }
      })
      mergedComp <- reactive({
        dat <- applyFiltersToMergedComparison(isolate(dc()), choicecounter$nc, input)
        dat[dat$Legend == "Sig", ]
      })

      datasetInput <- function(addIdFlag = FALSE) {
        tmpDat <- NULL
        sdata <- NULL
        if (input$selectedplot != "QC Heatmap") {
          sdata <- selectedData()
        } else {
          sdata <- isolate(selectedData())
        }
        if (buttonValues$startDE) {
          mergedCompDat <- NULL
          if (input$dataset == "comparisons") {
            mergedCompDat <- mergedComp()
          }
          tmpDat <- getSelectedDatasetInput(
            rdata = filt_data(),
            getSelected = sdata, getMostVaried = getMostVaried(),
            mergedCompDat, input = input
          )
        } else {
          tmpDat <- getSelectedDatasetInput(
            rdata = init_data(),
            getSelected = sdata,
            getMostVaried = getMostVaried(),
            input = input
          )
        }
        if (addIdFlag) {
          tmpDat <- addID(tmpDat)
        }
        return(tmpDat)
      }
      output$metaFile <- renderTable({
        read.delim(system.file("extdata", "www", "metaFile.txt",
          package = "debrowser"
        ), header = TRUE, skipNul = TRUE)
      })
      output$countFile <- renderTable({
        read.delim(system.file("extdata", "www", "countFile.txt",
          package = "debrowser"
        ), header = TRUE, skipNul = TRUE)
      })

      output$downloadData <- downloadHandler(filename = function() {
        paste(input$dataset, "csv", sep = ".")
      }, content = function(file) {
        dat <- datForTables()
        dat2 <- removeCols(c("x", "y", "Legend", "Size"), dat[[1]])
        if (!("ID" %in% names(dat2))) {
          dat2 <- addID(dat2)
        }
        write.table(dat2, file, sep = ",", row.names = FALSE)
      })

      output$downloadGOPlot <- downloadHandler(filename = function() {
        paste(input$goplot, ".pdf", sep = "")
      }, content = function(file) {
        pdf(file)
        print(inputGOstart()$p)
        dev.off()
      })
    },
    err = function(errorCondition) {
      cat("in err handler")
      message(errorCondition)
    },
    warn = function(warningCondition) {
      cat("in warn handler")
      message(warningCondition)
    }
  )
}
