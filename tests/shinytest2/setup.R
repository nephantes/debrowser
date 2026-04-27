# Minimal driver for the DEBrowser app, suitable for shinytest2.
# Returns a Shiny app object that AppDriver$new() accepts.

debrowser_app <- function() {
  shiny::shinyApp(
    ui = debrowser::deUI(),
    server = function(input, output, session) {
      debrowser::deServer(input, output, session)
    }
  )
}
