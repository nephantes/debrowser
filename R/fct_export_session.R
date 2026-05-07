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
    enrichment = state$enrichment,
    # E3.B: full filtered+batch-corrected matrix and sample metadata,
    # consumed by the rich-report sections (Sample Info / QC / PCA /
    # All2All). Both may be NULL when state_react does not capture them
    # (e.g. when a future caller passes an older-shape state).
    full_counts = state$full_counts,
    metadata    = state$metadata
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
  # Phase E9: assemble methods paragraph and word-wrap it as a comment block
  # so the .R script header reads as prose. The strwrap() call gives us
  # 76-char prose lines that fit inside the conventional 80-column window
  # once the leading "# " prefix is added.
  paragraph <- methods_paragraph(blocks)
  wrapped   <- strwrap(paragraph, width = 76)
  m_lines   <- paste0("# ", wrapped)

  header <- c(
    "# DEBrowser session export",
    sprintf("# Generated %s by debrowser %s",
            format(blocks$meta$timestamp, "%Y-%m-%d %H:%M:%S"),
            blocks$meta$debrowser_version),
    sprintf("# %s", blocks$meta$r_version),
    "#",
    "# Methods (auto-generated, refine before publication):",
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

#' Emit the .Rmd reproducibility report as a character vector.
#'
#' Phase E3.B rewrite: rich, manuscript-style report mirroring the
#' reference Rmd structure. Sections (in order):
#'   * YAML header (code_folding: hide, toc_float, theme: cosmo)
#'   * load_libraries + load_helpers (sourced from
#'     inst/templates/report_helpers.R)
#'   * ## Methods (paragraph from methods_paragraph())
#'   * ## Pipeline (Load -> Filter -> Batch -> Differential expression)
#'   * ## Sample Info (DT::datatable of metadata)
#'   * ## Quality Control {.tabset} -- Count Distribution / All2All / PCA
#'   * ## DESeq Analysis {.tabset} -- one tab per comparison with sub-tabs
#'     Results / Volcano / MA / Heatmap
#'   * ## Enrichment (GSEA) when configured
#'   * ## Session Info {.tabset}
#'
#' Pipeline chunks emit `eval = TRUE` so a server-side render produces
#' a complete report; for upload sessions the user must re-supply the
#' counts/metadata files (the script has `# EDIT THIS PATH` comments).
#'
#' @param blocks Output of [build_session_blocks()].
#' @return character vector.
#' @keywords internal
#' @noRd
emit_rmd <- function(blocks) {
  prose <- methods_paragraph(blocks)

  header <- c(
    "---",
    'title: "DEBrowser session report"',
    sprintf('date: "%s"', format(blocks$meta$timestamp, "%Y-%m-%d %H:%M:%S")),
    "output:",
    "  html_document:",
    "    code_folding: hide",
    "    toc: true",
    "    toc_float: true",
    "    theme: cosmo",
    "---",
    "",
    "```{r setup, include = FALSE}",
    "knitr::opts_chunk$set(eval = TRUE, echo = TRUE,",
    "                      warning = FALSE, message = FALSE)",
    "```",
    "",
    "```{r load_libraries, include = FALSE}",
    "suppressMessages({",
    "  library(dplyr)",
    "  library(ggplot2)",
    "  library(tidyr)",
    "  library(tibble)",
    "  library(rlang)",
    "  library(scales)",
    "  library(ggrepel)",
    "  library(DESeq2)",
    "  library(edgeR)",
    "  library(sva)",
    "  library(gplots)",
    "  library(DT)",
    "  library(htmltools)",
    "  library(debrowser)",
    "})",
    "```",
    "",
    "```{r load_helpers, include = FALSE}",
    paste0("source(system.file(\"templates\", \"report_helpers.R\", ",
           "package = \"debrowser\"))"),
    "```",
    "",
    "## Methods",
    "",
    sprintf("This report was generated by **DEBrowser %s** under %s.",
            blocks$meta$debrowser_version, blocks$meta$r_version),
    "",
    prose,
    "",
    "> *This narrative is auto-generated. Edit before publication; cite",
    "> DEBrowser (Kucukural et al., 2019) and the underlying tools",
    "> (DESeq2 -- Love et al., 2014; fgsea -- Korotkevich et al., 2021;",
    "> MSigDB -- Liberzon et al., 2015).*",
    "",
    "## Pipeline",
    ""
  )

  load_chunk <- if (identical(blocks$load$source, "upload")) {
    counts_name <- blocks$load$counts_path %||% "YOUR_COUNTS.tsv"
    meta_name   <- blocks$load$meta_path   %||% "YOUR_META.tsv"
    c(
      "### 1. Load counts and metadata", "",
      sprintf("Original upload: counts=`%s`, meta=`%s`. Edit the paths below.",
              counts_name, meta_name),
      "",
      "```{r load}",
      'counts <- read.table("YOUR_COUNTS.tsv", sep = "\\t", header = TRUE,',
      "                     row.names = 1, check.names = FALSE)",
      'meta   <- read.table("YOUR_META.tsv",   sep = "\\t", header = TRUE,',
      "                     row.names = 1, check.names = FALSE)",
      "```", ""
    )
  } else {
    fixture <- if (identical(blocks$load$source, "demo2")) "demodata2.Rda" else "demodata.Rda"
    c(
      "### 1. Load counts and metadata", "",
      "```{r load}",
      "demo_env <- new.env()",
      sprintf('load(system.file("extdata", "demo", "%s", package = "debrowser"), envir = demo_env)',
              fixture),
      "counts <- demo_env$demodata",
      "meta   <- demo_env$metadatatable",
      "```", ""
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
  filter_chunk <- c(
    "### 2. Low-count filter", "",
    "```{r filter}", filter_call, "```", ""
  )

  batch_chunk <- if (identical(blocks$batch$method, "none")) {
    c(
      "### 3. Batch correction", "",
      "*No batch correction was applied.*",
      "",
      "```{r batch_passthrough}",
      "corrected <- filtered",
      "```",
      "",
      "```{r coerce_counts, include = FALSE}",
      "# Defensive: downstream DESeq2 / edgeR / PCA helpers expect an",
      "# integer count matrix. The demo/upload paths deliver data.frames,",
      "# so coerce once here so every QC / DE Analysis section sees the",
      "# same clean matrix shape.",
      "if (!is.matrix(corrected)) corrected <- as.matrix(corrected)",
      "storage.mode(corrected) <- 'integer'",
      "```", ""
    )
  } else {
    treat_arg <- if (is.na(blocks$batch$treatment_column %||% NA_character_)) {
      "NULL"
    } else {
      sprintf('"%s"', blocks$batch$treatment_column)
    }
    c(
      "### 3. Batch correction", "",
      "```{r batch}",
      "corrected <- apply_batch_correction(",
      "  filtered, meta,",
      sprintf('  method = "%s", batch_col = "%s", treatment_col = %s',
              blocks$batch$method, blocks$batch$batch_column, treat_arg),
      ")", "```",
      "",
      "```{r coerce_counts, include = FALSE}",
      "if (!is.matrix(corrected)) corrected <- as.matrix(corrected)",
      "storage.mode(corrected) <- 'integer'",
      "```", ""
    )
  }

  de_chunks <- unlist(lapply(seq_along(blocks$de), function(i) {
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
      sprintf("#### Comparison %d: %s vs %s", i, d$treatment_label, d$control_label),
      "",
      sprintf("```{r de%d}", i),
      sprintf("cols_%d  <- c(%s)", i, cols_str),
      sprintf("conds_%d <- c(%s)", i, conds_str),
      sprintf("de%d <- run_de(", i),
      sprintf('  method = "%s",', d$de_method),
      sprintf("  counts = corrected, metadata = meta, columns = cols_%d, conds = conds_%d,",
              i, i),
      sprintf("  params = list(%s),", params_str),
      "  return_dds = FALSE",
      ")",
      sprintf("# Stash for downstream sections (Results / Volcano / MA / Heatmap)"),
      sprintf("post_res_%d <- post_processing(", i),
      sprintf("  as.data.frame(de%d) %%>%% tibble::rownames_to_column('feature'),", i),
      "  padj_significance_cutoff = 0.05,",
      "  fc_significance_cutoff   = 1,",
      "  num_labeled = Inf,",
      "  highlighted = character(0),",
      "  add_alias = FALSE,",
      "  apply_shrinkage = FALSE",
      ")",
      "```", ""
    )
  }))
  de_pipeline_chunk <- c("### 4. Differential expression", "", de_chunks)

  # ---- Sample Info section ----
  sample_info_chunk <- c(
    "## Sample Info", "",
    "```{r sample_info}",
    "# Normalize first column to 'sample_name' so the report helpers (which",
    "# expect that column) can join consistently across demo/upload paths.",
    "samples_df <- meta",
    "if (!is.null(samples_df) && ncol(samples_df) > 0L &&",
    "    !'sample_name' %in% colnames(samples_df)) {",
    "  colnames(samples_df)[1] <- 'sample_name'",
    "}",
    "DT::datatable(samples_df, rownames = FALSE,",
    "              options = list(pageLength = 10, dom = 'tip'))",
    "```", ""
  )

  # ---- Quality Control tabset (count dist / all2all / PCA) ----
  qc_chunk <- c(
    "## Quality Control {.tabset .tabset-pills}", "",
    "```{r qc_setup, include = FALSE}",
    "# Choose grouping column for QC plots: prefer 'treatment', then",
    "# 'condition', then 'group'; else fall back to first non-name column.",
    ".find_group_col <- function(meta) {",
    "  cols <- colnames(meta)",
    "  for (c in c('treatment', 'condition', 'group')) {",
    "    if (c %in% cols) return(c)",
    "  }",
    "  non_sample <- setdiff(cols, 'sample_name')",
    "  if (length(non_sample) > 0L) return(non_sample[1L]) else cols[1L]",
    "}",
    "grp_col <- .find_group_col(samples_df)",
    "```",
    "",
    "### Count distribution",
    "",
    "Histogram of average counts per feature, faceted by group.",
    "The dashed vertical line is the low-count filter cutoff.",
    "",
    "```{r count_dist}",
    sprintf(paste0("count_distribution(corrected, samples_df, ",
                   "min_counts_per_event = %s, group_by = grp_col)"),
            blocks$filter$cutoff),
    "```",
    "",
    "### Reproducibility (All2All)",
    "",
    "Pairwise sample-sample comparison on all detected genes",
    "(post-filter, post-batch matrix). Skipped when there are more",
    "than 10 samples.",
    "",
    "```{r all2all, fig.width = 8, fig.height = 8}",
    "if (ncol(corrected) <= 10) {",
    "  all2all(corrected, cex = 1)",
    "} else {",
    "  cat('More than 10 samples; skipping (use a sample subset to plot all2all).')",
    "}",
    "```",
    "",
    "### PCA + Scree",
    "",
    "PCA on all detected genes (post-filter, post-batch matrix), with",
    "scree plot of variance explained per principal component.",
    "",
    "```{r pca}",
    "pca <- run_pca(corrected, transformation = 'Default')",
    "print(pca_plot(pca, samples_df, color_by = grp_col))",
    "print(scree_plot(pca))",
    "```",
    ""
  )

  # ---- DESeq Analysis tabset (per-comparison) ----
  # D2.5 fix Issue 5: previously hard-coded `dplyr::select(... baseMean,
  # lfcSE ...)` failed for EdgeR/Limma which lacked those columns
  # ("Can't select columns that don't exist. x Column `baseMean`
  # doesn't exist."). Two-pronged fix:
  #   (1) run_edger / run_limma now produce a `baseMean` column (from
  #       2^logCPM and 2^AveExpr respectively) -- see R/fct_de_methods.R.
  #   (2) emit `dplyr::any_of()` so any column missing from a future
  #       DE method is silently dropped instead of erroring. lfcSE
  #       remains DESeq2-only so it's left in the union list and
  #       any_of() handles its absence.
  de_results_chunks <- unlist(lapply(seq_along(blocks$de), function(i) {
    d <- blocks$de[[i]]
    tab_label <- sprintf("%s vs %s", d$treatment_label, d$control_label)
    c(
      sprintf("### %s {.tabset}", tab_label), "",
      "#### Results", "",
      sprintf("```{r results_%d}", i),
      sprintf("DT::datatable(post_res_%d %%>%%", i),
      "  dplyr::select(dplyr::any_of(c('feature', 'baseMean',",
      "                                 'log2FoldChange', 'lfcSE',",
      "                                 'pvalue', 'padj', 'Direction'))) %>%",
      "  dplyr::arrange(padj),",
      "  rownames = FALSE,",
      "  extensions = 'Buttons',",
      sprintf(paste0("  options = list(pageLength = 10, dom = 'lftBipr',\n",
                     "                 buttons = list(list(extend = 'csvHtml5',\n",
                     "                                     filename = '%s_results',\n",
                     "                                     extension = '.tsv',\n",
                     "                                     fieldBoundary = '',\n",
                     "                                     fieldSeparator = '\\t')))) %%>%%"),
              d$safe_label),
      sprintf(paste0("  DT::formatRound(intersect(c('baseMean', 'log2FoldChange', 'lfcSE'),\n",
                     "                            colnames(post_res_%d)), digits = 4) %%>%%"),
              i),
      "  DT::formatSignif(c('pvalue', 'padj'), digits = 4) %>%",
      "  DT::formatStyle('Direction', target = 'row',",
      "    color = DT::styleEqual(c('No Change', 'Upregulated', 'Downregulated'),",
      "                            c('black', 'firebrick', 'steelblue')))",
      "```",
      "",
      "#### Volcano", "",
      sprintf("```{r volcano_%d}", i),
      sprintf("volcano_plot(post_res_%d, padj_cutoff = 0.05, fc_cutoff = 1)", i),
      "```",
      "",
      "#### MA", "",
      sprintf("```{r ma_%d}", i),
      sprintf("ma_plot(post_res_%d, padj_cutoff = 0.05, fc_cutoff = 1)", i),
      "```",
      "",
      "#### Heatmap", "",
      sprintf("```{r heatmap_%d}", i),
      sprintf("sig_features_%d <- (post_res_%d %%>%% dplyr::filter(Significant == 'Significant'))$feature",
              i, i),
      sprintf("sig_subset_%d <- corrected[rownames(corrected) %%in%% sig_features_%d, , drop = FALSE]",
              i, i),
      sprintf("if (nrow(sig_subset_%d) > 0) {", i),
      sprintf("  heatmap_plot(sig_subset_%d)", i),
      "} else {",
      "  cat('No significant features at padj < 0.05, |log2FC| > 1.')",
      "}",
      "```",
      ""
    )
  }))
  de_analysis_chunk <- c("## DESeq Analysis {.tabset .tabset-pills}", "",
                         de_results_chunks)

  enrichment_chunk <- if (is.null(blocks$enrichment)) character(0) else {
    setup <- if (identical(blocks$enrichment$source, "msigdb")) {
      sub <- blocks$enrichment$msigdb$subcollection
      sub_arg <- if (is.na(sub) || !nzchar(sub)) "NULL" else sprintf('"%s"', sub)
      sprintf('pathways <- msigdb_pathways(species = "%s", collection = "%s", subcollection = %s)',
              blocks$enrichment$msigdb$species,
              blocks$enrichment$msigdb$collection, sub_arg)
    } else {
      gmt_name <- blocks$enrichment$manual_file %||% "YOUR_GMT.gmt"
      sprintf('pathways <- gmt_to_pathways("%s")  # EDIT THIS PATH', gmt_name)
    }
    runs <- unlist(lapply(seq_along(blocks$de), function(i) {
      sprintf("gsea_%d <- run_gsea(de%d, pathways = pathways)", i, i)
    }))
    c(
      "## Enrichment (GSEA)", "",
      "```{r enrichment}", setup, runs, "```", ""
    )
  }

  session_chunk <- c(
    "## Session Info {.tabset .tabset-pills}", "",
    "### Hide", "",
    "### Show", "",
    "```{r sessioninfo, echo = FALSE}",
    "sessionInfo()",
    "```"
  )

  c(header,
    load_chunk, filter_chunk, batch_chunk, de_pipeline_chunk,
    sample_info_chunk, qc_chunk, de_analysis_chunk,
    enrichment_chunk, session_chunk)
}

#' Emit the .ipynb (Jupyter notebook) reproducibility report as chr(1).
#'
#' Parses the [emit_rmd()] output line-stream into Jupyter cells: each
#' fenced code chunk (```` ```{r ...} ... ``` ````) becomes one R-kernel
#' code cell; everything between code chunks (the YAML header is skipped,
#' prose / headings are kept) becomes markdown cells. Outputs are empty
#' (`outputs: []`, `execution_count: null`) so the user can run cells in
#' JupyterLab as a fresh interactive notebook.
#'
#' Kernelspec is fixed to `ir` (the IRkernel R kernel name).
#'
#' @param blocks Output of [build_session_blocks()].
#' @return character(1). The serialized .ipynb JSON.
#' @keywords internal
#' @noRd
emit_ipynb <- function(blocks) {
  rmd <- emit_rmd(blocks)

  # Strip the YAML front matter (between the first two `---` lines).
  if (length(rmd) >= 2L && identical(rmd[1L], "---")) {
    closer <- which(rmd == "---")[2L]
    if (!is.na(closer)) rmd <- rmd[(closer + 1L):length(rmd)]
  }

  # Walk the line stream, switching between markdown and code-chunk
  # accumulators. Code chunks are recognized by the opening ``` {r ...}
  # line and closed by the next bare ``` line (no nesting in our emit).
  cells <- list()
  buf   <- character(0)
  in_code <- FALSE

  flush_markdown <- function() {
    if (length(buf) == 0L) return(invisible())
    # Drop trailing blank lines so cells render cleanly.
    while (length(buf) > 0L && nzchar(trimws(buf[length(buf)])) == 0L) {
      buf <<- buf[-length(buf)]
    }
    if (length(buf) == 0L) return(invisible())
    cells[[length(cells) + 1L]] <<- list(
      cell_type = "markdown",
      metadata  = setNames(list(), character(0)),
      source    = .ipynb_source(buf)
    )
    buf <<- character(0)
  }

  flush_code <- function() {
    cells[[length(cells) + 1L]] <<- list(
      cell_type       = "code",
      metadata        = setNames(list(), character(0)),
      execution_count = NA,
      outputs         = list(),
      source          = .ipynb_source(buf)
    )
    buf <<- character(0)
  }

  for (line in rmd) {
    if (!in_code) {
      if (grepl("^```\\{r[^}]*\\}", line)) {
        flush_markdown()
        in_code <- TRUE
        # Drop the opening fence; the cell only carries chunk body lines.
      } else {
        buf <- c(buf, line)
      }
    } else {
      if (grepl("^```\\s*$", line)) {
        flush_code()
        in_code <- FALSE
      } else {
        buf <- c(buf, line)
      }
    }
  }
  if (in_code) {
    # Defensive: malformed emit; treat the trailing code as a code cell.
    flush_code()
  } else {
    flush_markdown()
  }

  notebook <- list(
    cells          = cells,
    metadata       = list(
      kernelspec   = list(name = "ir",
                          display_name = "R",
                          language = "R"),
      language_info = list(name = "R",
                           file_extension = ".r",
                           mimetype = "text/x-r-source",
                           pygments_lexer = "r",
                           codemirror_mode = "r")
    ),
    nbformat       = 4L,
    nbformat_minor = 5L
  )

  jsonlite::toJSON(notebook, auto_unbox = TRUE, pretty = 2,
                   null = "null", na = "null")
}

# Internal: convert a chr vector of lines into Jupyter's `source` array
# (each element ends with "\n" except the last, which is unterminated).
#' @noRd
.ipynb_source <- function(lines) {
  if (length(lines) == 0L) return(list())
  n <- length(lines)
  out <- vector("list", n)
  for (i in seq_len(n)) {
    out[[i]] <- if (i < n) paste0(lines[i], "\n") else lines[i]
  }
  out
}
