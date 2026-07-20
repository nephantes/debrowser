test_that("list_models returns fallback list when API throws", {
  testthat::skip_if_not_installed("ellmer")
  testthat::local_mocked_bindings(
    models_anthropic = function(api_key = NULL) stop("network error"),
    .package = "ellmer"
  )
  out <- list_models("anthropic", api_key = "key")
  expect_equal(out, "claude-sonnet-4-7")
})

test_that("list_models dispatches to ellmer::models_anthropic", {
  testthat::skip_if_not_installed("ellmer")
  called <- new.env()
  testthat::local_mocked_bindings(
    models_anthropic = function(api_key = NULL) {
      called$key <- api_key
      c("claude-opus-4-7", "claude-sonnet-4-7", "claude-haiku-4-5")
    },
    .package = "ellmer"
  )
  out <- list_models("anthropic", api_key = "test-key")
  expect_equal(called$key, "test-key")
  expect_equal(out, c("claude-opus-4-7", "claude-sonnet-4-7", "claude-haiku-4-5"))
})

test_that("list_models dispatches to ellmer::models_openai", {
  testthat::skip_if_not_installed("ellmer")
  testthat::local_mocked_bindings(
    models_openai = function(api_key = NULL) c("gpt-4.1", "gpt-4o"),
    .package = "ellmer"
  )
  expect_equal(list_models("openai", api_key = "k"), c("gpt-4.1", "gpt-4o"))
})

test_that("list_models dispatches to ellmer::models_ollama (no api_key)", {
  testthat::skip_if_not_installed("ellmer")
  testthat::local_mocked_bindings(
    models_ollama = function() c("llama3.2", "mistral"),
    .package = "ellmer"
  )
  expect_equal(list_models("ollama"), c("llama3.2", "mistral"))
})

test_that("list_models raises ai_invalid_response for unknown provider", {
  expect_error(
    list_models("nope"),
    class = "ai_invalid_response"
  )
})

test_that("list_models returns fallback list when API returns empty vector", {
  testthat::skip_if_not_installed("ellmer")
  testthat::local_mocked_bindings(
    models_anthropic = function(api_key = NULL) character(0),
    .package = "ellmer"
  )
  out <- list_models("anthropic", api_key = "k")
  expect_equal(out, "claude-sonnet-4-7")
})

test_that("ai_chat dispatches to ellmer::chat_anthropic", {
  testthat::skip_if_not_installed("ellmer")
  called <- new.env()
  testthat::local_mocked_bindings(
    chat_anthropic = function(api_key, model) {
      called$key <- api_key
      called$model <- model
      list(stub = TRUE)
    },
    .package = "ellmer"
  )
  out <- ai_chat("anthropic", "claude-sonnet-4-7", "key")
  expect_equal(called$key, "key")
  expect_equal(called$model, "claude-sonnet-4-7")
})

test_that("ai_chat raises ai_invalid_response for unknown provider", {
  expect_error(
    ai_chat("nope", "model", "key"),
    class = "ai_invalid_response"
  )
})
