test_that("run_deseq2() with structured params matches the legacy DESeq2 golden hash", {
  skip_on_cran()
  skip_if_not_installed("DESeq2")

  demo <- load_demo()
  data <- demo$counts[, demo_columns]
  data <- data[rowSums(data) > 10, ]

  set.seed(1L)
  res <- run_deseq2(
    counts   = data,
    metadata = demo$meta,
    columns  = demo_columns,
    conds    = demo_conds,
    params   = list(
      covariates = "NoCovariate",
      fit_type   = "parametric",
      beta_prior = FALSE,
      test_type  = "Wald",
      shrinkage  = "None"
    )
  )
  res <- as.data.frame(res)
  res <- res[order(rownames(res)), c("baseMean", "log2FoldChange", "padj"), drop = FALSE]

  # Same hash as test-golden-de.R "DESeq2 result" — the pure function
  # must be byte-identical to the legacy runDESeq2() path.
  expect_snapshot_value(stable_hash(res), style = "json2")
})

test_that("run_deseq2() raises de_error when fewer than 3 columns supplied", {
  expect_error(
    run_deseq2(matrix(1:4, 2, 2), data.frame(), c("a", "b"), factor(c("x", "y"))),
    class = "too_few_columns"
  )
})

test_that("run_edger() with structured params matches the legacy edgeR golden hash", {
  skip_on_cran()
  skip_if_not_installed("edgeR")

  demo <- load_demo()
  data <- demo$counts[, demo_columns]
  data <- data[rowSums(data) > 10, ]

  set.seed(1L)
  res <- as.data.frame(run_edger(
    counts   = data,
    metadata = demo$meta,
    columns  = demo_columns,
    conds    = demo_conds,
    params   = list(
      covariates = "NoCovariate",
      norm_fact  = "TMM",
      dispersion = "0",
      test_type  = "exactTest"
    )
  ))
  res <- res[order(rownames(res)), c("log2FoldChange", "pvalue", "padj"), drop = FALSE]
  expect_snapshot_value(stable_hash(res), style = "json2")
})

test_that("run_edger() returns log2FoldChange in log2 scale and aligned with input gene order", {
  # Regression for two B2.5 followup bugs in run_edger's exactTest branch:
  #   (1) `logFC / log(2)` inflated reported log2FoldChange by 1/log(2) ~= 1.44.
  #   (2) `topTags()` reordered rows by FDR, but `rownames(res) <- rownames(filtd)`
  #       reassigned the original gene names to the reordered values, scrambling
  #       which gene each log2FoldChange / pvalue / padj belonged to.
  # After fix, run_edger's per-gene log2FoldChange equals edgeR's native logFC.
  skip_on_cran()
  skip_if_not_installed("edgeR")

  set.seed(7L)
  counts <- matrix(
    c(50L, 60L, 100L, 120L,   # g1
      40L, 50L,  20L,  25L,   # g2
      30L, 35L,  30L,  35L),  # g3
    nrow = 3, byrow = TRUE,
    dimnames = list(c("g1", "g2", "g3"), c("a", "b", "c", "d"))
  )
  meta <- data.frame(sample = c("a", "b", "c", "d"), stringsAsFactors = FALSE)
  conds <- factor(c("Control", "Control", "Treat", "Treat"))

  ours <- run_edger(
    counts   = counts,
    metadata = meta,
    columns  = c("a", "b", "c", "d"),
    conds    = conds,
    params   = list(
      covariates = "NoCovariate", norm_fact = "TMM",
      dispersion = "0.1",          test_type = "exactTest"
    )
  )

  # Reference: native edgeR exactTest, no reordering.
  set.seed(7L)
  d <- edgeR::DGEList(counts = counts, group = conds)
  d <- edgeR::calcNormFactors(d, method = "TMM")
  ref <- edgeR::exactTest(d, dispersion = 0.1)$table

  # Per-gene log2FoldChange equals edgeR's logFC byte-for-byte.
  expect_equal(ours[rownames(ref), "log2FoldChange"], ref$logFC,
               tolerance = 1e-8)
  expect_equal(ours[rownames(ref), "pvalue"], ref$PValue,
               tolerance = 1e-8)
})

test_that("run_de() dispatches by method name and matches per-method results", {
  skip_on_cran()

  demo <- load_demo()
  data <- demo$counts[, demo_columns]
  data <- data[rowSums(data) > 10, ]

  set.seed(1L)
  via_dispatch <- run_de(
    "DESeq2", data, demo$meta, demo_columns, demo_conds,
    params = list(covariates = "NoCovariate")
  )
  set.seed(1L)
  direct <- run_deseq2(
    data, demo$meta, demo_columns, demo_conds,
    params = list(covariates = "NoCovariate")
  )
  expect_equal(
    stable_hash(as.data.frame(via_dispatch)),
    stable_hash(as.data.frame(direct))
  )
})

test_that("run_de() rejects unknown methods", {
  expect_error(
    run_de("NotAMethod", matrix(1:6, 2, 3)),
    class = "unknown_de_method"
  )
})

test_that("run_limma() with structured params matches the legacy limma golden hash", {
  skip_on_cran()
  skip_if_not_installed("limma")

  demo <- load_demo()
  data <- demo$counts[, demo_columns]
  data <- data[rowSums(data) > 10, ]

  set.seed(1L)
  res <- as.data.frame(run_limma(
    counts   = data,
    metadata = demo$meta,
    columns  = demo_columns,
    conds    = demo_conds,
    params   = list(
      covariates = "NoCovariate",
      norm_fact  = "TMM",
      fit_type   = "ls",
      norm_bet   = "none"
    )
  ))
  res <- res[order(rownames(res)), c("log2FoldChange", "pvalue", "padj"), drop = FALSE]
  expect_snapshot_value(stable_hash(res), style = "json2")
})
