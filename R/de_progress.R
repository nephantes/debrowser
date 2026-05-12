# Progress decoration helpers for the B2a wizard polish.
#
# These functions form a small layer that lets `deServer` push named
# progress events ("upload done", "filter pending", etc.) to the browser
# so the wizard sidebar pills and the Data Prep outer tab title can show
# done / locked / pending states without re-rendering the navbar.
#
# Pure pieces (`progress_message`, `compute_pill_class`) are testthat-
# tested. The IO wrapper (`update_progress`) is a thin
# `session$sendCustomMessage` call.

#' Build a named list payload for the "debrowser-progress" custom message.
#'
#' @param key character, progress key (e.g. "upload", "filter", "data_prep").
#' @param state character, one of "pending", "done", "locked", "skipped",
#'   or "" (empty clears the icon).
#' @return named list with elements `key` and `state`.
#'
#' @examples
#' progress_message("upload", "done")
#'
#' @export
progress_message <- function(key, state) {
  list(key = key, state = state)
}

#' Compute the CSS class name for a pill given its progress state.
#'
#' Used by the JS handler in `getTabUpdateJS()` (R/funcs.R) and as a
#' direct render path for static initial state.
#'
#' @param state character, progress state.
#' @return character, CSS class name or empty string.
#'
#' @examples
#' compute_pill_class("done")
#'
#' @export
compute_pill_class <- function(state) {
  switch(state,
    "done"    = "de-pill-done",
    "skipped" = "de-pill-skipped",  # B3.17: skipped is its own visual state
    "locked"  = "de-pill-locked",
    ""
  )
}

#' Render a label suitable for nav_panel(title=) or actionLink(label=)
#' that includes a slot the JS handler can decorate with a progress icon.
#'
#' @param name character, the visible label (e.g. "Upload", "Data Prep").
#' @param key character, the progress key the JS handler listens for.
#' @return a `tags$span` HTML wrapper.
#'
#' @examples
#' de_progress_label("Upload", "upload")
#'
#' @export
de_progress_label <- function(name, key) {
  shiny::tags$span(
    name,
    shiny::tags$span(
      class = "de-progress-icon",
      `data-progress-key` = key
    )
  )
}

#' Push a progress update to the browser for one key.
#'
#' Sends a Shiny custom message of type "debrowser-progress" with a
#' payload built by `progress_message(key, state)`. The handler installed
#' by `getTabUpdateJS()` (R/funcs.R) reads the message and toggles CSS
#' classes on the matching icon span and parent pill.
#'
#' @param session Shiny session object.
#' @param key character, progress key.
#' @param state character, progress state.
#' @return Invisibly NULL.
#'
#' @examples
#' \donttest{
#'   if (interactive()) {
#'     update_progress(session, "upload", "done")
#'   }
#' }
#'
#' @export
update_progress <- function(session, key, state) {
  session$sendCustomMessage(
    "debrowser-progress",
    progress_message(key, state)
  )
  invisible(NULL)
}
