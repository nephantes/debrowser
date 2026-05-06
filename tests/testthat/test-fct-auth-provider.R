test_that("new_auth_provider builds a valid provider with required fields", {
  p <- new_auth_provider(
    name = "demo",
    identify = function(session) "alice"
  )
  expect_true(is_auth_provider(p))
  expect_equal(p$name, "demo")
  expect_equal(p$identify(NULL), "alice")
  # Optional defaults present
  expect_type(p$wrap_app, "closure")
  expect_type(p$logout, "closure")
  expect_type(p$user_info, "closure")
  expect_identical(p$wrap_app("app-token"), "app-token")  # identity default
  expect_null(p$logout(NULL))                              # no-op default
  expect_equal(p$user_info("any"), list())                 # empty default
})

test_that("new_auth_provider rejects malformed input", {
  expect_error(
    new_auth_provider(name = NULL, identify = function(s) NULL),
    "name"
  )
  expect_error(
    new_auth_provider(name = "x", identify = "not a function"),
    "identify"
  )
  expect_error(
    new_auth_provider(name = "x", identify = function(s) NULL,
                      wrap_app = "not a function"),
    "wrap_app"
  )
})

test_that("is_auth_provider returns FALSE for plain lists", {
  expect_false(is_auth_provider(list(name = "x", identify = function(s) NULL)))
  expect_false(is_auth_provider(NULL))
  expect_false(is_auth_provider(42))
})
