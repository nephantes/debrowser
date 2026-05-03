# R/fct_methods_text.R
#
# E9-lite: per-step methods sentences consumed by emit_r_script() (header
# comment block) and emit_rmd() (Methods paragraph). Phase E9 will upgrade
# this to a citation-rich paragraph generator; the function name and
# signature are stable.
# Tested in tests/testthat/test-fct-methods-text.R.

#' Per-step methods sentences (E9-lite).
#'
#' Returns a named character vector with one entry per pipeline step
#' (`load, filter, batch, de, enrichment`). Each entry is one
#' English sentence (or NA if the step did not run, e.g. `batch$method ==
#' "none"`). Phase E9 will replace this with a paragraph-level generator
#' producing citation-rich prose; until then both the `.R` script header
#' and the `.Rmd` "Methods" section consume these per-step sentences.
#'
#' @param blocks Output of [build_session_blocks()].
#' @return Named character vector of length 5.
#' @keywords internal
#' @noRd
methods_sentences <- function(blocks) {
  load_msg <- switch(blocks$load$source,
    "demo1" = sprintf("Counts loaded from DEBrowser demo dataset 'Vernia et al.' (%d features x %d samples).",
                     blocks$load$n_features, blocks$load$n_samples),
    "demo2" = sprintf("Counts loaded from DEBrowser demo dataset 'Donnard et al.' (%d features x %d samples).",
                     blocks$load$n_features, blocks$load$n_samples),
    "json"  = sprintf("Counts loaded from JSON URL (%d features x %d samples).",
                     blocks$load$n_features, blocks$load$n_samples),
    "upload" = sprintf("Counts loaded from uploaded file '%s' (%d features x %d samples).",
                      blocks$load$counts_path %||% "counts.tsv",
                      blocks$load$n_features, blocks$load$n_samples)
  )

  filter_method_label <- switch(blocks$filter$method,
    "Max"  = sprintf("Max value < %s", blocks$filter$cutoff),
    "Mean" = sprintf("Mean value < %s", blocks$filter$cutoff),
    "CPM"  = sprintf("CPM < %s in fewer than %d samples",
                    blocks$filter$cutoff, blocks$filter$min_samples)
  )
  filter_msg <- sprintf(
    "Low-count features removed using filter (%s); %d of %d features retained.",
    filter_method_label,
    blocks$filter$n_features_out, blocks$filter$n_features_in
  )

  batch_msg <- if (identical(blocks$batch$method, "none")) {
    NA_character_
  } else {
    label <- switch(blocks$batch$method,
      "Combat"    = "ComBat (sva package)",
      "CombatSeq" = "ComBat-seq (sva package)",
      "Harman"    = "Harman"
    )
    sprintf("Batch effects corrected with %s, batch column '%s', treatment column '%s'.",
            label, blocks$batch$batch_column,
            blocks$batch$treatment_column %||% "(none)")
  }

  de_lines <- vapply(seq_along(blocks$de), function(i) {
    d <- blocks$de[[i]]
    param_str <- paste(sprintf("%s=%s", names(d$method_params),
                               unlist(d$method_params)), collapse = ", ")
    cov_str <- if (length(d$covariates) == 0L) "" else {
      sprintf(", covariates=%s", paste(d$covariates, collapse = "|"))
    }
    sprintf("Comparison %d: '%s' vs '%s' tested with %s (%s%s); %d features significant at padj<0.05, |log2FC|>1.",
            i, d$treatment_label, d$control_label, d$de_method,
            param_str, cov_str, d$n_sig_at_padj0.05_lfc1)
  }, character(1))
  de_msg <- paste(de_lines, collapse = " ")

  enrichment_msg <- if (is.null(blocks$enrichment)) {
    NA_character_
  } else if (identical(blocks$enrichment$source, "msigdb")) {
    sub <- blocks$enrichment$msigdb$subcollection
    sub_part <- if (is.na(sub) || !nzchar(sub)) "" else sprintf(" / %s", sub)
    sprintf("Gene set enrichment performed with fgsea against MSigDB %s / %s%s (%d gene sets).",
            blocks$enrichment$msigdb$species,
            blocks$enrichment$msigdb$collection,
            sub_part, blocks$enrichment$n_pathways)
  } else {
    sprintf("Gene set enrichment performed with fgsea against gene sets from '%s' (%d sets).",
            blocks$enrichment$manual_file %||% "uploaded .gmt",
            blocks$enrichment$n_pathways)
  }

  c(load = load_msg, filter = filter_msg, batch = batch_msg,
    de = de_msg, enrichment = enrichment_msg)
}

# Internal NULL-coalescing helper. Duplicated in mod_enrichment_gmt.R and
# mod_comparison_concordance.R; lift to R/utils_validate.R when R 4.4 is
# the package floor (R 4.4+ has it natively as `%||%`).
#' @noRd
`%||%` <- function(a, b) if (is.null(a)) b else a
