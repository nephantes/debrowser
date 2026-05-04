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

#' Render a whisker prompt template with the given slots.
#'
#' @param template_path chr(1). Path to a `.md` template file.
#' @param slots list. Substitutions for `{{name}}` and `{{#section}}` syntax.
#' @return chr(1). The rendered prompt.
#' @keywords internal
#' @noRd
.render_prompt <- function(template_path, slots) {
  if (!file.exists(template_path)) {
    ai_error(sprintf("Prompt template not found: '%s'", template_path),
             class = "ai_invalid_response")
  }
  require_pkg("whisker", "AI features")
  raw <- paste(readLines(template_path, warn = FALSE), collapse = "\n")
  whisker::whisker.render(raw, data = slots)
}

#' Translate an ellmer / HTTP error into a classed ai_error subclass.
#'
#' Inspects the error message for substring patterns and dispatches to
#' the right subclass. Falls back to `ai_invalid_response` when nothing
#' matches.
#'
#' @param e A condition (typically from a tryCatch around an ellmer call).
#' @return Never returns; raises a classed `ai_error`.
#' @keywords internal
#' @noRd
.map_provider_error <- function(e) {
  msg <- conditionMessage(e)
  lc  <- tolower(msg)
  if (grepl("401|unauthor|api[_ -]?key|forbidden", lc)) {
    ai_error(msg, class = "ai_no_key")
  } else if (grepl("429|rate[ -]?limit|too many requests", lc)) {
    ai_error(msg, class = "ai_rate_limit")
  } else if (grepl("could not resolve|connection refused|timeout|timed out|unreachable", lc)) {
    ai_error(msg, class = "ai_network")
  } else {
    ai_error(msg, class = "ai_invalid_response")
  }
}

#' Send a redacted analytical question to a configured LLM provider.
#'
#' Pure orchestrator over: payload redaction (per `privacy_mode`), prompt
#' template rendering (whisker), and dispatch to the provided ellmer chat
#' object. Returns the model's response as `chr(1)`. Errors are surfaced
#' as classed conditions of class `ai_error` so callers (the Shiny module)
#' can pattern-match for friendly messages.
#'
#' @param question chr(1). Preset key. v1 supports "summarize_geneset".
#' @param payload list. Pre-built payload. Shape: `list(genes = chr,
#'   stats = data.frame|NULL, enrichment = list|NULL)`.
#' @param privacy_mode chr(1). One of "symbols", "stats", "stats_enrichment".
#' @param provider_chat An ellmer chat object (output of `ai_chat()`).
#'   The chat object must have a `$chat(text)` method that returns chr(1)
#'   on success or raises an error on failure.
#' @param top_n integer(1). Cap on genes-list length. Default 50.
#' @param template_dir Directory containing `ai_*.md` templates. Default
#'   `system.file("templates", package = "debrowser")`.
#' @return character(1). Model's response text.
#' @export
ai_interpret <- function(question, payload, privacy_mode, provider_chat,
                         top_n = 50L,
                         template_dir = system.file("templates",
                                                    package = "debrowser")) {
  template_file <- file.path(template_dir, sprintf("ai_%s.md", question))
  if (!file.exists(template_file)) {
    ai_error(sprintf("Unknown AI question preset: '%s'", question),
             class = "ai_invalid_response")
  }

  redacted <- .redact_payload(payload, privacy_mode, top_n = top_n)
  truncated <- isTRUE(attr(redacted, "truncated"))
  n_total   <- attr(redacted, "n_total")

  slots <- list(
    n_genes        = length(redacted$genes),
    n_total        = n_total,
    truncated      = truncated,
    gene_list      = paste(redacted$genes, collapse = ", "),
    has_stats      = !is.null(redacted$stats),
    stats_table    = if (is.null(redacted$stats)) "" else .format_stats_table(redacted$stats),
    has_enrichment = !is.null(redacted$enrichment),
    enrichment_summary = if (is.null(redacted$enrichment)) "" else
      sprintf("Term: %s; p-value: %g; overlap: %d genes.",
              redacted$enrichment$term,
              redacted$enrichment$pvalue,
              redacted$enrichment$n_overlap)
  )
  prompt_text <- .render_prompt(template_file, slots)

  tryCatch(
    provider_chat$chat(prompt_text),
    error = function(e) .map_provider_error(e)
  )
}

#' Format a stats data.frame as a human-readable two-column table.
#' @keywords internal
#' @noRd
.format_stats_table <- function(stats) {
  rows <- vapply(seq_len(nrow(stats)), function(i) {
    sprintf("%s | %.3f | %.3g",
            stats$gene_id[i],
            stats$log2FoldChange[i],
            stats$padj[i])
  }, character(1))
  paste(rows, collapse = "\n")
}