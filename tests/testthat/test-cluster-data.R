test_that("clusterData() handles filt_data with metadata + DE columns", {
  # Reproduces the GOPlots1 / compareCluster crash:
  # clusterData() is called with dat[[1]] from getDataForTables(), which has
  # Legend/Size character cols and foldChange/padj numeric cols mixed in
  # with the sample count cols. Before the fix, this hit
  # de_assert_count_matrix() with "count matrix is not numeric".
  set.seed(1L)
  n <- 200L
  count_cols <- paste0("sample", 1:6)
  # Heterogeneous counts so the kmeans elbow-finder picks a valid k > 0.
  m <- matrix(
    rnbinom(n * 6L, size = 1, mu = rep(10^runif(n, 0, 4), each = 6L)),
    nrow = n, byrow = TRUE,
    dimnames = list(paste0("g", seq_len(n)), count_cols)
  )
  dat <- data.frame(
    m,
    foldChange     = runif(n, 0.5, 2),
    padj           = runif(n),
    pvalue         = runif(n),
    log2FoldChange = rnorm(n),
    x              = rnorm(n),
    y              = rnorm(n),
    Legend         = sample(c("Up", "Down", "NS"), n, replace = TRUE),
    Size           = "40",
    check.names    = FALSE
  )

  expect_no_error({
    pdf(NULL)
    on.exit(dev.off(), add = TRUE)
    clusterData(dat)
  })
})

test_that("clusterData() drops merged-comparison padj/foldChange columns", {
  set.seed(2L)
  n <- 60L
  count_cols <- paste0("sample", 1:6)
  m <- matrix(
    rpois(n * 6L, lambda = 100),
    nrow = n,
    dimnames = list(paste0("g", seq_len(n)), count_cols)
  )
  dat <- data.frame(
    m,
    `foldChange.A.vs.B` = runif(n, 0.5, 2),
    `padj.A.vs.B`       = runif(n),
    `pvalue.A.vs.B`     = runif(n),
    Legend              = "NS",
    Size                = "40",
    check.names         = FALSE
  )

  expect_no_error({
    pdf(NULL)
    on.exit(dev.off(), add = TRUE)
    clusterData(dat)
  })
})
