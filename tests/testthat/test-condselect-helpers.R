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
