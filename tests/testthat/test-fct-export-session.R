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
      n_features = 32451L, n_samples = 12L
    ),
    filter = list(
      method = "Max", cutoff = 10, min_samples = NA_integer_,
      n_features_in = 32451L, n_features_out = 28104L
    ),
    batch = list(
      method = "none", batch_column = NA_character_, treatment_column = NA_character_
    ),
    comparisons = list(
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
  s$comparisons <- c(s$comparisons, list(
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
  ))
  s$enrichment <- list(
    source = "msigdb", manual_file = NA_character_,
    msigdb = list(species = "Homo sapiens", collection = "H", subcollection = NA_character_),
    n_pathways = 50L
  )
  s
}

test_that("build_session_blocks returns the canonical block list", {
  blocks <- build_session_blocks(.fixture_state_demo_minimal())
  expect_named(blocks, c("meta", "load", "filter", "batch", "de", "enrichment"))
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
