# R/fct_ai_providers.R
#
# Phase E12.A - provider abstraction over ellmer. list_models() returns
# the user's available model ids per provider, with a hardcoded fallback
# list when the API call fails. ai_chat() returns a provider-specific
# ellmer chat object. Both gated via require_pkg("ellmer", "AI features").
# Tested in tests/testthat/test-fct-ai-providers.R.

#' List available models for a configured LLM provider.
#'
#' Calls the provider's models endpoint via ellmer. Returns the user's
#' available model ids on success, or a hardcoded fallback list on
#' failure. Always returns a non-empty character vector.
#'
#' @param provider chr(1). "anthropic" | "openai" | "ollama".
#' @param api_key chr(1) or NULL. Required for anthropic/openai; NULL
#'   for ollama.
#' @return character vector of model ids.
#' @export
list_models <- function(provider, api_key = NULL) {
  fallback <- switch(provider,
    "anthropic" = "claude-sonnet-4-7",
    "openai"    = "gpt-4.1",
    "ollama"    = "llama3.2",
    ai_error(sprintf("Unknown provider: '%s'", provider),
             class = "ai_invalid_response")
  )
  require_pkg("ellmer", "AI features")
  tryCatch({
    ids <- switch(provider,
      "anthropic" = ellmer::models_anthropic(api_key = api_key),
      "openai"    = ellmer::models_openai(api_key = api_key),
      "ollama"    = ellmer::models_ollama()
    )
    if (length(ids) == 0L) fallback else ids
  }, error = function(e) {
    fallback
  })
}

#' Build an ellmer chat object for the configured provider/model.
#'
#' @param provider chr(1).
#' @param model chr(1).
#' @param api_key chr(1) or NULL.
#' @return An ellmer Chat object. Caller invokes `$chat(prompt)` on it.
#' @export
ai_chat <- function(provider, model, api_key = NULL) {
  if (!provider %in% c("anthropic", "openai", "ollama")) {
    ai_error(sprintf("Unknown provider: '%s'", provider),
             class = "ai_invalid_response")
  }
  require_pkg("ellmer", "AI features")
  switch(provider,
    "anthropic" = ellmer::chat_anthropic(api_key = api_key, model = model),
    "openai"    = ellmer::chat_openai(api_key = api_key, model = model),
    "ollama"    = ellmer::chat_ollama(model = model)
  )
}
