-- DEBrowser hosted-mode user database (D2.1 schema, version 1).
-- Single source of truth for the SQLite tables consumed by
-- R/fct_user_db.R. All migrations are idempotent (CREATE IF NOT EXISTS).

CREATE TABLE IF NOT EXISTS users (
  user_id      TEXT PRIMARY KEY,
  kind         TEXT NOT NULL CHECK(kind IN ('shinymanager','oidc','header','local')),
  email        TEXT,
  display_name TEXT,
  hashed_pw    TEXT,
  created_at   INTEGER NOT NULL,
  last_login   INTEGER
);

CREATE TABLE IF NOT EXISTS ai_settings (
  user_id         TEXT PRIMARY KEY REFERENCES users(user_id) ON DELETE CASCADE,
  provider        TEXT,
  model           TEXT,
  api_key_enc     BLOB,
  default_privacy TEXT,
  master_switch   INTEGER NOT NULL DEFAULT 0,
  updated_at      INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS bookmarks (
  state_id    TEXT PRIMARY KEY,
  user_id     TEXT NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
  visibility  TEXT NOT NULL CHECK(visibility IN ('private','link')),
  label       TEXT,
  created_at  INTEGER NOT NULL,
  last_opened INTEGER
);

CREATE TABLE IF NOT EXISTS upload_refs (
  sha256   TEXT NOT NULL,
  user_id  TEXT NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
  refcount INTEGER NOT NULL DEFAULT 1,
  PRIMARY KEY (sha256, user_id)
);
CREATE INDEX IF NOT EXISTS upload_refs_sha ON upload_refs(sha256);

CREATE TABLE IF NOT EXISTS schema_version (version INTEGER PRIMARY KEY);
INSERT OR IGNORE INTO schema_version VALUES (1);
