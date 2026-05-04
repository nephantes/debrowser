# R/fct_ai_settings.R
#
# Phase E12.A - settings persistence. Non-secret preferences live in a
# plaintext JSON at R_user_dir("debrowser", "config")/ai-settings.json.
# API keys live in the OS keyring (service "debrowser-ai", username per
# provider). .has_required_credentials() encapsulates the
# "panel-should-render?" predicate. Tested in
# tests/testthat/test-fct-ai-settings.R.

# Default config directory: tools::R_user_dir-controlled per OS.
#' @keywords internal
#' @noRd
.ai_settings_default_dir <- function() {
  tools::R_user_dir("debrowser", which = "config")
}

#' @keywords internal
#' @noRd
.ai_settings_path <- function(config_dir = .ai_settings_default_dir()) {
  file.path(config_dir, "ai-settings.json")
}

#' Documented defaults for AI settings (returned when no file exists).
#' @keywords internal
#' @noRd
.ai_settings_defaults <- function() {
  list(
    enabled = FALSE,
    provider = NULL,
    model = NULL,
    default_privacy = "symbols"
  )
}

#' Load AI settings from disk.
#'
#' Reads `ai-settings.json` from the user's config directory. Returns
#' the documented defaults when no file exists or the file is malformed.
#'
#' @param config_dir Directory containing `ai-settings.json`. Defaults
#'   to `tools::R_user_dir("debrowser", "config")`.
#' @return list with components `enabled` (lgl), `provider` (chr|NULL),
#'   `model` (chr|NULL), `default_privacy` (chr).
#' @keywords internal
#' @noRd
ai_settings_load <- function(config_dir = .ai_settings_default_dir()) {
  path <- .ai_settings_path(config_dir)
  if (!file.exists(path)) return(.ai_settings_defaults())
  raw <- tryCatch(jsonlite::fromJSON(path, simplifyVector = TRUE),
                  error = function(e) NULL)
  if (is.null(raw)) return(.ai_settings_defaults())
  defaults <- .ai_settings_defaults()
  defaults[names(raw)] <- raw
  # Normalize empty strings back to NULL (jsonlite may render NULL as "")
  if (identical(defaults$provider, "")) defaults$provider <- NULL
  if (identical(defaults$model, ""))    defaults$model    <- NULL
  defaults
}

#' Save AI settings to disk.
#'
#' Persists non-secret preferences as plaintext JSON. Strips any `key`
#' field defensively so a caller bug cannot leak an API key to disk.
#'
#' @param settings list. Same shape as [ai_settings_load()].
#' @param config_dir Directory to write to. Created if absent.
#' @return invisible(NULL).
#' @keywords internal
#' @noRd
ai_settings_save <- function(settings,
                             config_dir = .ai_settings_default_dir()) {
  # Defensive: never persist a 'key' field even if a caller mistakenly
  # puts one in.
  settings$key <- NULL
  if (!dir.exists(config_dir)) {
    dir.create(config_dir, recursive = TRUE, showWarnings = FALSE)
  }
  jsonlite::write_json(settings, .ai_settings_path(config_dir),
                       auto_unbox = TRUE, null = "null", pretty = TRUE)
  invisible(NULL)
}

# --- keyring helpers (gated by require_pkg) -----------------------------------

.AI_KEYRING_SERVICE <- "debrowser-ai"

#' Get the API key for a provider from the OS keyring.
#'
#' @param provider chr(1). "anthropic" | "openai".
#' @return chr(1) or NULL when no entry exists.
#' @keywords internal
#' @noRd
ai_key_get <- function(provider) {
  require_pkg("keyring", "AI features")
  tryCatch(
    keyring::key_get(service = .AI_KEYRING_SERVICE, username = provider),
    error = function(e) NULL
  )
}

#' Set the API key for a provider in the OS keyring.
#'
#' @param provider chr(1). "anthropic" | "openai".
#' @param key chr(1). The API key.
#' @return invisible(NULL).
#' @keywords internal
#' @noRd
ai_key_set <- function(provider, key) {
  require_pkg("keyring", "AI features")
  keyring::key_set_with_value(service = .AI_KEYRING_SERVICE,
                              username = provider, password = key)
  invisible(NULL)
}

#' Clear the API key for a provider from the OS keyring.
#'
#' @param provider chr(1).
#' @return invisible(NULL). Silently succeeds when no entry exists.
#' @keywords internal
#' @noRd
ai_key_clear <- function(provider) {
  require_pkg("keyring", "AI features")
  tryCatch(
    keyring::key_delete(service = .AI_KEYRING_SERVICE, username = provider),
    error = function(e) NULL
  )
  invisible(NULL)
}

#' Predicate: should the AI panel render?
#'
#' Encapsulates the master-switch + provider + key check. The Shiny
#' module uses this to gate UI rendering (defense-in-depth: the AI panel
#' will never appear unless all three conditions hold).
#'
#' @param settings list, output of [ai_settings_load()].
#' @return TRUE/FALSE.
#' @keywords internal
#' @noRd
.has_required_credentials <- function(settings) {
  isTRUE(settings$enabled) &&
    !is.null(settings$provider) &&
    (settings$provider == "ollama" ||
       !is.null(ai_key_get(settings$provider)))
}
