# R/fct_share_modal.R
#
# Pure UI builder for the bookmark share modal (D2.4). Module-side
# wiring lives in R/server.R's onBookmarked.

#' Build the share modal UI body for a bookmark URL.
#'
#' @param url Character(1). The full bookmark URL (typically the value
#'   passed by Shiny to `onBookmarked`).
#' @param can_toggle Logical(1). When TRUE, render the visibility
#'   toggle (private vs. link). D2.4 ships the toggle UI but does NOT
#'   wire the DB UPDATE — D2.5's account UI does that. Default FALSE.
#' @param current_visibility Character(1). Either "private" or "link".
#'   Only consulted when `can_toggle = TRUE`.
#' @return A `shiny::tagList()` ready to embed in `modalDialog`.
#' @keywords internal
#' @noRd
build_share_modal_ui <- function(url,
                                 can_toggle = FALSE,
                                 current_visibility = "private") {
  shiny::tagList(
    shiny::div(
      class = "alert alert-success",
      "Bookmark created. Anyone with this URL who can see this bookmark may open it."
    ),
    shiny::tags$label("Share URL"),
    shiny::tags$input(
      type = "text", class = "form-control", readonly = NA,
      value = url, onclick = "this.select()"
    ),
    shiny::tags$br(),
    shiny::tags$a(
      href = url, target = "_blank", class = "btn btn-default",
      "Open in new tab"
    ),
    if (isTRUE(can_toggle)) {
      vis <- match.arg(current_visibility, c("private", "link"))
      shiny::tagList(
        shiny::tags$hr(),
        shiny::radioButtons(
          inputId = "bookmark_share_visibility",
          label   = "Visibility",
          choices = c("Private (only me)" = "private",
                      "Shared via link"   = "link"),
          selected = vis,
          inline = TRUE
        ),
        shiny::div(
          class = "text-muted small",
          paste0(
            "Private: only you can open this URL after logging in. ",
            "Shared via link: anyone with the URL can open it after ",
            "signing up and logging in. Changes save automatically."
          )
        )
      )
    }
  )
}
