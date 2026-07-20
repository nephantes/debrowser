# R/fct_data_dir.R
#
# Storage-path resolution for D2 (Phase D2.1, foundation). All Shiny
# bookmark state files, the content-hash upload cache, and the
# users.sqlite live under data_dir(). Hosted mode is the deployment
# toggle: when on, auth / per-user AI / bookmark ownership are enforced.

#' Resolve the absolute path to the DEBrowser data root.
#'
#' Precedence: `getOption("debrowser.data_dir")` > `DEBROWSER_DATA_DIR` env
#' > `tools::R_user_dir("debrowser", "data")`. Does not create the
#' directory; see [ensure_data_dir()].
#'
#' @return Absolute path (character(1)).
#' @keywords internal
#' @noRd
data_dir <- function() {
  opt <- getOption("debrowser.data_dir")
  if (!is.null(opt) && nzchar(opt)) return(opt)
  env <- Sys.getenv("DEBROWSER_DATA_DIR", unset = "")
  if (nzchar(env)) return(env)
  tools::R_user_dir("debrowser", "data")
}

#' Is DEBrowser running in hosted mode?
#'
#' Hosted mode flips three behaviors: (1) auth is required, (2) AI
#' settings move from OS keyring to per-user encrypted in users.sqlite,
#' (3) bookmark ownership is enforced. Resolves
#' `getOption("debrowser.hosted")` first, then `DEBROWSER_HOSTED` env.
#'
#' @return Logical scalar.
#' @keywords internal
#' @noRd
hosted_mode <- function() {
  opt <- getOption("debrowser.hosted")
  if (isTRUE(opt)) return(TRUE)
  if (identical(opt, FALSE)) return(FALSE)
  nzchar(Sys.getenv("DEBROWSER_HOSTED", unset = ""))
}

#' Create the data_dir tree if missing. Idempotent.
#'
#' Creates `<data_dir>`, `<data_dir>/shiny_bookmarks`, and
#' `<data_dir>/uploads`. Sets dir mode 0700 on POSIX.
#'
#' @param path data root (defaults to [data_dir()]).
#' @return The path, invisibly.
#' @keywords internal
#' @noRd
ensure_data_dir <- function(path = data_dir()) {
  dir.create(path, showWarnings = FALSE, recursive = TRUE)
  dir.create(file.path(path, "shiny_bookmarks"),
             showWarnings = FALSE, recursive = TRUE)
  dir.create(file.path(path, "uploads"),
             showWarnings = FALSE, recursive = TRUE)
  if (.Platform$OS.type == "unix") {
    Sys.chmod(path, mode = "0700")
  }
  invisible(path)
}

