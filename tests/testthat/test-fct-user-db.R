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

test_that("ai_settings CRUD: upsert / get / clear, cascade on user delete", {
  with_test_data_dir({
    ensure_data_dir()
    con <- user_db_connect()
    on.exit(DBI::dbDisconnect(con), add = TRUE)
    user_db_create_user(con, "alice", "shinymanager")

    # Initial get returns NULL
    expect_null(user_db_ai_settings_get(con, "alice"))

    # Upsert
    user_db_ai_settings_upsert(con, "alice",
      provider = "anthropic", model = "claude-sonnet-4-6",
      api_key_enc = as.raw(c(0x01, 0x02)), default_privacy = "symbols",
      master_switch = TRUE
    )
    s <- user_db_ai_settings_get(con, "alice")
    expect_equal(s$provider, "anthropic")
    expect_equal(s$model, "claude-sonnet-4-6")
    expect_identical(s$api_key_enc, as.raw(c(0x01, 0x02)))
    expect_equal(s$default_privacy, "symbols")
    expect_true(as.logical(s$master_switch))

    # Update via re-upsert
    user_db_ai_settings_upsert(con, "alice", provider = "openai",
      model = "gpt-4o", master_switch = FALSE
    )
    s2 <- user_db_ai_settings_get(con, "alice")
    expect_equal(s2$provider, "openai")
    expect_equal(s2$model, "gpt-4o")
    expect_false(as.logical(s2$master_switch))

    # Clear
    user_db_ai_settings_clear(con, "alice")
    expect_null(user_db_ai_settings_get(con, "alice"))

    # Cascade
    user_db_ai_settings_upsert(con, "alice", provider = "openai",
      model = "gpt-4o", master_switch = TRUE
    )
    user_db_delete_user(con, "alice")
    user_db_create_user(con, "alice", "shinymanager")  # re-create same id
    expect_null(user_db_ai_settings_get(con, "alice"))
  })
})

test_that("upload_refs: inc / dec / orphans / cascade", {
  with_test_data_dir({
    ensure_data_dir()
    con <- user_db_connect()
    on.exit(DBI::dbDisconnect(con), add = TRUE)
    user_db_create_user(con, "alice", "shinymanager")
    user_db_create_user(con, "bob",   "shinymanager")

    # Use real 64-char hex SHAs so upload_orphans() regex filter passes
    shaA <- strrep("a", 64)
    shaB <- strrep("b", 64)
    shaC <- strrep("c", 64)
    # Touch empty blobs so upload_orphans() sees them on disk
    uploads <- file.path(data_dir(), "uploads")
    file.create(file.path(uploads, shaA))
    file.create(file.path(uploads, shaB))
    file.create(file.path(uploads, shaC))

    # First inc creates a row at refcount=1
    user_db_upload_ref_inc(con, shaA, "alice")
    user_db_upload_ref_inc(con, shaA, "alice")  # alice now at 2
    user_db_upload_ref_inc(con, shaA, "bob")    # bob at 1
    user_db_upload_ref_inc(con, shaB, "alice")  # alice has 2 SHAs

    # Counts
    expect_equal(user_db_upload_ref_count(con, shaA, "alice"), 2L)
    expect_equal(user_db_upload_ref_count(con, shaA, "bob"),   1L)
    expect_equal(user_db_upload_ref_count(con, shaB, "alice"), 1L)

    # Dec: returns the new refcount; row deleted on 0
    expect_equal(user_db_upload_ref_dec(con, shaA, "alice"), 1L)
    expect_equal(user_db_upload_ref_dec(con, shaA, "alice"), 0L)
    expect_equal(user_db_upload_ref_count(con, shaA, "alice"), 0L)

    # shaA still has bob's row -> not an orphan
    orphans <- user_db_upload_orphans(con)
    expect_false(shaA %in% orphans)

    # Drop bob's last ref to shaA -> shaA becomes an orphan
    user_db_upload_ref_dec(con, shaA, "bob")
    orphans <- user_db_upload_orphans(con)
    expect_true(shaA %in% orphans)
    expect_false(shaB %in% orphans)

    # Cascade: deleting bob doesn't break alice's shaB row
    user_db_upload_ref_inc(con, shaC, "bob")
    user_db_delete_user(con, "bob")
    expect_equal(user_db_upload_ref_count(con, shaC, "bob"), 0L)
    expect_equal(user_db_upload_ref_count(con, shaB, "alice"), 1L)
  })
})

test_that("master_key_path / load_or_init_master_key: 32 bytes, 0600, idempotent", {
  skip_if_not_installed("sodium")
  with_test_data_dir({
    ensure_data_dir()
    expect_equal(
      normalizePath(master_key_path(), mustWork = FALSE),
      normalizePath(file.path(data_dir(), ".master_key"), mustWork = FALSE)
    )
    k1 <- load_or_init_master_key()
    expect_true(is.raw(k1))
    expect_length(k1, 32L)
    # Second call returns the same bytes (no rotation)
    k2 <- load_or_init_master_key()
    expect_identical(k1, k2)
    if (.Platform$OS.type == "unix") {
      mode <- file.info(master_key_path())$mode
      # mode is an octmode; bit-test owner-only
      expect_equal(as.character(mode), "600")
    }
  })
})

test_that("derive_user_key: deterministic per (master, user_id)", {
  skip_if_not_installed("sodium")
  with_test_data_dir({
    ensure_data_dir()
    m <- load_or_init_master_key()
    k_alice_1 <- derive_user_key(m, "alice")
    k_alice_2 <- derive_user_key(m, "alice")
    k_bob     <- derive_user_key(m, "bob")
    expect_identical(k_alice_1, k_alice_2)
    expect_false(identical(k_alice_1, k_bob))
    expect_length(k_alice_1, 32L)
  })
})

test_that("encrypt_for_user / decrypt_for_user round-trip", {
  skip_if_not_installed("sodium")
  with_test_data_dir({
    ensure_data_dir()
    plain <- "sk-fake-1234567890"
    blob <- encrypt_for_user("alice", plain)
    expect_true(is.raw(blob))
    expect_identical(decrypt_for_user("alice", blob), plain)
    # Wrong user can't decrypt:
    expect_error(decrypt_for_user("bob", blob))
  })
})

test_that("encrypt_for_user: NULL plaintext => NULL blob; decrypt(NULL) => NA", {
  skip_if_not_installed("sodium")
  with_test_data_dir({
    ensure_data_dir()
    expect_null(encrypt_for_user("alice", NULL))
    expect_true(is.na(decrypt_for_user("alice", NULL)))
  })
})
