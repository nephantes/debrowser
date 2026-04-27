test_that("runDE with DESeq2 produces a result on the demo data", {
  demo <- load_demo()
  data <- as.data.frame(demo$counts[, demo_columns])
  data <- subset(data, rowSums(data) > 10)

  params <- c("DESeq2", "NoCovariate", "parametric", FALSE, "Wald", "None")
  deseqrun <- runDE(data, demo$meta, demo_columns, demo_conds, params)

  expect_true(exists("deseqrun"))
  expect_true(nrow(deseqrun) > 100)
  expect_true(all(c("padj", "log2FoldChange") %in% colnames(as.data.frame(deseqrun))))
})
