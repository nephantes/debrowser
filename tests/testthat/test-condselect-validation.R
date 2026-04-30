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

test_that("validate_comparison: whitespace-only label is rejected", {
  records <- validate_comparison(mk_spec(treatment_label = "   "), mk_meta())
  errors <- Filter(function(r) r$severity == "error", records)
  expect_true(any(vapply(errors,
    function(r) r$field == "treatment_label", logical(1))))
})

test_that("validate_comparison: NA label is rejected", {
  records <- validate_comparison(mk_spec(control_label = NA_character_), mk_meta())
  errors <- Filter(function(r) r$severity == "error", records)
  expect_true(any(vapply(errors,
    function(r) r$field == "control_label", logical(1))))
})

test_that("validate_comparison: NULL label is rejected without crashing", {
  records <- validate_comparison(mk_spec(treatment_label = NULL), mk_meta())
  errors <- Filter(function(r) r$severity == "error", records)
  expect_true(any(vapply(errors,
    function(r) r$field == "treatment_label", logical(1))))
})

test_that("validate_comparison: factor-typed metadata column does not crash", {
  meta <- mk_meta()
  meta$cond <- factor(meta$cond)
  expect_silent(
    records <- validate_comparison(
      mk_spec(meta_column = "cond", treatment_level = "KO", control_level = "WT"),
      meta
    )
  )
  errors <- Filter(function(r) r$severity == "error", records)
  expect_length(errors, 0)
})

test_that("validate_comparison: surfaces every failing predicate, not just the first", {
  recs <- validate_comparison(
    mk_spec(treatment_samples = character(0), control_samples = character(0),
            treatment_label = "", control_label = ""),
    mk_meta()
  )
  errs <- Filter(function(r) r$severity == "error", recs)
  fields <- vapply(errs, function(r) r$field, character(1))
  expect_setequal(fields, c("treatment_samples", "control_samples",
                            "treatment_label", "control_label"))
})

test_that("covariate with NA in selected samples -> warning", {
  meta <- mk_meta()
  meta$batch[1] <- NA  # s1 has NA batch
  records <- validate_comparison(mk_spec(covariates = "batch"), meta)
  warnings <- Filter(function(r) r$severity == "warning", records)
  expect_true(any(vapply(warnings,
    function(r) r$field == "covariate_batch", logical(1))))
})

test_that("covariate with < 2 unique values in selected samples -> warning", {
  meta <- mk_meta()
  meta$batch <- c("A", "A", "A", "A")  # all same
  records <- validate_comparison(mk_spec(covariates = "batch"), meta)
  warnings <- Filter(function(r) r$severity == "warning", records)
  expect_true(any(vapply(warnings,
    function(r) r$field == "covariate_batch", logical(1))))
})

test_that("covariate confounded with treatment -> warning", {
  meta <- mk_meta()
  # batch perfectly correlated with treatment side: A on treatment, B on control.
  meta$batch <- c("A", "A", "B", "B")
  records <- validate_comparison(mk_spec(covariates = "batch"), meta)
  warnings <- Filter(function(r) r$severity == "warning", records)
  expect_true(any(vapply(warnings,
    function(r) r$field == "covariate_batch", logical(1))))
})

test_that("covariate equal to meta_column -> warning", {
  records <- validate_comparison(
    mk_spec(meta_column = "cond", treatment_level = "KO",
            control_level = "WT", covariates = "cond"),
    mk_meta()
  )
  warnings <- Filter(function(r) r$severity == "warning", records)
  expect_true(any(vapply(warnings,
    function(r) r$field == "covariate_cond", logical(1))))
})

test_that("baseline-valid covariate (well-balanced, no NA) yields no warning", {
  meta <- mk_meta()
  # batch crosses treatment cleanly.
  meta$batch <- c("A", "B", "A", "B")
  records <- validate_comparison(mk_spec(covariates = "batch"), meta)
  warnings <- Filter(function(r) r$severity == "warning", records)
  expect_length(warnings, 0)
})

test_that("validate_comparison: unknown covariate column surfaces as error", {
  records <- validate_comparison(mk_spec(covariates = "nonexistent"), mk_meta())
  errors <- Filter(function(r) r$severity == "error", records)
  expect_true(any(vapply(errors,
    function(r) r$field == "covariate_nonexistent", logical(1))))
})

test_that("validate_comparison: covariate evaluated correctly when sample column is not first", {
  meta <- data.frame(
    cond   = c("KO", "KO", "WT", "WT"),
    sample = c("s1", "s2", "s3", "s4"),
    batch  = c("A",  "B",  "A",  "B"),  # well-balanced
    stringsAsFactors = FALSE
  )
  records <- validate_comparison(mk_spec(covariates = "batch"), meta)
  warnings <- Filter(function(r) r$severity == "warning", records)
  expect_length(warnings, 0)  # no false-positive NA warning
})

test_that("validate_comparison: two covariates - emits one warning per bad cov", {
  meta <- mk_meta()
  meta$donor <- c("X", "X", "Y", "Y")  # confounded
  # batch is c("A","B","A","B") in mk_meta — well balanced, should not warn.
  records <- validate_comparison(
    mk_spec(covariates = c("batch", "donor")),
    meta
  )
  warnings <- Filter(function(r) r$severity == "warning", records)
  expect_length(warnings, 1)
  expect_equal(warnings[[1]]$field, "covariate_donor")
})
