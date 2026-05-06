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
