library(testthat)
library(shinytest2)
source(testthat::test_path("../shinytest2/setup.R"))

test_that("loading demo data and running DESeq2 renders the MA plot", {
  skip_on_cran()
  skip_on_ci() # turn on after Phase B2's three-stage shell stabilises top-level IDs
  skip_if_not_installed("shinytest2")

  app <- AppDriver$new(
    debrowser_app(),
    name = "smoke-demo-deseq2",
    timeout = 120000
  )
  on.exit(app$stop(), add = TRUE)

  # Stage 1: load demo data
  app$click("load-demo")
  app$wait_for_idle(timeout = 30000)

  # Move to DE analysis
  app$click("load-Filter")
  app$wait_for_idle()
  app$click("Filter")
  app$wait_for_idle()

  # Run with default DESeq2 params
  app$click("startDE")
  app$wait_for_idle(timeout = 60000)

  # Switch to Main Plots and confirm something rendered
  app$set_inputs(methodtabs = "panel1")
  app$wait_for_idle()

  expect_true(length(app$get_html("#main-mainplot")) > 0)
})
