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

#' Strip fields from an AI payload per privacy mode.
#'
#' @param payload list with components `genes` (chr), `stats`
#'   (data.frame with gene_id/log2FoldChange/padj), `enrichment`
#'   (list with term/pvalue/n_overlap). All but `genes` may be NULL.
#' @param privacy_mode chr(1). One of "symbols", "stats", "stats_enrichment".
#' @param top_n integer(1). Cap on genes-list and stats-row length.
#' @return list. Always has `genes`. Has `stats` for "stats" /
#'   "stats_enrichment" modes. Has `enrichment` for "stats_enrichment"
#'   mode only. Carries attributes `truncated` (logical) and `n_total`
#'   (integer) when `length(genes) > top_n`.
#' @keywords internal
#' @noRd
.redact_payload <- function(payload, privacy_mode, top_n = 50L) {
  if (!privacy_mode %in% c("symbols", "stats", "stats_enrichment")) {
    ai_error(sprintf("Unknown privacy_mode: '%s'", privacy_mode),
             class = "ai_invalid_response")
  }
  genes <- payload$genes
  n_total <- length(genes)
  truncated <- n_total > top_n
  if (truncated) {
    genes <- genes[seq_len(top_n)]
  }

  out <- list(genes = genes)
  if (privacy_mode %in% c("stats", "stats_enrichment") && !is.null(payload$stats)) {
    s <- payload$stats
    if (truncated) s <- s[seq_len(min(top_n, nrow(s))), , drop = FALSE]
    out$stats <- s
  }
  if (privacy_mode == "stats_enrichment" && !is.null(payload$enrichment)) {
    out$enrichment <- payload$enrichment
  }

  attr(out, "truncated") <- truncated
  attr(out, "n_total")   <- n_total
  out
}