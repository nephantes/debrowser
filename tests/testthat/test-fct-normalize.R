test_that("normalize_counts() with method='TMM' matches golden hash", {
  skip_on_cran()

  demo <- load_demo()
  data <- demo$counts[, demo_columns]
  data <- data[rowSums(data) > 10, ]

  set.seed(1L)
  norm <- normalize_counts(data, method = "TMM")
  norm <- norm[order(rownames(norm)), order(colnames(norm))]

  expect_snapshot_value(stable_hash(norm), style = "json2")
})

test_that("normalize_counts() rejects NULL", {
  expect_error(normalize_counts(NULL), class = "null_input")
})

test_that("normalize_counts(method='none') passes the matrix through", {
  m <- matrix(1:12, 3, 4, dimnames = list(NULL, paste0("s", 1:4)))
  out <- normalize_counts(m, method = "none")
  expect_equal(out, m)
})

test_that("apply_batch_correction(method='none') is identity", {
  m <- matrix(1:12, 3, 4, dimnames = list(NULL, paste0("s", 1:4)))
  meta <- data.frame(
    sample = paste0("s", 1:4),
    batch = c(1, 1, 2, 2),
    treatment = c("A", "B", "A", "B")
  )
  expect_equal(
    apply_batch_correction(m, meta,
      method = "none",
      batch_col = "batch", treatment_col = "treatment"
    ),
    m
  )
})

test_that("apply_batch_correction(method='Combat') runs without Shiny input", {
  skip_on_cran()
  skip_if_not_installed("sva")

  demo <- load_demo()
  data <- demo$counts[, demo_columns]
  data <- data[rowSums(data) > 10, ][1:200, ]
  meta <- data.frame(
    sample    = demo_columns,
    batch     = c(1, 2, 1, 2, 1, 2),
    treatment = as.character(demo_conds)
  )
  out <- apply_batch_correction(data, meta,
    method = "Combat",
    batch_col = "batch", treatment_col = "treatment"
  )
  expect_equal(dim(out), dim(data))
  expect_equal(rownames(out), rownames(data))
})

test_that("apply_batch_correction errors when batch_col missing", {
  m <- matrix(1:12, 3, 4)
  meta <- data.frame(sample = paste0("s", 1:4))
  expect_error(
    apply_batch_correction(m, meta,
      method = "Combat",
      batch_col = "nonexistent", treatment_col = "sample"
    ),
    class = "missing_batch_col"
  )
})
