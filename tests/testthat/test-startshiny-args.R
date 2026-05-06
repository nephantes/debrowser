test_that("startDEBrowser: hosted=TRUE sets options and calls ensure_data_dir", {
  with_test_data_dir({
    captured <- list()
    mockery::stub(startDEBrowser, "runApp",
                  function(app, ...) { captured$app <<- app; invisible(NULL) })
    mockery::stub(startDEBrowser, "interactive", function() TRUE)

    startDEBrowser(hosted = TRUE, trusted_proxies = c("127.0.0.1"))

    expect_true(getOption("debrowser.hosted"))
    expect_true(!is.null(getOption("debrowser.auth_chain")))
    expect_true(is_auth_provider(getOption("debrowser.auth_chain")))
    expect_true(dir.exists(data_dir()))
    expect_true(dir.exists(file.path(data_dir(), "shiny_bookmarks")))
    expect_true(dir.exists(file.path(data_dir(), "uploads")))
  })
})

test_that("startDEBrowser: hosted=FALSE produces local_anonymous chain", {
  with_test_data_dir({
    mockery::stub(startDEBrowser, "runApp", function(app, ...) invisible(NULL))
    mockery::stub(startDEBrowser, "interactive", function() TRUE)

    startDEBrowser(hosted = FALSE)
    chain <- getOption("debrowser.auth_chain")
    expect_true(is_auth_provider(chain))
    # local_anonymous always returns "local"
    expect_equal(chain$identify(NULL), "local")
  })
})

test_that("startDEBrowser: defaults are hosted=FALSE, trusted_proxies=character(0)", {
  with_test_data_dir({
    mockery::stub(startDEBrowser, "runApp", function(app, ...) invisible(NULL))
    mockery::stub(startDEBrowser, "interactive", function() TRUE)

    startDEBrowser()  # no args
    expect_false(isTRUE(getOption("debrowser.hosted")))
  })
})
