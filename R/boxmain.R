#' getBoxMainPlotUI
#'
#' main Box plots UI.
#'
#' @note \code{getBoxMainPlotUI}
#' @param id, namespace id
#' @return the panel for Density plots;
#'
#' @examples
#' x <- getBoxMainPlotUI("box")
#'
#' @export
#'
getBoxMainPlotUI <- function(id) {
  ns <- NS(id)
  uiOutput(ns("BoxMainUI"))
}

#' debrowserboxmainplot
#'
#' Module for a box plot that can be used in DEanalysis main part and
#' used heatmaps
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
#' x <- debrowserboxmainplot()
#'
debrowserboxmainplot <- function(id, data = NULL, cols = NULL, conds = NULL,
                                 cond_names = NULL, key = NULL) {
  if (is.null(data)) {
    return(NULL)
  }
  moduleServer(id, function(input, output, session) {
    output$BoxMain <- renderPlotly({
      getBoxMainPlot(data, cols, conds, cond_names, key, title = "", input)
    })

    output$BoxMainUI <- renderUI({
      shinydashboard::box(
        collapsible = TRUE, title = session$ns("plot"), status = "primary",
        solidHeader = TRUE, width = NULL,
        draggable = TRUE, plotlyOutput(session$ns("BoxMain"),
          height = input$height, width = input$width
        )
      )
    })
  })
}

#' BoxMainPlotControlsUI
#'
#' Generates the controls in the left menu for a Box main plot
#'
#' @note \code{BoxMainPlotControlsUI}
#' @param id, namespace id
#' @return returns the controls for left menu
#' @examples
#' x <- BoxMainPlotControlsUI("box")
#' @export
#'
BoxMainPlotControlsUI <- function(id) {
  ns <- NS(id)
  shinydashboard::menuItem(
    paste0(id, " - Options"),
    textInput(ns("breaks"), "Breaks", value = "100")
  )
}

#' getBoxMainPlot
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
#' getBoxMainPlot()
#'
getBoxMainPlot <- function(data = NULL, cols = NULL, conds = NULL, cond_names = NULL, key = NULL, title = "", input = NULL) {
  if (is.null(data)) {
    return(NULL)
  }

  cn <- unique(conds)
  conds[conds == cn[1]] <- cond_names[1]
  conds[conds == cn[2]] <- cond_names[2]
  vardata <- getVariationData(data, cols, conds, key)

  title <- paste(key, "variation")
  p <- plot_ly(vardata,
    x = ~conds, y = ~count,
    color = ~conds, colors = c("Red", "Blue"),
    boxpoints = "all", type = "box", height = input$height, width = input$width
  ) %>%
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
