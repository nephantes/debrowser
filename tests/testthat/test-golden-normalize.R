test_that("getNormalizedMatrix on demo data matches golden hash", {
  skip_on_cran()

  demo <- load_demo()
  data <- demo$counts[, demo_columns]
  data <- data[rowSums(data) > 10, ]

  set.seed(1L)
  norm <- getNormalizedMatrix(data)
  norm <- norm[order(rownames(norm)), order(colnames(norm))]

  expect_snapshot_value(stable_hash(norm), style = "json2")
})

test_that("PCA on demo normalized data matches golden coordinates", {
  skip_on_cran()

  demo <- load_demo()
  data <- demo$counts[, demo_columns]
  data <- data[rowSums(data) > 10, ]
  norm <- getNormalizedMatrix(data)

  set.seed(1L)
  pca <- prcomp(t(log2(norm + 1)))
  coords <- pca$x[, c("PC1", "PC2")]
  coords <- coords[order(rownames(coords)), ]

  expect_snapshot_value(stable_hash(coords), style = "json2")
})
