test_that("local_anonymous_provider: always returns 'local'", {
  p <- local_anonymous_provider()
  expect_true(is_auth_provider(p))
  expect_equal(p$name, "local_anonymous")
  expect_equal(p$identify(NULL), "local")
  expect_equal(p$identify(list()), "local")
  expect_equal(p$identify("anything"), "local")
})

test_that("local_anonymous_provider: user_info returns kind='local'", {
  p <- local_anonymous_provider()
  info <- p$user_info("local")
  expect_equal(info$kind, "local")
  expect_equal(info$display_name, "Local")
})

test_that("local_anonymous_provider: logout is a no-op", {
  p <- local_anonymous_provider()
  expect_null(p$logout(NULL))
})

test_that("local_anonymous_provider: wrap_app is identity", {
  p <- local_anonymous_provider()
  expect_identical(p$wrap_app("APP"), "APP")
})
