# R/fct_content_hash.R
#
# Content-addressed upload cache. Upload bytes are SHA-256'd and stored
# once at <data_dir>/uploads/<sha>. Bookmarks reference the SHA, not
# the original file. Identical uploads from any user collapse to one
# blob.
#
# Refcounting (which user owns which SHA, and gc of orphans) lands in
# Task 11 once the user_db tables exist. The closures below DO NOT
# expose unref/gc yet — those return NULL stubs that Task 11 wires.

#' Construct a content-addressed file store.
#'
#' @param dir Absolute directory path. Defaults to
#'   `file.path(data_dir(), "uploads")`. Must already exist (caller
#'   should have run [ensure_data_dir()]).
#' @return A list of closures: `put(path)`, `path(sha)`, `exists(sha)`,
#'   `list()`. `unref(sha, user_id)` and `gc()` are present but
#'   no-ops in D2.1 (Task 11 wires them).
#' @keywords internal
#' @noRd
content_hash_store <- function(dir = file.path(data_dir(), "uploads")) {
  if (!dir.exists(dir)) {
    stop(sprintf(
      "content_hash_store: directory '%s' does not exist; call ensure_data_dir() first.",
      dir
    ))
  }

  put <- function(path) {
    if (!file.exists(path)) {
      stop(sprintf("content_hash_store$put: source file '%s' does not exist.",
                   path))
    }
    sha <- digest::digest(file = path, algo = "sha256")
    target <- file.path(dir, sha)
    if (!file.exists(target)) {
      ok <- file.copy(path, target, overwrite = FALSE)
      if (!isTRUE(ok)) {
        stop(sprintf(
          "content_hash_store$put: failed to copy '%s' -> '%s'.",
          path, target
        ))
      }
    }
    sha
  }

  list(
    put    = put,
    path   = function(sha) file.path(dir, sha),
    exists = function(sha) file.exists(file.path(dir, sha)),
    list   = function() {
      files <- list.files(dir, full.names = FALSE)
      # Only well-formed SHA-256 hex names belong to the store; ignore
      # accidental cohabitation (.gitkeep, leftover .meta sidecars, etc.)
      grep("^[0-9a-f]{64}$", files, value = TRUE)
    },
    unref  = function(sha, user_id) invisible(NULL),  # Task 11
    gc     = function()              invisible(NULL)   # Task 11
  )
}
