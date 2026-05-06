test_that("header_auth_provider: constructor accepts character vector", {
  p <- header_auth_provider(trusted_proxies = c("127.0.0.1", "10.0.0.0/8"))
  expect_true(is_auth_provider(p))
  expect_equal(p$name, "header_auth")
})

test_that("header_auth_provider: constructor rejects non-character input", {
  expect_error(header_auth_provider(trusted_proxies = 123),
               "trusted_proxies")
  expect_error(header_auth_provider(trusted_proxies = list("127.0.0.1")),
               "trusted_proxies")
})

test_that("header_auth_provider: empty trusted_proxies is allowed (no-op provider)", {
  p <- header_auth_provider(trusted_proxies = character(0))
  expect_true(is_auth_provider(p))
  # identify will always return NULL (no trusted proxies → no headers honored)
  fake_session <- list(request = list(
    REMOTE_ADDR = "127.0.0.1",
    HTTP_X_FORWARDED_USER = "alice"
  ))
  expect_null(p$identify(fake_session))
})

test_that("is_trusted_proxy_ip: exact-match IPs", {
  skip_if_not_installed("ipaddress")
  expect_true(is_trusted_proxy_ip("127.0.0.1", c("127.0.0.1")))
  expect_true(is_trusted_proxy_ip("10.0.0.5", c("10.0.0.5")))
  expect_false(is_trusted_proxy_ip("10.0.0.6", c("10.0.0.5")))
})

test_that("is_trusted_proxy_ip: CIDR network membership", {
  skip_if_not_installed("ipaddress")
  expect_true(is_trusted_proxy_ip("10.0.0.5", c("10.0.0.0/8")))
  expect_true(is_trusted_proxy_ip("10.255.255.254", c("10.0.0.0/8")))
  expect_false(is_trusted_proxy_ip("11.0.0.1", c("10.0.0.0/8")))
})

test_that("is_trusted_proxy_ip: mix of exact and CIDR", {
  skip_if_not_installed("ipaddress")
  allow <- c("127.0.0.1", "10.0.0.0/8", "192.168.1.1")
  expect_true(is_trusted_proxy_ip("127.0.0.1", allow))
  expect_true(is_trusted_proxy_ip("10.5.5.5", allow))
  expect_true(is_trusted_proxy_ip("192.168.1.1", allow))
  expect_false(is_trusted_proxy_ip("8.8.8.8", allow))
})

test_that("is_trusted_proxy_ip: malformed IP returns FALSE (no error)", {
  skip_if_not_installed("ipaddress")
  expect_false(is_trusted_proxy_ip("not-an-ip", c("10.0.0.0/8")))
  expect_false(is_trusted_proxy_ip(NA_character_, c("10.0.0.0/8")))
  expect_false(is_trusted_proxy_ip("", c("10.0.0.0/8")))
})

test_that("is_trusted_proxy_ip: empty allowlist returns FALSE", {
  expect_false(is_trusted_proxy_ip("127.0.0.1", character(0)))
})
