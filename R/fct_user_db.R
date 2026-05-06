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
