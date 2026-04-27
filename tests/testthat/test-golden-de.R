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
