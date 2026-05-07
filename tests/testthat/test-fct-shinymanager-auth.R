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
