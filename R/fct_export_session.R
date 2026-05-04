# R/fct_export_session.R
#
# Pure helpers for reproducible session export (R script + RMarkdown report).
# Tested in tests/testthat/test-fct-export-session.R.

#' Sanitize a comparison label for use in a filename.
#'
#' Replaces every character that is not alphanumeric, dot, underscore, or
#' hyphen with a single underscore. Used by the export emitters when building
#' per-comparison TSV filenames so that labels like "treated vs control" or
#' "high dose / low dose" produce safe paths.
#'
#' @param label character(1).
#' @return character(1).
#' @keywords internal
#' @noRd
sanitize_label <- function(label) {
  gsub("[^A-Za-z0-9._-]", "_", label)
}

#' Build the structured block list consumed by emit_r_script() / emit_rmd().
#'
#' Pure transformation from a plain-list `state` snapshot (collected by
#' the Shiny export module on download click) into a structured block list:
#' `list(meta, load, filter, batch, de, enrichment)`. Each `de` entry is one
#' comparison; `enrichment` is NULL when the user has not loaded gene sets.
#'
#' The transformation adds two fields per `de` block that the emitters need
#' but the snapshot doesn't carry: `cond_codes` (the `Cond1/Cond2` paired
#' codes that the live app's `prep_comparison_inputs()` builds from the
#' comparison's 1-based slot) and `safe_label` (the sanitized comparison
#' label used as a TSV filename component).
#'
#' @param state Plain list with components `meta, load, filter, batch,
#'   comparisons, enrichment` (see spec section "State snapshot shape").
#' @return list with components `meta, load, filter, batch, de, enrichment`.
#' @keywords internal
#' @noRd
build_session_blocks <- function(state) {
  de_blocks <- lapply(seq_along(state$comparisons), function(i) {
    cmp <- state$comparisons[[i]]
    safe_treat   <- sanitize_label(cmp$treatment_label)
    safe_control <- sanitize_label(cmp$control_label)
    c(cmp, list(
      cond_codes = c(paste0("Cond", 2L * i - 1L),
                     paste0("Cond", 2L * i)),
      safe_label = paste0(safe_treat, "_vs_", safe_control)
    ))
  })
  # Dedupe collisions: when two comparisons produce the same safe_label,
  # later ones get _2, _3, ... suffixes. Same intent as the live-app
  # comparison_labels() helper from R/fct_method_concordance.R but operating
  # on the filename-safe form.
  labels <- vapply(de_blocks, function(b) b$safe_label, character(1))
  for (j in seq_along(labels)) {
    if (sum(labels[seq_len(j)] == labels[j]) > 1L) {
      n <- sum(labels[seq_len(j)] == labels[j])
      de_blocks[[j]]$safe_label <- paste0(labels[j], "_", n)
    }
  }
  list(
    meta       = state$meta,
    load       = state$load,
    filter     = state$filter,
    batch      = state$batch,
    de         = de_blocks,
    enrichment = state$enrichment
  )
}

#' Emit the .R reproducibility script as a character vector.
#'
#' One element per line. The caller (`exportMenuServer`'s downloadHandler)
#' writes this to disk via `writeLines()`. The script calls only
#' already-exported pure helpers so it has no Shiny dependency.
#'
#' Layout:
#'   1. Comment header (timestamp, version, methods sentences, frozen
#'      sessionInfo)
#'   2. library(debrowser)
#'   3. Load counts/metadata (system.file demo / read.table upload)
#'   4. filter_low_counts(...) call
#'   5. apply_batch_correction(...) call (omitted when method=="none")
#'   6. One run_de(...) block per comparison
#'   7. msigdb_pathways() / gmt_to_pathways() + run_gsea() block (omitted
#'      when blocks$enrichment is NULL)
#'   8. dir.create + write.table per comparison + GSEA TSV
#'   9. sessionInfo() at run time
#'
#' @param blocks Output of [build_session_blocks()].
#' @return character vector.
#' @keywords internal
#' @noRd
emit_r_script <- function(blocks) {
  m <- methods_sentences(blocks)
  m_lines <- c(
    sprintf("# - %s", m["load"]),
    sprintf("# - %s", m["filter"]),
    if (!is.na(m["batch"])) sprintf("# - %s", m["batch"]),
    sprintf("# - %s", m["de"]),
    if (!is.na(m["enrichment"])) sprintf("# - %s", m["enrichment"])
  )

  header <- c(
    "# DEBrowser session export",
    sprintf("# Generated %s by debrowser %s",
            format(blocks$meta$timestamp, "%Y-%m-%d %H:%M:%S"),
            blocks$meta$debrowser_version),
    sprintf("# %s", blocks$meta$r_version),
    "#",
    "# Methods (E9-lite -- auto-generated, refine before publication):",
    m_lines,
    "#",
    "# Frozen sessionInfo (at export time):",
    paste0("# ", blocks$meta$session_info),
    "",
    "library(debrowser)",
    ""
  )

  load_block <- if (identical(blocks$load$source, "upload")) {
    counts_name <- blocks$load$counts_path %||% "YOUR_COUNTS.tsv"
    meta_name   <- blocks$load$meta_path   %||% "YOUR_META.tsv"
    c(
      "# 1. Load counts and metadata --------------------------------------------------",
      sprintf("# original upload: counts='%s', meta='%s'", counts_name, meta_name),
      "# EDIT THIS PATH to point at your local copy of the file:",
      'counts <- read.table("YOUR_COUNTS.tsv", sep = "\\t", header = TRUE,',
      "                     row.names = 1, check.names = FALSE)",
      'meta   <- read.table("YOUR_META.tsv",   sep = "\\t", header = TRUE,',
      "                     row.names = 1, check.names = FALSE)",
      ""
    )
  } else {
    fixture <- if (identical(blocks$load$source, "demo2")) "demodata2.Rda" else "demodata.Rda"
    c(
      "# 1. Load counts and metadata --------------------------------------------------",
      "demo_env <- new.env()",
      sprintf('load(system.file("extdata", "demo", "%s", package = "debrowser"), envir = demo_env)',
              fixture),
      "counts <- demo_env$demodata",
      "meta   <- demo_env$metadatatable",
      ""
    )
  }

  filter_call <- switch(blocks$filter$method,
    "Max"  = sprintf('filtered <- filter_low_counts(counts, method = "max",  cutoff = %s)',
                    blocks$filter$cutoff),
    "Mean" = sprintf('filtered <- filter_low_counts(counts, method = "mean", cutoff = %s)',
                    blocks$filter$cutoff),
    "CPM"  = sprintf('filtered <- filter_low_counts(counts, method = "cpm",  cutoff = %s, min_samples = %d)',
                    blocks$filter$cutoff, blocks$filter$min_samples)
  )
  filter_block <- c(
    "# 2. Low-count filter ----------------------------------------------------------",
    filter_call,
    ""
  )

  batch_block <- if (identical(blocks$batch$method, "none")) {
    c(
      "# 3. Batch correction ----------------------------------------------------------",
      "# (none configured)",
      "corrected <- filtered",
      ""
    )
  } else {
    treat_arg <- if (is.na(blocks$batch$treatment_column %||% NA_character_)) {
      "NULL"
    } else {
      sprintf('"%s"', blocks$batch$treatment_column)
    }
    c(
      "# 3. Batch correction ----------------------------------------------------------",
      "corrected <- apply_batch_correction(",
      "  filtered, meta,",
      sprintf('  method = "%s", batch_col = "%s", treatment_col = %s',
              blocks$batch$method, blocks$batch$batch_column, treat_arg),
      ")",
      ""
    )
  }

  de_blocks <- unlist(lapply(seq_along(blocks$de), function(i) {
    d <- blocks$de[[i]]
    cols_str  <- paste(sprintf('"%s"', c(d$treatment_samples, d$control_samples)),
                       collapse = ", ")
    conds_vec <- c(rep(d$cond_codes[1L], length(d$treatment_samples)),
                   rep(d$cond_codes[2L], length(d$control_samples)))
    conds_str <- paste(sprintf('"%s"', conds_vec), collapse = ", ")
    cov_token <- if (length(d$covariates) == 0L) "NoCovariate" else {
      paste(d$covariates, collapse = "|")
    }
    params_pairs <- switch(d$de_method,
      "DESeq2" = c(
        sprintf('covariates = "%s"', cov_token),
        sprintf('fit_type   = "%s"', d$method_params$fitType),
        sprintf('beta_prior = %s',   toupper(as.character(d$method_params$betaPrior))),
        sprintf('test_type  = "%s"', d$method_params$testType),
        sprintf('shrinkage  = "%s"', d$method_params$shrinkage)
      ),
      "EdgeR"  = c(
        sprintf('covariates = "%s"', cov_token),
        sprintf('norm_fact  = "%s"', d$method_params$edgeR_normfact),
        sprintf('dispersion = "%s"', d$method_params$dispersion),
        sprintf('test_type  = "%s"', d$method_params$edgeR_testType)
      ),
      "Limma"  = c(
        sprintf('covariates = "%s"', cov_token),
        sprintf('norm_fact  = "%s"', d$method_params$limma_normfact),
        sprintf('fit_type   = "%s"', d$method_params$limma_fitType),
        sprintf('norm_bet   = "%s"', d$method_params$normBetween)
      )
    )
    params_str <- paste(params_pairs, collapse = ", ")
    c(
      sprintf("# --- Comparison %d: %s vs %s ---", i, d$treatment_label, d$control_label),
      sprintf("cols_%d  <- c(%s)", i, cols_str),
      sprintf("conds_%d <- c(%s)", i, conds_str),
      sprintf("de%d <- run_de(", i),
      sprintf('  method = "%s",', d$de_method),
      sprintf("  counts = corrected, metadata = meta, columns = cols_%d, conds = conds_%d,",
              i, i),
      sprintf("  params = list(%s),", params_str),
      "  return_dds = FALSE",
      ")",
      ""
    )
  }))
  de_block <- c(
    "# 4. Differential expression ---------------------------------------------------",
    de_blocks
  )

  enrichment_block <- if (is.null(blocks$enrichment)) character(0) else {
    setup <- if (identical(blocks$enrichment$source, "msigdb")) {
      sub <- blocks$enrichment$msigdb$subcollection
      sub_arg <- if (is.na(sub) || !nzchar(sub)) "NULL" else sprintf('"%s"', sub)
      sprintf('pathways <- msigdb_pathways(species = "%s", collection = "%s", subcollection = %s)',
              blocks$enrichment$msigdb$species,
              blocks$enrichment$msigdb$collection, sub_arg)
    } else {
      gmt_name <- blocks$enrichment$manual_file %||% "YOUR_GMT.gmt"
      c(
        sprintf("# original upload: '%s' -- EDIT THIS PATH:", gmt_name),
        sprintf('pathways <- gmt_to_pathways("%s")', gmt_name)
      )
    }
    runs <- unlist(lapply(seq_along(blocks$de), function(i) {
      sprintf("gsea_%d <- run_gsea(de%d, pathways = pathways)", i, i)
    }))
    c(
      "# 5. Enrichment (GSEA) ---------------------------------------------------------",
      setup,
      runs,
      ""
    )
  }

  write_lines <- unlist(lapply(seq_along(blocks$de), function(i) {
    d <- blocks$de[[i]]
    base <- sprintf("debrowser_results/results_%s.tsv", d$safe_label)
    line <- sprintf('write.table(de%d, "%s",', i, base)
    c(line,
      '            sep = "\\t", quote = FALSE, col.names = NA)')
  }))
  gsea_write_lines <- if (is.null(blocks$enrichment)) character(0) else {
    unlist(lapply(seq_along(blocks$de), function(i) {
      d <- blocks$de[[i]]
      base <- sprintf("debrowser_results/gsea_%s.tsv", d$safe_label)
      line <- sprintf('write.table(gsea_%d, "%s",', i, base)
      c(line,
        '            sep = "\\t", quote = FALSE, row.names = FALSE)')
    }))
  }
  n_files <- length(blocks$de) +
    (if (is.null(blocks$enrichment)) 0L else length(blocks$de))
  results_block <- c(
    "# 6. Write per-comparison result tables ----------------------------------------",
    'dir.create("debrowser_results", showWarnings = FALSE)',
    write_lines,
    gsea_write_lines,
    "",
    sprintf('cat("Wrote %d result files to debrowser_results/\\n")', n_files),
    ""
  )

  session_block <- c(
    "# 7. Session info (run-time) ---------------------------------------------------",
    "sessionInfo()"
  )

  c(header, load_block, filter_block, batch_block, de_block,
    enrichment_block, results_block, session_block)
}
