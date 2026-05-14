#' de_card
#'
#' DEBrowser card wrapper used at every former `shinydashboard::box()` site.
#' Optionally renders a small primary download button on the right of the
#' card header.
#'
#' @param title character -- card title shown in the header
#' @param ... card body content
#' @param download_id character or NULL -- if non-NULL, render a
#'   `downloadButton` with this id in the header
#' @param full_screen logical -- passed through to `bslib::card()`
#'
#' @return a `bslib::card` tagList
#' @examples
#' x <- de_card("Heatmap", shiny::plotOutput("heat"))
#' @export
de_card <- function(title, ..., download_id = NULL, full_screen = FALSE) {
  header <- if (is.null(download_id)) {
    bslib::card_header(title)
  } else {
    bslib::card_header(
      class = "d-flex align-items-center",
      title,
      shiny::tags$div(
        class = "ms-auto",
        shiny::downloadButton(
          download_id,
          label = NULL,
          icon  = shiny::icon("download"),
          class = "btn-primary btn-sm"
        )
      )
    )
  }
  bslib::card(header, ..., full_screen = full_screen)
}
