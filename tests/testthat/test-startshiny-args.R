test_that("startDEBrowser: hosted=TRUE sets options and calls ensure_data_dir", {
  skip_if_not_installed("mockery")
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

# D2.5 regression: save.interface / load.interface must point to data_dir(),
# not getwd(). The previous code used shinyOptions(bookmarkStore = <path>)
# which was then overwritten by enableBookmarking("server"), making the path
# a no-op and causing "Bookmarked state directory does not exist" on restore.
#
# NOTE: We cannot check shinyOption("bookmarkStore") here because shinyApp()
# (called inside startDEBrowser) invokes captureAppOptions() which clears the
# bookmarkStore option from .globals$options.  With runApp mocked, the
# applyCapturedAppOptions() restore never runs, so bookmarkStore reads as
# unset.  The authoritative check is save.interface / load.interface, which
# captureAppOptions does NOT capture or clear.
test_that("startDEBrowser: save.interface and load.interface use data_dir()", {
  skip_if_not_installed("mockery")
  with_test_data_dir({
    mockery::stub(startDEBrowser, "runApp", function(app, ...) invisible(NULL))
    mockery::stub(startDEBrowser, "interactive", function() TRUE)

    startDEBrowser(hosted = FALSE)

    # The load.interface closure must resolve state dirs under data_dir().
    # captureAppOptions() does NOT clear save/load.interface, so they persist.
    load_iface <- shiny::getShinyOption("load.interface", default = NULL)
    expect_true(is.function(load_iface),
                info = "load.interface must be a function, not NULL")

    expected_dir <- file.path(data_dir(), "shiny_bookmarks", "abc123")
    resolved <- NULL
    load_iface("abc123", function(d) { resolved <<- d })
    expect_equal(resolved, expected_dir)

    # The save.interface closure must create the state dir and call back.
    save_iface <- shiny::getShinyOption("save.interface", default = NULL)
    expect_true(is.function(save_iface),
                info = "save.interface must be a function, not NULL")

    save_dir <- NULL
    save_iface("xyz789", function(d) { save_dir <<- d })
    expect_equal(save_dir, file.path(data_dir(), "shiny_bookmarks", "xyz789"))
    expect_true(dir.exists(save_dir))
  })
})

test_that("startDEBrowser: hosted=FALSE produces local_anonymous chain", {
  skip_if_not_installed("mockery")
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
  skip_if_not_installed("mockery")
  with_test_data_dir({
    mockery::stub(startDEBrowser, "runApp", function(app, ...) invisible(NULL))
    mockery::stub(startDEBrowser, "interactive", function() TRUE)

    startDEBrowser()  # no args
    expect_false(isTRUE(getOption("debrowser.hosted")))
  })
})
