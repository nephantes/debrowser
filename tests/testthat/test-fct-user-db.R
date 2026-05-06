test_that("user_db_connect creates tables on first call (idempotent)", {
  with_test_data_dir({
    ensure_data_dir()
    con <- user_db_connect()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    tbls <- DBI::dbListTables(con)
    expect_true(all(c("users", "ai_settings", "bookmarks", "upload_refs",
                      "schema_version") %in% tbls))

    # Idempotent: re-running the migration does not error and does not
    # change schema_version.
    user_db_migrate(con)
    v <- DBI::dbGetQuery(con, "SELECT version FROM schema_version")$version
    expect_equal(v, 1L)
  })
})

test_that("user_db_path resolves under data_dir", {
  with_test_data_dir({
    ensure_data_dir()
    expect_equal(
      normalizePath(user_db_path(), mustWork = FALSE),
      normalizePath(file.path(data_dir(), "users.sqlite"), mustWork = FALSE)
    )
  })
})

test_that("users CRUD: create / get / update_login / delete", {
  with_test_data_dir({
    ensure_data_dir()
    con <- user_db_connect()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    user_db_create_user(con,
      user_id = "alice", kind = "shinymanager",
      email = "alice@lab.org", display_name = "Alice",
      hashed_pw = "scrypt$xxx"
    )
    u <- user_db_get_user(con, "alice")
    expect_equal(u$user_id, "alice")
    expect_equal(u$kind, "shinymanager")
    expect_equal(u$email, "alice@lab.org")
    expect_equal(u$display_name, "Alice")
    expect_true(is.na(u$last_login))

    # Duplicate user_id is an error
    expect_error(
      user_db_create_user(con, user_id = "alice", kind = "shinymanager"),
      regexp = "UNIQUE|already exists|PRIMARY KEY",
      ignore.case = TRUE
    )

    # Update last_login
    user_db_update_login(con, "alice")
    u2 <- user_db_get_user(con, "alice")
    expect_true(!is.na(u2$last_login))

    # Delete cascades downstream tables (verified in Task 7/8/9 tests)
    user_db_delete_user(con, "alice")
    expect_null(user_db_get_user(con, "alice"))
  })
})

test_that("users: get_user returns NULL for unknown user", {
  with_test_data_dir({
    ensure_data_dir()
    con <- user_db_connect()
    on.exit(DBI::dbDisconnect(con), add = TRUE)
    expect_null(user_db_get_user(con, "ghost"))
  })
})

test_that("users: kind constraint rejects bogus values", {
  with_test_data_dir({
    ensure_data_dir()
    con <- user_db_connect()
    on.exit(DBI::dbDisconnect(con), add = TRUE)
    expect_error(
      user_db_create_user(con, user_id = "x", kind = "bogus"),
      regexp = "CHECK|constraint",
      ignore.case = TRUE
    )
  })
})

test_that("bookmarks CRUD: insert / get / list_for_user / set_visibility / delete", {
  with_test_data_dir({
    ensure_data_dir()
    con <- user_db_connect()
    on.exit(DBI::dbDisconnect(con), add = TRUE)
    user_db_create_user(con, "alice", "shinymanager")

    user_db_bookmark_insert(con,
      state_id = "abc123", user_id = "alice",
      visibility = "private", label = "first run"
    )
    bm <- user_db_bookmark_get(con, "abc123")
    expect_equal(bm$user_id, "alice")
    expect_equal(bm$visibility, "private")
    expect_equal(bm$label, "first run")
    expect_true(!is.na(bm$created_at))

    # list_for_user
    user_db_bookmark_insert(con,
      state_id = "def456", user_id = "alice", visibility = "link"
    )
    bms <- user_db_bookmarks_for_user(con, "alice")
    expect_equal(nrow(bms), 2L)

    # set_visibility
    user_db_bookmark_set_visibility(con, "abc123", "link")
    expect_equal(user_db_bookmark_get(con, "abc123")$visibility, "link")

    # invalid visibility rejected
    expect_error(
      user_db_bookmark_set_visibility(con, "abc123", "bogus"),
      regexp = "CHECK|constraint",
      ignore.case = TRUE
    )

    # delete
    user_db_bookmark_delete(con, "abc123")
    expect_null(user_db_bookmark_get(con, "abc123"))

    # deleting the user cascades to remaining bookmarks
    user_db_delete_user(con, "alice")
    expect_null(user_db_bookmark_get(con, "def456"))
  })
})

test_that("user_db_can_open: private⇒owner-only, link⇒anyone", {
  with_test_data_dir({
    ensure_data_dir()
    con <- user_db_connect()
    on.exit(DBI::dbDisconnect(con), add = TRUE)
    user_db_create_user(con, "alice", "shinymanager")
    user_db_create_user(con, "bob",   "shinymanager")
    user_db_bookmark_insert(con, "priv1", "alice", "private")
    user_db_bookmark_insert(con, "link1", "alice", "link")

    expect_true(user_db_can_open(con, "priv1", "alice"))
    expect_false(user_db_can_open(con, "priv1", "bob"))
    expect_true(user_db_can_open(con, "link1", "alice"))
    expect_true(user_db_can_open(con, "link1", "bob"))
    # Anonymous (NULL user_id) can open link, not private:
    expect_true(user_db_can_open(con, "link1", NULL))
    expect_false(user_db_can_open(con, "priv1", NULL))
    # Unknown bookmark always FALSE:
    expect_false(user_db_can_open(con, "ghost", "alice"))
  })
})
