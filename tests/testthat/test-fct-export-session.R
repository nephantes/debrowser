test_that("sanitize_label replaces unsafe chars with underscore", {
  expect_equal(sanitize_label("treated vs control"), "treated_vs_control")
  expect_equal(sanitize_label("high dose / low dose"), "high_dose___low_dose")
  expect_equal(sanitize_label("Wt+IL6"), "Wt_IL6")
})

test_that("sanitize_label preserves alphanumeric, dot, underscore, dash", {
  expect_equal(sanitize_label("Sample_1.A-2"), "Sample_1.A-2")
  expect_equal(sanitize_label("Cond123"), "Cond123")
})

test_that("sanitize_label handles empty and pure-punctuation input", {
  expect_equal(sanitize_label(""), "")
  expect_equal(sanitize_label("@@@"), "___")
})

# Helper: minimal-but-valid demo state (DESeq2, no batch, no enrichment).
.fixture_state_demo_minimal <- function() {
  list(
    meta = list(
      debrowser_version = "1.31.2",
      r_version         = "R version 4.4.2 (2024-10-31)",
      timestamp         = as.POSIXct("2026-05-03 14:22:11", tz = "UTC"),
      session_info      = c("R version 4.4.2 (2024-10-31)",
                            "Platform: aarch64-apple-darwin20")
    ),
    load = list(
      source = "demo1", counts_path = NA_character_, meta_path = NA_character_,
      n_features = 30739L, n_samples = 6L
    ),
    filter = list(
      method = "Max", cutoff = 10, min_samples = NA_integer_,
      n_features_in = 30739L, n_features_out = 18000L
    ),
    batch = list(
      method = "none", batch_column = NA_character_, treatment_column = NA_character_
    ),
    comparisons = list(
      list(
        treatment_label   = "exper", control_label = "control",
        treatment_samples = c("exper_rep1", "exper_rep2", "exper_rep3"),
        control_samples   = c("control_rep1", "control_rep2", "control_rep3"),
        de_method         = "DESeq2",
        method_params     = list(fitType = "parametric", betaPrior = FALSE,
                                 testType = "Wald", shrinkage = "apeglm"),
        covariates        = character(0),
        n_features_in     = 18000L,
        n_sig_at_padj0.05_lfc1 = 1247L
      )
    ),
    enrichment = NULL
  )
}

# Helper: upload + CPM filter + ComBat + 2 DESeq2 comparisons + MSigDB Hallmark.
.fixture_state_full <- function() {
  s <- .fixture_state_demo_minimal()
  s$load <- list(
    source = "upload",
    counts_path = "my_counts.tsv", meta_path = "my_meta.tsv",
    n_features = 32451L, n_samples = 12L
  )
  s$filter <- list(method = "CPM", cutoff = 1, min_samples = 11L,
                   n_features_in = 32451L, n_features_out = 28104L)
  s$batch <- list(method = "Combat", batch_column = "batch",
                  treatment_column = "condition")
  s$comparisons <- list(
    list(
      treatment_label   = "treated", control_label = "control",
      treatment_samples = c("S1", "S2", "S3"),
      control_samples   = c("S4", "S5", "S6"),
      de_method         = "DESeq2",
      method_params     = list(fitType = "parametric", betaPrior = FALSE,
                               testType = "Wald", shrinkage = "apeglm"),
      covariates        = character(0),
      n_features_in     = 28104L,
      n_sig_at_padj0.05_lfc1 = 1247L
    ),
    list(
      treatment_label   = "high_dose", control_label = "control",
      treatment_samples = c("S7", "S8", "S9"),
      control_samples   = c("S4", "S5", "S6"),
      de_method         = "DESeq2",
      method_params     = list(fitType = "parametric", betaPrior = FALSE,
                               testType = "Wald", shrinkage = "apeglm"),
      covariates        = character(0),
      n_features_in     = 28104L,
      n_sig_at_padj0.05_lfc1 = 892L
    )
  )
  s$enrichment <- list(
    source = "msigdb", manual_file = NA_character_,
    msigdb = list(species = "Homo sapiens", collection = "H", subcollection = NA_character_),
    n_pathways = 50L
  )
  s
}

test_that("build_session_blocks returns the canonical block list", {
  blocks <- build_session_blocks(.fixture_state_demo_minimal())
  expect_named(blocks, c("meta", "load", "filter", "batch", "de", "enrichment",
                         "full_counts", "metadata"))
  expect_length(blocks$de, 1L)
  expect_null(blocks$enrichment)
})

test_that("build_session_blocks expands one DE block per comparison", {
  blocks <- build_session_blocks(.fixture_state_full())
  expect_length(blocks$de, 2L)
  expect_equal(blocks$de[[1]]$treatment_label, "treated")
  expect_equal(blocks$de[[2]]$treatment_label, "high_dose")
})

test_that("build_session_blocks carries enrichment fields through unchanged", {
  blocks <- build_session_blocks(.fixture_state_full())
  expect_equal(blocks$enrichment$source, "msigdb")
  expect_equal(blocks$enrichment$msigdb$collection, "H")
})

test_that("build_session_blocks copies cond_codes from comparison index", {
  blocks <- build_session_blocks(.fixture_state_full())
  expect_equal(blocks$de[[1]]$cond_codes, c("Cond1", "Cond2"))
  expect_equal(blocks$de[[2]]$cond_codes, c("Cond3", "Cond4"))
})

test_that("build_session_blocks dedupes safe_label on collision", {
  s <- .fixture_state_full()
  # Force a collision: second comparison has the same labels as the first.
  s$comparisons[[2]]$treatment_label <- "treated"
  s$comparisons[[2]]$control_label   <- "control"
  blocks <- build_session_blocks(s)
  expect_equal(blocks$de[[1]]$safe_label, "treated_vs_control")
  expect_equal(blocks$de[[2]]$safe_label, "treated_vs_control_2")
})

test_that("emit_r_script demo+DESeq2 minimal matches snapshot", {
  blocks <- build_session_blocks(.fixture_state_demo_minimal())
  expect_snapshot(cat(emit_r_script(blocks), sep = "\n"))
})

test_that("emit_r_script upload+CPM+Combat+2xDESeq2+MSigDB matches snapshot", {
  blocks <- build_session_blocks(.fixture_state_full())
  expect_snapshot(cat(emit_r_script(blocks), sep = "\n"))
})

test_that("emit_r_script upload variant uses read.table with EDIT THIS PATH", {
  blocks <- build_session_blocks(.fixture_state_full())
  out <- emit_r_script(blocks)
  expect_true(any(grepl('read\\.table\\("YOUR_COUNTS', out)))
  expect_true(any(grepl("EDIT THIS PATH", out, ignore.case = TRUE)))
})

test_that("emit_r_script demo variant uses system.file()", {
  blocks <- build_session_blocks(.fixture_state_demo_minimal())
  out <- emit_r_script(blocks)
  expect_true(any(grepl("system\\.file.*demodata\\.Rda", out)))
})

test_that("emit_r_script writes per-comparison TSVs with sanitized labels", {
  blocks <- build_session_blocks(.fixture_state_full())
  out <- emit_r_script(blocks)
  expect_true(any(grepl("results_treated_vs_control\\.tsv", out)))
  expect_true(any(grepl("results_high_dose_vs_control\\.tsv", out)))
})

test_that("emit_r_script omits batch and enrichment blocks when not configured", {
  blocks <- build_session_blocks(.fixture_state_demo_minimal())
  out_str <- paste(emit_r_script(blocks), collapse = "\n")
  expect_false(grepl("apply_batch_correction", out_str))
  expect_false(grepl("run_gsea", out_str))
})

test_that("emitted .R script sources cleanly and produces de1 against demo data", {
  testthat::skip_on_cran()
  testthat::skip_if_not_installed("DESeq2")

  blocks <- build_session_blocks(.fixture_state_demo_minimal())
  script <- emit_r_script(blocks)

  tmpdir  <- tempfile("debrowser_export_roundtrip_")
  dir.create(tmpdir)
  on.exit(unlink(tmpdir, recursive = TRUE), add = TRUE)
  rfile <- file.path(tmpdir, "session.R")
  writeLines(script, rfile)

  # Run in a fresh environment with cwd set to tmpdir so that
  # debrowser_results/ lands inside the cleanup-on-exit scope.
  old_wd <- setwd(tmpdir); on.exit(setwd(old_wd), add = TRUE)
  env <- new.env(parent = globalenv())
  source(rfile, local = env, echo = FALSE)

  expect_true(exists("de1", envir = env))
  expect_true(
    is.data.frame(env$de1) ||
    methods::is(env$de1, "DESeqResults") ||
    methods::is(env$de1, "DataFrame")
  )
  expect_gt(nrow(env$de1), 100L)

  expect_true(file.exists(
    file.path(tmpdir, "debrowser_results", "results_exper_vs_control.tsv")
  ))
})

test_that("emit_rmd minimal demo matches snapshot", {
  blocks <- build_session_blocks(.fixture_state_demo_minimal())
  expect_snapshot(cat(emit_rmd(blocks), sep = "\n"))
})

test_that("emit_rmd full session matches snapshot", {
  blocks <- build_session_blocks(.fixture_state_full())
  expect_snapshot(cat(emit_rmd(blocks), sep = "\n"))
})

test_that("emit_rmd default chunk options set eval=TRUE (E3.B)", {
  # Phase E3.B reversed the eval default: chunks now run on render so the
  # report includes actual plots from the demo path. For upload sessions
  # the user must supply files; load chunks have EDIT THIS PATH comments.
  blocks <- build_session_blocks(.fixture_state_demo_minimal())
  out <- emit_rmd(blocks)
  expect_true(any(grepl("knitr::opts_chunk\\$set\\(eval = TRUE", out)))
})

test_that("emit_rmd YAML enables code_folding: hide", {
  blocks <- build_session_blocks(.fixture_state_demo_minimal())
  out_str <- paste(emit_rmd(blocks), collapse = "\n")
  expect_match(out_str, "code_folding: hide")
})

test_that("emit_rmd sources report_helpers.R from inst/templates", {
  blocks <- build_session_blocks(.fixture_state_demo_minimal())
  out_str <- paste(emit_rmd(blocks), collapse = "\n")
  expect_match(out_str,
    'system\\.file\\("templates", "report_helpers\\.R", package = "debrowser"\\)')
})

test_that("emit_rmd has Sample Info section with DT::datatable", {
  blocks <- build_session_blocks(.fixture_state_demo_minimal())
  out_str <- paste(emit_rmd(blocks), collapse = "\n")
  expect_match(out_str, "## Sample Info")
  expect_match(out_str, "DT::datatable\\(samples_df")
})

test_that("emit_rmd has Quality Control tabset with count_dist / all2all / pca", {
  blocks <- build_session_blocks(.fixture_state_demo_minimal())
  out_str <- paste(emit_rmd(blocks), collapse = "\n")
  expect_match(out_str, "## Quality Control \\{\\.tabset")
  expect_match(out_str, "### Count distribution")
  expect_match(out_str, "### Reproducibility \\(All2All\\)")
  expect_match(out_str, "### PCA \\+ Scree")
  expect_match(out_str, "count_distribution\\(corrected, samples_df")
  expect_match(out_str, "all2all\\(corrected")
  expect_match(out_str, "run_pca\\(corrected")
})

test_that("emit_rmd has DESeq Analysis tabset with per-comparison sub-tabs", {
  blocks <- build_session_blocks(.fixture_state_full())
  out_str <- paste(emit_rmd(blocks), collapse = "\n")
  expect_match(out_str, "## DESeq Analysis \\{\\.tabset")
  expect_match(out_str, "### treated vs control \\{\\.tabset\\}")
  expect_match(out_str, "### high_dose vs control \\{\\.tabset\\}")
  expect_match(out_str, "#### Results")
  expect_match(out_str, "#### Volcano")
  expect_match(out_str, "#### MA")
  expect_match(out_str, "#### Heatmap")
})

test_that("emit_rmd Session Info is a tabset with Hide/Show", {
  blocks <- build_session_blocks(.fixture_state_demo_minimal())
  out_str <- paste(emit_rmd(blocks), collapse = "\n")
  expect_match(out_str, "## Session Info \\{\\.tabset")
  expect_match(out_str, "\\{r sessioninfo, echo = FALSE\\}")
})

test_that("emit_rmd embeds methods_paragraph as Methods prose with citations", {
  blocks <- build_session_blocks(.fixture_state_full())
  out_str <- paste(emit_rmd(blocks), collapse = "\n")
  # E9: paragraph-form prose with inline citations; assertions match the
  # new methods_sentences/methods_paragraph output rather than the E3-lite
  # bullet wording.
  expect_match(out_str, "loaded from a user-uploaded TSV")
  expect_match(out_str, "`treated`")
  expect_match(out_str, "`high_dose`")
  expect_match(out_str, "Love et al")
  expect_match(out_str, "MSigDB Homo sapiens H")
  expect_match(out_str, "Liberzon et al")
})

# ---------------------------------------------------------------------------
# emit_ipynb (Phase E3.B)
# ---------------------------------------------------------------------------

test_that("emit_ipynb returns chr(1) of valid JSON", {
  blocks <- build_session_blocks(.fixture_state_demo_minimal())
  out <- emit_ipynb(blocks)
  expect_type(out, "character")
  expect_length(out, 1L)
  expect_no_error(jsonlite::fromJSON(out, simplifyVector = FALSE))
})

test_that("emit_ipynb declares the R kernelspec (ir)", {
  blocks <- build_session_blocks(.fixture_state_demo_minimal())
  parsed <- jsonlite::fromJSON(emit_ipynb(blocks), simplifyVector = FALSE)
  expect_equal(parsed$metadata$kernelspec$name, "ir")
  expect_equal(parsed$metadata$kernelspec$language, "R")
  expect_equal(parsed$nbformat, 4L)
  expect_equal(parsed$nbformat_minor, 5L)
})

test_that("emit_ipynb cell stream alternates markdown and code cells", {
  blocks <- build_session_blocks(.fixture_state_demo_minimal())
  parsed <- jsonlite::fromJSON(emit_ipynb(blocks), simplifyVector = FALSE)
  cells <- parsed$cells
  cell_types <- vapply(cells, function(c) c$cell_type, character(1))
  expect_true(all(cell_types %in% c("markdown", "code")))
  # The stream should have at least one of each.
  expect_true(any(cell_types == "markdown"))
  expect_true(any(cell_types == "code"))
})

test_that("emit_ipynb code cells have empty outputs and null execution_count", {
  blocks <- build_session_blocks(.fixture_state_demo_minimal())
  parsed <- jsonlite::fromJSON(emit_ipynb(blocks), simplifyVector = FALSE)
  code_cells <- Filter(function(c) c$cell_type == "code", parsed$cells)
  expect_true(length(code_cells) > 0L)
  for (cell in code_cells) {
    expect_length(cell$outputs, 0L)
    # `null` JSON deserializes to NULL in fromJSON
    expect_true(is.null(cell$execution_count) ||
                is.na(cell$execution_count))
  }
})

test_that("emit_ipynb markdown cells include Methods + Sample Info + QC headings", {
  blocks <- build_session_blocks(.fixture_state_full())
  parsed <- jsonlite::fromJSON(emit_ipynb(blocks), simplifyVector = FALSE)
  md_cells <- Filter(function(c) c$cell_type == "markdown", parsed$cells)
  joined <- paste(unlist(lapply(md_cells, function(c) {
    paste(unlist(c$source), collapse = "")
  })), collapse = "\n")
  expect_match(joined, "## Methods")
  expect_match(joined, "## Sample Info")
  expect_match(joined, "## Quality Control")
  expect_match(joined, "## DESeq Analysis")
  expect_match(joined, "## Session Info")
})

test_that("emit_ipynb code cells include the helper-source line", {
  blocks <- build_session_blocks(.fixture_state_demo_minimal())
  parsed <- jsonlite::fromJSON(emit_ipynb(blocks), simplifyVector = FALSE)
  code_cells <- Filter(function(c) c$cell_type == "code", parsed$cells)
  joined <- paste(unlist(lapply(code_cells, function(c) {
    paste(unlist(c$source), collapse = "")
  })), collapse = "\n")
  expect_match(joined, "report_helpers\\.R")
  expect_match(joined, "library\\(debrowser\\)")
})

test_that("emit_ipynb strips YAML front matter (no --- in cells)", {
  blocks <- build_session_blocks(.fixture_state_demo_minimal())
  parsed <- jsonlite::fromJSON(emit_ipynb(blocks), simplifyVector = FALSE)
  joined <- paste(unlist(lapply(parsed$cells, function(c) {
    paste(unlist(c$source), collapse = "")
  })), collapse = "\n")
  # The YAML title/output block should not appear in any cell source.
  expect_false(grepl('title: "DEBrowser session report"', joined, fixed = TRUE))
  expect_false(grepl("code_folding: hide", joined, fixed = TRUE))
})
