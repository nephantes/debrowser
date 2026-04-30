test_that("default_cutoffs returns named list with expected values", {
  d <- default_cutoffs()
  expect_type(d, "list")
  expect_named(d, c("padj", "log2fc", "gopvalue"))
  expect_equal(d$padj, 0.01)
  expect_equal(d$log2fc, 1)
  expect_equal(d$gopvalue, 0.01)
})

test_that("cutoff_presets returns a 2-row data frame with expected schema", {
  p <- cutoff_presets()
  expect_s3_class(p, "data.frame")
  expect_equal(nrow(p), 2L)
  expect_named(p, c("name", "label", "padj", "log2fc"))
  expect_equal(p$name, c("strict", "standard"))
  expect_equal(p$padj, c(0.01, 0.05))
  expect_true(all(p$log2fc == 1))
  expect_match(p$label[1], "Strict")
  expect_match(p$label[2], "Standard")
})

test_that("match_preset returns the strict preset name on exact match", {
  expect_identical(match_preset(0.01, 1), "strict")
})

test_that("match_preset returns the standard preset name on exact match", {
  expect_identical(match_preset(0.05, 1), "standard")
})

test_that("match_preset accepts a small tolerance around preset values", {
  expect_identical(match_preset(0.01 + 1e-12, 1 - 1e-12), "strict")
})

test_that("match_preset returns NA_character_ when the pair matches no preset", {
  expect_identical(match_preset(0.025, 1), NA_character_)
  expect_identical(match_preset(0.01, 0.5), NA_character_)
})

test_that("match_preset returns NA_character_ for NA inputs", {
  expect_identical(match_preset(NA_real_, 1), NA_character_)
  expect_identical(match_preset(0.01, NA_real_), NA_character_)
})

test_that("match_preset returns NA_character_ for NULL inputs", {
  expect_identical(match_preset(NULL, 1), NA_character_)
  expect_identical(match_preset(0.01, NULL), NA_character_)
})

test_that("match_preset returns NA_character_ for non-finite inputs", {
  expect_identical(match_preset(NaN, 1), NA_character_)
  expect_identical(match_preset(Inf, 1), NA_character_)
})

test_that("match_preset returns NA_character_ for length>1 inputs", {
  expect_identical(match_preset(c(0.01, 0.05), 1), NA_character_)
  expect_identical(match_preset(0.01, c(1, 2)), NA_character_)
})

test_that("log2fc_to_fold inverts fold_to_log2fc", {
  expect_equal(log2fc_to_fold(fold_to_log2fc(1.5)), 1.5)
  expect_equal(log2fc_to_fold(fold_to_log2fc(2)),   2)
  expect_equal(log2fc_to_fold(fold_to_log2fc(8)),   8)
})

test_that("log2fc_to_fold maps 1 to 2 and 0 to 1", {
  expect_equal(log2fc_to_fold(1), 2)
  expect_equal(log2fc_to_fold(0), 1)
})

test_that("fold_to_log2fc maps 2 to 1 and 1 to 0", {
  expect_equal(fold_to_log2fc(2), 1)
  expect_equal(fold_to_log2fc(1), 0)
})
