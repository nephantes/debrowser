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

#' Insert a new bookmark row.
#' @keywords internal
#' @noRd
user_db_bookmark_insert <- function(con, state_id, user_id,
                                    visibility = "private",
                                    label = NA_character_) {
  DBI::dbExecute(con,
    "INSERT INTO bookmarks
       (state_id, user_id, visibility, label, created_at)
     VALUES (?, ?, ?, ?, ?)",
    params = list(state_id, user_id, visibility, label,
                  as.integer(Sys.time()))
  )
  invisible(state_id)
}

#' @keywords internal
#' @noRd
user_db_bookmark_get <- function(con, state_id) {
  rows <- DBI::dbGetQuery(con,
    "SELECT state_id, user_id, visibility, label, created_at, last_opened
       FROM bookmarks WHERE state_id = ?",
    params = list(state_id)
  )
  if (nrow(rows) == 0L) return(NULL)
  as.list(rows[1L, ])
}

#' @keywords internal
#' @noRd
user_db_bookmarks_for_user <- function(con, user_id) {
  DBI::dbGetQuery(con,
    "SELECT state_id, visibility, label, created_at, last_opened
       FROM bookmarks WHERE user_id = ?
      ORDER BY created_at DESC",
    params = list(user_id)
  )
}

#' @keywords internal
#' @noRd
user_db_bookmark_set_visibility <- function(con, state_id, visibility) {
  DBI::dbExecute(con,
    "UPDATE bookmarks SET visibility = ? WHERE state_id = ?",
    params = list(visibility, state_id)
  )
  invisible(NULL)
}

#' @keywords internal
#' @noRd
user_db_bookmark_delete <- function(con, state_id) {
  DBI::dbExecute(con,
    "DELETE FROM bookmarks WHERE state_id = ?",
    params = list(state_id)
  )
  invisible(NULL)
}

#' Authorization check used by the bookmark restore flow.
#'
#' Returns TRUE iff the bookmark exists AND (visibility = 'link' OR
#' user_id matches the owner). Anonymous viewers (NULL user_id) can
#' open 'link' bookmarks only.
#'
#' @keywords internal
#' @noRd
user_db_can_open <- function(con, state_id, user_id) {
  bm <- user_db_bookmark_get(con, state_id)
  if (is.null(bm)) return(FALSE)
  if (identical(bm$visibility, "link")) return(TRUE)
  if (is.null(user_id)) return(FALSE)
  identical(bm$user_id, user_id)
}

#' Insert or update a row in `ai_settings` for `user_id`.
#'
#' Uses INSERT…ON CONFLICT(user_id) DO UPDATE for atomic upsert. Any
#' parameter left at its default (`NULL` or formals-default) is written
#' verbatim — the caller controls whether to clear or preserve fields.
#' Use [user_db_ai_settings_clear()] to delete the row entirely.
#'
#' @param api_key_enc raw vector of sodium-encrypted bytes, or NULL.
#' @keywords internal
#' @noRd
user_db_ai_settings_upsert <- function(con, user_id,
                                       provider = NA_character_,
                                       model = NA_character_,
                                       api_key_enc = NULL,
                                       default_privacy = NA_character_,
                                       master_switch = FALSE) {
  api_key_blob <- if (is.null(api_key_enc)) NA else list(api_key_enc)
  DBI::dbExecute(con,
    "INSERT INTO ai_settings
       (user_id, provider, model, api_key_enc, default_privacy,
        master_switch, updated_at)
     VALUES (?, ?, ?, ?, ?, ?, ?)
     ON CONFLICT(user_id) DO UPDATE SET
       provider        = excluded.provider,
       model           = excluded.model,
       api_key_enc     = excluded.api_key_enc,
       default_privacy = excluded.default_privacy,
       master_switch   = excluded.master_switch,
       updated_at      = excluded.updated_at",
    params = list(user_id, provider, model, api_key_blob,
                  default_privacy, as.integer(isTRUE(master_switch)),
                  as.integer(Sys.time()))
  )
  invisible(NULL)
}

#' @keywords internal
#' @noRd
user_db_ai_settings_get <- function(con, user_id) {
  rows <- DBI::dbGetQuery(con,
    "SELECT provider, model, api_key_enc, default_privacy,
            master_switch, updated_at
       FROM ai_settings WHERE user_id = ?",
    params = list(user_id)
  )
  if (nrow(rows) == 0L) return(NULL)
  out <- as.list(rows[1L, ])
  # RSQLite returns BLOB columns as a list of raw vectors; unwrap so
  # callers see a single raw vector per row.
  if (is.list(out$api_key_enc) && length(out$api_key_enc) == 1L) {
    out$api_key_enc <- out$api_key_enc[[1]]
  }
  out
}

#' @keywords internal
#' @noRd
user_db_ai_settings_clear <- function(con, user_id) {
  DBI::dbExecute(con,
    "DELETE FROM ai_settings WHERE user_id = ?",
    params = list(user_id)
  )
  invisible(NULL)
}
