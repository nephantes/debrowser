#' debrowserbarmainplot
#'
#' Module for a bar plot that can be used in data prep, main plots
#' low count removal modules or any desired module
#'
#' @param input, input variables
#' @param output, output objects
#' @param session, session
#' @param data, a matrix that includes expression values
#' @param cols, columns
#' @param conds, conditions
#' @param cond_names, condition names
#' @param key, the gene or region name
#' @return density plot
#' @export
#'
#' @examples
#' x <- debrowserbarmainplot()
#'
debrowserbarmainplot <- function(id, data = NULL, cols = NULL, conds = NULL,
                                 cond_names = NULL, key = NULL) {
  if (is.null(data)) {
    return(NULL)
  }
  moduleServer(id, function(input, output, session) {
    output$BarMainUI <- renderUI({
      shinydashboard::box(
        collapsible = TRUE, title = session$ns("plot"), status = "primary",
        solidHeader = TRUE, width = NULL,
        draggable = TRUE, plotlyOutput(session$ns("BarMain"),
          height = input$height, width = input$width
        )
      )
    })
    output$BarMain <- renderPlotly({
      getBarMainPlot(data, cols, conds, cond_names, key, title = "", input = input)
    })
  })
}

#' getBarMainPlotUI
#'
#' main bar plots UI.
#'
#' @note \code{getBarMainPlotUI}
#' @param id, namespace id
#' @return the panel for Density plots;
#'
#' @examples
#' x <- getBarMainPlotUI("bar")
#'
#' @export
#'
getBarMainPlotUI <- function(id) {
  ns <- NS(id)
  uiOutput(ns("BarMainUI"))
}


#' barMainPlotControlsUI
#'
#' Generates the controls in the left menu for a bar main plot
#'
#' @note \code{barMainPlotControlsUI}
#' @param id, namespace id
#' @return returns the controls for left menu
#' @examples
#' x <- barMainPlotControlsUI("bar")
#' @export
#'
barMainPlotControlsUI <- function(id) {
  ns <- NS(id)
  shinydashboard::menuItem(
    paste0(id, " - Options"),
    textInput(ns("genename"), "Gene/Region Name", value = "Foxa3")
  )
}

#' getBarMainPlot
#'
#' Makes Density plots
#'
#' @param data, count or normalized data
#' @param cols, cols
#' @param conds, conds
#' @param cond_names, condition names
#' @param key, key
#' @param title, title
#' @param input, input
#' @export
#'
#' @examples
#' getBarMainPlot()
#'
getBarMainPlot <- function(data = NULL, cols = NULL, conds = NULL, cond_names = NULL, key = NULL, title = "", input = NULL) {
  if (is.null(data)) {
    return(NULL)
  }

  cn <- unique(conds)
  conds[conds == cn[1]] <- cond_names[1]
  conds[conds == cn[2]] <- cond_names[2]
  vardata <- getVariationData(data, cols, conds, key)

  title <- paste(key, "variation")

  p <- plot_ly(vardata,
    x = ~libs, y = ~count,
    color = ~conds, colors = c("Red", "Blue"),
    type = "bar", height = input$height, width = input$width
  )
  p <- p %>%
    plotly::layout(
      title = title,
      xaxis = list(
        categoryorder = "array",
        categoryarray = cols,
        title = "Conditions"
      ),
      yaxis = list(title = "Read Count"),
      margin = list(
        l = input$left,
        b = input$bottom,
        t = input$top,
        r = input$right
      )
    )
  if (!is.null(input$svg) && input$svg == TRUE) {
    p <- p %>% config(toImageButtonOptions = list(format = "svg"))
  }
  p$elementId <- NULL
  p
}
