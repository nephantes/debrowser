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
