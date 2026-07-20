# Regression: serialize a fake bookmark state with sensitive content
# pretending to be input fields, run redact_for_bookmark, and assert
# nothing recognizably-secret survives.
test_that("redact_for_bookmark blocks well-known secret patterns", {
  fake_state <- list(
    `ai_settings-api_key`   = "sk-anth-abcdef1234567890",
    `ai_settings-master_switch` = TRUE,
    `ai_settings-provider`  = "anthropic",
    `ai_enrichment-response_text` = "(should not be bookmarked)",
    api_key_other = "should-also-go",
    SOME_API_KEY  = "should-also-go-2",
    foo = "kept",
    bar = 42
  )
  redacted <- redact_for_bookmark(fake_state)
  serialized <- paste(capture.output(dput(redacted)), collapse = " ")

  # No secret values should appear after redaction
  expect_false(grepl("sk-anth-abcdef1234567890", serialized, fixed = TRUE))
  expect_false(grepl("should not be bookmarked", serialized, fixed = TRUE))
  expect_false(grepl("should-also-go", serialized, fixed = TRUE))
  expect_false(grepl("should-also-go-2", serialized, fixed = TRUE))

  # Non-sensitive values are preserved
  expect_equal(redacted$foo, "kept")
  expect_equal(redacted$bar, 42)
})

# Verifies the centralized list of excluded inputs covers the documented
# AI / file-input / button surface. This is a DESIGN INVARIANT test.
test_that("expected setBookmarkExclude entries are present in server.R", {
  # Resolve server.R from the source tree (we're running under devtools::test
  # which sets the cwd to the tests/testthat dir).
  here <- testthat::test_path("..", "..", "R", "server.R")
  if (!file.exists(here)) {
    # Try installed-package path as a fallback
    here <- system.file("R", "server.R", package = "debrowser")
  }
  if (!file.exists(here) || nchar(here) == 0) {
    skip("server.R not in expected path")
  }
  src <- readLines(here)
  text <- paste(src, collapse = "\n")
  # IDs audited 2026-05-06 against actual ns() calls in each module.
  required <- c(
    "ai_settings-api_key",
    "ai_settings-enabled",
    "ai_enrichment-ask",
    "load-countdata",
    "load-metadata",
    "fgsea_gmt-manual_gmt",
    "load-uploadFile",
    "lcf-submitLCF",
    "batcheffect-submitBatchEffect",
    "cs-startDE",
    # D2.5 fix: bslib page_navbar / navset_hidden tab selections must be
    # excluded to prevent JS "There is no tabsetPanel" errors during restore.
    "methodtabs",
    "DataPrep",
    # D2.5 fix Bug B: shinymanager-owned login form inputs must not be
    # bookmarked, otherwise the login UI re-binds duplicates on restore.
    "auth-user_id", "auth-user_pwd", "auth-go_auth",
    "shinymanager_language"
  )
  for (r in required) {
    expect_true(grepl(r, text, fixed = TRUE),
                info = sprintf("setBookmarkExclude must include '%s'", r))
  }
})

# D2.5 fix Bug A: restore-side filter for inputs that break Shiny's
# updateTabsetPanel-style replay (bslib navs) and shinymanager's own
# login UI (which gets re-bound and triggers duplicate-input errors).
test_that("strip_unrestorable_inputs drops bslib + shinymanager keys", {
  fake_input <- list(
    methodtabs = "panel1",                  # bslib page_navbar
    DataPrep = "Upload",                    # bslib navset_hidden
    `auth-user_id` = "alice",               # shinymanager
    `auth-user_pwd` = "secret",             # shinymanager
    `auth-go_auth` = 1L,                    # shinymanager
    shinymanager_language = "en",           # shinymanager
    shinymanager_loglout = 0L,              # shinymanager
    shinymanager_where = "x",               # shinymanager
    keep_me = "yes",                        # NOT touched
    `load-data_source` = "demo1",           # NOT touched
    `cs-startDE` = 0L                       # NOT touched
  )
  cleaned <- strip_unrestorable_inputs(fake_input)

  # Must be removed
  for (k in c("methodtabs", "DataPrep",
              "auth-user_id", "auth-user_pwd", "auth-go_auth",
              "shinymanager_language", "shinymanager_loglout",
              "shinymanager_where")) {
    expect_false(k %in% names(cleaned),
                 info = sprintf("strip_unrestorable_inputs must drop '%s'", k))
  }

  # Must be kept (these are how DE auto-replay reconstructs the session)
  for (k in c("keep_me", "load-data_source", "cs-startDE")) {
    expect_true(k %in% names(cleaned),
                info = sprintf("strip_unrestorable_inputs must keep '%s'", k))
  }
})

test_that("strip_unrestorable_inputs is no-op on empty/NULL", {
  expect_equal(strip_unrestorable_inputs(list()), list())
  expect_null(strip_unrestorable_inputs(NULL))
})

test_that("strip_unrestorable_inputs mutates env in place", {
  e <- new.env(parent = emptyenv())
  e$methodtabs <- "panel1"
  e$keep_me <- "yes"
  out <- strip_unrestorable_inputs(e)
  expect_identical(out, e)              # same env returned
  expect_false(exists("methodtabs", envir = e, inherits = FALSE))
  expect_true(exists("keep_me", envir = e, inherits = FALSE))
})

# CRITICAL regression: in production, Shiny passes state$input to
# onRestore as a LIST (subagent E2E confirmed length=279, class=list),
# despite older code comments claiming env. The list branch returns
# a NEW filtered list; the caller MUST assign it back. Earlier the
# call site was `strip_unrestorable_inputs(state$input)` (return
# discarded), which silently no-op'd in production. The deServer
# onRestore now does `state$input <- strip_unrestorable_inputs(...)`.
test_that("strip_unrestorable_inputs returns a new filtered list", {
  fake_input <- list(methodtabs = "panel1", keep_me = "x")
  out <- strip_unrestorable_inputs(fake_input)
  # Verify caller could assign back and observe the strip
  expect_false("methodtabs" %in% names(out))
  expect_true("keep_me" %in% names(out))
  # Original list is NOT mutated (R copy-on-write semantics for lists)
  expect_true("methodtabs" %in% names(fake_input))
})

test_that("redact_for_bookmark returns a new filtered list", {
  fake_values <- list(
    `ai_settings-api_key` = "sk-secret",
    SOME_API_KEY = "leak",
    foo = "kept"
  )
  out <- redact_for_bookmark(fake_values)
  expect_false("ai_settings-api_key" %in% names(out))
  expect_false("SOME_API_KEY" %in% names(out))
  expect_true("foo" %in% names(out))
  # Caller-must-assign-back contract documented; original unchanged.
  expect_true("ai_settings-api_key" %in% names(fake_values))
})

# Regression: the deServer onRestore must assign the strip helpers'
# return values back to state$input (the previous bug). Search the
# source for the assignment patterns to keep the contract enforced.
test_that("deServer onRestore assigns strip/redact return values back to state", {
  here <- testthat::test_path("..", "..", "R", "server.R")
  if (!file.exists(here)) {
    here <- system.file("R", "server.R", package = "debrowser")
  }
  if (!file.exists(here) || nchar(here) == 0) {
    skip("server.R not in expected path")
  }
  src <- paste(readLines(here), collapse = "\n")
  expect_true(grepl(
    "state\\$input\\s*<-\\s*strip_unrestorable_inputs\\(state\\$input\\)",
    src),
    info = "deServer onRestore must assign strip_unrestorable_inputs return back"
  )
  expect_true(grepl(
    "state\\$input\\s*<-\\s*redact_for_bookmark\\(state\\$input\\)",
    src),
    info = "deServer onRestore must assign redact_for_bookmark return back for state$input"
  )
  expect_true(grepl(
    "state\\$values\\s*<-\\s*redact_for_bookmark\\(state\\$values\\)",
    src),
    info = "deServer onRestore must assign redact_for_bookmark return back for state$values"
  )
})

# D2.5 Issue 1: deServer onBookmark must snapshot dc() into
# state$values$dc_data so the restored session can plug DE results
# directly without re-running DESeq2 / EdgeR / Limma.
test_that("deServer onBookmark snapshots dc() into state$values$dc_data", {
  here <- testthat::test_path("..", "..", "R", "server.R")
  if (!file.exists(here)) {
    here <- system.file("R", "server.R", package = "debrowser")
  }
  if (!file.exists(here) || nchar(here) == 0) {
    skip("server.R not in expected path")
  }
  src <- paste(readLines(here), collapse = "\n")
  expect_true(grepl("state\\$values\\$dc_data\\s*<-\\s*current_dc", src),
              info = "deServer onBookmark must save current_dc to state$values$dc_data")
  expect_true(grepl("isolate\\(dc\\(\\)\\)", src),
              info = "deServer onBookmark must use shiny::isolate(dc()) to snapshot")
})

# D2.5 Issue 1: deServer onRestore must capture state$values$dc_data
# into pending_dc_restore so the auto-replay observer can use it
# instead of running DE.
test_that("deServer onRestore captures dc_data into pending_dc_restore", {
  here <- testthat::test_path("..", "..", "R", "server.R")
  if (!file.exists(here)) {
    here <- system.file("R", "server.R", package = "debrowser")
  }
  if (!file.exists(here) || nchar(here) == 0) {
    skip("server.R not in expected path")
  }
  src <- paste(readLines(here), collapse = "\n")
  expect_true(grepl("pending_dc_restore\\(saved_dc\\)", src),
              info = "deServer onRestore must call pending_dc_restore(saved_dc)")
  expect_true(grepl("state\\$values\\$dc_data", src),
              info = "deServer onRestore must read state$values$dc_data")
})

# D2.5 Issue 1: auto-replay observer FAST PATH must short-circuit
# when cached_dc is non-NULL (no prepDataContainer call).
test_that("auto-replay observer has FAST PATH that uses cached dc directly", {
  here <- testthat::test_path("..", "..", "R", "server.R")
  if (!file.exists(here)) {
    here <- system.file("R", "server.R", package = "debrowser")
  }
  if (!file.exists(here) || nchar(here) == 0) {
    skip("server.R not in expected path")
  }
  src <- paste(readLines(here), collapse = "\n")
  expect_true(grepl("FAST PATH", src),
              info = "auto-replay observer must have a FAST PATH branch for cached dc")
  expect_true(grepl("dc_res <- cached_dc", src),
              info = "FAST PATH must assign cached_dc to dc_res (no prepDataContainer call)")
})

# D2.5 Issue 2: shinymanager session timeout must be set high enough
# that users don't get bounced mid-analysis. Originally tried
# `cookie_validity = 7L` for cross-restart persistence, but
# shinymanager 1.0.410 doesn't accept that parameter -- passing it is
# a fatal "unused argument" error that blocks login entirely. Until
# upstream support lands, the inactivity timeout is the lever we have.
test_that("secure_server uses a long inactivity timeout (no cookie_validity)", {
  here <- testthat::test_path("..", "..", "R", "server.R")
  if (!file.exists(here)) {
    here <- system.file("R", "server.R", package = "debrowser")
  }
  if (!file.exists(here) || nchar(here) == 0) {
    skip("server.R not in expected path")
  }
  src <- paste(readLines(here), collapse = "\n")
  # MUST NOT pass cookie_validity \u2014 shinymanager 1.0.410 errors on it.
  expect_false(grepl("cookie_validity\\s*=", src),
               info = "secure_server must NOT pass cookie_validity (unsupported by shinymanager 1.0.410)")
  # MUST set a long timeout \u2014 the only knob shinymanager exposes for keeping
  # the user logged in within a single browser session.
  expect_true(grepl("timeout\\s*=\\s*60\\s*\\*\\s*24", src),
              info = "secure_server should set a multi-day timeout in minutes")
})

# Regression: pending_de_replay capture must run BEFORE the token-guard
# early-return so that hosted-mode (shinymanager) sessions \u2014 which keep
# `?token=...` in the URL for the entire post-auth lifetime \u2014 still
# trigger DE auto-replay.
test_that("onRestore captures pending_de_replay before the token guard", {
  here <- testthat::test_path("..", "..", "R", "server.R")
  if (!file.exists(here)) {
    here <- system.file("R", "server.R", package = "debrowser")
  }
  if (!file.exists(here) || nchar(here) == 0) {
    skip("server.R not in expected path")
  }
  src <- readLines(here)
  text <- paste(src, collapse = "\n")
  # Find positions
  capture_pos <- regexpr("pending_de_replay\\(cs_state\\$comparisons_spec\\)", text)
  guard_pos <- regexpr(
    "url_query\\[\\[\"token\"\\]\\]\\)\\s*&&\\s*nzchar\\(url_query\\[\\[\"token\"\\]\\]\\)",
    text
  )
  expect_true(capture_pos > 0,
              info = "must call pending_de_replay(cs_state$comparisons_spec)")
  expect_true(guard_pos > 0,
              info = "must have token-guard")
  expect_true(capture_pos < guard_pos,
              info = "capture must come before the token-guard early-return")
})
