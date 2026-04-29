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
        )
      ),
      debrowser::getJSLine(),
      debrowser::getTabUpdateJS()
    ),

    sidebar = bslib::sidebar(
      id = "shared_sidebar",
      width = 320, open = "open",
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
      title = "Data Prep", value = "panel0",
      bslib::navset_pill_list(
        id = "DataPrep",
        widths = c(3, 9),
        well = FALSE,
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
          tagList(
            de_card(
              title = "DE Filter",
              uiOutput("cutOffUI"),
              uiOutput("compselectUI")
            ),
            conditionalPanel(
              condition = "input.goDE || input.goDEFromFilter",
              uiOutput("deresUI")
            )
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
