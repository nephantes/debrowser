# tests/testthat/test-make_default_metadata.R

test_that("make_default_metadata builds a 1-condition 1-batch df from counts colnames", {
  counts <- data.frame(s1 = 1:3, s2 = 4:6, s3 = 7:9)
  meta <- make_default_metadata(counts)
  expect_s3_class(meta, "data.frame")
  expect_equal(colnames(meta), c("Sample", "Condition", "Batch"))
  expect_equal(meta$Sample, c("s1", "s2", "s3"))
  expect_equal(unique(meta$Condition), "All")
  expect_equal(unique(meta$Batch), 1)
})

test_that("make_default_metadata preserves sample order from counts", {
  counts <- data.frame(zz = 1:2, aa = 3:4, mm = 5:6)
  meta <- make_default_metadata(counts)
  expect_equal(meta$Sample, c("zz", "aa", "mm"))
})

test_that("make_default_metadata returns a 0-row df for empty counts", {
  counts <- data.frame()
  meta <- make_default_metadata(counts)
  expect_equal(nrow(meta), 0)
  expect_equal(colnames(meta), c("Sample", "Condition", "Batch"))
})
