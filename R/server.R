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
#' @importFrom shiny actionButton actionLink addResourcePath column
#'             conditionalPanel downloadButton downloadHandler
#'             eventReactive fileInput fluidPage helpText isolate
#'             mainPanel need numericInput observe observeEvent
#'             outputOptions parseQueryString plotOutput radioButtons
#'             reactive reactiveValues renderPlot renderUI runApp
#'             selectInput shinyApp  shinyServer  shinyUI sidebarLayout
#'             sidebarPanel sliderInput  stopApp  tabPanel tabsetPanel
#'             textInput textOutput titlePanel uiOutput tags HTML
#'             h4 img icon updateNumericInput updateTabsetPanel updateTextInput  validate
#'             wellPanel checkboxInput br p checkboxGroupInput onRestore
#'             reactiveValuesToList renderText onBookmark onBookmarked
#'             updateQueryString enableBookmarking htmlOutput
#'             onRestored NS reactiveVal withProgress tableOutput
#'             selectizeInput fluidRow div renderPrint renderImage
#'             verbatimTextOutput imageOutput renderTable incProgress
#'             a h3 strong h2 withMathJax updateCheckboxInput
#'             showNotification updateSelectInput moduleServer
#'             showModal modalDialog modalButton tagList req
#'             span updateRadioButtons
#' @importFrom shinyjs show hide enable disable useShinyjs extendShinyjs
#'             js inlineCSS onclick
#' @importFrom DT datatable dataTableOutput renderDataTable formatStyle
#'             styleInterval formatRound
#' @importFrom ggplot2 aes geom_bar geom_point ggplot
#'             labs scale_x_discrete scale_y_discrete ylab
#'             autoplot theme_minimal theme geom_density
#'             geom_text element_blank margin facet_grid
#' @importFrom plotly renderPlotly plotlyOutput plot_ly add_bars event_data
#'             hide_legend %>% group_by ggplotly config
#' @importFrom gplots heatmap.2 redblue bluered
#' @importFrom igraph layout.kamada.kawai
#' @importFrom grDevices dev.off pdf colorRampPalette
#' @importFrom graphics barplot hist pairs par rect text plot
#' @importFrom stats aggregate as.dist cor cor.test dist
#'             hclust kmeans na.omit prcomp var sd model.matrix
#'             p.adjust runif cov mahalanobis quantile as.dendrogram
#'             density as.formula coef
#' @importFrom utils read.csv read.table write.table update.packages
#'             download.file read.delim data install.packages
#'             packageDescription installed.packages modifyList
#' @importMethodsFrom AnnotationDbi as.data.frame as.list colnames
#'             exists sample subset head mappedkeys ncol nrow subset
#'             keys mapIds select
#' @importMethodsFrom GenomicRanges as.factor setdiff
#' @importMethodsFrom IRanges as.matrix "colnames<-" mean
#'             nchar paste rownames toupper unique which
#'             as.matrix lapply "rownames<-" gsub
#' @importMethodsFrom S4Vectors eval grep grepl levels sapply t
#' @importMethodsFrom SummarizedExperiment cbind order rbind
#' @importFrom jsonlite fromJSON
#' @importFrom methods new is
#' @importFrom stringi stri_rand_strings
#' @importFrom annotate geneSymbols
#' @importFrom reshape2 melt
#' @importFrom clusterProfiler compareCluster enrichKEGG enrichGO gseGO bitr
#' @importFrom DESeq2 DESeq DESeqDataSetFromMatrix results estimateSizeFactors
#'             counts lfcShrink
#' @importFrom edgeR calcNormFactors equalizeLibSizes DGEList glmLRT
#'             exactTest estimateCommonDisp glmFit topTags
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
      # are no-ops.) startDE / cs-startDE — both ids exist post-A4ac.
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
            # B2a.12: re-upload mid-session — reset downstream pills so
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
            # B2a: filter clicked → mark filter done; unlock batch.
            progress$filter <- "done"
            progress$batch  <- "pending"
          }
        })
        observeEvent(input$Batch, {
          if (!is.null(filtd()$filter())) {
            bslib::nav_select("DataPrep", "BatchEffect", session = session)
            batch(debrowserbatcheffect("batcheffect", filtd()$filter()))
            # B2a: batch step entered → mark batch done; unlock condselect.
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
          # B2a: skipping past Filter+Batch — mark them done/skipped.
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
          # B2a: DE finished — mark done, unlock all outer tabs, and
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
            debrowserIQRplot("IQR", df_select())
            debrowserIQRplot("normIQR", normdat())
          } else if (input$qcplot == "Density") {
            debrowserdensityplot("density", df_select())
            debrowserdensityplot("normdensity", normdat())
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
            "Please select a category in the GO/KEGG table tab to be able
                to see the pathway diagram"
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
        dat[[1]] <- genedata
        dat
      })
      output$GOGeneTable <- DT::renderDataTable({
        shiny::validate(need(
          !is.null(input$gotable_rows_selected),
          "Please select a category in the GO/KEGG table to be able
                to see the gene list"
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
