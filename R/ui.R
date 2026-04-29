#' deUI
#'
#' Creates a shinyUI to be able to run DEBrowser interactively.
#' B1 shell: bslib::page_navbar with 5 nav panels (Data Prep / Main Plots /
#' QC Plots / GO Term / Tables), Slate + OK-blue theme, light/dark toggle.
#'
#' @note \code{deUI}
#' @return the page tagList for DEBrowser
#'
#' @examples
#' x <- deUI()
#'
#' @export
deUI <- function() {
  addResourcePath(
    prefix = "www",
    directoryPath = system.file("extdata", "www", package = "debrowser")
  )

  version_label <- getNamespaceVersion("debrowser")

  bslib::page_navbar(
    id      = "methodtabs",
    title   = HTML(paste0(
      "DEBrowser <span class='text-light opacity-50 small ms-1'>v",
      version_label, "</span>"
    )),
    window_title = paste0("DEBrowser v", version_label),
    theme   = de_theme(),
    bg      = "#0f172a",
    inverse = TRUE,
    fillable = FALSE,

    header = tagList(
      shinyjs::useShinyjs(),
      shinyjs::inlineCSS("
        #loading-debrowser {
          position: absolute;
          background: #000000;
          opacity: 0.9;
          z-index: 100;
          left: 0; right: 0;
          height: 100%;
          text-align: center;
          color: #EFEFEF;
        }"),
      tags$div(
        h4(paste0("Loading DEBrowser v", version_label)),
        id = "loading-debrowser",
        tags$img(src = "www/images/initial_loading.gif")
      ),
      tags$head(
        tags$link(
          rel = "stylesheet", type = "text/css",
          href = "www/debrowser.css"
        ),
        tags$script(src = "www/dropzone.js")
      ),
      debrowser::getJSLine(),
      debrowser::getTabUpdateJS()
    ),

    sidebar = bslib::sidebar(
      id = "shared_sidebar",
      width = 250, open = "open",

      # Data Prep tab — wizard nav lives in the sidebar (was nested in
      # navset_pill_list inside the panel content prior to B1.16). DE
      # Filter (cutoff + comparison-selector) docks below the wizard nav
      # when on the DEAnalysis step (matches pre-B1 sidebar location;
      # B1.2 had moved it into the DEAnalysis panel content but the user
      # asked for the sidebar location).
      conditionalPanel(
        condition = "input.methodtabs == 'panel0'",
        tags$div(
          class = "wizard-step-list list-group list-group-flush",
          actionLink("nav_DataPrep_Intro",       "Quick Start Guide",
                     class = "list-group-item list-group-item-action"),
          actionLink("nav_DataPrep_Upload",      de_progress_label("Upload", "upload"),
                     class = "list-group-item list-group-item-action",
                     `data-progress-pill` = "upload"),
          conditionalPanel(
            condition = "input.Filter",
            actionLink("nav_DataPrep_Filter",      de_progress_label("Filter", "filter"),
                       class = "list-group-item list-group-item-action",
                       `data-progress-pill` = "filter")
          ),
          conditionalPanel(
            condition = "input.Batch",
            actionLink("nav_DataPrep_BatchEffect", de_progress_label("BatchEffect", "batch"),
                       class = "list-group-item list-group-item-action",
                       `data-progress-pill` = "batch")
          ),
          conditionalPanel(
            condition = "input.goDE || input.goDEFromFilter",
            actionLink("nav_DataPrep_CondSelect",  de_progress_label("CondSelect", "condselect"),
                       class = "list-group-item list-group-item-action",
                       `data-progress-pill` = "condselect")
          ),
          conditionalPanel(
            condition = "input.startDE || input['cs-startDE']",
            actionLink("nav_DataPrep_DEAnalysis",  de_progress_label("DE Analysis", "de"),
                       class = "list-group-item list-group-item-action",
                       `data-progress-pill` = "de")
          )
        ),
        conditionalPanel(
          condition = "input.DataPrep == 'DEAnalysis'",
          tags$hr(),
          tags$h6("DE Filter", style = "font-weight: 600; margin-top: 8px;"),
          uiOutput("cutOffUI"),
          uiOutput("compselectUI")
        )
      ),

      # Plot/table tabs — existing left-menu content
      conditionalPanel(
        condition = "input.methodtabs != 'panel0'",
        conditionalPanel(
          condition = "(output.dataready)",
          conditionalPanel(
            condition = "input.methodtabs == 'panel1'",
            debrowser::mainPlotControlsUI("main")
          ),
          uiOutput("downloadSection"),
          uiOutput("cutoffSelection"),
          uiOutput("leftMenu")
        )
      )
    ),

    bslib::nav_panel(
      title = de_progress_label("Data Prep", "data_prep"), value = "panel0",
      bslib::navset_hidden(
        id = "DataPrep",
        bslib::nav_panel(
          title = "Quick Start Guide", value = "Intro",
          bslib::navset_pill(
            bslib::nav_panel("Introduction",       debrowser::getIntroText()),
            bslib::nav_panel("Data Assesment",     debrowser::getDataAssesmentText()),
            bslib::nav_panel("Data Preparation",   debrowser::getDataPreparationText()),
            bslib::nav_panel("DE Analysis",        debrowser::getDEAnalysisText()),
            bslib::nav_panel("FAQ",                debrowser::getQAText())
          )
        ),
        bslib::nav_panel(
          title = "Upload", value = "Upload",
          debrowser::dataLoadUI("load")
        ),
        bslib::nav_panel(
          title = "Filter", value = "Filter",
          conditionalPanel(
            condition = "input.Filter",
            debrowser::dataLCFUI("lcf")
          )
        ),
        bslib::nav_panel(
          title = "BatchEffect", value = "BatchEffect",
          conditionalPanel(
            condition = "input.Batch",
            debrowser::batchEffectUI("batcheffect")
          )
        ),
        bslib::nav_panel(
          title = "CondSelect", value = "CondSelect",
          conditionalPanel(
            condition = "input.goDE || input.goDEFromFilter",
            debrowser::condSelectUI("cs")
          )
        ),
        bslib::nav_panel(
          title = "DE Analysis", value = "DEAnalysis",
          conditionalPanel(
            condition = "input.goDE || input.goDEFromFilter",
            uiOutput("deresUI")
          )
        )
      )
    ),

    bslib::nav_panel(
      title = "Main Plots", value = "panel1",
      uiOutput("mainmsgs"),
      uiOutput("mainpanel")
    ),

    bslib::nav_panel(
      title = "QC Plots", value = "panel2",
      uiOutput("qcpanel")
    ),

    bslib::nav_panel(
      title = "GO Term", value = "panel3",
      uiOutput("gopanel")
    ),

    bslib::nav_panel(
      title = "Tables", value = "panel4",
      DT::dataTableOutput("tables")
    ),

    bslib::nav_spacer(),

    bslib::nav_item(
      bslib::input_dark_mode(id = "dark_mode", mode = "light")
    ),

    bslib::nav_item(
      tags$a(
        href = "https://www.umassmed.edu/biocore/",
        target = "_blank",
        class = "nav-link",
        "UMMS Biocore"
      )
    )
  )
}
