test_that("is_safe_to_restore: same major+minor => safe", {
  expect_equal(is_safe_to_restore("1.35.0", "1.35.0"), "safe")
  expect_equal(is_safe_to_restore("1.35.0", "1.35.5"), "safe")
})

test_that("is_safe_to_restore: same major, different minor => warn", {
  expect_equal(is_safe_to_restore("1.35.0", "1.36.0"), "warn")
  expect_equal(is_safe_to_restore("1.36.0", "1.35.0"), "warn")
})

test_that("is_safe_to_restore: different major => unsafe", {
  expect_equal(is_safe_to_restore("1.35.0", "2.0.0"), "unsafe")
  expect_equal(is_safe_to_restore("2.0.0", "1.35.0"), "unsafe")
})

test_that("is_safe_to_restore: handles malformed versions defensively", {
  expect_equal(is_safe_to_restore(NA, "1.35.0"), "unsafe")
  expect_equal(is_safe_to_restore("1.35.0", NA), "unsafe")
  expect_equal(is_safe_to_restore("not-a-version", "1.35.0"), "unsafe")
  expect_equal(is_safe_to_restore("", "1.35.0"), "unsafe")
})

test_that("redact_for_bookmark: drops keys with 'api_key' substring", {
  values <- list(
    `ai_settings-api_key` = "sk-secret",
    `ai_enrichment-api_key` = "sk-other",
    foo = 1, bar = 2
  )
  redacted <- redact_for_bookmark(values)
  expect_false("ai_settings-api_key" %in% names(redacted))
  expect_false("ai_enrichment-api_key" %in% names(redacted))
  expect_true(all(c("foo", "bar") %in% names(redacted)))
})

test_that("redact_for_bookmark: drops anything in the ai_* namespace", {
  values <- list(
    `ai_settings-master_switch` = TRUE,
    `ai_settings-provider` = "anthropic",
    `ai_settings-model` = "claude-sonnet-4-6",
    `ai_enrichment-response_text` = "lengthy text",
    other = 42
  )
  redacted <- redact_for_bookmark(values)
  expect_false(any(grepl("^ai_", names(redacted))))
  expect_equal(redacted$other, 42)
})

test_that("redact_for_bookmark: returns named list even when input has no sensitive keys", {
  values <- list(foo = 1, bar = 2)
  redacted <- redact_for_bookmark(values)
  expect_equal(redacted, values)
})

test_that("redact_for_bookmark: handles environments by mutating in place", {
  # Shiny passes state$values / state$input as environments in onRestore.
  e <- new.env()
  e$`ai_settings-api_key` <- "sk-secret"
  e$`ai_enrichment-question` <- "what is this?"
  e$foo <- 1L
  e$bar <- 2L

  redacted <- redact_for_bookmark(e)
  expect_identical(redacted, e)  # same env, mutated in place
  expect_false("ai_settings-api_key" %in% ls(e))
  expect_false("ai_enrichment-question" %in% ls(e))
  expect_true(all(c("foo", "bar") %in% ls(e)))
})

test_that("redact_for_bookmark: empty environment passes through unchanged", {
  e <- new.env()
  redact_for_bookmark(e)
  expect_equal(length(ls(e)), 0L)
})

test_that("bookmark_authorize: TRUE for owner-of-private", {
  with_test_data_dir({
    ensure_data_dir()
    con <- user_db_connect()
    on.exit(DBI::dbDisconnect(con), add = TRUE)
    user_db_create_user(con, "alice", "shinymanager")
    user_db_bookmark_insert(con, "abc", "alice", "private")
    expect_true(bookmark_authorize(con, "abc", "alice"))
  })
})

test_that("bookmark_authorize: stops with 'bookmark_denied' for non-owner of private", {
  with_test_data_dir({
    ensure_data_dir()
    con <- user_db_connect()
    on.exit(DBI::dbDisconnect(con), add = TRUE)
    user_db_create_user(con, "alice", "shinymanager")
    user_db_create_user(con, "bob",   "shinymanager")
    user_db_bookmark_insert(con, "priv", "alice", "private")
    expect_error(
      bookmark_authorize(con, "priv", "bob"),
      class = "bookmark_denied"
    )
  })
})

test_that("bookmark_authorize: TRUE for any user on link-shared", {
  with_test_data_dir({
    ensure_data_dir()
    con <- user_db_connect()
    on.exit(DBI::dbDisconnect(con), add = TRUE)
    user_db_create_user(con, "alice", "shinymanager")
    user_db_create_user(con, "bob",   "shinymanager")
    user_db_bookmark_insert(con, "linkbm", "alice", "link")
    expect_true(bookmark_authorize(con, "linkbm", "bob"))
    expect_true(bookmark_authorize(con, "linkbm", NULL))
  })
})
