test_that("filter_low_counts(method='max', cutoff=10) keeps rows with max >= 10", {
  m <- matrix(
    c(
      0, 0, 0,
      5, 6, 7,
      100, 200, 300
    ),
    3, 3,
    byrow = TRUE,
    dimnames = list(c("g1", "g2", "g3"), c("s1", "s2", "s3"))
  )
  out <- filter_low_counts(m, method = "max", cutoff = 10)
  expect_equal(nrow(out), 1L)
  expect_equal(rownames(out), "g3")
})

test_that("filter_low_counts(method='mean', cutoff=10) keeps rows with mean >= 10", {
  m <- matrix(
    c(
      0, 0, 0,
      5, 6, 7,
      100, 200, 300
    ),
    3, 3,
    byrow = TRUE,
    dimnames = list(c("g1", "g2", "g3"), c("s1", "s2", "s3"))
  )
  out <- filter_low_counts(m, method = "mean", cutoff = 10)
  expect_equal(rownames(out), "g3")
})

test_that("filter_low_counts(method='cpm') keeps rows where CPM > cutoff in >= n samples", {
  m <- matrix(
    c(
      0, 0, 0,
      100, 0, 0,
      100, 100, 100
    ),
    3, 3,
    byrow = TRUE,
    dimnames = list(c("g1", "g2", "g3"), c("s1", "s2", "s3"))
  )
  out <- filter_low_counts(m, method = "cpm", cutoff = 1, min_samples = 2)
  expect_true("g3" %in% rownames(out))
  expect_false("g2" %in% rownames(out))
})

test_that("filter_low_counts() rejects unknown methods", {
  m <- matrix(1:9, 3, 3)
  expect_error(filter_low_counts(m, method = "wat"),
    class = "unknown_filter_method"
  )
})

test_that("filter_low_counts default cutoff matches explicit cutoff = 10", {
  m <- matrix(
    c(
      0, 0, 0,
      5, 6, 7,
      100, 200, 300
    ),
    3, 3,
    byrow = TRUE,
    dimnames = list(c("g1", "g2", "g3"), c("s1", "s2", "s3"))
  )
  # Auto-apply path uses cutoff = 10 (the textInput default value).
  # The function's own default arg is also 10. This test guards both
  # against silent drift.
  out_default  <- filter_low_counts(m, method = "max")
  out_explicit <- filter_low_counts(m, method = "max", cutoff = 10)
  expect_equal(out_default, out_explicit)
})
