test_that("de_error() raises a classed condition with message and class", {
  err <- tryCatch(
    de_error("count matrix must have at least 3 columns", class = "too_few_columns"),
    error = identity
  )
  expect_s3_class(err, "debrowser_error")
  expect_s3_class(err, "too_few_columns")
  expect_match(conditionMessage(err), "at least 3 columns")
})

test_that("de_error() defaults class to 'debrowser_error' only", {
  err <- tryCatch(de_error("boom"), error = identity)
  expect_s3_class(err, "debrowser_error")
  expect_false(inherits(err, "too_few_columns"))
})

test_that("de_assert_count_matrix() rejects non-numeric, NA-filled, or empty matrices", {
  expect_error(de_assert_count_matrix(NULL), class = "null_input")
  expect_error(de_assert_count_matrix(matrix("a", 1, 1)), class = "non_numeric")
  expect_error(de_assert_count_matrix(matrix(numeric(0), 0, 0)), class = "empty_matrix")
  expect_silent(de_assert_count_matrix(matrix(1:6, 2, 3)))
})
