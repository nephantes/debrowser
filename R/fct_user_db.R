# R/fct_user_db.R
#
# SQLite-backed user / AI settings / bookmark ownership / upload refcount
# database for D2 hosted mode. Schema lives at
# system.file("sql/users-schema.sql", package = "debrowser") and is
# applied idempotently on connect.
#
# Connection lifecycle is the caller's responsibility: callers obtain a
# connection via `user_db_connect()`, perform their CRUD, and close
# with DBI::dbDisconnect(). Helpers in this file accept an open `con`
# argument; they do not retain hidden state.

#' Absolute path to the users.sqlite file under data_dir().
#' @keywords internal
#' @noRd
user_db_path <- function() {
  file.path(data_dir(), "users.sqlite")
}

#' Open a connection to users.sqlite, applying schema migrations.
#'
#' Creates the file on first call. Idempotent: if the schema is already
#' at version 1, [user_db_migrate()] is a no-op. Foreign-key support
#' is enabled per-connection (SQLite default is OFF).
#'
#' @return An open `SQLiteConnection`. The caller is responsible for
#'   `DBI::dbDisconnect(con)`.
#' @keywords internal
#' @noRd
user_db_connect <- function() {
  require_pkg("RSQLite", feature = "user database")
  con <- DBI::dbConnect(RSQLite::SQLite(), user_db_path())
  DBI::dbExecute(con, "PRAGMA foreign_keys = ON")
  user_db_migrate(con)
  con
}

#' Apply schema migrations to an open connection. Idempotent.
#' @keywords internal
#' @noRd
user_db_migrate <- function(con) {
  schema_path <- system.file("sql/users-schema.sql", package = "debrowser")
  if (!nzchar(schema_path) || !file.exists(schema_path)) {
    stop("user_db_migrate: cannot locate inst/sql/users-schema.sql.")
  }
  lines <- readLines(schema_path, warn = FALSE)
  # Strip comment-only lines before splitting so leading comment blocks do
  # not cause the first real statement (users table) to be filtered out.
  lines <- lines[!grepl("^\\s*--", lines)]
  sql <- paste(lines, collapse = "\n")
  # Split on `;` followed by optional whitespace + newline. SQLite's DBI
  # driver does not run multiple statements in one call, so we execute
  # them one by one.
  stmts <- strsplit(sql, ";\\s*\\n", perl = TRUE)[[1]]
  stmts <- trimws(stmts)
  stmts <- stmts[nzchar(stmts)]
  for (s in stmts) {
    DBI::dbExecute(con, s)
  }
  invisible(NULL)
}

#' Insert a new row into `users`. Errors on duplicate user_id or
#' invalid `kind`.
#'
#' @param con Open `SQLiteConnection`.
#' @param user_id Unique string id (shinymanager username, OIDC sub,
#'   header value, or "local").
#' @param kind One of `c("shinymanager","oidc","header","local")`.
#' @param email,display_name,hashed_pw Optional metadata.
#' @keywords internal
#' @noRd
user_db_create_user <- function(con, user_id, kind,
                                email = NA_character_,
                                display_name = NA_character_,
                                hashed_pw = NA_character_) {
  DBI::dbExecute(con,
    "INSERT INTO users
      (user_id, kind, email, display_name, hashed_pw, created_at)
     VALUES (?, ?, ?, ?, ?, ?)",
    params = list(user_id, kind, email, display_name, hashed_pw,
                  as.integer(Sys.time()))
  )
  invisible(user_id)
}

#' Fetch one row from `users` by user_id, or NULL.
#' @keywords internal
#' @noRd
user_db_get_user <- function(con, user_id) {
  rows <- DBI::dbGetQuery(con,
    "SELECT user_id, kind, email, display_name, hashed_pw,
            created_at, last_login
       FROM users WHERE user_id = ?",
    params = list(user_id)
  )
  if (nrow(rows) == 0L) return(NULL)
  as.list(rows[1L, ])
}

#' Stamp `last_login = now`.
#' @keywords internal
#' @noRd
user_db_update_login <- function(con, user_id) {
  DBI::dbExecute(con,
    "UPDATE users SET last_login = ? WHERE user_id = ?",
    params = list(as.integer(Sys.time()), user_id)
  )
  invisible(NULL)
}

#' Delete a user (cascades to ai_settings, bookmarks, upload_refs).
#' @keywords internal
#' @noRd
user_db_delete_user <- function(con, user_id) {
  DBI::dbExecute(con,
    "DELETE FROM users WHERE user_id = ?",
    params = list(user_id)
  )
  invisible(NULL)
}
