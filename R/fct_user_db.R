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
  # ------------------------------------------------------------------
  # Schema v2: email verification columns. Added in R rather than in
  # users-schema.sql because SQLite's `ALTER TABLE ADD COLUMN` errors
  # on a second run -- there's no `IF NOT EXISTS` for ALTER. We add
  # them here under a tryCatch so the migration is idempotent.
  # ------------------------------------------------------------------
  existing_cols <- tryCatch(
    DBI::dbGetQuery(con, "PRAGMA table_info(users)")$name,
    error = function(e) character()
  )
  add_col <- function(col, ddl) {
    if (!(col %in% existing_cols)) {
      tryCatch(
        DBI::dbExecute(con, sprintf("ALTER TABLE users ADD COLUMN %s", ddl)),
        error = function(e) {
          # If another connection added it in a race, ignore "duplicate
          # column" but re-raise anything else.
          if (!grepl("duplicate column", conditionMessage(e),
                     ignore.case = TRUE)) stop(e)
        }
      )
    }
  }
  add_col("email_verified",
          "email_verified INTEGER NOT NULL DEFAULT 0")
  add_col("email_verify_token",
          "email_verify_token TEXT")
  add_col("email_verify_expires_at",
          "email_verify_expires_at INTEGER")
  add_col("email_verify_sent_at",
          "email_verify_sent_at INTEGER")
  # Schema v3: consent timestamps for terms / privacy / cookies. Storing
  # the actual acceptance time lets us re-prompt if the relevant policy
  # version changes later. NULL = never accepted.
  add_col("terms_accepted_at",
          "terms_accepted_at INTEGER")
  add_col("privacy_accepted_at",
          "privacy_accepted_at INTEGER")
  add_col("cookies_accepted_at",
          "cookies_accepted_at INTEGER")
  # Useful index for the URL-token consumption path.
  tryCatch(
    DBI::dbExecute(con,
      "CREATE INDEX IF NOT EXISTS idx_users_verify_token
         ON users(email_verify_token)"),
    error = function(e) NULL
  )
  # Grandfather pre-existing users. The ALTER above adds the column with
  # DEFAULT 0, so every account that existed before the verification
  # migration is now flagged unverified and would be locked out at the
  # check_credentials gate.
  #
  # A legitimate unverified row (created by the new signup flow) ALWAYS
  # has email_verify_token set. So the safe heuristic is: if email_verified=0
  # AND email_verify_token IS NULL, the row predates this migration --
  # mark it verified so login keeps working.
  #
  # Idempotent across repeat runs: once grandfathered, the row's
  # email_verified is 1 and the WHERE clause skips it. A new signup
  # (token written) is never matched by the WHERE clause, so we don't
  # accidentally mark unverified signups as verified.
  tryCatch(
    DBI::dbExecute(con,
      "UPDATE users
          SET email_verified = 1
        WHERE email_verified = 0
          AND email_verify_token IS NULL"),
    error = function(e) NULL
  )
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
                                hashed_pw = NA_character_,
                                email_verified = 0L,
                                email_verify_token = NA_character_,
                                email_verify_expires_at = NA_integer_,
                                email_verify_sent_at = NA_integer_,
                                terms_accepted_at = NA_integer_,
                                privacy_accepted_at = NA_integer_,
                                cookies_accepted_at = NA_integer_) {
  DBI::dbExecute(con,
    "INSERT INTO users
      (user_id, kind, email, display_name, hashed_pw, created_at,
       email_verified, email_verify_token, email_verify_expires_at,
       email_verify_sent_at,
       terms_accepted_at, privacy_accepted_at, cookies_accepted_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
    params = list(user_id, kind, email, display_name, hashed_pw,
                  as.integer(Sys.time()),
                  as.integer(email_verified),
                  email_verify_token,
                  email_verify_expires_at,
                  email_verify_sent_at,
                  terms_accepted_at,
                  privacy_accepted_at,
                  cookies_accepted_at)
  )
  invisible(user_id)
}

#' Fetch one row from `users` by user_id, or NULL.
#' @keywords internal
#' @noRd
user_db_get_user <- function(con, user_id) {
  rows <- DBI::dbGetQuery(con,
    "SELECT user_id, kind, email, display_name, hashed_pw,
            created_at, last_login,
            email_verified, email_verify_token,
            email_verify_expires_at, email_verify_sent_at
       FROM users WHERE user_id = ?",
    params = list(user_id)
  )
  if (nrow(rows) == 0L) return(NULL)
  as.list(rows[1L, ])
}

#' Fetch one row by an unconsumed email-verification token, or NULL.
#'
#' Returns NULL if no row matches OR if the matching row has already
#' been verified (defensive — token should have been cleared on verify).
#'
#' @keywords internal
#' @noRd
user_db_get_user_by_verify_token <- function(con, token) {
  if (is.null(token) || !nzchar(token)) return(NULL)
  rows <- DBI::dbGetQuery(con,
    "SELECT user_id, kind, email, hashed_pw, email_verified,
            email_verify_token, email_verify_expires_at
       FROM users
      WHERE email_verify_token = ?
        AND email_verified = 0
      LIMIT 1",
    params = list(token)
  )
  if (nrow(rows) == 0L) return(NULL)
  as.list(rows[1L, ])
}

#' Mark a user's email as verified and clear the token.
#' @keywords internal
#' @noRd
user_db_set_email_verified <- function(con, user_id) {
  DBI::dbExecute(con,
    "UPDATE users
        SET email_verified = 1,
            email_verify_token = NULL,
            email_verify_expires_at = NULL
      WHERE user_id = ?",
    params = list(user_id)
  )
  invisible(NULL)
}

#' Replace a user's verification token (e.g. for a resend).
#' @keywords internal
#' @noRd
user_db_set_email_verify_token <- function(con, user_id,
                                           token,
                                           expires_at,
                                           sent_at = as.integer(Sys.time())) {
  DBI::dbExecute(con,
    "UPDATE users
        SET email_verify_token = ?,
            email_verify_expires_at = ?,
            email_verify_sent_at = ?,
            email_verified = 0
      WHERE user_id = ?",
    params = list(token, as.integer(expires_at), as.integer(sent_at),
                  user_id)
  )
  invisible(NULL)
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

#' Set the user-facing name on a bookmark row. Empty string is stored
#' as NA so downstream queries can filter "unnamed" bookmarks cleanly.
#' @keywords internal
#' @noRd
user_db_bookmark_set_label <- function(con, state_id, label) {
  if (is.null(label)) label <- NA_character_
  if (length(label) != 1L) label <- NA_character_
  if (!is.na(label) && !nzchar(trimws(as.character(label)))) {
    label <- NA_character_
  }
  if (!is.na(label)) label <- trimws(as.character(label))
  DBI::dbExecute(con,
    "UPDATE bookmarks SET label = ? WHERE state_id = ?",
    params = list(label, state_id)
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
#' Uses INSERT...ON CONFLICT(user_id) DO UPDATE for atomic upsert. Any
#' parameter left at its default (`NULL` or formals-default) is written
#' verbatim -- the caller controls whether to clear or preserve fields.
#' Use [user_db_ai_settings_clear()] to delete the row entirely.
#'
#' @param api_key_enc raw vector of AES-GCM-encrypted bytes, or NULL.
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

#' Increment (or insert) the (sha, user_id) refcount.
#' @keywords internal
#' @noRd
user_db_upload_ref_inc <- function(con, sha256, user_id) {
  DBI::dbExecute(con,
    "INSERT INTO upload_refs (sha256, user_id, refcount)
     VALUES (?, ?, 1)
     ON CONFLICT(sha256, user_id)
       DO UPDATE SET refcount = refcount + 1",
    params = list(sha256, user_id)
  )
  invisible(NULL)
}

#' Decrement the (sha, user_id) refcount. Deletes the row when it hits
#' zero. Returns the new refcount (0 means row deleted).
#' @keywords internal
#' @noRd
user_db_upload_ref_dec <- function(con, sha256, user_id) {
  DBI::dbWithTransaction(con, {
    DBI::dbExecute(con,
      "UPDATE upload_refs SET refcount = refcount - 1
        WHERE sha256 = ? AND user_id = ?",
      params = list(sha256, user_id)
    )
    rows <- DBI::dbGetQuery(con,
      "SELECT refcount FROM upload_refs
        WHERE sha256 = ? AND user_id = ?",
      params = list(sha256, user_id)
    )
    new <- if (nrow(rows) == 0L) 0L else as.integer(rows$refcount[[1]])
    if (new <= 0L) {
      DBI::dbExecute(con,
        "DELETE FROM upload_refs WHERE sha256 = ? AND user_id = ?",
        params = list(sha256, user_id)
      )
      0L
    } else {
      new
    }
  })
}

#' Current refcount for (sha, user_id), or 0L if absent.
#' @keywords internal
#' @noRd
user_db_upload_ref_count <- function(con, sha256, user_id) {
  rows <- DBI::dbGetQuery(con,
    "SELECT refcount FROM upload_refs
      WHERE sha256 = ? AND user_id = ?",
    params = list(sha256, user_id)
  )
  if (nrow(rows) == 0L) return(0L)
  as.integer(rows$refcount[[1]])
}

#' SHA-256 list with no remaining (sha, user_id) refs across any user.
#' Used by content_hash_store$gc() to delete orphan blobs.
#' @keywords internal
#' @noRd
user_db_upload_orphans <- function(con) {
  # All SHAs the store thinks exist but for which upload_refs has no
  # remaining row, i.e. SHAs only known to the filesystem.
  rows <- DBI::dbGetQuery(con,
    "SELECT DISTINCT sha256 FROM upload_refs"
  )
  on_disk <- list.files(file.path(data_dir(), "uploads"))
  on_disk <- grep("^[0-9a-f]{64}$", on_disk, value = TRUE)
  setdiff(on_disk, rows$sha256)
}

#' Absolute path of the server-side master secret file.
#' @keywords internal
#' @noRd
master_key_path <- function() {
  file.path(data_dir(), ".master_key")
}

#' Read the master key from disk; create it (32 random bytes, mode 0600)
#' on first call. Idempotent thereafter.
#' @keywords internal
#' @noRd
load_or_init_master_key <- function() {
  p <- master_key_path()
  if (file.exists(p)) {
    return(readBin(p, what = "raw", n = 32L))
  }
  require_pkg("openssl", feature = "per-user AI key encryption")
  k <- openssl::rand_bytes(32L)
  writeBin(k, p)
  if (.Platform$OS.type == "unix") {
    Sys.chmod(p, mode = "0600")
  }
  k
}

#' Derive a per-user 32-byte key from the master secret + user_id.
#'
#' HMAC-SHA256; 32-byte output, sized for AES-256. Deterministic for the
#' same (master, user_id, purpose), distinct across user_ids. `purpose`
#' domain-separates the confidentiality key from the authentication key
#' so the same bytes are never used for both.
#'
#' @param purpose "enc" (AES-256-GCM) or "mac" (HMAC-SHA256).
#' @keywords internal
#' @noRd
derive_user_key <- function(master_key, user_id, purpose = "enc") {
  require_pkg("openssl", feature = "per-user AI key encryption")
  # Drop openssl's "hash" class so the result is a plain raw vector.
  as.raw(openssl::sha256(
    charToRaw(paste0(purpose, ":", as.character(user_id))),
    key = master_key
  ))
}

#' Length-safe, non-short-circuiting raw comparison for MAC checking.
#' @keywords internal
#' @noRd
raw_identical_ct <- function(a, b) {
  if (length(a) != length(b)) return(FALSE)
  sum(bitwXor(as.integer(a), as.integer(b))) == 0L
}

#' Encrypt a plaintext string for a user. Returns NULL when input is NULL
#' so callers can pass through "no key set".
#' @keywords internal
#' @noRd
encrypt_for_user <- function(user_id, plaintext) {
  if (is.null(plaintext) || (length(plaintext) == 1L && is.na(plaintext))) {
    return(NULL)
  }
  require_pkg("openssl", feature = "per-user AI key encryption")
  master <- load_or_init_master_key()
  iv <- openssl::rand_bytes(12L)
  ct <- as.raw(openssl::aes_gcm_encrypt(
    charToRaw(plaintext),
    key = derive_user_key(master, user_id, "enc"),
    iv  = iv
  ))
  # openssl's aes_gcm_* does not emit or verify a GCM tag, so authenticate
  # explicitly (encrypt-then-MAC over iv || ciphertext).
  tag <- as.raw(openssl::sha256(
    c(iv, ct),
    key = derive_user_key(master, user_id, "mac")
  ))
  c(iv, ct, tag)
}

#' Decrypt a blob produced by [encrypt_for_user()] for the same user.
#' NULL or NA input => NA output. Wrong user => error.
#' @keywords internal
#' @noRd
decrypt_for_user <- function(user_id, blob) {
  if (is.null(blob)) return(NA_character_)
  if (length(blob) == 1L && is.raw(blob) && all(blob == as.raw(0))) {
    return(NA_character_)
  }
  # Shortest possible real blob: 12-byte IV + >=1 ciphertext byte +
  # 32-byte HMAC tag.
  if (length(blob) < 45L) return(NA_character_)
  require_pkg("openssl", feature = "per-user AI key encryption")
  master <- load_or_init_master_key()
  iv   <- blob[seq_len(12L)]
  ct   <- blob[seq(13L, length(blob) - 32L)]
  tag  <- blob[seq(length(blob) - 31L, length(blob))]
  want <- as.raw(openssl::sha256(
    c(iv, ct),
    key = derive_user_key(master, user_id, "mac")
  ))
  # Verify before decrypting: a wrong user or a modified blob must fail
  # loudly rather than yield garbage.
  if (!raw_identical_ct(tag, want)) {
    de_error("Stored API key failed authentication.",
             class = "api_key_auth_failure")
  }
  rawToChar(openssl::aes_gcm_decrypt(
    ct,
    key = derive_user_key(master, user_id, "enc"),
    iv  = iv
  ))
}
