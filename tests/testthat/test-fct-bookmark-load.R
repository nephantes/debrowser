make_loaded_upload <- function(n_genes = 10L, n_samples = 6L) {
  mat <- matrix(as.integer(abs(rnorm(n_genes * n_samples, 50, 20))),
                nrow = n_genes,
                dimnames = list(paste0("g", seq_len(n_genes)),
                                paste0("s", seq_len(n_samples))))
  meta <- data.frame(sample = paste0("s", seq_len(n_samples)),
                     condition = rep(c("A", "B"), length.out = n_samples),
                     stringsAsFactors = FALSE)
  list(count = as.data.frame(mat), meta = meta, data_source = "upload")
}

test_that("serialize_load_state: upload produces SHA pair", {
  with_test_data_dir({
    ensure_data_dir()
    con <- user_db_connect()
    on.exit(DBI::dbDisconnect(con), add = TRUE)
    user_db_create_user(con, "alice", "shinymanager")
    store <- content_hash_store()

    loaded <- make_loaded_upload()
    s <- serialize_load_state(loaded, store, con, "alice")

    expect_equal(s$data_source, "upload")
    expect_match(s$count_sha, "^[0-9a-f]{64}$")
    expect_match(s$meta_sha, "^[0-9a-f]{64}$")
    expect_equal(user_db_upload_ref_count(con, s$count_sha, "alice"), 1L)
    expect_equal(user_db_upload_ref_count(con, s$meta_sha, "alice"), 1L)
  })
})

test_that("serialize_load_state: demo produces a token, no SHAs", {
  with_test_data_dir({
    ensure_data_dir()
    con <- user_db_connect()
    on.exit(DBI::dbDisconnect(con), add = TRUE)
    user_db_create_user(con, "alice", "shinymanager")
    store <- content_hash_store()

    loaded <- list(count = NULL, meta = NULL, data_source = "demo1")
    s <- serialize_load_state(loaded, store, con, "alice")
    expect_equal(s$data_source, "demo1")
    expect_null(s$count_sha)
    expect_null(s$meta_sha)
  })
})

test_that("restore_load_state: returns paths that round-trip the data", {
  with_test_data_dir({
    ensure_data_dir()
    con <- user_db_connect()
    on.exit(DBI::dbDisconnect(con), add = TRUE)
    user_db_create_user(con, "alice", "shinymanager")
    store <- content_hash_store()

    original <- make_loaded_upload()
    s <- serialize_load_state(original, store, con, "alice")

    paths <- restore_load_state(s, store)
    expect_true(file.exists(paths$count_path))
    expect_true(file.exists(paths$meta_path))
    expect_equal(paths$data_source, "upload")

    # Bytes round-trip
    rt_count <- read.table(paths$count_path, sep = "\t",
                           header = TRUE, row.names = 1, check.names = FALSE)
    expect_equal(dim(rt_count), dim(original$count))
  })
})

test_that("restore_load_state: demo returns a marker only", {
  with_test_data_dir({
    ensure_data_dir()
    store <- content_hash_store()
    s <- list(data_source = "demo2", count_sha = NULL, meta_sha = NULL)
    paths <- restore_load_state(s, store)
    expect_equal(paths$data_source, "demo2")
    expect_null(paths$count_path)
    expect_null(paths$meta_path)
  })
})

test_that("serialize/restore: identical uploads collapse to one blob", {
  with_test_data_dir({
    ensure_data_dir()
    con <- user_db_connect()
    on.exit(DBI::dbDisconnect(con), add = TRUE)
    user_db_create_user(con, "alice", "shinymanager")
    store <- content_hash_store()

    loaded <- make_loaded_upload(n_genes = 5L, n_samples = 4L)
    s1 <- serialize_load_state(loaded, store, con, "alice")
    s2 <- serialize_load_state(loaded, store, con, "alice")
    expect_identical(s1$count_sha, s2$count_sha)
    expect_identical(s1$meta_sha, s2$meta_sha)
    expect_equal(user_db_upload_ref_count(con, s1$count_sha, "alice"), 2L)
  })
})

test_that("serialize_load_state: refuses json source with classed condition", {
  with_test_data_dir({
    ensure_data_dir()
    con <- user_db_connect()
    on.exit(DBI::dbDisconnect(con), add = TRUE)
    user_db_create_user(con, "alice", "shinymanager")
    store <- content_hash_store()
    loaded <- list(count = NULL, meta = NULL, data_source = "json")
    expect_error(
      serialize_load_state(loaded, store, con, "alice"),
      class = "bookmark_unsupported"
    )
  })
})
