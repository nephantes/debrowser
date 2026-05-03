# Tests for the pure GSEA helpers in R/fct_gsea.R.

test_that("gmt_to_pathways() returns a named list of character vectors", {
  skip_on_cran()
  skip_if_not_installed("fgsea")

  path <- system.file("extdata", "test-gmt", "hallmark-mini.gmt",
                      package = "debrowser")
  expect_true(nzchar(path))

  pw <- gmt_to_pathways(path)
  expect_type(pw, "list")
  expect_named(pw)
  expect_equal(length(pw), 5L)
  expect_true(all(vapply(pw, is.character, logical(1))))
  expect_true("HALLMARK_HYPOXIA" %in% names(pw))
  expect_true("VEGFA" %in% pw[["HALLMARK_HYPOXIA"]])
})

test_that("gmt_to_pathways() raises de_error for missing file", {
  expect_error(
    gmt_to_pathways("/no/such/file.gmt"),
    class = "missing_file"
  )
})

# Synthetic DE fixture used by run_gsea tests below.
.gsea_fixture_de_table <- function() {
  set.seed(1L)
  rng_genes <- paste0("GENE", sprintf("%04d", seq_len(500)))
  hyp <- c("PGK1", "PDK1", "GBE1", "PFKL", "ALDOA", "ENO1", "GAPDH",
           "LDHA", "TPI1", "HK2", "VEGFA", "BNIP3", "ANGPTL4", "ADM", "EGLN3")
  inf <- c("IL6", "IL1B", "TNF", "CCL2", "CXCL10", "NFKB1", "IRF1",
           "STAT1", "NLRP3", "TLR4", "MYD88", "IFNG", "CXCR4", "IL18", "NOS2")
  noise <- setdiff(rng_genes, c(hyp, inf))
  log2fc <- c(rep(3.5, length(hyp)), rep(-3.0, length(inf)),
              stats::rnorm(length(noise), mean = 0, sd = 0.4))
  data.frame(
    gene = c(hyp, inf, noise),
    log2FoldChange = log2fc,
    padj = c(rep(1e-8, length(hyp)), rep(1e-8, length(inf)),
             stats::runif(length(noise), 0.1, 1.0)),
    stringsAsFactors = FALSE
  )
}

test_that("run_gsea() returns expected columns and orders by absolute NES", {
  skip_on_cran()
  skip_if_not_installed("fgsea")

  pathways <- gmt_to_pathways(
    system.file("extdata", "test-gmt", "hallmark-mini.gmt",
                package = "debrowser")
  )
  res <- run_gsea(.gsea_fixture_de_table(), pathways = pathways,
                  min_size = 5, max_size = 200, n_perm = 1000, seed = 1L)

  expect_s3_class(res, "data.frame")
  expect_named(res, c("pathway", "size", "NES", "padj", "pval",
                      "leading_edge"))
  # The synthetic fixture only ships hyp + inf genes (15 each) by name,
  # so fgsea's min_size = 5 filter retains 3 pathways: HYPOXIA (15),
  # INFLAMMATORY_RESPONSE (15), and GLYCOLYSIS (8 overlap with hyp).
  expect_equal(nrow(res), 3L)
  expect_true(all(diff(-abs(res$NES)) >= -1e-9))
  expect_true("HALLMARK_HYPOXIA" %in% res$pathway)
  expect_true("HALLMARK_INFLAMMATORY_RESPONSE" %in% res$pathway)
})

test_that("run_gsea() ranks HYPOXIA at top NES (positive) for the synthetic input", {
  skip_on_cran()
  skip_if_not_installed("fgsea")

  pathways <- gmt_to_pathways(
    system.file("extdata", "test-gmt", "hallmark-mini.gmt",
                package = "debrowser")
  )
  res <- run_gsea(.gsea_fixture_de_table(), pathways = pathways,
                  min_size = 5, max_size = 200, n_perm = 1000, seed = 1L)
  top <- res[which.max(res$NES), ]
  expect_equal(top$pathway, "HALLMARK_HYPOXIA")
  expect_gt(top$NES, 1.0)
  expect_lt(top$padj, 0.05)
})

test_that("run_gsea() raises de_error when stat_col missing", {
  skip_on_cran()
  skip_if_not_installed("fgsea")
  pathways <- gmt_to_pathways(
    system.file("extdata", "test-gmt", "hallmark-mini.gmt",
                package = "debrowser")
  )
  bad <- data.frame(gene = "TP53", padj = 0.5, stringsAsFactors = FALSE)
  expect_error(run_gsea(bad, pathways = pathways),
               class = "missing_column")
})

test_that("nes_heatmap_data() pivots a list of GSEA results into long form", {
  res_a <- data.frame(pathway = c("P1", "P2", "P3"), NES = c(1.5, -1.2, 0.3),
                      padj = c(0.01, 0.04, 0.5), size = c(20, 30, 25),
                      pval = c(0.001, 0.02, 0.4),
                      stringsAsFactors = FALSE)
  res_b <- data.frame(pathway = c("P1", "P2", "P3"), NES = c(0.4, -2.1, 1.8),
                      padj = c(0.6, 0.001, 0.005), size = c(20, 30, 25),
                      pval = c(0.4, 0.0001, 0.001),
                      stringsAsFactors = FALSE)
  long <- nes_heatmap_data(list(comparisonA = res_a, comparisonB = res_b))

  expect_s3_class(long, "data.frame")
  expect_named(long, c("pathway", "comparison", "NES", "padj"))
  expect_equal(nrow(long), 6L)
  expect_setequal(unique(long$comparison), c("comparisonA", "comparisonB"))
})

test_that("nes_heatmap_data() filters to significant pathways when sig_only", {
  res_a <- data.frame(pathway = c("P1", "P2"), NES = c(1.5, -1.2),
                      padj = c(0.01, 0.5), size = c(20, 30),
                      pval = c(0.001, 0.4),
                      stringsAsFactors = FALSE)
  long <- nes_heatmap_data(list(c1 = res_a),
                           sig_only = TRUE, sig_threshold = 0.05)
  expect_equal(nrow(long), 1L)
  expect_equal(long$pathway, "P1")
})

test_that("nes_heatmap_data() rejects empty input", {
  expect_error(nes_heatmap_data(list()), class = "empty_input")
})
