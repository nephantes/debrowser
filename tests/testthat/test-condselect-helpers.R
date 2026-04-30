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
