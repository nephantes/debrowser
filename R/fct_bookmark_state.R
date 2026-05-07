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
    # In some test contexts state$values / state$input are passed as
    # environments. Mutate in place via rm() and return the same env.
    drop_names <- nm[drop_mask]
    for (k in drop_names) {
      if (exists(k, envir = values, inherits = FALSE)) {
        rm(list = k, envir = values)
      }
    }
    return(values)
  }
  # Production path: state$values / state$input are LISTS in onRestore
  # (subagent E2E confirmed `class=list, length=279`). The CALLER MUST
  # assign the return value back: `state$X <- redact_for_bookmark(state$X)`.
  values[!drop_mask]
}

#' Drop input keys that must not be replayed on restore.
#'
#' D2.5 fix for restore-side breakage caused by:
#'   1. bslib `page_navbar` / `navset_hidden` ids ("methodtabs", "DataPrep").
#'      Shiny replays bookmarked tab selections via `updateTabsetPanel`-style
#'      messages, which bslib does NOT implement. The client throws
#'      "There is no tabsetPanel with id equal to 'methodtabs'" repeatedly.
#'   2. shinymanager's own login-form inputs ("auth-user_id", "auth-user_pwd",
#'      "shinymanager_language", etc.). These belong to the login UI that
#'      shinymanager mounts BEFORE secure_app swaps to the wrapped UI; if
#'      they're replayed, shinymanager re-binds a second copy and we get
#'      "Duplicate input ID was found - shinymanager_language".
#'
#' Belt-and-suspenders with `setBookmarkExclude` in deServer: the exclude
#' list prevents future bookmarks from saving these keys; this restore-side
#' filter handles bookmarks created BEFORE the exclude list was extended.
#'
#' @param input Environment or list (state$input passed to onRestore).
#' @return `input` with the offending keys removed in place; same object.
#' @keywords internal
#' @noRd
strip_unrestorable_inputs <- function(input) {
  if (length(input) == 0L) return(input)
  nm <- names(input)
  if (is.null(nm)) return(input)
  drop_mask <- nm %in% c("methodtabs", "DataPrep") |
               grepl("^auth-", nm) |
               grepl("^shinymanager_", nm)
  if (is.environment(input)) {
    drop_names <- nm[drop_mask]
    for (k in drop_names) {
      if (exists(k, envir = input, inherits = FALSE)) {
        rm(list = k, envir = input)
      }
    }
    return(input)
  }
  # Production path (onRestore passes state$input as LIST): caller MUST
  # assign return value back, otherwise this is a no-op.
  input[!drop_mask]
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
