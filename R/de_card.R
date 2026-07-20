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
#' @param class character or NULL -- extra CSS class(es) forwarded to
#'   `bslib::card()` (e.g. "de-subcard", "de-comparison")
#'
#' @return a `bslib::card` tagList
#' @examples
#' x <- de_card("Heatmap", shiny::plotOutput("heat"))
#' @export
de_card <- function(title, ..., download_id = NULL, full_screen = FALSE,
                    class = NULL) {
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
  bslib::card(header, ..., full_screen = full_screen, class = class)
}

#' de_plot_h
#'
#' Single source of truth for the three `plotOutput(height=)` tiers used
#' across DEBrowser, so they can't drift into intent-free magic numbers.
#' Returned as literal CSS px strings: bslib/shiny run `height` through
#' `validateCssUnit()`, which rejects `var()` custom properties, so these
#' plot heights cannot live as CSS tokens like the `--de-space-*` scale.
#'
#' @param size one of "sm" (360px), "md" (420px), "lg" (500px).
#' @return a CSS length string.
#' @noRd
de_plot_h <- function(size = c("md", "sm", "lg")) {
  switch(match.arg(size),
    sm = "360px",
    md = "420px",
    lg = "500px"
  )
}
