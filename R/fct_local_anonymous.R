# R/fct_local_anonymous.R
#
# The trivial auth provider for non-hosted mode. Returns "local" as
# user_id for every session. Used by build_auth_chain() (D2.2 Task 7)
# when hosted_mode() is FALSE.

#' Provider that identifies every session as the single user "local".
#'
#' Used in non-hosted mode (`startDEBrowser()` with no args). Bookmarks,
#' AI settings, etc. are all owned by the implicit `"local"` user. The
#' user_db_create_user(con, "local", "local") row is created on first
#' write by the consuming module — this provider doesn't touch the DB.
#'
#' @keywords internal
#' @noRd
local_anonymous_provider <- function() {
  new_auth_provider(
    name = "local_anonymous",
    identify = function(session) "local",
    user_info = function(user_id) {
      list(kind = "local", display_name = "Local",
           email = NA_character_)
    }
  )
}
