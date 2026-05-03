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
      treatment_label = "treated", control_label = "control",
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

test_that("methods_sentences returns a sentence per pipeline step", {
  s <- methods_sentences(.fixture_blocks_minimal())
  expect_named(s, c("load", "filter", "batch", "de", "enrichment"))
  expect_match(s["load"], "demo")
  expect_match(s["filter"], "Max")
  expect_equal(unname(s["batch"]), NA_character_)  # method=none -> no sentence
  expect_match(s["de"], "DESeq2")
  expect_match(s["de"], "treated")
  expect_match(s["de"], "1247")
  expect_equal(unname(s["enrichment"]), NA_character_)
})

test_that("methods_sentences includes batch sentence when method != none", {
  blocks <- .fixture_blocks_minimal()
  blocks$batch <- list(method = "Combat", batch_column = "batch",
                       treatment_column = "condition")
  s <- methods_sentences(blocks)
  expect_match(s["batch"], "ComBat")
  expect_match(s["batch"], "batch")
  expect_match(s["batch"], "condition")
})

test_that("methods_sentences enumerates multiple comparisons", {
  blocks <- .fixture_blocks_minimal()
  blocks$de <- c(blocks$de, list(blocks$de[[1]]))  # duplicate, fine for prose
  blocks$de[[2]]$treatment_label <- "high_dose"
  blocks$de[[2]]$n_sig_at_padj0.05_lfc1 <- 892L
  s <- methods_sentences(blocks)
  expect_match(s["de"], "treated")
  expect_match(s["de"], "high_dose")
  expect_match(s["de"], "892")
})

test_that("methods_sentences includes enrichment when MSigDB loaded", {
  blocks <- .fixture_blocks_minimal()
  blocks$enrichment <- list(
    source = "msigdb", manual_file = NA_character_,
    msigdb = list(species = "Homo sapiens", collection = "H",
                  subcollection = NA_character_),
    n_pathways = 50L
  )
  s <- methods_sentences(blocks)
  expect_match(s["enrichment"], "fgsea")
  expect_match(s["enrichment"], "Homo sapiens")
  expect_match(s["enrichment"], "50 gene sets")
})
