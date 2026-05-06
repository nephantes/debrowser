test_that("data_dir() resolves option > env > default", {
  withr::with_options(list(debrowser.data_dir = NULL), {
    withr::with_envvar(c(DEBROWSER_DATA_DIR = ""), {
      # Default path
      expect_equal(
        normalizePath(data_dir(), mustWork = FALSE),
        normalizePath(tools::R_user_dir("debrowser", "data"),
                      mustWork = FALSE)
      )
    })
  })

  withr::with_envvar(c(DEBROWSER_DATA_DIR = "/tmp/dd-env"), {
    withr::with_options(list(debrowser.data_dir = NULL), {
      expect_equal(data_dir(), "/tmp/dd-env")
    })
  })

  withr::with_envvar(c(DEBROWSER_DATA_DIR = "/tmp/dd-env"), {
    withr::with_options(list(debrowser.data_dir = "/tmp/dd-opt"), {
      # option wins over env
      expect_equal(data_dir(), "/tmp/dd-opt")
    })
  })
})

test_that("hosted_mode() resolves option > env, default FALSE", {
  withr::with_options(list(debrowser.hosted = NULL), {
    withr::with_envvar(c(DEBROWSER_HOSTED = ""), {
      expect_false(hosted_mode())
    })
  })

  withr::with_envvar(c(DEBROWSER_HOSTED = "1"), {
    withr::with_options(list(debrowser.hosted = NULL), {
      expect_true(hosted_mode())
    })
  })

  withr::with_options(list(debrowser.hosted = TRUE), {
    expect_true(hosted_mode())
  })
})

test_that("ensure_data_dir() creates the tree and is idempotent", {
  with_test_data_dir({
    p <- ensure_data_dir()
    expect_true(dir.exists(p))
    expect_true(dir.exists(file.path(p, "shiny_bookmarks")))
    expect_true(dir.exists(file.path(p, "uploads")))
    # idempotent
    expect_silent(ensure_data_dir())
  })
})

test_that("with_test_data_dir() restores prior option/env on exit", {
  withr::with_options(list(debrowser.data_dir = "/sentinel"), {
    with_test_data_dir({
      expect_false(identical(getOption("debrowser.data_dir"), "/sentinel"))
    })
    expect_identical(getOption("debrowser.data_dir"), "/sentinel")
  })
})
