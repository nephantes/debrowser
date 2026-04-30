# tests/testthat/test-condselect-helpers.R

test_that("infer_control_level picks reference-shaped level", {
  expect_equal(infer_control_level(c("KO", "WT")), "WT")
  expect_equal(infer_control_level(c("Drug", "DMSO")), "DMSO")
  expect_equal(infer_control_level(c("Treated", "Control")), "Control")
  expect_equal(infer_control_level(c("ctrl", "test")), "ctrl")
  expect_equal(infer_control_level(c("vehicle", "compoundA")), "vehicle")
  expect_equal(infer_control_level(c("Day7", "Day0")), "Day0")
  expect_equal(infer_control_level(c("0h", "24h")), "0h")
})

test_that("infer_control_level falls back to alphabetical when no match", {
  expect_equal(infer_control_level(c("Tumor", "Normal")), "Normal")
  expect_equal(infer_control_level(c("Z", "A")), "A")
  expect_equal(infer_control_level(c("groupB", "groupA")), "groupA")
})

test_that("infer_control_level falls back to alphabetical when ambiguous", {
  # Both look like references — alphabetical wins.
  expect_equal(infer_control_level(c("control", "wt")), "control")
})

test_that("infer_control_level is anchored (avoids substring matches)", {
  # 'controllab' should NOT match 'control'.
  expect_equal(infer_control_level(c("controllab", "tester")), "controllab") # alphabetical
})

test_that("infer_control_level is case-insensitive", {
  expect_equal(infer_control_level(c("WILDTYPE", "MUTANT")), "WILDTYPE")
})

test_that("default_side_labels uses level names when meta column is set", {
  result <- default_side_labels(meta_column = "Cell Type",
                                treatment_level = "KO",
                                control_level   = "WT")
  expect_equal(result, c(treatment = "KO", control = "WT"))
})

test_that("default_side_labels falls back to Treatment/Control when no meta", {
  result <- default_side_labels(meta_column = NA_character_,
                                treatment_level = NA_character_,
                                control_level   = NA_character_)
  expect_equal(result, c(treatment = "Treatment", control = "Control"))
})

test_that("default_side_labels handles partial NA gracefully", {
  # Defensive: if only one level is NA (shouldn't happen but be safe), fall back.
  result <- default_side_labels(meta_column = "Cell Type",
                                treatment_level = "KO",
                                control_level   = NA_character_)
  expect_equal(result, c(treatment = "Treatment", control = "Control"))
})

test_that("halve_sample_names splits sample list into two halves", {
  result <- halve_sample_names(c("s1", "s2", "s3", "s4", "s5", "s6"))
  expect_equal(result$treatment, c("s1", "s2", "s3"))
  expect_equal(result$control,   c("s4", "s5", "s6"))
})

test_that("halve_sample_names handles odd-count by giving control the extra", {
  # Today's getSampleNames floor()s the cut so part 1 gets the smaller half.
  # New behavior preserves that exactly.
  result <- halve_sample_names(c("s1", "s2", "s3", "s4", "s5"))
  expect_equal(result$treatment, c("s1", "s2"))
  expect_equal(result$control,   c("s3", "s4", "s5"))
})

test_that("halve_sample_names returns empty halves for empty input", {
  result <- halve_sample_names(character(0))
  expect_equal(result$treatment, character(0))
  expect_equal(result$control,   character(0))
})

test_that("halve_sample_names returns NULL on NULL input", {
  expect_null(halve_sample_names(NULL))
})

test_that("halve_sample_names with length-1 input gives empty treatment", {
  # Locks in the deliberate divergence from the legacy 1:0-reversal behavior.
  result <- halve_sample_names("only")
  expect_equal(result$treatment, character(0))
  expect_equal(result$control, "only")
})

test_that("compute_cond_names extracts the two display labels in order", {
  spec <- list(treatment_label = "Drug 24h", control_label = "DMSO")
  expect_equal(compute_cond_names(spec), c("Drug 24h", "DMSO"))
})

test_that("build_demethod_params_string reproduces today's DESeq2 format", {
  s <- build_demethod_params_string(
    de_method = "DESeq2",
    method_params = list(
      fitType = "parametric", betaPrior = FALSE,
      testType = "LRT", shrinkage = "None"
    ),
    covariates = character(0)
  )
  expect_equal(s, "DESeq2,NoCovariate,parametric,FALSE,LRT,None")
})

test_that("build_demethod_params_string handles single covariate", {
  s <- build_demethod_params_string(
    de_method = "DESeq2",
    method_params = list(
      fitType = "parametric", betaPrior = FALSE,
      testType = "LRT", shrinkage = "None"
    ),
    covariates = "batch"
  )
  expect_equal(s, "DESeq2,batch,parametric,FALSE,LRT,None")
})

test_that("build_demethod_params_string handles multiple covariates with pipe sep", {
  s <- build_demethod_params_string(
    de_method = "DESeq2",
    method_params = list(
      fitType = "parametric", betaPrior = FALSE,
      testType = "LRT", shrinkage = "None"
    ),
    covariates = c("batch", "donor")
  )
  expect_equal(s, "DESeq2,batch|donor,parametric,FALSE,LRT,None")
})

test_that("build_demethod_params_string reproduces today's EdgeR format", {
  s <- build_demethod_params_string(
    de_method = "EdgeR",
    method_params = list(
      edgeR_normfact = "TMM", dispersion = "0", edgeR_testType = "exactTest"
    ),
    covariates = character(0)
  )
  expect_equal(s, "EdgeR,NoCovariate,TMM,0,exactTest")
})

test_that("build_demethod_params_string reproduces today's Limma format", {
  s <- build_demethod_params_string(
    de_method = "Limma",
    method_params = list(
      limma_normfact = "TMM", limma_fitType = "ls", normBetween = "none"
    ),
    covariates = character(0)
  )
  expect_equal(s, "Limma,NoCovariate,TMM,ls,none")
})

test_that("build_demethod_params_string normalizes empty-string covariate to NoCovariate", {
  s <- build_demethod_params_string(
    de_method = "DESeq2",
    method_params = list(
      fitType = "parametric", betaPrior = FALSE,
      testType = "LRT", shrinkage = "None"
    ),
    covariates = ""
  )
  expect_equal(s, "DESeq2,NoCovariate,parametric,FALSE,LRT,None")
})

test_that("build_demethod_params_string drops empty strings inside a covariate vector", {
  s <- build_demethod_params_string(
    de_method = "DESeq2",
    method_params = list(
      fitType = "parametric", betaPrior = FALSE,
      testType = "LRT", shrinkage = "None"
    ),
    covariates = c("", "batch", "")
  )
  expect_equal(s, "DESeq2,batch,parametric,FALSE,LRT,None")
})

test_that("build_demethod_params_string errors hard on missing method_params field", {
  expect_error(
    build_demethod_params_string(
      de_method = "DESeq2",
      method_params = list(  # shrinkage missing
        fitType = "parametric", betaPrior = FALSE, testType = "LRT"
      ),
      covariates = character(0)
    ),
    regexp = "shrinkage"
  )
})

test_that("build_demethod_params_string errors hard on NULL method_params field", {
  expect_error(
    build_demethod_params_string(
      de_method = "EdgeR",
      method_params = list(
        edgeR_normfact = NULL, dispersion = "0", edgeR_testType = "exactTest"
      ),
      covariates = character(0)
    ),
    regexp = "edgeR_normfact"
  )
})

test_that("build_demethod_params_string covariate handling works for EdgeR + Limma", {
  s_e <- build_demethod_params_string(
    de_method = "EdgeR",
    method_params = list(
      edgeR_normfact = "TMM", dispersion = "0", edgeR_testType = "exactTest"
    ),
    covariates = c("batch", "donor")
  )
  expect_equal(s_e, "EdgeR,batch|donor,TMM,0,exactTest")

  s_l <- build_demethod_params_string(
    de_method = "Limma",
    method_params = list(
      limma_normfact = "TMM", limma_fitType = "ls", normBetween = "none"
    ),
    covariates = "batch"
  )
  expect_equal(s_l, "Limma,batch,TMM,ls,none")
})
