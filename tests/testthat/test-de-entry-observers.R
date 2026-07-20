# Regression tests for the DE-entry observers in R/server.R:
# observeEvent(input$goDEFromFilter) and observeEvent(input$goDE).
#
# Both mount condSelectServer() with the batch-corrected count and then
# read sel()$n_comparisons(). condSelectServer() returns NULL whenever
# that count is NULL -- the batch-effect module exists but was never
# submitted (BatchEffect() -> NULL), or there is no batch at all. The
# read then evaluates NULL$n_comparisons() -> NULL() and Shiny logs
# "attempt to apply non-function", silently aborting the rest of the
# observer so choicecounter$nc is never set. These tests pin the guarded
# behavior on both the NULL-count path and the normal path.

skip_if_not_installed("shiny")

# Fire a DE-entry button inside deServer with batch()$BatchEffect()
# returning `batcheffect`. Captures stderr (where Shiny prints swallowed
# observer errors) and reports the resulting counter/module state.
fire_de_entry <- function(input_id, batcheffect) {
  err <- character(0); nc <- NA; sel_ok <- NA
  con <- textConnection("err", "w", local = TRUE)
  sink(con, type = "message")
  on.exit({ suppressWarnings(sink(type = "message")); close(con) }, add = TRUE)
  shiny::testServer(debrowser::deServer, {
    batch(list(BatchEffect = shiny::reactive(batcheffect)))
    filtd(NULL)
    session$setInputs(!!input_id := 1)
    session$flushReact()
    nc <<- choicecounter$nc
    sel_ok <<- !is.null(sel()) && is.function(sel()$n_comparisons)
  })
  suppressWarnings(sink(type = "message")); close(con); on.exit()
  list(err = paste(err, collapse = "\n"), nc = nc, sel_ok = sel_ok)
}

test_that("goDE / goDEFromFilter survive a NULL batch-corrected count", {
  for (id in c("goDE", "goDEFromFilter")) {
    r <- fire_de_entry(id, NULL)  # BatchEffect() -> NULL -> $count is NULL
    expect_false(
      grepl("attempt to apply non-function", r$err, fixed = TRUE),
      info = id
    )
    expect_equal(r$nc, 0)  # left at its safe initial value, not crashed past
  }
})

test_that("goDE / goDEFromFilter mount condSelect for a valid count", {
  cnt <- matrix(as.integer(c(100, 200, 10, 12, 40, 60,
                             30, 50, 70, 5, 8, 11)),
                nrow = 3,
                dimnames = list(c("G1", "G2", "G3"),
                                c("s1", "s2", "s3", "s4")))
  meta <- data.frame(Sample = c("s1", "s2", "s3", "s4"),
                     Condition = c("Ctrl", "Ctrl", "Treat", "Treat"),
                     stringsAsFactors = FALSE)
  for (id in c("goDE", "goDEFromFilter")) {
    r <- fire_de_entry(id, list(count = cnt, meta = meta))
    expect_false(
      grepl("attempt to apply non-function", r$err, fixed = TRUE),
      info = id
    )
    expect_true(r$sel_ok, info = id)
    expect_equal(r$nc, 1)  # condSelectServer starts with one comparison
  }
})
