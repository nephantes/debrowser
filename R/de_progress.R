#' Progress decoration helpers for the B2a wizard polish.
#'
#' These functions form a small layer that lets `deServer` push named
#' progress events ("upload done", "filter pending", etc.) to the browser
#' so the wizard sidebar pills and the Data Prep outer tab title can show
#' done / locked / pending states without re-rendering the navbar.
#'
#' Pure pieces (`progress_message`, `compute_pill_class`) are testthat-
#' tested. The IO wrapper (`update_progress`) is a thin
#' `session$sendCustomMessage` call.
#'
#' @keywords internal
NULL

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
