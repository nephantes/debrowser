# Phase E12.B.2 - tests for per-shape payload adapters.

test_that(".build_geneset_payload returns NULL when genes empty", {
  out <- .build_geneset_payload(genes = character(0),
                                primary_de = NULL,
                                term = NULL,
                                context_mode = "enrichGO")
  expect_null(out)
})

test_that(".build_geneset_payload builds shape = geneset", {
  de <- data.frame(ID = c("A", "B", "C"),
                   log2FoldChange = c(1, -2, 0.5),
                   padj = c(0.01, 0.04, 0.5))
  out <- .build_geneset_payload(
    genes = c("A", "B"),
    primary_de = de,
    term = list(term = "GO:000001", pvalue = 0.001, n_overlap = 2L),
    context_mode = "enrichGO"
  )
  expect_equal(out$shape, "geneset")
  expect_equal(out$genes, c("A", "B"))
  expect_equal(nrow(out$stats), 2L)
  expect_equal(out$context_mode, "enrichGO")
  expect_equal(out$enrichment$term, "GO:000001")
})

test_that(".build_geneset_payload handles NULL primary_de gracefully", {
  out <- .build_geneset_payload(
    genes = c("A", "B"),
    primary_de = NULL,
    term = NULL,
    context_mode = "enrichKEGG"
  )
  expect_equal(out$genes, c("A", "B"))
  expect_null(out$stats)
  expect_null(out$enrichment)
})

test_that(".build_de_payload returns NULL when filt_data empty", {
  empty <- data.frame(ID = character(0),
                      log2FoldChange = numeric(0),
                      padj = numeric(0))
  out <- .build_de_payload(filt_data = empty,
                           comparison_label = "Treat vs Ctrl",
                           top_n = 50L,
                           cutoffs = list(padj = 0.05, lfc = 0))
  expect_null(out)
})

test_that(".build_de_payload builds shape = de_table and sorts by padj", {
  df <- data.frame(
    ID = c("G1", "G2", "G3", "G4"),
    log2FoldChange = c(0.5, 2, -1.5, 0.1),
    padj = c(0.20, 0.001, 0.01, 0.50)
  )
  out <- .build_de_payload(filt_data = df,
                           comparison_label = "Treat vs Ctrl",
                           top_n = 2L,
                           cutoffs = list(padj = 0.05, lfc = 0))
  expect_equal(out$shape, "de_table")
  expect_equal(out$comparison_label, "Treat vs Ctrl")
  # top_n = 2; sort by padj; expect G2, G3 first.
  expect_equal(out$genes, c("G2", "G3"))
  expect_equal(nrow(out$stats), 2L)
  expect_true(out$n_total_de >= 2L)
})

test_that(".build_de_payload respects top_n cap", {
  df <- data.frame(
    ID = paste0("G", 1:100),
    log2FoldChange = rnorm(100),
    padj = runif(100, 0, 0.01)
  )
  out <- .build_de_payload(filt_data = df,
                           comparison_label = "x",
                           top_n = 10L,
                           cutoffs = list(padj = 0.05, lfc = 0))
  expect_equal(length(out$genes), 10L)
})

test_that(".build_concordance_payload returns NULL when < 2 comparisons", {
  de_list <- list("A vs B" = data.frame(ID = "X",
                                        log2FoldChange = 1,
                                        padj = 0.01))
  out <- .build_concordance_payload(de_results_list = de_list,
                                    concordance_table = data.frame(),
                                    top_n = 20L,
                                    cutoffs = list(padj = 0.05, lfc = 0))
  expect_null(out)
})

test_that(".build_concordance_payload names per_comparison_top by label", {
  de_list <- list(
    "Treat vs Ctrl" = data.frame(ID = c("G1", "G2"),
                                 log2FoldChange = c(1, -2),
                                 padj = c(0.01, 0.04)),
    "Drug vs Veh"   = data.frame(ID = c("G3", "G4"),
                                 log2FoldChange = c(2, -1),
                                 padj = c(0.001, 0.02))
  )
  cs <- data.frame(comparison1 = "Treat vs Ctrl",
                   comparison2 = "Drug vs Veh",
                   jaccard = 0.5, spearman_lfc = 0.7)
  out <- .build_concordance_payload(de_results_list = de_list,
                                    concordance_table = cs,
                                    top_n = 10L,
                                    cutoffs = list(padj = 0.05, lfc = 0))
  expect_equal(out$shape, "concordance")
  expect_equal(out$comparison_labels, c("Treat vs Ctrl", "Drug vs Veh"))
  expect_named(out$per_comparison_top, c("Treat vs Ctrl", "Drug vs Veh"))
  expect_s3_class(out$per_comparison_top[["Treat vs Ctrl"]], "data.frame")
})

test_that(".build_concordance_payload applies cutoffs per comparison", {
  de_list <- list(
    "A vs B" = data.frame(ID = c("G1", "G2", "G3"),
                          log2FoldChange = c(0.1, 5, -3),
                          padj = c(0.5, 0.001, 0.01)),
    "C vs D" = data.frame(ID = c("G4", "G5"),
                          log2FoldChange = c(2, 0.05),
                          padj = c(0.01, 0.9))
  )
  out <- .build_concordance_payload(de_results_list = de_list,
                                    concordance_table = data.frame(),
                                    top_n = 50L,
                                    cutoffs = list(padj = 0.05, lfc = 1))
  # A vs B: G2 (lfc 5, padj 0.001), G3 (lfc -3, padj 0.01) -> 2 pass
  # C vs D: G4 (lfc 2, padj 0.01) -> 1 pass
  expect_equal(nrow(out$per_comparison_top[["A vs B"]]), 2L)
  expect_equal(nrow(out$per_comparison_top[["C vs D"]]), 1L)
})

test_that(".applicable_questions filters per shape + payload", {
  # geneset shape, no NES-across-comparisons -> only summarize_geneset
  out <- .applicable_questions("geneset", list(shape = "geneset",
                                               genes = c("A","B")))
  expect_true("summarize_geneset" %in% out)
  # de_table -> summarize_geneset + suggest_followup + draft_methods
  out2 <- .applicable_questions("de_table",
                                list(shape = "de_table",
                                     genes = c("A","B")))
  expect_setequal(out2,
                  c("summarize_geneset", "suggest_followup", "draft_methods"))
  # concordance -> suggest_followup + draft_methods (no nes data)
  out3 <- .applicable_questions("concordance",
                                list(shape = "concordance",
                                     comparison_labels = c("A","B")))
  expect_true("suggest_followup" %in% out3)
  expect_true("draft_methods" %in% out3)
})
