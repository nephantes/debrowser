test_that("sanitize_label replaces unsafe chars with underscore", {
  expect_equal(sanitize_label("treated vs control"), "treated_vs_control")
  expect_equal(sanitize_label("high dose / low dose"), "high_dose___low_dose")
  expect_equal(sanitize_label("Wt+IL6"), "Wt_IL6")
})

test_that("sanitize_label preserves alphanumeric, dot, underscore, dash", {
  expect_equal(sanitize_label("Sample_1.A-2"), "Sample_1.A-2")
  expect_equal(sanitize_label("Cond123"), "Cond123")
})

test_that("sanitize_label handles empty and pure-punctuation input", {
  expect_equal(sanitize_label(""), "")
  expect_equal(sanitize_label("@@@"), "___")
})
