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

test_that("compute_pill_class returns no class for pending or empty state", {
  expect_equal(compute_pill_class("pending"), "")
  expect_equal(compute_pill_class(""), "")
})

test_that("compute_pill_class returns 'de-pill-done' for done state", {
  expect_equal(compute_pill_class("done"), "de-pill-done")
})

test_that("compute_pill_class returns 'de-pill-locked' for locked state", {
  expect_equal(compute_pill_class("locked"), "de-pill-locked")
})

test_that("compute_pill_class treats skipped like done (faded check)", {
  # "skipped" is the explicit terminal state for an optional step the
  # user bypassed. Visually it's done — a tick — but downstream stages
  # treat skipped == done for unlock purposes.
  expect_equal(compute_pill_class("skipped"), "de-pill-done")
})

test_that("de_progress_label wraps name + icon span with the right key", {
  lbl <- de_progress_label("Upload", "upload")
  html <- as.character(lbl)
  expect_match(html, "Upload", fixed = TRUE)
  expect_match(html, 'class="de-progress-icon"', fixed = TRUE)
  expect_match(html, 'data-progress-key="upload"', fixed = TRUE)
})

test_that("de_progress_label preserves the visible name verbatim", {
  lbl <- de_progress_label("DE Analysis", "de")
  html <- as.character(lbl)
  # The name should appear before the icon span
  expect_match(html, "DE Analysis", fixed = TRUE)
})
