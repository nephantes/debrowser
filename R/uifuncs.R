#' de_nav_chip
#'
#' B3.2 helper. Renders an HTML title for `bslib::nav_panel(title = ...)`
#' that consists of a small numbered chip + the panel name. Matches the
#' mockup header pattern (numbered tabs like in aidrift.geniohub.com).
#' Optionally accepts a `de_progress_label()`-style progress-pill marker
#' so the Data Prep tab keeps its workflow checkmark behavior.
#'
#' @param num integer/character -- the chip number (1..N)
#' @param label character -- the tab label
#' @param progress_pill optional progress pill key (e.g. `"data_prep"`)
#' @return an `htmltools::HTML` blob suitable for `nav_panel(title = ...)`
#' @examples
#' x <- de_nav_chip(1, "Data Prep")
#' @export
de_nav_chip <- function(num, label, progress_pill = NULL) {
  inner <- paste0(
    "<span class='de-nav-chip-num'>", num, "</span>",
    "<span class='de-nav-chip-label'>",
    htmltools::htmlEscape(label),
    "</span>"
  )
  if (!is.null(progress_pill)) {
    # Wrap in the existing progress-pill machinery so the Data Prep tab
    # still gets its tick / locked / done state.
    inner <- paste0(
      inner,
      "<span class='de-progress-icon' data-progress-pill='",
      progress_pill, "'></span>"
    )
  }
  htmltools::HTML(paste0(
    "<span class='de-nav-chip'>", inner, "</span>"
  ))
}

#' de_eyebrow
#'
#' B3 helper. Renders a small numbered chip + eyebrow label above a panel
#' headline. The CSS for `.de-eyebrow` and `.de-eyebrow-chip` lives in
#' inst/extdata/www/debrowser.css and is dormant until the redesign layer
#' is toggled on via `data-debrowser-redesign="1"` on `<html>`.
#'
#' @param num character / numeric -- the chip number (1..N)
#' @param label character -- the eyebrow text
#' @return an `htmltools::tag` (`<div class="de-eyebrow">`).
#' @examples
#' x <- de_eyebrow(1, "Upload & configure")
#' @export
de_eyebrow <- function(num, label) {
  htmltools::tags$div(
    class = "de-eyebrow",
    htmltools::tags$span(class = "de-eyebrow-chip", num),
    label
  )
}

#' de_headline
#'
#' B3 helper. Page-level headline rendered just under the eyebrow.
#'
#' @param text character -- the headline text
#' @return an `htmltools::tag` (`<h2 class="de-headline">`).
#' @examples
#' x <- de_headline("Bring your counts & metadata in.")
#' @export
de_headline <- function(text) {
  htmltools::tags$h2(class = "de-headline", text)
}

#' de_stat_strip
#'
#' B3 helper. Renders a compact pill-shaped strip of stats (counts of
#' samples / genes / conditions / current method) just under the headline.
#' Each item is built with `de_stat()`.
#'
#' @param ... `de_stat()` items
#' @return an `htmltools::tag` (`<div class="de-stat-strip">`).
#' @examples
#' x <- de_stat_strip(de_stat("6", "samples"), de_stat("30,739", "genes"))
#' @export
de_stat_strip <- function(...) {
  htmltools::tags$div(class = "de-stat-strip", ...)
}

#' de_stat
#'
#' B3 helper. Single stat inside a `de_stat_strip()`.
#'
#' @param value character -- the value (e.g. "6")
#' @param label character -- the trailing label (e.g. "samples")
#' @param color CSS color -- the dot color (default cyan)
#' @return an `htmltools::tag` (`<span>` with a dot + value + label).
#' @examples
#' x <- de_stat("6", "samples", color = "var(--de-cyan)")
#' @export
de_stat <- function(value, label, color = "var(--de-cyan)") {
  htmltools::tags$span(
    htmltools::tags$span(class = "de-stat-dot",
                         style = sprintf("background:%s", color)),
    htmltools::tags$b(value), " ", label
  )
}

#' de_workbar
#'
#' B3 helper. Small breadcrumb / toolbar row that sits above a tab's
#' headline. Accepts a current-tab label and optional trailing actions.
#'
#' @param crumb character -- current tab label, shown bold
#' @param ... trailing tags (e.g. `actionButton`s)
#' @return an `htmltools::tag` (`<div class="de-workbar">`).
#' @examples
#' x <- de_workbar("Data Prep")
#' @export
de_workbar <- function(crumb, ...) {
  htmltools::tags$div(
    class = "de-workbar",
    htmltools::tags$div(class = "de-crumbs",
                        "Workspace \u00b7 ", htmltools::tags$b(crumb)),
    htmltools::tags$div(class = "spacer"),
    ...
  )
}

#' getLeftMenu
#'
#' Generates the left menu for for plots within the DEBrowser.
#'
#' @param input, input values
#' @note \code{getLeftMenu}
#' @return returns the left menu according to the selected tab;
#' @examples
#' x <- getLeftMenu()
#' @export
#'
getLeftMenu <- function(input = NULL) {
  if (is.null(input)) {
    return(NULL)
  }
  leftMenu <- list(
    conditionalPanel(
      (condition <- "input.methodtabs=='panel1'"),
      getMainPlotsLeftMenu()
    ),
    conditionalPanel(
      (condition <- "input.methodtabs=='panel2'"),
      bslib::accordion(
        multiple = TRUE,
        open = c(" Plot Type", " Select Columns"),
        bslib::accordion_panel(
          " Plot Type",
          wellPanel(radioButtons(
            "qcplot",
            paste("QC Plots:", sep = ""),
            c(
              PCA = "pca", All2All = "all2all", Heatmap = "heatmap", IQR = "IQR",
              Density = "Density",
              LibraryDepth = "libraryDepth",
              DetectionRate = "detectionRate",
              MtPct = "mtPct",
              SampleDist = "sampleDist",
              Dispersion = "dispersion",
              SizeFactors = "sizeFactors",
              Cooks = "cooks"
            )
          ))
        ),
        getQCLeftMenu(input)
      )
    ),
    conditionalPanel(
      (condition <- "input.methodtabs=='panel3'"),
      actionButton("startGO", "Submit"),
      bslib::accordion(
        multiple = TRUE,
        open = c(" Plot Type", " Go Term Options", " GSEA (fgsea) Options"),
        bslib::accordion_panel(
          " Plot Type",
          wellPanel(radioButtons(
            "goplot", paste("Enrichment method:", sep = ""),
            c(
              enrichGO        = "enrichGO",
              enrichKEGG      = "enrichKEGG",
              Disease         = "disease",
              compareClusters = "compare",
              "GSEA (gseGO)"  = "GSEA",
              "GSEA (fgsea / .gmt or MSigDB)" = "fgseaGSEA"
            )
          ))
        ),
        getGOLeftMenu(),
        bslib::accordion_panel(
          " GSEA (fgsea) Options",
          conditionalPanel(
            (condition <- "input.goplot=='fgseaGSEA'"),
            enrichmentGmtUI("fgsea_gmt"),
            numericInput("fgsea_min_size", "Min set size", 15,
                         min = 1, step = 1),
            numericInput("fgsea_max_size", "Max set size", 500,
                         min = 1, step = 1),
            numericInput("fgsea_n_perm", "Permutations", 1000,
                         min = 100, step = 100),
            numericInput("fgsea_seed", "Seed", 1, step = 1)
          )
        )
      )
    ),
    conditionalPanel(
      (condition <- "input.methodtabs=='panel4'"),
      bslib::accordion(
        open = TRUE,
        bslib::accordion_panel(
          " Select Columns",
          uiOutput("getColumnsForTables")
        )
      )
    )
  )
  return(leftMenu)
}
#' getMainPlotsLeftMenu
#'
#' Generates the Main PLots Left menu to be displayed within the DEBrowser.
#'
#' @note \code{getMainPlotsLeftMenu}
#' @return returns the left menu according to the selected tab;
#' @examples
#' x <- getMainPlotsLeftMenu()
#' @export
#'
getMainPlotsLeftMenu <- function() {
  mainPlotsLeftMenu <- list(
    plotSizeMarginsUI("main", w = 600, h = 400),
    bslib::accordion(
      open = FALSE,
      bslib::accordion_panel(
        "Heatmap Options",
        heatmapControlsUI("heatmap"),
        plotSizeMarginsUI("heatmap", w = 550, h = 400)
      )
    ),
    plotSizeMarginsUI("barmain", w = 550, h = 400, t = 90),
    plotSizeMarginsUI("boxmain", w = 550, h = 400, t = 90)
  )
  return(mainPlotsLeftMenu)
}

#' getGOLeftMenu
#'
#' Generates the GO Left menu to be displayed within the DEBrowser.
#'
#' @note \code{getGOLeftMenu}
#' @return returns the left menu according to the selected tab;
#' @examples
#' x <- getGOLeftMenu()
#' @export
#'
getGOLeftMenu <- function() {
  bslib::accordion_panel(
    " Go Term Options",
    numericInput("gopvalue", "p.adjust <=",
      value = default_cutoffs()$gopvalue,
      min = 0, max = 1, step = 0.01
    ),
    getOrganismBox(),
    actionButton("GeneTableButton", "DE Genes"),
    conditionalPanel(
      (condition <- "input.goplot=='enrichKEGG'"),
      actionButton("KeggPathway", "KeggPathway")
    ),
    conditionalPanel(
      (condition <- "(input.goplot=='enrichGO' ||
          (input.goplot=='compare' && input.gofunc!='enrichDO' &&
          input.gofunc!='enrichKEGG'))"),
      selectInput("ontology", "Choose an ontology:",
        choices = c("CC", "MF", "BP")
      )
    ),
    conditionalPanel(
      (condition <- "input.goplot!='compare'"),
      selectInput("goextplot", "Plot Type:",
        choices = c("Summary", "Dotplot")
      )
    ),
    conditionalPanel(
      (condition <- "input.goplot=='compare'"),
      selectInput("gofunc", "Plot Function:",
        choices = c("enrichGO", "enrichDO", "enrichKEGG")
      )
    ),
    conditionalPanel(
      (condition <- "input.goplot=='GSEA'"),
      selectInput("sortfield", "Sort field:",
        choices = c("stat", "log2FoldChange")
      )
    ),
    downloadButton("downloadGOPlot", "Download Plots")
  )
}

#' getQCLeftMenu
#'
#' Generates the left menu to be used for QC plots within the
#' DEBrowser.
#'
#' @param input, input values
#' @note \code{getQCLeftMenu}
#' @return QC left menu
#' @examples
#' x <- getQCLeftMenu()
#' @export
#'
getQCLeftMenu <- function(input = NULL) {
  if (is.null(input)) {
    return(NULL)
  }
  list(
    bslib::accordion_panel(
      " Select Columns",
      uiOutput("columnSelForQC")
    ),
    bslib::accordion_panel(
      " QC Options",
      conditionalPanel(
        (condition <- "input.qcplot=='heatmap'"),
        plotSizeMarginsUI("heatmapQC"),
        heatmapControlsUI("heatmapQC")
      ),
      conditionalPanel(
        condition <- "(input.qcplot=='all2all')",
        plotSizeMarginsUI("all2all"),
        all2allControlsUI("all2all")
      ),
      conditionalPanel(
        condition <- "(input.qcplot=='Density')",
        plotSizeMarginsUI("density"),
        plotSizeMarginsUI("normdensity")
      ),
      conditionalPanel(
        condition <- "(input.qcplot=='IQR')",
        plotSizeMarginsUI("IQR"),
        plotSizeMarginsUI("normIQR")
      ),
      getHelpButton(
        "method",
        "http://debrowser.readthedocs.io/en/master/heatmap/heatmap.html"
      ),
      conditionalPanel(
        (condition <- "input.qcplot=='pca'"),
        bslib::accordion(
          open = FALSE,
          bslib::accordion_panel(
            "PCA Options",
            pcaPlotControlsUI("qcpca")
          )
        ),
        plotSizeMarginsUI("qcpca", w = 600, h = 400, t = 0, b = 0, l = 0, r = 0)
      )
    )
  )
}

#' getCutOffSelection
#'
#' Gathers the cut off selection for DE analysis
#'
#' @param nc, total number of comparisons
#' @note \code{getCutOffSelection}
#' @return returns the left menu according to the selected tab;
#' @examples
#' x <- getCutOffSelection()
#' @export
#'
getCutOffSelection <- function(nc = 1) {
  compselect <- getCompSelection("compselect", nc)
  list(conditionalPanel(
    (condition <- "input.dataset!='most-varied' &&
        input.methodtabs!='panel0'"),
    bslib::accordion(
      open = FALSE,
      bslib::accordion_panel(
        " Filter",
        shinyWidgets::radioGroupButtons(
          "cutoff_preset",
          label    = NULL,
          choices  = setNames(cutoff_presets()$name, cutoff_presets()$label),
          selected = "strict",
          size     = "sm",
          justified = TRUE
        ),
        numericInput("padj", "padj <=",
          value = default_cutoffs()$padj,
          min = 0, max = 1, step = 0.01
        ),
        numericInput("log2fc_cutoff", "|log2FC| >=",
          value = default_cutoffs()$log2fc,
          min = 0, step = 0.5
        ),
        compselect
      )
    )
  ))
}

#' getMainPanel
#'
#' main panel for volcano, scatter and maplot.
#' Barplot and box plots are in this page as well.
#'
#' @note \code{getMainPanel}
#' @return the panel for main plots;
#'
#' @examples
#' x <- getMainPanel()
#'
#' @export
#'
getMainPanel <- function() {
  list(
    bslib::layout_columns(
      col_widths = c(6, 6),
      getMainPlotUI("main"),
      getHeatmapUI("heatmap")
    ),
    bslib::layout_columns(
      col_widths = c(6, 6),
      getBarMainPlotUI("barmain"),
      getBoxMainPlotUI("boxmain")
    )
  )
}

#' getProgramTitle
#'
#' Generates the title of the program to be displayed within DEBrowser.
#' If it is called in a program, the program title will be hidden
#'
#' @param session, session var
#' @note \code{getProgramTitle}
#' @return program title
#' @examples
#' title <- getProgramTitle()
#' @export
#'
getProgramTitle <- function(session = NULL) {
  if (is.null(session)) {
    return(NULL)
  }
  DEBrowser <- NULL
  title <- parseQueryString(session$clientData$url_search)$title
  if (is.null(title) || title != "no") {
    DEBrowser <- list(titlePanel("DEBrowser"))
  } else {
    DEBrowser <- list(titlePanel(" "))
  }
  return(DEBrowser)
}

#' getLoadingMsg
#'
#' Creates and displays the loading message/gif to be displayed
#' within the DEBrowser.
#'
#' @param output, output message
#' @note \code{getLoadingMsg}
#' @return loading msg
#' @examples
#' x <- getLoadingMsg()
#' @export
#'
getLoadingMsg <- function(output = NULL) {
  addResourcePath(
    prefix = "www", directoryPath =
      system.file("extdata", "www",
        package = "debrowser"
      )
  )
  imgsrc_full <- "www/images/loading_start.gif"
  imgsrc_small <- "www/images/loading.gif"
  a <- list(
    tags$head(tags$style(type = "text/css", "
            #loadmessage {
            position: fixed;
            top: 0px;
            left: 0px;
            width: 100%;
            height: 100%;
            padding: 5px 0px 5px 0px;
            text-align: center;
            font-weight: bold;
            font-size: 100%;
            color: #000000;
            opacity: 0.8;
            z-index: 100;
            }
            #loadmessage_small {
            position: fixed;
            left: 50%;
            transform: translateX(-50%);
            top: 50px;
            text-align: center;
            opacity: 0.8;
            z-index: 999999;
            }
                             ")),
    conditionalPanel(
      condition = paste0(
        "$('html').hasClass('shiny-busy')",
        "& input.startDE & input.methodtabs=='panel0'"
      ),
      tags$div(
        id = "loadmessage",
        tags$img(src = imgsrc_full)
      )
    ),
    conditionalPanel(
      condition = paste0(
        "$('html').hasClass('shiny-busy')",
        "& !(input.startDE & input.methodtabs=='panel0')"
      ),
      tags$div(
        id = "loadmessage_small",
        tags$img(src = imgsrc_small)
      )
    )
  )
}

#' getLogo
#'
#' Generates and displays the logo to be shown within DEBrowser.
#'
#' @note \code{getLogo}
#' @return return logo
#' @examples
#' x <- getLogo()
#' @export
#'
getLogo <- function() {
  addResourcePath(
    prefix = "www", directoryPath =
      system.file("extdata", "www",
        package = "debrowser"
      )
  )
  imgsrc <- "www/images/logo.png"
  a <- list(img(src = imgsrc, align = "right"))
}

#' getStartupMsg
#'
#' Generates and displays the starting message within DEBrowser.
#'
#' @note \code{getStartupMsg}
#' @return return startup msg
#' @examples
#' x <- getStartupMsg()
#' @export
#'
getStartupMsg <- function() {
  a <- list(column(
    12,
    helpText("Please select a file or load the demo data."),
    helpText("For more information;"),
    helpText(
      a("Quick Start Guide",
        href = "http://debrowser.readthedocs.org",
        target = "_blank"
      ),
      getHelpButton("method", "http://debrowser.readthedocs.org")
    )
  ))
}

#' getAfterLoadMsg
#'
#' Generates and displays the message to be shown after loading data
#' within the DEBrowser.
#'
#' @note \code{getAfterLoadMsg}
#' @return return After Load Msg
#' @examples
#' x <- getAfterLoadMsg()
#' @export
#'
getAfterLoadMsg <- function() {
  a <- list(column(12, wellPanel(
    helpText("Please choose the appropriate conditions for DESeq analysis
            and press 'Run DESeq' button in the left menu"),
    helpText("To be able to select conditions please click
            'Condition1' or 'Condition2' boxes.
            You can also use delete button to remove the
            samples from the list.")
  )))
}

#' getStartPlotsMsg
#'
#' Generates and displays the starting messgae to be shown once
#' the user has first seen the main plots page within DEBrowser.
#'
#' @note \code{getStartPlotsMsg}
#' @return return start plot msg
#' @examples
#' x <- getStartPlotsMsg()
#' @export
#'
getStartPlotsMsg <- function() {
  a <- list(conditionalPanel(
    condition <- "!input.goMain",
    column(
      12,
      helpText("Please choose the appropriate parameters to discover
               more in DE Results"),
      getHelpButton("method", "http://debrowser.readthedocs.io/en/master/quickstart/quickstart.html")
    )
  ))
}

#' getCondMsg
#'
#' Generates and displays the current conditions and their samples
#' within the DEBrowser.
#'
#' @param dc, columns
#' @param input, selected comparison
#' @param cols, columns
#' @param conds, selected conditions
#' @note \code{getCondMsg}
#' @return return conditions
#' @examples
#' x <- getCondMsg()
#' @export
#'
getCondMsg <- function(dc = NULL, input = NULL, cols = NULL, conds = NULL) {
  if (is.null(cols) || is.null(conds)) {
    return(NULL)
  }
  num <- input$compselect
  if (is.null(num)) num <- 1
  cnd <- data.frame(cbind(conds, cols))
  cond_names <- dc[[as.numeric(num)]]$cond_names

  params_str <- paste(dc[[as.numeric(num)]]$demethod_params, collapse = ",")
  heatmap_str <- paste0(
    "<b>Heatmap Params: Scaled:</b> ", input[["heatmap-scale"]],
    " <b>Centered:</b> ", input[["heatmap-center"]],
    " <b>Log:</b> ", input[["heatmap-log"]],
    " <b>Pseudo-count:</b> ", input[["heatmap-pseudo"]]
  )
  a <- list(conditionalPanel(
    condition <- "input.goMain",
    de_card(
      title = "Plot Information",
      tags$div(
        style = "overflow-x:scroll",
        HTML(
          paste0(
            "<b>DE Params:</b> ", params_str,
            " - <b>Dataset:</b> ", input$dataset, " <b>Normalization:</b> ", input$norm_method,
            " - ", heatmap_str,
            "</br><b>", cond_names[1], ":</b> "
          ),
          paste(cnd[cnd$conds == unique(conds)[1], "cols"],
            collapse = ","
          ),
          paste0(" vs. ", "<b>", cond_names[2], ":", "</b> "),
          paste(cnd[cnd$conds == unique(conds)[2], "cols"],
            collapse = ","
          )
        ),
        getHelpButton(
          "method",
          "http://debrowser.readthedocs.io/en/master/quickstart/quickstart.html#the-main-plots-of-de-analysis"
        )
      )
    )
  ))
}

#' togglePanels
#'
#' User defined toggle to display which panels are to be shown within
#' DEBrowser.
#'
#' @param num, selected panel
#' @param nums, all panels
#' @param session, session info
#' @note \code{togglePanels}
#' @return invisible(NULL); called for the navbar nav_show / nav_hide /
#'   nav_select side effects on the methodtabs nav.
#' @examples
#' x <- togglePanels()
#' @export
#'
togglePanels <- function(num = NULL, nums = NULL, session = NULL) {
  if (is.null(num)) {
    return(NULL)
  }
  # D2.5 noise fix: skip nav_show/hide/select messages when the
  # shinymanager login wall is still mounted (pre-auth Token A) --
  # the methodtabs panel doesn't exist in the DOM yet, so every
  # message would error client-side with "There is no tabsetPanel
  # with id equal to 'methodtabs'". The post-auth session reload
  # (Token B) re-runs deServer and we'll fire these calls then.
  if (!is.null(session) && !auth_complete(session)) {
    return(invisible())
  }
  # E2.5: panel3 (formerly "GO Term") is now the consolidated
  # Enrichment tab; panel5 was removed. Only panels 0..4 remain.
  for (i in 0:4) {
    target <- paste0("panel", i)
    if (i %in% nums) {
      bslib::nav_show("methodtabs", target = target, session = session)
    } else {
      bslib::nav_hide("methodtabs", target = target, session = session)
    }
  }
  if (num) {
    bslib::nav_select("methodtabs", selected = paste0("panel", num),
                      session = session)
  }
}


#' getTableStyle
#'
#' User defined selection that selects the style of table to display
#' within the DEBrowser.
#'
#' @param dat, dataset
#' @param input, input params
#' @param padj, the name of the padj value column in the dataset
#' @param foldChange, the name of the foldChange column in the dataset
#' @param DEsection, if it is in DESection or not
#' @note \code{getTableStyle}
#' @return A `DT::datatable` HTML widget with row colouring driven by
#'   the supplied padj / log2FoldChange thresholds.
#' @examples
#' x <- getTableStyle()
#' @export
#'
getTableStyle <- function(
  dat = NULL, input = NULL,
  padj = c("padj"), foldChange = c("foldChange"), DEsection = TRUE
) {
  if (is.null(dat)) {
    return(NULL)
  }

  a <- dat
  if (!is.null(padj) && DEsection && all(padj %in% names(dat$x$data))) {
    a <- a %>% formatStyle(
      padj,
      color = styleInterval(
        c(0, input$padj),
        c("black", "white", "black")
      ),
      backgroundColor = styleInterval(
        input$padj, c("green", "white")
      )
    )
  }
  if (!is.null(foldChange) && DEsection && all(foldChange %in% names(dat$x$data))) {
    # input$padj and input$log2fc_cutoff here are the GLOBAL sidebar
    # cutoffs (from getCutOffSelection), not the namespaced per-plot
    # ones -- the main DT colours genes by the user's overall threshold.
    fc <- log2fc_to_fold(as.numeric(input$log2fc_cutoff))
    a <- a %>%
      formatStyle(
        foldChange,
        color = styleInterval(c(
          1 / fc,
          fc
        ), c("white", "black", "white")),
        backgroundColor = styleInterval(
          c(
            1 / fc,
            fc
          ),
          c("blue", "white", "red")
        )
      )
  }
  a
}

#' textareaInput
#'
#' Generates a text area input to be used for gene selection within
#' the DEBrowser.
#'
#' @param id, id of the control
#' @param label, label of the control
#' @param value, initial value
#' @param rows, the # of rows
#' @param cols, the # of  cols
#' @param class, css class
#' @return A `shiny::tags$div` containing a `<label>` and a
#'   `<textarea>` Shiny-bound input.
#' @examples
#' x <- textareaInput("genesetarea", "Gene Set",
#'   "Fgf21",
#'   rows = 5, cols = 35
#' )
#' @export
#'
textareaInput <- function(
  id, label, value, rows = 20, cols = 35,
  class = "form-control"
) {
  tags$div(
    class = "form-group shiny-input-container",
    tags$label("for" = id, label),
    tags$textarea(id = id, class = class, rows = rows, cols = cols, value)
  )
}

#' showObj
#'
#' Displays a shiny object.
#'
#' @param btns, show group of objects with shinyjs
#' @return invisible(NULL); called for the side effect of calling
#'   `shinyjs::show()` on each supplied id.
#' @examples
#' x <- showObj()
#' @export
#'
showObj <- function(btns = NULL) {
  if (is.null(btns)) {
    return(NULL)
  }
  for (btn in seq_along(btns)) {
    shinyjs::show(btns[btn])
  }
}

#' hideObj
#'
#' Hides a shiny object.
#'
#' @param btns, hide group of objects with shinyjs
#' @return invisible(NULL); called for the side effect of calling
#'   `shinyjs::hide()` on each supplied id.
#' @examples
#' x <- hideObj()
#' @export
#'
hideObj <- function(btns = NULL) {
  if (is.null(btns)) {
    return(NULL)
  }
  for (btn in seq_along(btns)) {
    shinyjs::hide(btns[btn])
  }
}

#' getDownloadSection
#'
#' download section button and dataset selection box in the
#' menu for user to download selected data.
#'
#' @param choices, main vs. QC section
#'
#' @note \code{getDownloadSection}
#' @return the panel for download section in the menu;
#'
#' @examples
#' x <- getDownloadSection()
#'
#' @export
#'
getDownloadSection <- function(choices = NULL) {
  list(conditionalPanel(
    (condition <- "input.methodtabs!='panel0'"),
    bslib::accordion(
      open = FALSE,
      bslib::accordion_panel(
        " Data Options",
        selectInput("dataset", "Choose a dataset:",
          choices = choices
        ),
        conditionalPanel(
          (condition <- "input.dataset=='selected'"),
          selectInput("selectedplot", "The plot used in selection:",
            choices = c("Main Plot", "Main Heatmap", "QC Heatmap")
          )
        ),
        selectInput("norm_method", "Normalization Method:",
          c("none", "MRN", "TMM", "RLE", "upperquartile"),
          selected = "MRN"
        ),
        downloadButton("downloadData", "Download Data"),
        conditionalPanel(
          condition = "input.dataset=='most-varied'",
          textInput("topn", "top-n", value = "500"),
          textInput("mincount", "total min count", value = "10")
        ),
        textareaInput("genesetarea", "Search",
          "",
          rows = 5, cols = 35
        ),
        helpText("Regular expressions can be used\n
          Ex: ^Al => Al.., Al$ => ...al")
      )
    )
  ))
}

#' getQCPanel
#'
#' Gathers the conditional panel for QC plots
#'
#' @param input, user input
#' @note \code{getQCSection}
#' @return the panel for QC plots
#'
#' @examples
#' x <- getQCPanel()
#'
#' @export
#'
getQCPanel <- function(input = NULL) {
  height <- "700"
  width <- "500"
  if (!is.null(input)) {
    height <- input$height
    width <- input$width
  }
  qcPanel <- list(
    wellPanel(
      helpText(HTML("Please select the parameters and press the
                            submit button in the left menu for the plots.
                            The default data set is <b>'most-varied'</b> 500 genes
                            and total min count is 10 in QC plots. Make sure to
                            change the parameters, if you need to look another part of th data.
                            For example if you need to draw plots for all detected genes after
                            filtering, select <b>'alldetected'</b> in
                            'Data Options' -> 'Choose Dataset' on the left menu.")),
      getHelpButton(
        "method",
        "http://debrowser.readthedocs.io/en/master/quickstart/quickstart.html#quality-control-plots"
      )
    ),
    conditionalPanel(
      condition = "input.qcplot == 'pca'",
      getPCAPlotUI("qcpca")
    ),
    conditionalPanel(
      condition = "(input.qcplot == 'heatmap')",
      getHeatmapUI("heatmapQC")
    ),
    conditionalPanel(
      condition = "(input.qcplot == 'IQR')",
      getIQRPlotUI("IQR"),
      getIQRPlotUI("normIQR")
    ),
    conditionalPanel(
      condition = "(input.qcplot == 'Density')",
      getDensityPlotUI("density"),
      getDensityPlotUI("normdensity")
    ),
    conditionalPanel(
      condition = "(input.qcplot == 'all2all')",
      getAll2AllPlotUI("all2all")
    ),
    conditionalPanel(
      condition = "(input.qcplot == 'libraryDepth')",
      qcLibraryDepthUI("libraryDepth")
    ),
    conditionalPanel(
      condition = "(input.qcplot == 'detectionRate')",
      qcDetectionRateUI("detectionRate")
    ),
    conditionalPanel(
      condition = "(input.qcplot == 'mtPct')",
      qcMtPctUI("mtPct")
    ),
    conditionalPanel(
      condition = "(input.qcplot == 'sampleDist')",
      qcSampleDistUI("sampleDist")
    ),
    conditionalPanel(
      condition = "(input.qcplot == 'dispersion')",
      qcDispersionUI("dispersion")
    ),
    conditionalPanel(
      condition = "(input.qcplot == 'sizeFactors')",
      qcSizeFactorsUI("sizeFactors")
    ),
    conditionalPanel(
      condition = "(input.qcplot == 'cooks')",
      qcCooksUI("cooks")
    )
  )
  return(qcPanel)
}

#' getSelectedCols
#'
#' gets selected columns
#'
#' @param data, all loaded data
#' @param datasetInput, selected dataset
#' @param input, user input params
#'
#' @return A subset of `data` (rows of `datasetInput`, columns selected
#'   in `input$col_list`), or NULL when neither input is provided.
#' @export
#'
#' @examples
#' getSelectedCols()
#'
getSelectedCols <- function(data = NULL, datasetInput = NULL, input = NULL) {
  if (is.null(data) || is.null(datasetInput)) {
    return(NULL)
  }
  selCols <- NULL
  if (!is.null(input$dataset)) {
    selection <- colnames(data)
    if (!is.null(input$col_list)) {
      selection <- input$col_list
    }

    selection <- selection[selection %in% colnames(data)]

    if (!is.null(selection)) {
      selCols <- data[rownames(datasetInput), selection]
    }
  }
  return(selCols)
}


#' removeExtraCols
#'
#' remove extra columns for QC plots
#'
#' @param dat, selected data
#'
#' @return `dat` with QC-extraneous columns (padj/foldChange/Legend/etc.)
#'   stripped, leaving only sample columns suitable for plotting.
#' @export
#'
#' @examples
#' removeExtraCols()
#'
removeExtraCols <- function(dat = NULL) {
  rcols <- c(
    names(dat)[grep("^padj", names(dat))],
    names(dat)[grep("^foldChange", names(dat))],
    names(dat)[grep("^log2FoldChange$", names(dat))],
    names(dat)[grep("^pvalue$", names(dat))],
    names(dat)[grep("^Legend$", names(dat))],
    names(dat)[grep("^Size$", names(dat))],
    names(dat)[grep("^log10padj$", names(dat))],
    names(dat)[grep("^x$", names(dat))],
    names(dat)[grep("^y$", names(dat))],
    names(dat)[grep("^M$", names(dat))],
    names(dat)[grep("^A$", names(dat))],
    names(dat)[grep("^ID$", names(dat))],
    names(dat)[grep("^stat$", names(dat))]
  )
  if (!is.null(rcols)) {
    dat <- dat[, !(names(dat) %in% rcols)]
  } else {
    dat
  }
}
