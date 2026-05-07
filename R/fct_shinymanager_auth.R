# R/fct_shinymanager_auth.R
#
# shinymanager-backed auth provider for D2.5. The provider's wrap_app
# calls shinymanager::secure_app(app, check_credentials = ...) which
# inserts a login screen above the app when no user is authenticated.
# After login, shinymanager stores the user info in session$userData$user;
# our identify() reads that.
#
# The check_credentials function is passed at construction time so tests
# can mock it without reaching the user_db. Task 3 adds the live
# constructor shinymanager_check_credentials_fn().

#' Construct the shinymanager auth provider.
#'
#' @param check_credentials_fn function(user, password) -> list with
#'   `result` (TRUE/FALSE) and optional `user_info` per shinymanager's
#'   contract. Defaults to a function that always denies.
#' @keywords internal
#' @noRd
shinymanager_auth_provider <- function(
    check_credentials_fn = function(user, password) list(result = FALSE)) {

  identify <- function(session) {
    if (is.null(session) || is.null(session$userData)) return(NULL)
    u <- session$userData$user
    if (is.null(u) || is.null(u$user)) return(NULL)
    as.character(u$user)
  }

  wrap_app <- function(app) {
    if (!requireNamespace("shinymanager", quietly = TRUE)) {
      # Graceful degradation when the Suggests dep isn't installed:
      # return the app un-wrapped. The chain falls through to
      # local_anonymous_provider in this case.
      return(app)
    }
    shinymanager::secure_app(app, check_credentials = check_credentials_fn)
  }

  logout <- function(session) {
    if (!is.null(session) && !is.null(session$userData)) {
      session$userData$user <- NULL
    }
    invisible(NULL)
  }

  user_info <- function(user_id) {
    if (is.null(user_id) || length(user_id) != 1L ||
        is.na(user_id) || !nzchar(user_id)) {
      return(list(kind = "shinymanager",
                  display_name = NA_character_,
                  email = NA_character_))
    }
    list(kind = "shinymanager",
         display_name = as.character(user_id),
         email = NA_character_)
  }

  new_auth_provider(
    name = "shinymanager",
    identify = identify,
    wrap_app = wrap_app,
    logout = logout,
    user_info = user_info
  )
}

#' Construct the check_credentials function passed to
#' [shinymanager::secure_app()].
#'
#' Consults `users.sqlite` (D2.1) — only rows with `kind = 'shinymanager'`
#' may authenticate via this path. OIDC/header users authenticate
#' through their respective providers' identify().
#'
#' @param db_path Optional override of the user_db path. Defaults to
#'   `user_db_path()`. Useful for tests.
#' @return A function `function(user, password)` returning a list with
#'   `result` (TRUE/FALSE) per shinymanager's contract.
#' @keywords internal
#' @noRd
shinymanager_check_credentials_fn <- function(db_path = NULL) {
  function(user, password) {
    deny <- list(result = FALSE)
    if (is.null(user) || is.null(password)) return(deny)
    if (!nzchar(user) || !nzchar(password)) return(deny)

    con <- tryCatch(
      {
        if (is.null(db_path)) user_db_connect() else {
          require_pkg("RSQLite", feature = "user database")
          c <- DBI::dbConnect(RSQLite::SQLite(), db_path)
          DBI::dbExecute(c, "PRAGMA foreign_keys = ON")
          user_db_migrate(c)
          c
        }
      },
      error = function(e) NULL
    )
    if (is.null(con)) return(deny)
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    row <- tryCatch(user_db_get_user(con, user), error = function(e) NULL)
    if (is.null(row)) return(deny)
    if (!identical(row$kind, "shinymanager")) return(deny)
    if (!verify_password(password, row$hashed_pw)) return(deny)

    user_db_update_login(con, user)
    list(result = TRUE,
         user_info = list(user = user))
  }
}
