# R/fct_bookmark_state.R
#
# Pure helpers for D2.3 bookmark hooks. The actual hook wiring lives in
# R/server.R (top-level onBookmark/onRestore/etc.). This file holds
# helpers that are easy to unit-test without a Shiny session.

#' Drop sensitive keys from a Shiny bookmark `values` or `input` list.
#'
#' Defense in depth on top of `setBookmarkExclude`. `setBookmarkExclude`
#' is the PRIMARY mechanism for keeping things out of bookmarks; this
#' helper is the secondary line: even if the exclude list ever drifts,
#' the redact pass strips known-sensitive prefixes/substrings.
#'
#' Drops:
#' - any name beginning with `ai_settings-` or `ai_enrichment-` or `ai_`
#' - any name containing the substring `api_key` (case-insensitive)
#'
#' @param values Named list (typically `state$values` or `state$input`).
#' @return The list with sensitive entries removed.
#' @keywords internal
#' @noRd
redact_for_bookmark <- function(values) {
  if (length(values) == 0L) return(values)
  nm <- names(values)
  if (is.null(nm)) return(values)
  drop_mask <- grepl("^ai_", nm) |
               grepl("api_key", nm, ignore.case = TRUE)
  if (is.environment(values)) {
    # Shiny passes state$values / state$input as environments in
    # onRestore; subset-with-logical doesn't work on those. Remove
    # the matching keys in place.
    drop_names <- nm[drop_mask]
    for (k in drop_names) {
      if (exists(k, envir = values, inherits = FALSE)) {
        rm(list = k, envir = values)
      }
    }
    return(values)
  }
  values[!drop_mask]
}

#' Compatibility classification for a bookmark restore.
#'
#' @param saved_version Version string written into the bookmark at
#'   creation time (`utils::packageVersion("debrowser")` formatted).
#' @param current_version The currently-installed package version.
#' @return One of `"safe"`, `"warn"`, `"unsafe"`. The caller (deServer
#'   onRestore) decides what to surface (silent / warning modal / hard
#'   error modal).
#' @keywords internal
#' @noRd
is_safe_to_restore <- function(saved_version, current_version) {
  parse_one <- function(v) {
    if (is.null(v) || length(v) != 1L || is.na(v) || !nzchar(v)) {
      return(NULL)
    }
    parts <- tryCatch(
      as.integer(strsplit(as.character(v), "\\.")[[1]]),
      error = function(e) NULL,
      warning = function(w) NULL
    )
    if (is.null(parts) || length(parts) < 2L || any(is.na(parts[1:2]))) {
      return(NULL)
    }
    parts
  }
  s <- parse_one(saved_version)
  cur <- parse_one(current_version)
  if (is.null(s) || is.null(cur)) return("unsafe")
  if (s[1] != cur[1]) return("unsafe")
  if (s[2] != cur[2]) return("warn")
  "safe"
}

#' Check that `user_id` may open the bookmark; stop with a classed
#' condition if not.
#'
#' Wraps [user_db_can_open()] (D2.1) for the restore flow. The classed
#' condition lets the deServer onRestore handler catch denials and
#' surface a clean "Permission denied" modal instead of crashing the
#' whole session.
#'
#' @param con Open user_db connection.
#' @param state_id Shiny bookmark state id.
#' @param user_id Resolved current user (NULL for anonymous).
#' @return TRUE.
#' @keywords internal
#' @noRd
bookmark_authorize <- function(con, state_id, user_id) {
  if (isTRUE(user_db_can_open(con, state_id, user_id))) return(TRUE)
  cond <- structure(
    class = c("bookmark_denied", "error", "condition"),
    list(
      message = sprintf(
        "Bookmark '%s' is private and cannot be opened by user '%s'.",
        state_id,
        if (is.null(user_id)) "<anonymous>" else user_id
      ),
      state_id = state_id,
      user_id = user_id
    )
  )
  stop(cond)
}
