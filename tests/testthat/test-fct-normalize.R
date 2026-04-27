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
