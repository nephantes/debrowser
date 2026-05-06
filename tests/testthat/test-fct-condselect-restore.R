make_spec_entry <- function(label = "treatment", control = "control") {
  list(
    meta_column       = "condition",
    treatment_level   = "A",
    control_level     = "B",
    treatment_samples = c("s1", "s2"),
    control_samples   = c("s3", "s4"),
    treatment_label   = label,
    control_label     = control,
    de_method         = "DESeq2",
    method_params     = list(fitType = "parametric",
                             betaPrior = FALSE,
                             testType  = "LRT",
                             shrinkage = "apeglm"),
    covariates        = c("batch")
  )
}

test_that("restore_comparisons_spec: empty spec returns empty list", {
  expect_equal(restore_comparisons_spec(list()), list())
  expect_equal(restore_comparisons_spec(NULL), list())
})

test_that("restore_comparisons_spec: round-trip preserves all 10 fields", {
  spec <- list(make_spec_entry("treat", "ctrl"))
  out <- restore_comparisons_spec(spec)
  expect_length(out, 1L)
  expect_equal(names(out), "1")
  rv1 <- out[[1]]
  expect_equal(rv1$meta_column,       "condition")
  expect_equal(rv1$treatment_level,   "A")
  expect_equal(rv1$control_level,     "B")
  expect_equal(rv1$treatment_samples, c("s1", "s2"))
  expect_equal(rv1$control_samples,   c("s3", "s4"))
  expect_equal(rv1$treatment_label,   "treat")
  expect_equal(rv1$control_label,     "ctrl")
  expect_equal(rv1$de_method,         "DESeq2")
  expect_equal(rv1$method_params$fitType, "parametric")
  expect_equal(rv1$covariates,        c("batch"))
})

test_that("restore_comparisons_spec: multiple comparisons get sequential keys", {
  spec <- list(
    make_spec_entry("a", "b"),
    make_spec_entry("c", "d"),
    make_spec_entry("e", "f")
  )
  out <- restore_comparisons_spec(spec)
  expect_length(out, 3L)
  expect_equal(names(out), c("1", "2", "3"))
  expect_equal(out[["1"]]$treatment_label, "a")
  expect_equal(out[["2"]]$treatment_label, "c")
  expect_equal(out[["3"]]$treatment_label, "e")
})

test_that("restore_comparisons_spec: missing fields default to safe values", {
  partial <- list(
    treatment_label = "x", control_label = "y",
    treatment_samples = c("s1")
    # other fields missing
  )
  out <- restore_comparisons_spec(list(partial))
  rv1 <- out[[1]]
  expect_true(is.na(rv1$meta_column))
  expect_equal(rv1$de_method, "DESeq2")
  expect_equal(rv1$control_samples, character(0))
  expect_true(is.list(rv1$method_params))
})
