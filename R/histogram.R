#' getHistogramUI
#'
#' Histogram plots UI.
#'
#' @note \code{getHistogramUI}
#' @param id, namespace id
#' @return the panel for PCA plots;
#'
#' @examples
#' x <- getHistogramUI("histogram")
#'
#' @export
#'
getHistogramUI <- function(id) {
  ns <- NS(id)
  uiOutput(ns("histogramUI"))
}

#' debrowserhistogram
#'
#' Module for a histogram that can be used in data prep and
#' low count removal modules
#'
#' @param id, namespace id
#' @param data, a matrix that includes expression values
#' @return histogram
#' @export
#'
#' @examples
#' \dontrun{
#' x <- debrowserhistogram("histogram")
#' }
#'
debrowserhistogram <- function(id, data = NULL) {
  if (is.null(data)) {
    return(NULL)
  }
  moduleServer(id, function(input, output, session) {
  output$histogram <- renderPlotly({
    withProgress(message = "Drawing histogram", style = "notification", value = 0.1, {
      h <- hist(log10(rowSums(data)), breaks = as.numeric(input$breaks), plot = FALSE)

      # Pin size to the host plotlyOutput rather than to never-defined
      # input$width/height (the histogramControlsUI only exposes a
      # "breaks" textInput, so those legacy inputs evaluated to NULL
      # and Plotly defaulted to ~700x500 inside an already-wide card,
      # producing the enormous filter-step histograms reported by
      # users). Compact margins keep the actual bars dominant over
      # axis padding.
      p <- plot_ly(
        x = h$mids, y = h$counts,
        type = "bar"
      ) %>%
        plotly::layout(
          autosize = TRUE,
          margin = list(l = 40, b = 36, t = 12, r = 12),
          xaxis = list(title = "log10(rowSums)"),
          yaxis = list(title = "Count")
        )
      p$elementId <- NULL
      if (!is.null(input$svg) && input$svg == TRUE) {
        p <- p %>% config(toImageButtonOptions = list(format = "svg"))
      }
      p
    })
  })
  output$histogramUI <- renderUI({
    de_card(
      title = "Plot",
      plotlyOutput(session$ns("histogram"),
        width  = "100%",
        height = "260px"
      )
    )
  })
  })
}

#' histogramControlsUI
#'
#' Generates the controls in the left menu for a histogram
#'
#' @note \code{histogramControlsUI}
#' @param id, namespace id
#' @return returns the left menu
#' @examples
#' x <- histogramControlsUI("histogram")
#' @export
#'
histogramControlsUI <- function(id) {
  ns <- NS(id)
  textInput(ns("breaks"), "Breaks", value = "100")
}
