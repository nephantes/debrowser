# tests/testthat/test-condselect-validation.R

# Helper to build a baseline-valid manual-mode spec for tests below.
mk_spec <- function(...) {
  base <- list(
    meta_column       = NA_character_,
    treatment_level   = NA_character_,
    control_level     = NA_character_,
    treatment_samples = c("s1", "s2"),
    control_samples   = c("s3", "s4"),
    treatment_label   = "Treatment",
    control_label     = "Control",
    de_method         = "DESeq2",
    method_params     = list(
      fitType = "parametric", betaPrior = FALSE,
      testType = "LRT", shrinkage = "None"
    ),
    covariates        = character(0)
  )
  modifyList(base, list(...))
}

# Synthetic metadata for predicate tests.
mk_meta <- function() {
  data.frame(
    sample = c("s1", "s2", "s3", "s4"),
    cond   = c("KO", "KO", "WT", "WT"),
    batch  = c("A",  "B",  "A",  "B"),
    stringsAsFactors = FALSE
  )
}

test_that("validate_comparison: baseline-valid spec yields no error records", {
  records <- validate_comparison(mk_spec(), mk_meta())
  errors <- Filter(function(r) r$severity == "error", records)
  expect_length(errors, 0)
})

test_that("validate_comparison: empty treatment side -> error", {
  records <- validate_comparison(mk_spec(treatment_samples = character(0)), mk_meta())
  errors <- Filter(function(r) r$severity == "error", records)
  expect_true(any(vapply(errors, function(r) r$field == "treatment_samples", logical(1))))
})

test_that("validate_comparison: empty control side -> error", {
  records <- validate_comparison(mk_spec(control_samples = character(0)), mk_meta())
  errors <- Filter(function(r) r$severity == "error", records)
  expect_true(any(vapply(errors, function(r) r$field == "control_samples", logical(1))))
})

test_that("validate_comparison: overlap between sides -> error", {
  records <- validate_comparison(
    mk_spec(treatment_samples = c("s1", "s2"), control_samples = c("s2", "s3")),
    mk_meta()
  )
  errors <- Filter(function(r) r$severity == "error", records)
  expect_true(any(vapply(errors, function(r) r$field == "samples_disjoint", logical(1))))
})

test_that("validate_comparison: empty treatment label -> error", {
  records <- validate_comparison(mk_spec(treatment_label = ""), mk_meta())
  errors <- Filter(function(r) r$severity == "error", records)
  expect_true(any(vapply(errors, function(r) r$field == "treatment_label", logical(1))))
})

test_that("validate_comparison: empty control label -> error", {
  records <- validate_comparison(mk_spec(control_label = ""), mk_meta())
  errors <- Filter(function(r) r$severity == "error", records)
  expect_true(any(vapply(errors, function(r) r$field == "control_label", logical(1))))
})

test_that("validate_comparison: meta column with < 2 distinct levels -> error", {
  bad_meta <- mk_meta()
  bad_meta$cond <- c("KO", "KO", "KO", "KO")
  records <- validate_comparison(
    mk_spec(meta_column = "cond", treatment_level = "KO", control_level = "KO"),
    bad_meta
  )
  errors <- Filter(function(r) r$severity == "error", records)
  expect_true(any(vapply(errors, function(r) r$field == "meta_levels", logical(1))))
})

test_that("validate_comparison: treatment_level == control_level -> error", {
  records <- validate_comparison(
    mk_spec(meta_column = "cond", treatment_level = "KO", control_level = "KO"),
    mk_meta()
  )
  errors <- Filter(function(r) r$severity == "error", records)
  expect_true(any(vapply(errors, function(r) r$field == "level_distinct", logical(1))))
})
