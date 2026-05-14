#' debrowserlowcountfilter
#'
#' Module to filter low count genes/regions
#'
#' @param id, namespace id
#' @param ldata, loaded data
#' @return main plot
#'
#' @return panel
#' @export
#'
#' @examples
#' \dontrun{
#' x <- debrowserlowcountfilter("lcf")
#' }
#'
debrowserlowcountfilter <- function(id, ldata = NULL) {
  if (is.null(ldata)) {
    return(NULL)
  }
  moduleServer(id, function(input, output, session) {
  fdata <- reactiveValues(count = NULL, meta = NULL)
  observeEvent(input$submitLCF, {
    if (is.null(ldata$count)) {
      return(NULL)
    }
    fdata$count <- switch(input$lcfmethod,
      "Max"  = filter_low_counts(ldata$count, "max", input$maxCutoff),
      "Mean" = filter_low_counts(ldata$count, "mean", input$meanCutoff),
      "CPM"  = filter_low_counts(ldata$count, "cpm", input$CPMCutoff,
        min_samples = input$numSample
      )
    )
    fdata$meta <- ldata$meta
  })

  init_done <- reactiveVal(FALSE)
  observe({
    req(ldata$count)
    if (init_done()) return()
    # Apply the same default Max < 10 filter the user would get from
    # clicking Filter, so the after-histogram and filtered table populate
    # on data load. ldata is a closed-over plain list (not a reactive),
    # so this observe fires once on module flush; init_done + isolate()
    # are defensive in case the module's reactivity surface changes.
    method <- if (is.null(isolate(input$lcfmethod))) "Max" else isolate(input$lcfmethod)
    fdata$count <- switch(method,
      "Max"  = filter_low_counts(ldata$count, "max",
                                 if (is.null(isolate(input$maxCutoff)))  10 else as.numeric(isolate(input$maxCutoff))),
      "Mean" = filter_low_counts(ldata$count, "mean",
                                 if (is.null(isolate(input$meanCutoff))) 10 else as.numeric(isolate(input$meanCutoff))),
      "CPM"  = filter_low_counts(ldata$count, "cpm",
                                 if (is.null(isolate(input$CPMCutoff)))  1  else as.numeric(isolate(input$CPMCutoff)),
                                 min_samples = if (is.null(isolate(input$numSample)))
                                                 (ncol(ldata$count) - 1)
                                               else as.numeric(isolate(input$numSample)))
    )
    fdata$meta <- ldata$meta
    init_done(TRUE)
  })

  output$cutoffLCFMet <- renderUI({
    ret <- textInput(session$ns("maxCutoff"), "Filter features where Max Value <", value = "10")
    if (input$lcfmethod == "Mean") {
      ret <- textInput(session$ns("meanCutoff"), "Filter features where Row Means <", value = "10")
    } else if (input$lcfmethod == "CPM") {
      ret <- list(
        textInput(session$ns("CPMCutoff"), "Filter features where CPM <", value = "1"),
        textInput(session$ns("numSample"), "at least # of samples", value = toString(ncol(ldata$count) - 1))
      )
    }
    ret
  })

  filtereddata <- reactive({
    ret <- NULL
    if (!is.null(fdata$count)) {
      ret <- fdata
    }
    return(ret)
  })

  observe({
    getSampleDetails(output, "uploadSummary", "sampleDetails", ldata)
    getSampleDetails(output, "filteredSummary", "filteredDetails", filtereddata())
    getTableDetails(output, session, "loadedtable", data = ldata$count, modal = TRUE)
    debrowserhistogram("beforeFiltering", ldata$count)

    if (!is.null(filtereddata()$count) && nrow(filtereddata()$count) > 2) {
      getTableDetails(output, session, "filteredtable", data = filtereddata()$count, modal = TRUE)
      debrowserhistogram("afterFiltering", filtereddata()$count)
    }
  })

  list(filter = filtereddata)
  })
}

#' dataLCFUI
#' Creates a panel to filter low count genes and regions
#'
#' @param id, namespace id
#' @return panel
#' @examples
#' x <- dataLCFUI("lcf")
#'
#' @export
#'
dataLCFUI <- function(id) {
  ns <- NS(id)
  list(
    fluidRow(
      bslib::card(
        bslib::card_header("Low Count Filtering"),
        bslib::layout_columns(
          col_widths = c(5, 2, 5),
          tagList(
            div(
              style = "overflow: scroll",
              tableOutput(ns("uploadSummary")),
              DT::dataTableOutput(ns("sampleDetails"))
            ),
            uiOutput(ns("loadedtable"))
          ),
          de_card(
            title = "Filtering Methods",
            # B3.23 -- Filter form on top; next-step CTAs INSIDE the same
            # card, stacked vertically below the Filter button, all the
            # same width, with the last CTA pinned to the card bottom.
            div(
              class = "de-lcf-card-content",
              div(
                class = "de-lcf-form",
                lcfMetRadio(id),
                uiOutput(ns("cutoffLCFMet")),
                actionButtonDE(ns("submitLCF"), label = "Filter", styleclass = "primary")
              ),
              conditionalPanel(
                condition = paste0("input['", ns("submitLCF"), "']"),
                div(
                  class = "de-lcf-cta-stack",
                  actionButtonDE("Batch", label = "Batch Effect Correction", styleclass = "primary"),
                  conditionalPanel(
                    condition = "!(input.Batch)",
                    actionButtonDE("goDEFromFilter", "Go to DE Analysis", styleclass = "primary"),
                    actionButtonDE("goQCplotsFromFilter", "Go to QC plots", styleclass = "primary")
                  )
                )
              )
            )
          ),
          tagList(
            div(
              style = "overflow: scroll",
              tableOutput(ns("filteredSummary")),
              DT::dataTableOutput(ns("filteredDetails"))
            ),
            uiOutput(ns("filteredtable"))
          )
        ),
        # B3.23 -- The next-step CTAs were moved INSIDE the Filtering
        # Methods card above. This empty placeholder kept for visual
        # spacing only; intentionally rendering nothing.
        NULL
      ),
      bslib::card(
        bslib::card_header("Histograms"),
        fluidRow(
          column(
            6, histogramControlsUI(ns("beforeFiltering")),
            getHistogramUI(ns("beforeFiltering"))
          ),
          column(
            6, histogramControlsUI(ns("afterFiltering")),
            getHistogramUI(ns("afterFiltering"))
          )
        )
      )
    )
  )
}

#' lcfMetRadio
#'
#' Radio buttons for low count removal methods
#'
#' @param id, namespace id
#' @note \code{lcfMetRadio}
#' @return radio control
#'
#' @examples
#'
#' x <- lcfMetRadio("lcf")
#'
#' @export
#'
lcfMetRadio <- function(id) {
  ns <- NS(id)
  radioButtons(
    inputId = ns("lcfmethod"),
    label = "Low count filtering method:",
    choices = c(
      Max = "Max",
      Mean = "Mean",
      CPM = "CPM"
    ),
    selected = "Max"
  )
}
