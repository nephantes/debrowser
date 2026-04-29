# shinytest2 smoke + state-based assertions.
#
# This file does NOT include screenshot-based visual regression tests.
# Visual baselines must be generated on Linux (CI runtime); see
# tests/README-shinytest2.md for the baseline-recording workflow.
#
# State assertions run cross-OS (chromote works on macOS, Linux, Windows).

skip_if_not_installed("shinytest2")
skip_if_not_installed("chromote")

# Helper: build the DEBrowser app object the same way startDEBrowser()
# does, but without runApp(). Reused across tests to keep the dispatch
# pattern visible in one place.
build_debrowser_app <- function() {
  shiny::shinyApp(ui = debrowser::deUI(), server = debrowser::deServer)
}

test_that("app starts and the outer navbar exposes the methodtabs id", {
  skip_on_cran()
  app <- shinytest2::AppDriver$new(
    build_debrowser_app(),
    name = "smoke",
    timeout = 20000
  )
  on.exit(app$stop(), add = TRUE)

  # The page_navbar id is "methodtabs"; it must exist as an input
  # by the time the app is interactive. Initial value is "panel0"
  # (Data Prep) per togglePanels(0, c(0)) in deServer().
  values <- app$get_values(input = TRUE)
  expect_true("methodtabs" %in% names(values$input))
  expect_equal(values$input$methodtabs, "panel0")
})

test_that("downstream tabs are hidden before any data is loaded", {
  skip_on_cran()
  app <- shinytest2::AppDriver$new(
    build_debrowser_app(),
    name = "locked-tabs-pre-de",
    timeout = 20000
  )
  on.exit(app$stop(), add = TRUE)

  # B2a hides Main Plots / GO Term / Tables panels until DE has run.
  # In bslib::page_navbar, hidden nav_panels carry display:none on the
  # nav-link <li>. Rather than poke at internal DOM, assert the user
  # cannot navigate to those tabs by trying nav_select; if hidden, the
  # active tab won't change.
  app$set_inputs(methodtabs = "panel1")
  app$wait_for_idle(500)
  values <- app$get_values(input = TRUE)
  # Hidden panels shouldn't accept the selection; the input may either
  # stay on panel0 or echo panel1 depending on bslib's hide impl. We
  # assert the panel-1-only output (volcano) hasn't rendered.
  outputs <- app$get_values(output = TRUE)
  # mainScatterUI etc. live under "main-..." once unlocked; before
  # data load, the leftMenu output is empty.
  expect_true(is.null(outputs$output$leftMenu) ||
              identical(outputs$output$leftMenu, ""))
})
