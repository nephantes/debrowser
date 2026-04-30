# tests/testthat/test-prepdatacontainer.R
#
# `prepDataContainer` is a Shiny-coupled function (uses `withProgress` and
# `debrowserdeanalysis`, the latter being a `moduleServer`). End-to-end DE
# integration is covered by manual smoke (Vernia demo) + shinytest2 in CI.
#
# Here we test the pure spec → (cols, conds, cond_names, demethod_params)
# mapping via the `prep_comparison_inputs()` helper. That mapping is the
# deterministic part of `prepDataContainer` and the part most likely to
# regress on rewrites of the wizard.

mk_minimal_spec <- function(...) {
  base <- list(
    meta_column       = NA_character_,
    treatment_level   = NA_character_,
    control_level     = NA_character_,
    treatment_samples = c("exper_rep1", "exper_rep2", "exper_rep3"),
    control_samples   = c("control_rep1", "control_rep2", "control_rep3"),
    treatment_label   = "Treatment",
    control_label     = "Control",
    de_method         = "DESeq2",
    method_params     = list(
      fitType = "parametric", betaPrior = FALSE,
      testType = "Wald", shrinkage = "None"
    ),
    covariates        = character(0)
  )
  modifyList(base, list(...))
}

test_that("prep_comparison_inputs builds expected cols/conds for manual path", {
  inputs <- prep_comparison_inputs(mk_minimal_spec())
  expect_equal(inputs$cols, c("exper_rep1", "exper_rep2", "exper_rep3",
                              "control_rep1", "control_rep2", "control_rep3"))
  expect_equal(inputs$conds, c("Cond1", "Cond1", "Cond1",
                               "Cond2", "Cond2", "Cond2"))
})

test_that("prep_comparison_inputs uses user labels for cond_names", {
  inputs <- prep_comparison_inputs(
    mk_minimal_spec(treatment_label = "Drug 24h", control_label = "DMSO")
  )
  expect_equal(inputs$cond_names, c("Drug 24h", "DMSO"))
})

test_that("prep_comparison_inputs serializes DE method + covariates correctly", {
  inputs <- prep_comparison_inputs(mk_minimal_spec())
  expect_equal(inputs$demethod_params,
               "DESeq2,NoCovariate,parametric,FALSE,Wald,None")

  inputs2 <- prep_comparison_inputs(
    mk_minimal_spec(covariates = c("batch", "donor"))
  )
  expect_equal(inputs2$demethod_params,
               "DESeq2,batch|donor,parametric,FALSE,Wald,None")
})

test_that("prepDataContainer returns NULL for empty/missing inputs", {
  expect_null(prepDataContainer(NULL, data.frame(), list(mk_minimal_spec())))
  expect_null(prepDataContainer(matrix(1, 1, 1), data.frame(), list()))
})
