# test-bookmark-module-restore-timing.R
#
# Regression test for D2.3 fix: debrowserdataload must be called
# synchronously in deServer(), not inside observe(), so that
# session$makeScope("load") registers its onRestore bridge on the parent
# session BEFORE Shiny's high-priority (priority=1e6) restore observe fires.
#
# When a module is initialised inside observe() (priority 0), the restore
# observe (priority 1e6) fires on the FIRST flush, before the module has
# been created.  At that point the makeScope bridge has not yet been
# registered, so the module's onRestore callback never gets invoked.
#
# The fix is verified analytically here: we confirm that
# shiny::moduleServer (via callModule -> makeScope) registers an onRestore
# bridge on the *parent* session, and that this bridge is only callable
# after makeScope has been invoked.

test_that("makeScope registers parent onRestore bridge synchronously", {
  library(shiny)

  env <- getNamespace("shiny")
  ss <- get("ShinySession", envir = env)

  # makeScope is a public method of ShinySession.  Confirm it exists and
  # its body references self$onRestore (the bridge-registration side-effect
  # we depend on for correct restore timing).
  expect_true(is.function(ss$public_methods$makeScope))

  body_src <- deparse(body(ss$public_methods$makeScope))
  expect_true(
    any(grepl("self\\$onRestore", body_src)),
    info = "makeScope must register an onRestore bridge on the parent session"
  )
})

test_that("createBookmarkObservers uses priority = 1e6 for restore observe", {
  library(shiny)
  env <- getNamespace("shiny")
  ss <- get("ShinySession", envir = env)

  body_src <- deparse(body(ss$public_methods$createBookmarkObservers))

  # The restore observe must use a non-zero, high priority so it fires
  # before default-priority (0) observers.
  expect_true(
    any(grepl("priority\\s*=\\s*1e\\+?0*6", body_src)) ||
      any(grepl("priority\\s*=\\s*1000000", body_src)),
    info = "The restore observe should have priority 1e6 to fire before normal observers"
  )
})

test_that("debrowserdataload is called outside observe() in deServer", {
  # Parse server.R and verify the call pattern.  We check that the line
  # updata(debrowserdataload("load", ...)) appears OUTSIDE any observe({})
  # wrapper, which is the fix for the timing bug.
  server_path <- system.file("R", "server.R", package = "debrowser")
  if (!nzchar(server_path)) {
    server_path <- file.path(
      find.package("debrowser"), "..", "..", "debrowser", "R", "server.R"
    )
  }
  # Fall back to the source tree when running devtools::test()
  if (!file.exists(server_path)) {
    server_path <- file.path("../../R/server.R")
  }
  if (!file.exists(server_path)) {
    skip("Cannot locate R/server.R for static analysis")
  }

  lines <- readLines(server_path, warn = FALSE)

  # Find the line that calls debrowserdataload
  dl_line_idx <- which(grepl("debrowserdataload\\(", lines))
  expect_true(length(dl_line_idx) >= 1L,
    info = "Expected at least one debrowserdataload() call in server.R"
  )

  dl_line <- dl_line_idx[1]

  # The line must NOT be indented by more than 6 spaces relative to the
  # body of deServer().  Specifically it must NOT be inside an observe({})
  # wrapper -- anything with 8+ spaces of indent is inside observe().
  # We check that no "observe({" block starts before dl_line without a
  # matching closing brace.
  #
  # Simplified check: the debrowserdataload line itself must start
  # with exactly 6 spaces (inside the tryCatch block in deServer, but
  # NOT inside an observe({ ... }) sub-block).
  indent <- nchar(lines[dl_line]) - nchar(trimws(lines[dl_line], "left"))
  expect_true(
    indent <= 6L,
    info = paste0(
      "debrowserdataload() is indented ", indent, " spaces; ",
      "it must be called directly in deServer() body (<=6 spaces), ",
      "not inside observe() (8+ spaces). ",
      "This is the D2.3 restore-timing fix."
    )
  )

  # Also verify the comment explaining the fix is present.
  fix_comment_present <- any(grepl("D2.3 fix", lines))
  expect_true(fix_comment_present,
    info = "The D2.3 fix comment should be present near debrowserdataload()"
  )
})
