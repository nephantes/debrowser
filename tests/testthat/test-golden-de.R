test_that("DESeq2 result on demo data matches golden hash", {
  skip_on_cran()
  skip_if_not_installed("DESeq2")

  demo <- load_demo()
  data <- demo$counts[, demo_columns]
  data <- data[rowSums(data) > 10, ]

  params <- c("DESeq2", "NoCovariate", "parametric", FALSE, "Wald", "None")

  set.seed(1L)
  res <- runDE(data, demo$meta, demo_columns, demo_conds, params)
  res <- as.data.frame(res)

  # Sort by gene id so the hash is invariant to row-order shuffles
  # introduced by internal DESeq2 changes; only values matter.
  res <- res[order(rownames(res)), c("baseMean", "log2FoldChange", "padj"), drop = FALSE]

  expect_snapshot_value(stable_hash(res), style = "json2")
})

test_that("EdgeR result on demo data matches golden hash", {
  skip_on_cran()
  skip_if_not_installed("edgeR")

  demo <- load_demo()
  data <- demo$counts[, demo_columns]
  data <- data[rowSums(data) > 10, ]

  params <- c("EdgeR", "NoCovariate", "TMM", "0", "exactTest")

  set.seed(1L)
  res <- as.data.frame(runDE(data, demo$meta, demo_columns, demo_conds, params))
  res <- res[order(rownames(res)), c("log2FoldChange", "pvalue", "padj"), drop = FALSE]

  expect_snapshot_value(stable_hash(res), style = "json2")
})

test_that("Limma result on demo data matches golden hash", {
  skip_on_cran()
  skip_if_not_installed("limma")

  demo <- load_demo()
  data <- demo$counts[, demo_columns]
  data <- data[rowSums(data) > 10, ]

  params <- c("Limma", "NoCovariate", "TMM", "ls", "none")

  set.seed(1L)
  res <- as.data.frame(runDE(data, demo$meta, demo_columns, demo_conds, params))
  res <- res[order(rownames(res)), c("log2FoldChange", "pvalue", "padj"), drop = FALSE]

  expect_snapshot_value(stable_hash(res), style = "json2")
})
