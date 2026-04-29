test_that("progress_message returns a named list with key and state", {
  msg <- progress_message("upload", "done")
  expect_type(msg, "list")
  expect_named(msg, c("key", "state"))
  expect_equal(msg$key, "upload")
  expect_equal(msg$state, "done")
})

test_that("progress_message accepts the four canonical states", {
  for (state in c("pending", "done", "locked", "skipped")) {
    msg <- progress_message("filter", state)
    expect_equal(msg$state, state)
  }
})

test_that("progress_message tolerates empty state (used to clear icons)", {
  msg <- progress_message("data_prep", "")
  expect_equal(msg$state, "")
})
