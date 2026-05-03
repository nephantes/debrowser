# Tests for the pure helpers in R/fct_method_concordance.R.

# Synthetic per-method DE list shared by several tests below.
# Three methods, 6 genes, with deliberate disagreement on g3+g4.
.mc_fixture_de_list <- function() {
  mk <- function(genes, lfc, padj) {
    data.frame(ID = genes, log2FoldChange = lfc, padj = padj,
               pvalue = padj, stat = lfc,
               stringsAsFactors = FALSE)
  }
  list(
    DESeq2 = mk(paste0("g", 1:6),
                lfc  = c( 2.0,  1.5,  0.7, -1.8, -0.3,  0.1),
                padj = c(0.001, 0.01, 0.20, 0.001, 0.30, 0.50)),
    EdgeR  = mk(paste0("g", 1:6),
                lfc  = c( 1.9,  1.6,  1.2, -1.7,  0.2, -0.1),
                padj = c(0.002, 0.02, 0.04, 0.002, 0.40, 0.60)),
    Limma  = mk(paste0("g", 1:6),
                lfc  = c( 2.1,  1.4, -0.2, -1.9, -0.4,  0.2),
                padj = c(0.001, 0.03, 0.30, 0.003, 0.20, 0.55))
  )
}

test_that("run_de_methods() returns a named list keyed by method name", {
  skip_on_cran()
  skip_on_ci()
  skip_if_not_installed("DESeq2")
  skip_if_not_installed("edgeR")
  skip_if_not_installed("limma")

  demo <- load_demo()
  data <- demo$counts[, demo_columns]
  data <- data[rowSums(data) > 10, ]

  out <- run_de_methods(
    counts = data, metadata = demo$meta,
    columns = demo_columns, conds = demo_conds,
    methods = c("DESeq2", "EdgeR", "Limma"),
    params_per_method = list(
      DESeq2 = list(test_type = "Wald", shrinkage = "None")
    )
  )
  expect_type(out, "list")
  expect_named(out, c("DESeq2", "EdgeR", "Limma"))
  for (m in names(out)) {
    expect_true(all(c("ID", "log2FoldChange", "padj") %in%
                    names(out[[m]])),
                info = sprintf("method = %s", m))
    expect_gt(nrow(out[[m]]), 0L)
  }
})

test_that("run_de_methods() raises empty_input when methods is empty", {
  expect_error(
    run_de_methods(matrix(1:9, 3, 3), columns = letters[1:3],
                   conds = factor(c("a","b","c")),
                   methods = character()),
    class = "empty_input"
  )
})

test_that("concordance_sets() returns per-method significant gene IDs", {
  de <- .mc_fixture_de_list()
  s <- concordance_sets(de, padj_cutoff = 0.05, lfc_cutoff = 0)
  expect_named(s, c("DESeq2", "EdgeR", "Limma"))
  expect_setequal(s$DESeq2, c("g1", "g2", "g4"))
  expect_setequal(s$EdgeR,  c("g1", "g2", "g3", "g4"))
  expect_setequal(s$Limma,  c("g1", "g2", "g4"))
})

test_that("concordance_sets() respects lfc_cutoff", {
  de <- .mc_fixture_de_list()
  # Tighter |log2FC| >= 1.6 drops g2 from DESeq2 (|1.5| < 1.6) and
  # drops g3 from EdgeR (|1.2| < 1.6); g2 stays in EdgeR (|1.6| >= 1.6).
  s <- concordance_sets(de, padj_cutoff = 0.05, lfc_cutoff = 1.6)
  expect_setequal(s$DESeq2, c("g1", "g4"))
  expect_setequal(s$EdgeR,  c("g1", "g2", "g4"))
})

test_that("concordance_sets() raises empty_input on empty list", {
  expect_error(concordance_sets(list()), class = "empty_input")
})

test_that("concordance_summary() returns one row per pair with expected columns", {
  de <- .mc_fixture_de_list()
  cs <- concordance_summary(de, padj_cutoff = 0.05)
  expect_s3_class(cs, "data.frame")
  expect_named(cs, c("method1", "method2", "n_method1", "n_method2",
                     "n_overlap", "jaccard", "spearman_lfc",
                     "n_genes_compared"))
  # 3 methods => choose(3, 2) == 3 pairs
  expect_equal(nrow(cs), 3L)
  expect_setequal(paste(cs$method1, cs$method2),
                  c("DESeq2 EdgeR", "DESeq2 Limma", "EdgeR Limma"))
  # DESeq2-Limma overlap should be the highest (both flag {g1,g2,g4}).
  dl <- cs[cs$method1 == "DESeq2" & cs$method2 == "Limma", ]
  expect_equal(dl$n_overlap, 3L)
  expect_equal(dl$jaccard, 1.0)
  # Spearman across all 6 genes is high but not 1 (g3 disagrees in sign).
  expect_gt(dl$spearman_lfc, 0.5)
  expect_lte(dl$spearman_lfc, 1.0)
})

test_that("concordance_summary() returns empty data.frame for <2 methods", {
  de <- .mc_fixture_de_list()
  cs <- concordance_summary(de["DESeq2"])
  expect_s3_class(cs, "data.frame")
  expect_equal(nrow(cs), 0L)
  expect_named(cs, c("method1", "method2", "n_method1", "n_method2",
                     "n_overlap", "jaccard", "spearman_lfc",
                     "n_genes_compared"))
})

test_that("plot_method_upset() returns NULL when fewer than 2 non-empty sets", {
  skip_on_cran()
  skip_if_not_installed("UpSetR")
  de <- .mc_fixture_de_list()
  # Cutoff so tight only DESeq2 gets a non-empty set:
  de2 <- list(
    DESeq2 = de$DESeq2,
    EdgeR  = de$EdgeR[FALSE, , drop = FALSE],
    Limma  = de$Limma[FALSE, , drop = FALSE]
  )
  expect_null(plot_method_upset(de2))
})

test_that("plot_method_upset() returns an upset object for >=2 non-empty sets", {
  skip_on_cran()
  skip_if_not_installed("UpSetR")
  de <- .mc_fixture_de_list()
  p <- plot_method_upset(de, padj_cutoff = 0.05)
  expect_false(is.null(p))
  # UpSetR::upset returns a list; check it has the typical pieces.
  expect_type(p, "list")
})

test_that("plot_method_scatter() returns a ggplot with Spearman in subtitle", {
  de <- .mc_fixture_de_list()
  p <- plot_method_scatter(de, "DESeq2", "EdgeR")
  expect_s3_class(p, "ggplot")
  # Subtitle pattern: "Spearman rho = 0.xxx  (n = N)"
  expect_match(p$labels$subtitle, "Spearman rho =")
})

test_that("plot_method_scatter() raises unknown_de_method for unknown method", {
  de <- .mc_fixture_de_list()
  expect_error(
    plot_method_scatter(de, "DESeq2", "RandomMethod"),
    class = "unknown_de_method"
  )
})

test_that("comparison_labels() returns 'treatment vs control' format", {
  comps <- list(
    list(cond_names = c("Treated", "Control")),
    list(cond_names = c("KO", "WT"))
  )
  expect_equal(comparison_labels(comps),
               c("Treated vs Control", "KO vs WT"))
})

test_that("comparison_labels() suffixes duplicates in input order", {
  comps <- list(
    list(cond_names = c("A", "B")),
    list(cond_names = c("A", "B")),
    list(cond_names = c("X", "Y")),
    list(cond_names = c("A", "B"))
  )
  expect_equal(comparison_labels(comps),
               c("A vs B (1)", "A vs B (2)", "X vs Y", "A vs B (3)"))
})

test_that("comparison_labels() falls back to comparison_N when cond_names missing", {
  comps <- list(
    list(),
    list(cond_names = c("A", "B"))
  )
  expect_equal(comparison_labels(comps),
               c("comparison_1", "A vs B"))
})

test_that("comparison_labels() returns character(0) for empty input", {
  expect_equal(comparison_labels(list()), character(0))
})

test_that("comparison_labels() handles single-element cond_names with fallback", {
  comps <- list(list(cond_names = "OnlyOne"))
  expect_equal(comparison_labels(comps), "comparison_1")
})
