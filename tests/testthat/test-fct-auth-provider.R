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

test_that("auth_chain: identify returns first non-NULL user_id", {
  none <- new_auth_provider(name = "none", identify = function(s) NULL)
  alice <- new_auth_provider(name = "a", identify = function(s) "alice")
  bob <- new_auth_provider(name = "b", identify = function(s) "bob")

  chain1 <- auth_chain(none, alice, bob)
  expect_equal(chain1$identify(NULL), "alice")

  chain2 <- auth_chain(none, bob)
  expect_equal(chain2$identify(NULL), "bob")

  chain_empty <- auth_chain(none)
  expect_null(chain_empty$identify(NULL))
})

test_that("auth_chain: wrap_app composes left-to-right", {
  outer <- new_auth_provider(
    name = "outer", identify = function(s) NULL,
    wrap_app = function(app) paste0("[outer ", app, " outer]")
  )
  inner <- new_auth_provider(
    name = "inner", identify = function(s) NULL,
    wrap_app = function(app) paste0("(inner ", app, " inner)")
  )
  chain <- auth_chain(outer, inner)
  # inner runs first (as innermost wrapper), outer wraps the result
  expect_equal(chain$wrap_app("APP"), "[outer (inner APP inner) outer]")
})

test_that("auth_chain: logout fan-outs to every provider", {
  calls <- character(0)
  a <- new_auth_provider(
    name = "a", identify = function(s) NULL,
    logout = function(s) {
      calls <<- c(calls, "a")
      invisible(NULL)
    }
  )
  b <- new_auth_provider(
    name = "b", identify = function(s) NULL,
    logout = function(s) {
      calls <<- c(calls, "b")
      invisible(NULL)
    }
  )
  chain <- auth_chain(a, b)
  chain$logout(NULL)
  expect_equal(calls, c("a", "b"))
})

test_that("auth_chain: user_info returns first non-empty result", {
  a <- new_auth_provider(
    name = "a", identify = function(s) NULL,
    user_info = function(uid) list()
  )
  b <- new_auth_provider(
    name = "b", identify = function(s) NULL,
    user_info = function(uid) list(email = paste0(uid, "@x"))
  )
  chain <- auth_chain(a, b)
  expect_equal(chain$user_info("alice")$email, "alice@x")
})

test_that("auth_chain: rejects non-providers", {
  expect_error(auth_chain(list(name = "x")), "auth_provider")
  expect_error(auth_chain("string"), "auth_provider")
})

test_that("auth_chain: name describes the chain", {
  a <- new_auth_provider(name = "alpha", identify = function(s) NULL)
  b <- new_auth_provider(name = "beta",  identify = function(s) NULL)
  chain <- auth_chain(a, b)
  expect_match(chain$name, "alpha")
  expect_match(chain$name, "beta")
})
