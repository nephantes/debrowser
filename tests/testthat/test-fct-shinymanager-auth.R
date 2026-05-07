test_that("shinymanager_auth_provider: returns valid auth_provider", {
  fake_check <- function(user, password) list(result = FALSE)
  p <- shinymanager_auth_provider(check_credentials_fn = fake_check)
  expect_true(is_auth_provider(p))
  expect_equal(p$name, "shinymanager")
})

test_that("shinymanager_auth_provider: identify reads session$userData$user", {
  fake_check <- function(user, password) list(result = FALSE)
  p <- shinymanager_auth_provider(check_credentials_fn = fake_check)
  ud <- new.env()
  ud$user <- list(user = "alice")
  s <- list(userData = ud)
  expect_equal(p$identify(s), "alice")
})

test_that("shinymanager_auth_provider: identify returns NULL for unauth session", {
  fake_check <- function(user, password) list(result = FALSE)
  p <- shinymanager_auth_provider(check_credentials_fn = fake_check)
  expect_null(p$identify(NULL))
  expect_null(p$identify(list()))
  expect_null(p$identify(list(userData = new.env())))
})

test_that("shinymanager_auth_provider: user_info returns kind='shinymanager'", {
  fake_check <- function(user, password) list(result = FALSE)
  p <- shinymanager_auth_provider(check_credentials_fn = fake_check)
  info <- p$user_info("alice")
  expect_equal(info$kind, "shinymanager")
  expect_equal(info$display_name, "alice")
  expect_true(is.na(info$email))
})

test_that("shinymanager_auth_provider: wrap_app callable", {
  fake_check <- function(user, password) list(result = FALSE)
  p <- shinymanager_auth_provider(check_credentials_fn = fake_check)
  result <- tryCatch(p$wrap_app("APP"), error = function(e) NULL)
  expect_true(!is.null(result))
})

test_that("shinymanager_check_credentials_fn: valid creds => result=TRUE", {
  skip_if_not_installed("sodium")
  with_test_data_dir({
    ensure_data_dir()
    con <- user_db_connect()
    user_db_create_user(con, "alice", "shinymanager",
                        hashed_pw = hash_password("hunter2"))
    DBI::dbDisconnect(con)

    f <- shinymanager_check_credentials_fn()
    res <- f("alice", "hunter2")
    expect_true(isTRUE(res$result))
    expect_equal(res$user_info$user, "alice")
  })
})

test_that("shinymanager_check_credentials_fn: wrong password => result=FALSE", {
  skip_if_not_installed("sodium")
  with_test_data_dir({
    ensure_data_dir()
    con <- user_db_connect()
    user_db_create_user(con, "alice", "shinymanager",
                        hashed_pw = hash_password("hunter2"))
    DBI::dbDisconnect(con)

    f <- shinymanager_check_credentials_fn()
    expect_false(isTRUE(f("alice", "wrong")$result))
  })
})

test_that("shinymanager_check_credentials_fn: unknown user => result=FALSE", {
  skip_if_not_installed("sodium")
  with_test_data_dir({
    ensure_data_dir()
    f <- shinymanager_check_credentials_fn()
    expect_false(isTRUE(f("ghost", "any")$result))
  })
})

test_that("shinymanager_check_credentials_fn: rejects non-shinymanager kind", {
  skip_if_not_installed("sodium")
  with_test_data_dir({
    ensure_data_dir()
    con <- user_db_connect()
    user_db_create_user(con, "alice", "header")
    DBI::dbDisconnect(con)

    f <- shinymanager_check_credentials_fn()
    expect_false(isTRUE(f("alice", "any")$result))
  })
})
