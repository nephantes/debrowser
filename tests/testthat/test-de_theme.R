test_that("de_theme() with no args returns a bs_theme object", {
  t <- de_theme()
  expect_s3_class(t, "bs_theme")
})

test_that("de_theme(preset) returns a bs_theme using the named preset", {
  t <- de_theme(preset = "zephyr")
  expect_s3_class(t, "bs_theme")
})

test_that("de_theme(preset = '<unknown>') falls back to default with a message", {
  expect_message(
    t <- de_theme(preset = "not-a-real-preset"),
    regexp = "not-a-real-preset"
  )
  expect_s3_class(t, "bs_theme")
})

test_that("startDEBrowser passes deUI as a function reference (not shinyUI(deUI))", {
  # Regression: shinyUI(deUI) calls deUI() at app-construction with no `req`,
  # freezing the UI tag list and silently breaking the ?preset= URL playground.
  # Shiny must receive the function itself so it gets called per-session with
  # the incoming request. See R/startShiny.R.
  src <- deparse(body(startDEBrowser))
  expect_false(
    any(grepl("shinyUI\\s*\\(\\s*deUI", src)),
    info = "startDEBrowser must not wrap deUI in shinyUI() — pass the function"
  )
})
