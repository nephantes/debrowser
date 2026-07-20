.fixture_blocks_minimal <- function() {
  build_session_blocks(list(
    meta = list(debrowser_version = "1.31.2", r_version = "R 4.4.2",
                timestamp = Sys.time(), session_info = character()),
    load = list(source = "demo1", counts_path = NA_character_,
                meta_path = NA_character_, n_features = 32451L, n_samples = 12L),
    filter = list(method = "Max", cutoff = 10, min_samples = NA_integer_,
                  n_features_in = 32451L, n_features_out = 28104L),
    batch = list(method = "none", batch_column = NA_character_,
                 treatment_column = NA_character_),
    comparisons = list(list(
      treatment_label = "exper", control_label = "control",
      treatment_samples = c("S1"), control_samples = c("S4"),
      de_method = "DESeq2",
      method_params = list(fitType = "parametric", betaPrior = FALSE,
                           testType = "Wald", shrinkage = "apeglm"),
      covariates = character(0),
      n_features_in = 28104L, n_sig_at_padj0.05_lfc1 = 1247L
    )),
    enrichment = NULL
  ))
}

test_that("methods_sentences returns a sentence per pipeline step with DEBrowser intro citation", {
  s <- methods_sentences(.fixture_blocks_minimal())
  expect_named(s, c("load", "filter", "batch", "de", "enrichment"))
  expect_match(s["load"], "Differential expression analysis was performed using DEBrowser v")
  expect_match(s["load"], "Kucukural et al")
  expect_match(s["load"], "demo dataset")
  expect_match(s["filter"], "Max")
  expect_equal(unname(s["batch"]), NA_character_)  # method=none -> no sentence
  expect_match(s["de"], "DESeq2 v")
  expect_match(s["de"], "Love et al")
  expect_match(s["de"], "exper")  # treatment label from fixture
  expect_match(s["de"], "1247|1,247")  # n_sig (with or without comma formatting)
  expect_equal(unname(s["enrichment"]), NA_character_)
})

test_that("methods_sentences includes batch sentence with citation when method != none", {
  blocks <- .fixture_blocks_minimal()
  blocks$batch <- list(method = "Combat", batch_column = "batch",
                       treatment_column = "condition")
  s <- methods_sentences(blocks)
  expect_match(s["batch"], "ComBat")
  expect_match(s["batch"], "Johnson et al")
  expect_match(s["batch"], "batch")
  expect_match(s["batch"], "condition")
})

test_that("methods_sentences enumerates multiple comparisons each with citation", {
  blocks <- .fixture_blocks_minimal()
  blocks$de <- c(blocks$de, list(blocks$de[[1]]))  # duplicate, fine for prose
  blocks$de[[2]]$treatment_label <- "high_dose"
  blocks$de[[2]]$n_sig_at_padj0.05_lfc1 <- 892L
  s <- methods_sentences(blocks)
  expect_match(s["de"], "exper")
  expect_match(s["de"], "high_dose")
  expect_match(s["de"], "892")
  # Per-comparison citations: "Love et al" should appear at least twice
  matches <- gregexpr("Love et al", s["de"], fixed = TRUE)[[1]]
  expect_true(length(matches) >= 2L)
})

test_that("methods_sentences includes enrichment with fgsea + MSigDB citations when MSigDB loaded", {
  blocks <- .fixture_blocks_minimal()
  blocks$enrichment <- list(
    source = "msigdb", manual_file = NA_character_,
    msigdb = list(species = "Homo sapiens", collection = "H",
                  subcollection = NA_character_),
    n_pathways = 50L
  )
  s <- methods_sentences(blocks)
  expect_match(s["enrichment"], "fgsea v")
  expect_match(s["enrichment"], "Korotkevich et al")
  expect_match(s["enrichment"], "MSigDB Homo sapiens H")
  expect_match(s["enrichment"], "Liberzon et al")
  expect_match(s["enrichment"], "50 gene sets")
})

# --- Phase E9 tests -----------------------------------------------------------

test_that(".method_refs covers every UI-producible method value", {
  # All de_method values from R/mod_condselect.R
  expect_true(!is.null(.method_refs$deseq2))
  expect_true(!is.null(.method_refs$edger))
  expect_true(!is.null(.method_refs$limma))
  # All batch methods from R/batcheffect.R::batchEffectUI choices
  expect_true(!is.null(.method_refs$combat))
  expect_true(!is.null(.method_refs$combat_seq))
  expect_true(!is.null(.method_refs$harman))
  # Enrichment + base
  expect_true(!is.null(.method_refs$debrowser))
  expect_true(!is.null(.method_refs$fgsea))
  expect_true(!is.null(.method_refs$msigdb))
})

test_that(".method_refs entries have name, version_pkg, cite fields", {
  for (key in names(.method_refs)) {
    entry <- .method_refs[[key]]
    expect_true(!is.null(entry$name),        info = key)
    expect_true(!is.null(entry$version_pkg), info = key)
    expect_true(!is.null(entry$cite),        info = key)
    expect_true(grepl("et al\\.,", entry$cite), info = key)
  }
})

test_that(".pkg_version_or_unknown returns a version string for installed pkg", {
  # 'utils' is base R; always installed
  v <- .pkg_version_or_unknown("utils")
  expect_match(v, "^[0-9]+\\.[0-9]+")
})

test_that(".pkg_version_or_unknown returns '(version unknown)' for missing pkg", {
  # Use a name that cannot be a real installed package
  v <- .pkg_version_or_unknown("debrowser_no_such_pkg_xxxxx_e9")
  expect_equal(v, "(version unknown)")
})

# --- Phase E9: methods_paragraph tests ---------------------------------------

test_that("methods_paragraph returns chr(1) starting with the DEBrowser intro", {
  blocks <- .fixture_blocks_minimal()
  out <- methods_paragraph(blocks)
  expect_type(out, "character")
  expect_length(out, 1L)
  expect_gt(nchar(out), 100L)
  expect_match(out, "^Differential expression analysis was performed using DEBrowser v")
})

test_that("methods_paragraph word count is in the spec target band for full session", {
  # Build a "full" blocks fixture with batch + 2 comparisons + MSigDB enrichment.
  blocks <- .fixture_blocks_minimal()
  blocks$batch <- list(method = "Combat", batch_column = "batch",
                       treatment_column = "condition")
  blocks$de <- c(blocks$de, list(blocks$de[[1]]))
  blocks$de[[2]]$treatment_label <- "high_dose"
  blocks$de[[2]]$n_sig_at_padj0.05_lfc1 <- 892L
  blocks$enrichment <- list(
    source = "msigdb", manual_file = NA_character_,
    msigdb = list(species = "Homo sapiens", collection = "H",
                  subcollection = NA_character_),
    n_pathways = 50L
  )
  out <- methods_paragraph(blocks)
  word_count <- length(strsplit(out, "\\s+")[[1]])
  expect_gt(word_count, 150L)
  expect_lt(word_count, 300L)
})

test_that("methods_paragraph minimal session still produces > 50 words", {
  out <- methods_paragraph(.fixture_blocks_minimal())
  word_count <- length(strsplit(out, "\\s+")[[1]])
  expect_gt(word_count, 50L)
})

test_that("methods_paragraph drops NA entries (no 'NA' string in output)", {
  out <- methods_paragraph(.fixture_blocks_minimal())
  # Minimal fixture has no batch and no enrichment; ensure no literal "NA"
  # leaked into the joined paragraph.
  expect_false(grepl("\\bNA\\b", out))
})

test_that("methods_paragraph returns single-paragraph chr(1) (no embedded newlines)", {
  out <- methods_paragraph(.fixture_blocks_minimal())
  expect_false(grepl("\n", out))
})
