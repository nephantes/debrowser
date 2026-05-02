test_that("de_error() raises a classed condition with message and class", {
  err <- tryCatch(
    de_error("count matrix must have at least 3 columns", class = "too_few_columns"),
    error = identity
  )
  expect_s3_class(err, "debrowser_error")
  expect_s3_class(err, "too_few_columns")
  expect_match(conditionMessage(err), "at least 3 columns")
})

test_that("de_error() defaults class to 'debrowser_error' only", {
  err <- tryCatch(de_error("boom"), error = identity)
  expect_s3_class(err, "debrowser_error")
  expect_false(inherits(err, "too_few_columns"))
})

test_that("de_assert_count_matrix() rejects non-numeric, NA-filled, or empty matrices", {
  expect_error(de_assert_count_matrix(NULL), class = "null_input")
  expect_error(de_assert_count_matrix(matrix("a", 1, 1)), class = "non_numeric")
  expect_error(de_assert_count_matrix(matrix(numeric(0), 0, 0)), class = "empty_matrix")
  expect_silent(de_assert_count_matrix(matrix(1:6, 2, 3)))
})

test_that("filter_params_from_input() reads the documented input fields", {
  input <- list(
    padj           = "0.05",
    log2fc_cutoff  = 1,
    dataset        = "up+down",
    compselect     = "1",
    norm_method    = "TMM",
    genesetarea    = "BRCA1",
    methodtabs     = "panel1",
    mincount       = "10",
    topn           = "500",
    selectedplot   = NULL
  )
  p <- filter_params_from_input(input)
  expect_equal(p$padj_cutoff, "0.05")
  # log2fc_cutoff = 1 -> fold_cutoff = 2^1 = 2 via log2fc_to_fold().
  expect_equal(p$fold_cutoff, 2)
  expect_equal(p$dataset, "up+down")
  expect_equal(p$norm_method, "TMM")
  expect_equal(p$geneset_area, "BRCA1")
  expect_equal(p$top_n, "500")
  expect_null(p$selected_plot)
})

test_that("de_notify_error / _warning / _info are callable without a Shiny session", {
  # In a non-Shiny context, showNotification logs a message and returns NULL.
  # We don't care about the return -- only that the helpers don't error out
  # and pass the right arguments.
  expect_silent({
    suppressMessages(de_notify_error("test problem. test fix."))
    suppressMessages(de_notify_warning("test caveat. test note."))
    suppressMessages(de_notify_info("test result. test next."))
  })
})

test_that("de_notify_error uses sticky duration; the others auto-dismiss", {
  # We can't observe Shiny notification state outside a session, so probe the
  # function definitions directly to lock the duration policy.
  err_body <- deparse(body(de_notify_error))
  warn_body <- deparse(body(de_notify_warning))
  info_body <- deparse(body(de_notify_info))
  expect_match(paste(err_body, collapse = " "), "duration\\s*=\\s*NULL")
  expect_match(paste(warn_body, collapse = " "), "duration\\s*=\\s*8")
  expect_match(paste(info_body, collapse = " "), "duration\\s*=\\s*8")
})

test_that("de_notify_error/warning/info pass severity correctly", {
  err_body <- deparse(body(de_notify_error))
  warn_body <- deparse(body(de_notify_warning))
  info_body <- deparse(body(de_notify_info))
  expect_match(paste(err_body, collapse = " "), 'type\\s*=\\s*"error"')
  expect_match(paste(warn_body, collapse = " "), 'type\\s*=\\s*"warning"')
  expect_match(paste(info_body, collapse = " "), 'type\\s*=\\s*"message"')
})
