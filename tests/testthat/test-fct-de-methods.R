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
