# R/fct_ai_interpret.R
#
# Phase E12.A - pure AI interpretation orchestrator. ai_interpret() takes a
# preset question key, a payload of analytical context, a privacy mode, and
# an ellmer chat object, and returns the model's response. Errors are
# raised as classed conditions (ai_error subclasses) for the Shiny module
# to map to friendly notifications. Tested in
# tests/testthat/test-fct-ai-interpret.R.


#' Raise a classed condition for AI interpretation errors.
#'
#' All AI-path errors go through `ai_error()` so the Shiny module can
#' pattern-match for friendly messages. Subclasses (passed via `class =`):
#' `ai_no_key`, `ai_rate_limit`, `ai_network`, `ai_invalid_response`,
#' `ai_disabled`. All inherit from `ai_error`.
#'
#' @param message chr(1). Human-readable message (used as fallback when
#'   the UI doesn't have a friendlier mapping for the subclass).
#' @param class chr. Subclass name(s). `"ai_error"` is appended automatically.
#' @return Never returns; raises a condition.
#' @keywords internal
#' @noRd
ai_error <- function(message, class = NULL) {
  cond <- structure(
    class = c(class, "ai_error", "error", "condition"),
    list(message = message, call = sys.call(-1))
  )
  stop(cond)
}