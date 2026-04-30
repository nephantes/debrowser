# shinytest2 smoke + state-based assertions.
#
# This file does NOT include screenshot-based visual regression tests.
# Visual baselines must be generated on Linux (CI runtime); see
# tests/README-shinytest2.md for the baseline-recording workflow.
#
# State assertions run cross-OS (chromote works on macOS, Linux, Windows).

skip_if_not_installed("shinytest2")
skip_if_not_installed("chromote")

# Skip when Chrome isn't reachable. R-CMD-check workflow installs
# `shinytest2` + `chromote` (because they're in Suggests) but does NOT
# install Chrome — only the dedicated `shinytest2` workflow does.
# Without this guard the AppDriver$new() call below times out at 15s
# and fails 11 tests in R-CMD-check; the dedicated job still covers them.
chrome_path <- tryCatch(chromote::find_chrome(), error = function(e) NULL)
if (is.null(chrome_path)) {
  skip("Chrome not available; shinytest2 covered by dedicated CI job")
}

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
    timeout = 20000,
    load_timeout = 60000
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
    timeout = 20000,
    load_timeout = 60000
  )
  on.exit(app$stop(), add = TRUE)

  # B2a hides Main Plots / GO Term / Tables panels until DE has run.
  # We assert pre-DE state by checking an output that *only* renders
  # after `sel()` is populated by the wizard — `compselectUI` is
  # rendered as NULL when no condSelectServer module is wired, which is
  # the pre-DE state. Checking `leftMenu` was unreliable: getLeftMenu()
  # returns a static `list(conditionalPanel(...))` that always renders
  # an HTML envelope (visibility is client-side via the conditions).
  outputs <- app$get_values(output = TRUE)
  expect_true(is.null(outputs$output$compselectUI) ||
              identical(outputs$output$compselectUI, ""))
})
