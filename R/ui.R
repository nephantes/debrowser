#' deUI
#'
#' Creates a shinyUI to be able to run DEBrowser interactively.
#' B1 shell: bslib::page_navbar with 5 nav panels (Data Prep / Main Plots /
#' QC Plots / GO Term / Tables), Slate + OK-blue theme, light/dark toggle.
#'
#' Accepts a Shiny `request` argument so that the theme can be swapped at
#' runtime via the `?preset=NAME` query parameter (e.g. `?preset=zephyr`).
#' Unknown or missing `preset` keeps the default theme.
#'
#' @param req Shiny request object (auto-supplied by Shiny when `deUI` is
#'   used as the `ui` argument to `shinyApp()`).
#' @note \code{deUI}
#' @return the page tagList for DEBrowser
#'
#' @examples
#' \dontrun{
#'   shiny::shinyApp(ui = deUI, server = deServer)
#' }
#'
#' @export
deUI <- function(req = NULL) {
  addResourcePath(
    prefix = "www",
    directoryPath = system.file("extdata", "www", package = "debrowser")
  )

  version_label <- getNamespaceVersion("debrowser")

  # Theme playground: ?preset=NAME swaps the bslib preset at runtime.
  # Precedence: explicit URL ?preset= wins, then `debrowser_preset` cookie,
  # then default. Unknown values → default Slate theme via de_theme().
  preset <- if (!is.null(req)) {
    p <- shiny::parseQueryString(req$QUERY_STRING)[["preset"]]
    if (is.null(p) || !nzchar(p)) p <- parse_preset_cookie(req$HTTP_COOKIE)
    p
  } else {
    NULL
  }

  # Visible badge so the active preset is obvious at a glance.
  preset_badge <- if (!is.null(preset)) {
    paste0(" <span class='badge bg-secondary ms-2 small'>preset: ",
           htmltools::htmlEscape(preset), "</span>")
  } else {
    ""
  }

  # Navbar coloring strategy (no non-standard classes):
  #  * Default mode: keep the original dark Slate (#0f172a) inline bg so
  #    nothing changes for users not using the playground.
  #  * Preset mode:  drop the inline bg and let a tiny <style> override
  #    paint the navbar with `var(--bs-primary)`, the standard Bootstrap 5
  #    CSS variable that bootswatch sets per preset. Result: the navbar
  #    bg automatically tracks whichever preset is active. `inverse=TRUE`
  #    is kept so bslib emits the standard `navbar-dark` class — light
  #    text on the colored bar.
  navbar_bg <- if (is.null(preset)) "#0f172a" else NULL

  bslib::page_navbar(
    id      = "methodtabs",
    title   = HTML(paste0(
      "DEBrowser <span class='text-light opacity-50 small ms-1'>v",
      version_label, "</span>", preset_badge
    )),
    window_title = paste0("DEBrowser v", version_label),
    theme    = de_theme(preset = preset),
    bg       = navbar_bg,
    inverse  = TRUE,
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
        # Bootswatch CDN preset (when ?preset=NAME is set). Each preset
        # gets a unique CDN URL so multiple browser tabs comparing presets
        # don't collide on a single shared bslib-compiled bootstrap.min.css.
        # Loaded BEFORE debrowser.css so our overrides still win.
        de_bootswatch_link(preset),
        # Preset mode: paint the navbar with the preset's --bs-primary so
        # the menu bar adapts. Uses standard Bootstrap CSS variables only
        # (no custom classes). Includes nav-link colors so contrast holds.
        if (!is.null(preset)) tags$style(htmltools::HTML(
          paste(
            ".navbar { background-color: var(--bs-primary) !important; }",
            ".navbar .navbar-brand, .navbar .nav-link { color: rgba(255,255,255,.85) !important; }",
            ".navbar .nav-link:hover, .navbar .nav-link.active, .navbar .navbar-brand:hover { color: #fff !important; }",
            ".navbar .badge.bg-secondary { background-color: rgba(0,0,0,.25) !important; }",
            sep = "\n"
          )
        )),
        tags$link(
          rel = "stylesheet", type = "text/css",
          href = "www/debrowser.css"
        ),
        tags$script(src = "www/dropzone.js"),
        # Wires the navbar preset picker → cookie + reload (see de_theme.R).
        de_preset_js(),
        # Dark-mode toggle: flips data-bs-theme on <html> on click.
        tags$script(htmltools::HTML(
          "document.addEventListener('click', function(e) {
             var btn = e.target.closest && e.target.closest('#dark_mode_toggle');
             if (!btn) return;
             var html = document.documentElement;
             var current = html.getAttribute('data-bs-theme');
             html.setAttribute('data-bs-theme', current === 'dark' ? 'light' : 'dark');
           });"
        ))
      ),
      debrowser::getJSLine(),
      debrowser::getTabUpdateJS()
    ),

    sidebar = bslib::sidebar(
      id = "shared_sidebar",
      width = 300, open = "open",

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
      tags$button(
        id = "dark_mode_toggle",
        type = "button",
        class = "nav-link de-theme-toggle",
        `aria-label` = "Toggle dark mode",
        title = "Toggle dark mode",
        # Shown in light mode; clicking switches to dark.
        tags$svg(
          class = "de-theme-icon de-theme-icon-moon",
          xmlns = "http://www.w3.org/2000/svg",
          viewBox = "0 0 16 16", width = "18", height = "18",
          fill = "currentColor", `aria-hidden` = "true",
          tags$path(d = "M6 .278a.77.77 0 0 1 .08.858 7.2 7.2 0 0 0-.878 3.46c0 4.021 3.278 7.277 7.318 7.277q.792-.001 1.533-.16a.79.79 0 0 1 .81.316.73.73 0 0 1-.031.893A8.35 8.35 0 0 1 8.344 16C3.734 16 0 12.286 0 7.71 0 4.266 2.114 1.312 5.124.06A.75.75 0 0 1 6 .278")
        ),
        # Shown in dark mode; clicking switches to light.
        tags$svg(
          class = "de-theme-icon de-theme-icon-sun",
          xmlns = "http://www.w3.org/2000/svg",
          viewBox = "0 0 16 16", width = "18", height = "18",
          fill = "currentColor", `aria-hidden` = "true",
          tags$path(d = "M8 11a3 3 0 1 1 0-6 3 3 0 0 1 0 6m0 1a4 4 0 1 0 0-8 4 4 0 0 0 0 8M8 0a.5.5 0 0 1 .5.5v2a.5.5 0 0 1-1 0v-2A.5.5 0 0 1 8 0m0 13a.5.5 0 0 1 .5.5v2a.5.5 0 0 1-1 0v-2A.5.5 0 0 1 8 13m8-5a.5.5 0 0 1-.5.5h-2a.5.5 0 0 1 0-1h2a.5.5 0 0 1 .5.5M3 8a.5.5 0 0 1-.5.5h-2a.5.5 0 0 1 0-1h2A.5.5 0 0 1 3 8m10.657-5.657a.5.5 0 0 1 0 .707l-1.414 1.415a.5.5 0 1 1-.707-.708l1.414-1.414a.5.5 0 0 1 .707 0m-9.193 9.193a.5.5 0 0 1 0 .707L3.05 13.657a.5.5 0 0 1-.707-.707l1.414-1.414a.5.5 0 0 1 .707 0m9.193 2.121a.5.5 0 0 1-.707 0l-1.414-1.414a.5.5 0 0 1 .707-.707l1.414 1.414a.5.5 0 0 1 0 .707M4.464 4.465a.5.5 0 0 1-.707 0L2.343 3.05a.5.5 0 1 1 .707-.707l1.414 1.414a.5.5 0 0 1 0 .708")
        )
      )
    ),

    # Theme preset picker. Persists choice in `debrowser_preset` cookie via
    # de_preset_js(). Reload-driven so the chosen preset's CSS is loaded
    # cleanly (bslib doesn't support hot-swapping themes mid-session).
    bslib::nav_item(de_preset_picker(current = preset)),

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
