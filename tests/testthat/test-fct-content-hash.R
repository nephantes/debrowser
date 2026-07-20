test_that("content_hash_store: put copies file and returns SHA", {
  with_test_data_dir({
    ensure_data_dir()
    store <- content_hash_store()
    src <- tempfile(); writeLines("hello world", src)
    sha <- store$put(src)
    expect_match(sha, "^[0-9a-f]{64}$")
    expect_true(store$exists(sha))
    expect_true(file.exists(store$path(sha)))
    # Stored bytes match input bytes
    expect_equal(
      readLines(src),
      readLines(store$path(sha))
    )
  })
})

test_that("content_hash_store: identical bytes => identical SHA, idempotent put", {
  with_test_data_dir({
    ensure_data_dir()
    store <- content_hash_store()
    a <- tempfile(); b <- tempfile()
    writeLines(c("a", "b", "c"), a)
    writeLines(c("a", "b", "c"), b)
    sha_a <- store$put(a)
    sha_b <- store$put(b)
    expect_identical(sha_a, sha_b)
    expect_length(store$list(), 1L)
  })
})

test_that("content_hash_store: different bytes => different SHA", {
  with_test_data_dir({
    ensure_data_dir()
    store <- content_hash_store()
    a <- tempfile(); b <- tempfile()
    writeLines(c("a"), a)
    writeLines(c("b"), b)
    expect_false(identical(store$put(a), store$put(b)))
    expect_length(store$list(), 2L)
  })
})

test_that("content_hash_store: missing file => informative error", {
  with_test_data_dir({
    ensure_data_dir()
    store <- content_hash_store()
    expect_error(store$put("/no/such/path"), "does not exist")
  })
})

test_that("content_hash_store: dir defaults to <data_dir>/uploads", {
  with_test_data_dir({
    ensure_data_dir()
    store <- content_hash_store()
    src <- tempfile(); writeLines("payload", src)
    sha <- store$put(src)
    expect_true(startsWith(
      normalizePath(store$path(sha), mustWork = FALSE),
      normalizePath(file.path(data_dir(), "uploads"), mustWork = FALSE)
    ))
  })
})

test_that("content_hash_store: put(user_id) increments refcount; unref decrements; gc removes orphans", {
  with_test_data_dir({
    ensure_data_dir()
    store <- content_hash_store()
    con <- user_db_connect()
    on.exit(DBI::dbDisconnect(con), add = TRUE)
    user_db_create_user(con, "alice", "shinymanager")
    user_db_create_user(con, "bob",   "shinymanager")

    src <- tempfile(); writeLines("payload", src)

    sha <- store$put(src, user_id = "alice", con = con)
    expect_equal(user_db_upload_ref_count(con, sha, "alice"), 1L)
    sha2 <- store$put(src, user_id = "alice", con = con)
    expect_identical(sha, sha2)
    expect_equal(user_db_upload_ref_count(con, sha, "alice"), 2L)

    store$put(src, user_id = "bob", con = con)
    expect_equal(user_db_upload_ref_count(con, sha, "bob"), 1L)

    # Drop alice's refs to 0; SHA still alive (bob holds it).
    store$unref(sha, "alice", con = con)
    store$unref(sha, "alice", con = con)
    expect_equal(user_db_upload_ref_count(con, sha, "alice"), 0L)
    store$gc(con = con)
    expect_true(store$exists(sha))

    # Drop bob's last ref; SHA becomes orphaned and gc removes it.
    store$unref(sha, "bob", con = con)
    expect_true(store$exists(sha))      # gc has not run yet
    store$gc(con = con)
    expect_false(store$exists(sha))
  })
})
