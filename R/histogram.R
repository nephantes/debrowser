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
    h <- hist(log10(rowSums(data)), breaks = as.numeric(input$breaks), plot = FALSE)

    p <- plot_ly(
      x = h$mids, y = h$counts,
      width = input$width, height = input$height
    ) %>%
      add_bars() %>%
      plotly::layout(
        margin = list(
          l = input$left,
          b = input$bottom,
          t = input$top,
          r = input$right
        )
      )
    p$elementId <- NULL
    if (!is.null(input$svg) && input$svg == TRUE) {
      p <- p %>% config(toImageButtonOptions = list(format = "svg"))
    }
    p
  })
  output$histogramUI <- renderUI({
    de_card(
      title = "Plot",
      plotlyOutput(session$ns("histogram"),
        width = input$width, height = input$height
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
