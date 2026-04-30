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

test_that("prep_comparison_inputs emits globally-numbered conds per slot", {
  # Legacy contract: comparison i uses Cond(2i-1) and Cond(2i) so that
  # R/fct_prep_data.R::apply_de_filters can slice norm_data[, conds == x]
  # using `paste0("Cond", 2*compselect - 1)` / `paste0("Cond", 2*compselect)`.
  i2 <- prep_comparison_inputs(mk_minimal_spec(), comparison_idx = 2L)
  expect_equal(unique(i2$conds), c("Cond3", "Cond4"))

  i3 <- prep_comparison_inputs(mk_minimal_spec(), comparison_idx = 3L)
  expect_equal(unique(i3$conds), c("Cond5", "Cond6"))
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

test_that("prep_comparison_inputs preserves meta-path labels (Task 9)", {
  # Meta-path spec — meta_column is set, and the user has overridden the
  # auto-defaulted level names to friendlier labels.
  spec <- mk_minimal_spec(
    meta_column     = "treatment",
    treatment_level = "exper",
    control_level   = "control",
    treatment_label = "Drug 24h",
    control_label   = "DMSO"
  )
  inputs <- prep_comparison_inputs(spec)
  expect_equal(inputs$cond_names, c("Drug 24h", "DMSO"))
  expect_equal(inputs$conds, c("Cond1", "Cond1", "Cond1",
                               "Cond2", "Cond2", "Cond2"))
})

test_that("prep_comparison_inputs handles N comparisons independently (Task 10)", {
  # Two comparisons with different labels. Multi-comparison correctness in
  # `prepDataContainer` is the for-loop's responsibility; per-spec
  # field-derivation must remain a pure mapping (no shared mutable state).
  spec_a <- mk_minimal_spec(treatment_label = "A", control_label = "B")
  spec_b <- mk_minimal_spec(treatment_label = "C", control_label = "D",
                            covariates = "batch")

  ia <- prep_comparison_inputs(spec_a, comparison_idx = 1L)
  ib <- prep_comparison_inputs(spec_b, comparison_idx = 2L)

  expect_equal(ia$cond_names, c("A", "B"))
  expect_equal(ib$cond_names, c("C", "D"))
  expect_equal(unique(ia$conds), c("Cond1", "Cond2"))
  expect_equal(unique(ib$conds), c("Cond3", "Cond4"))
  expect_equal(ia$demethod_params,
               "DESeq2,NoCovariate,parametric,FALSE,Wald,None")
  expect_equal(ib$demethod_params,
               "DESeq2,batch,parametric,FALSE,Wald,None")
})

test_that("prepDataContainer integration: stub debrowserdeanalysis verifies loop semantics", {
  # Mock `debrowserdeanalysis` so we can exercise prepDataContainer's loop
  # without DESeq2 or a real Shiny session. Captures the per-iteration
  # arguments to verify global-numbered conds per slot + matching DEResultsN.
  captured <- list()
  testthat::local_mocked_bindings(
    debrowserdeanalysis = function(id, data, metadata, columns, conds, params) {
      captured[[length(captured) + 1L]] <<- list(
        id = id, columns = columns, conds = conds
      )
      list(dat = function() data.frame(
        foldChange = 1:5, padj = rep(0.5, 5),
        row.names = letters[1:5]
      ))
    },
    .package = "debrowser"
  )
  # withProgress requires a Shiny session; stub to bare expression evaluation.
  testthat::local_mocked_bindings(
    withProgress = function(expr, ...) force(expr),
    incProgress  = function(...) invisible(NULL),
    .package = "shiny"
  )

  spec <- list(
    mk_minimal_spec(treatment_label = "A", control_label = "B"),
    mk_minimal_spec(treatment_label = "C", control_label = "D")
  )
  data <- matrix(1, nrow = 5, ncol = 6,
                 dimnames = list(letters[1:5],
                                 c("exper_rep1", "exper_rep2", "exper_rep3",
                                   "control_rep1", "control_rep2", "control_rep3")))
  meta <- data.frame(
    sample = c("exper_rep1", "exper_rep2", "exper_rep3",
               "control_rep1", "control_rep2", "control_rep3"),
    stringsAsFactors = FALSE
  )

  out <- shiny::isolate(prepDataContainer(data, meta, spec))

  expect_length(out, 2L)
  expect_length(captured, 2L)
  expect_equal(captured[[1]]$id, "DEResults1")
  expect_equal(captured[[2]]$id, "DEResults2")
  expect_equal(unique(captured[[1]]$conds), c("Cond1", "Cond2"))
  expect_equal(unique(captured[[2]]$conds), c("Cond3", "Cond4"))
  expect_equal(out[[1]]$cond_names, c("A", "B"))
  expect_equal(out[[2]]$cond_names, c("C", "D"))
})
