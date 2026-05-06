# R/fct_content_hash.R
#
# Content-addressed upload cache. Upload bytes are SHA-256'd and stored
# once at <data_dir>/uploads/<sha>. Bookmarks reference the SHA, not
# the original file. Identical uploads from any user collapse to one
# blob.
#
# Refcounting is live: put(path, user_id, con) increments the per-user
# refcount via user_db_upload_ref_inc; unref(sha, user_id, con)
# decrements it; gc(con) removes blobs with no remaining refs.

#' Construct a content-addressed file store.
#'
#' @param dir Absolute directory path. Defaults to
#'   `file.path(data_dir(), "uploads")`. Must already exist (caller
#'   should have run [ensure_data_dir()]).
#' @return A list of closures: `put(path, user_id, con)`, `path(sha)`,
#'   `exists(sha)`, `list()`, `unref(sha, user_id, con)`, `gc(con)`.
#' @keywords internal
#' @noRd
content_hash_store <- function(dir = file.path(data_dir(), "uploads")) {
  if (!dir.exists(dir)) {
    stop(sprintf(
      "content_hash_store: directory '%s' does not exist; call ensure_data_dir() first.",
      dir
    ))
  }

  put <- function(path, user_id = NULL, con = NULL) {
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
    if (!is.null(user_id) && !is.null(con)) {
      user_db_upload_ref_inc(con, sha, user_id)
    }
    sha
  }

  unref <- function(sha, user_id, con) {
    user_db_upload_ref_dec(con, sha, user_id)
    invisible(NULL)
  }

  gc <- function(con) {
    orphans <- user_db_upload_orphans(con)
    for (o in orphans) {
      file.remove(file.path(dir, o))
    }
    invisible(orphans)
  }

  list(
    put    = put,
    path   = function(sha) file.path(dir, sha),
    exists = function(sha) file.exists(file.path(dir, sha)),
    list   = function() {
      files <- list.files(dir, full.names = FALSE)
      grep("^[0-9a-f]{64}$", files, value = TRUE)
    },
    unref  = unref,
    gc     = gc
  )
}
