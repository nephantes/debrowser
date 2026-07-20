.fresh_settings_dir <- function() {
  d <- tempfile("debrowser_ai_test_")
  dir.create(d, recursive = TRUE)
  d
}

test_that("ai_settings_load returns documented defaults when file missing", {
  d <- .fresh_settings_dir()
  on.exit(unlink(d, recursive = TRUE), add = TRUE)
  s <- ai_settings_load(config_dir = d)
  expect_false(s$enabled)
  expect_null(s$provider)
  expect_null(s$model)
  expect_equal(s$default_privacy, "symbols")
})

test_that("ai_settings_save then ai_settings_load round-trips", {
  d <- .fresh_settings_dir()
  on.exit(unlink(d, recursive = TRUE), add = TRUE)
  ai_settings_save(
    list(enabled = TRUE, provider = "anthropic",
         model = "claude-sonnet-4-7", default_privacy = "stats"),
    config_dir = d
  )
  s <- ai_settings_load(config_dir = d)
  expect_true(s$enabled)
  expect_equal(s$provider, "anthropic")
  expect_equal(s$model, "claude-sonnet-4-7")
  expect_equal(s$default_privacy, "stats")
})

test_that("ai_settings_save strips secrets (key field is never persisted)", {
  d <- .fresh_settings_dir()
  on.exit(unlink(d, recursive = TRUE), add = TRUE)
  ai_settings_save(
    list(enabled = TRUE, provider = "anthropic", model = "x",
         default_privacy = "symbols",
         key = "this-must-not-be-saved-to-disk"),
    config_dir = d
  )
  raw <- paste(readLines(file.path(d, "ai-settings.json")), collapse = "\n")
  expect_false(grepl("this-must-not-be-saved-to-disk", raw, fixed = TRUE))
  expect_false(grepl("\\bkey\\b", raw))
})

# --- keyring helpers (mocked) ---

test_that("ai_key_get returns NULL when keyring has no entry", {
  testthat::skip_if_not_installed("keyring")
  testthat::local_mocked_bindings(
    key_get = function(service, username) stop("no entry"),
    .package = "keyring"
  )
  expect_null(ai_key_get("anthropic"))
})

test_that("ai_key_set then ai_key_get round-trip via keyring", {
  testthat::skip_if_not_installed("keyring")
  store <- new.env()
  testthat::local_mocked_bindings(
    key_set_with_value = function(service, username, password) {
      store[[paste(service, username, sep = ":")]] <- password
      invisible(NULL)
    },
    key_get = function(service, username) {
      val <- store[[paste(service, username, sep = ":")]]
      if (is.null(val)) stop("no entry")
      val
    },
    .package = "keyring"
  )
  ai_key_set("anthropic", "sk-test-12345")
  expect_equal(ai_key_get("anthropic"), "sk-test-12345")
})

test_that("ai_key_clear removes the entry", {
  testthat::skip_if_not_installed("keyring")
  store <- new.env(); store[["debrowser-ai:anthropic"]] <- "old"
  testthat::local_mocked_bindings(
    key_delete = function(service, username) {
      rm(list = paste(service, username, sep = ":"), envir = store)
      invisible(NULL)
    },
    key_get = function(service, username) {
      val <- store[[paste(service, username, sep = ":")]]
      if (is.null(val)) stop("no entry")
      val
    },
    .package = "keyring"
  )
  ai_key_clear("anthropic")
  expect_null(ai_key_get("anthropic"))
})

# --- .has_required_credentials predicate ---

test_that(".has_required_credentials returns FALSE when disabled", {
  expect_false(.has_required_credentials(list(enabled = FALSE,
                                              provider = "anthropic")))
})

test_that(".has_required_credentials returns FALSE when no provider", {
  expect_false(.has_required_credentials(list(enabled = TRUE,
                                             provider = NULL)))
})

test_that(".has_required_credentials returns TRUE for ollama (no key needed)", {
  expect_true(.has_required_credentials(list(enabled = TRUE,
                                            provider = "ollama")))
})

test_that(".has_required_credentials returns TRUE when anthropic key exists", {
  testthat::skip_if_not_installed("keyring")
  testthat::local_mocked_bindings(
    key_get = function(service, username) "sk-key",
    .package = "keyring"
  )
  expect_true(.has_required_credentials(list(enabled = TRUE,
                                            provider = "anthropic")))
})

test_that(".has_required_credentials returns FALSE when anthropic key missing", {
  testthat::skip_if_not_installed("keyring")
  testthat::local_mocked_bindings(
    key_get = function(service, username) stop("no entry"),
    .package = "keyring"
  )
  expect_false(.has_required_credentials(list(enabled = TRUE,
                                             provider = "anthropic")))
})
