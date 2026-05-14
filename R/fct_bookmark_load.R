# R/fct_bookmark_load.R
#
# Bridges the dataLoad module's loadeddata() output to the content-hash
# store for D2.3 bookmark serialization. Pure helpers (no Shiny scope);
# the module-side onBookmark/onRestore in R/dataLoad.R is just a thin
# wrapper around these.

#' Write loaded counts + metadata to the content-hash store and return
#' a compact serialized handle.
#'
#' For `data_source = "upload"`, writes the count data.frame and metadata
#' data.frame to TSV temp files, hashes them via [content_hash_store()],
#' and returns the SHA-256 pair. For `data_source = "demo1"`/`"demo2"`/
#' `"json"`, returns just the data_source token (the dataLoad module's
#' restore path will reconstitute via system.file()/RCurl).
#'
#' @param loaded The list returned by `loadeddata()` in the dataLoad
#'   module (`list(count, meta, data_source)`).
#' @param store A `content_hash_store()` instance.
#' @param con An open user_db connection.
#' @param user_id The current user.
#' @keywords internal
#' @noRd
serialize_load_state <- function(loaded, store, con, user_id) {
  if (is.null(loaded)) return(NULL)
  src <- if (is.null(loaded$data_source)) "upload" else loaded$data_source
  if (!identical(src, "upload")) {
    if (identical(src, "json")) {
      cond <- structure(
        class = c("bookmark_unsupported", "error", "condition"),
        list(
          message = paste(
            "JSON-URL sessions cannot be bookmarked.",
            "Use Export > Reproducibility script for a permanent record."
          ),
          data_source = src
        )
      )
      stop(cond)
    }
    return(list(data_source = src, count_sha = NULL, meta_sha = NULL))
  }
  count_path <- tempfile(fileext = ".tsv")
  meta_path  <- tempfile(fileext = ".tsv")
  on.exit(unlink(c(count_path, meta_path)), add = TRUE)
  utils::write.table(loaded$count, file = count_path, sep = "\t",
                     quote = FALSE, row.names = TRUE,
                     col.names = NA)
  utils::write.table(loaded$meta, file = meta_path, sep = "\t",
                     quote = FALSE, row.names = FALSE)
  count_sha <- store$put(count_path, user_id = user_id, con = con)
  meta_sha  <- store$put(meta_path,  user_id = user_id, con = con)
  list(data_source = "upload",
       count_sha = count_sha,
       meta_sha  = meta_sha)
}

#' Inverse of [serialize_load_state()] -- return file paths the dataLoad
#' module can read from. For demo/json, the helper just returns the
#' data_source marker; the dataLoad module's onRestore handles the
#' reconstitution.
#'
#' @keywords internal
#' @noRd
restore_load_state <- function(state, store) {
  if (is.null(state)) return(NULL)
  src <- if (is.null(state$data_source)) "upload" else state$data_source
  if (!identical(src, "upload")) {
    return(list(data_source = src,
                count_path = NULL,
                meta_path = NULL))
  }
  list(
    data_source = "upload",
    count_path = store$path(state$count_sha),
    meta_path  = store$path(state$meta_sha)
  )
}
