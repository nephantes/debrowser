#' getDensityPlotUI
#'
#' Density plot UI.
#'
#' @param id, namespace id
#' @note \code{getDensityPlotUI}
#' @return the panel for Density plots;
#'
#' @examples
#' x <- getDensityPlotUI("density")
#'
#' @export
#'
getDensityPlotUI <- function(id) {
  ns <- NS(id)
  uiOutput(ns("DensityUI"))
}

#' debrowserdensityplot
#'
#' Module for a density plot that can be used in data prep and
#' low count removal modules
#'
#' @param id, namespace id
#' @param data, a matrix that includes expression values
#' @return density plot
#' @export
#'
#' @examples
#' \donttest{
#' x <- debrowserdensityplot("density")
#' }
#'
debrowserdensityplot <- function(id, data = NULL) {
  if (is.null(data)) {
    return(NULL)
  }
  moduleServer(id, function(input, output, session) {
    output$Density <- renderPlotly({
      withProgress(message = "Drawing density plot", style = "notification", value = 0.1, {
        getDensityPlot(data, input)
      })
    })
    output$DensityUI <- renderUI({
      de_card(
        title = "Plot",
        plotlyOutput(session$ns("Density"),
          width = input$width, height = input$height
        )
      )
    })
  })
}

#' densityPlotControlsUI
#'
#' Generates the controls in the left menu for a densityPlot
#'
#' @note \code{densityPlotControlsUI}
#' @param id, namespace id
#' @return returns the left menu
#' @examples
#' x <- densityPlotControlsUI("density")
#' @export
#'
densityPlotControlsUI <- function(id) {
  ns <- NS(id)
  bslib::accordion(
    open = FALSE,
    bslib::accordion_panel(
      paste0(id, " - Options"),
      textInput(ns("breaks"), "Breaks", value = "100")
    )
  )
}

#' getDensityPlot
#'
#' Makes Density plots
#'
#' @param data, count or normalized data
#' @param input, input
#' @param title, title
#'
#' @return A `plotly` density plot showing the per-sample distributions
#'   of the input count matrix (one density curve per sample).
#' @export
#'
#' @examples
#' getDensityPlot()
#'
getDensityPlot <- function(data = NULL, input = NULL, title = "") {
  if (is.null(data)) {
    return(NULL)
  }
  data <- as.data.frame(data)
  cols <- colnames(data)
  data[, cols] <- apply(
    data[, cols], 2,
    function(x) log10(as.integer(x) + 1)
  )

  data <- addID(data)
  mdata <- melt(as.data.frame(data[, c("ID", cols)]), "ID")
  colnames(mdata) <- c("ID", "samples", "density")

  p <- ggplot(data = mdata, aes(x = density)) +
    geom_density(aes(fill = samples), alpha = 0.5) +
    labs(x = "logcount", y = "Density") +
    theme_minimal()
  if (!is.null(input$top)) {
    p <- p + theme(plot.margin = margin(t = input$top, r = input$right, b = input$bottom, l = input$left, "pt"))
  }
  p <- ggplotly(p, width = input$width, height = input$height)
  if (!is.null(input$svg) && input$svg == TRUE) {
    p <- p %>% config(toImageButtonOptions = list(format = "svg"))
  }
  p$elementId <- NULL
  p
}
