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

make_fake_session <- function(remote_addr = "10.0.0.5", forwarded_user = "alice") {
  list(request = list(
    REMOTE_ADDR = remote_addr,
    HTTP_X_FORWARDED_USER = forwarded_user
  ))
}

test_that("header_auth_provider$identify: trusted IP + header => user_id", {
  skip_if_not_installed("ipaddress")
  p <- header_auth_provider(trusted_proxies = c("10.0.0.0/8"))
  expect_equal(p$identify(make_fake_session("10.0.0.5", "alice")), "alice")
})

test_that("header_auth_provider$identify: untrusted IP => NULL", {
  skip_if_not_installed("ipaddress")
  p <- header_auth_provider(trusted_proxies = c("10.0.0.0/8"))
  expect_null(p$identify(make_fake_session("8.8.8.8", "alice")))
})

test_that("header_auth_provider$identify: trusted IP but no header => NULL", {
  skip_if_not_installed("ipaddress")
  p <- header_auth_provider(trusted_proxies = c("10.0.0.0/8"))
  expect_null(p$identify(make_fake_session("10.0.0.5", "")))
  expect_null(p$identify(make_fake_session("10.0.0.5", NULL)))
  # missing field entirely
  s <- list(request = list(REMOTE_ADDR = "10.0.0.5"))
  expect_null(p$identify(s))
})

test_that("header_auth_provider$identify: NULL session / missing request => NULL", {
  skip_if_not_installed("ipaddress")
  p <- header_auth_provider(trusted_proxies = c("10.0.0.0/8"))
  expect_null(p$identify(NULL))
  expect_null(p$identify(list()))
  expect_null(p$identify(list(request = NULL)))
})

test_that("header_auth_provider$identify: empty allowlist => NULL even with header", {
  skip_if_not_installed("ipaddress")
  p <- header_auth_provider(trusted_proxies = character(0))
  expect_null(p$identify(make_fake_session("127.0.0.1", "alice")))
})

test_that("header_auth_provider$identify: trims whitespace and rejects whitespace-only headers", {
  skip_if_not_installed("ipaddress")
  p <- header_auth_provider(trusted_proxies = c("127.0.0.1"))
  expect_equal(p$identify(make_fake_session("127.0.0.1", "  alice  ")), "alice")
  expect_null(p$identify(make_fake_session("127.0.0.1", "   ")))
})

test_that("header_auth_provider: user_info reports kind='header'", {
  skip_if_not_installed("ipaddress")
  p <- header_auth_provider(trusted_proxies = c("127.0.0.1"))
  info <- p$user_info("alice")
  expect_equal(info$kind, "header")
  expect_equal(info$display_name, "alice")
  expect_true(is.na(info$email))
})

test_that("header_auth_provider: user_info handles NULL/NA user_id", {
  skip_if_not_installed("ipaddress")
  p <- header_auth_provider(trusted_proxies = c("127.0.0.1"))
  expect_equal(p$user_info(NULL)$display_name, NA_character_)
  expect_equal(p$user_info(NA)$display_name, NA_character_)
  expect_equal(p$user_info("")$display_name, NA_character_)
})

test_that("auth_chain consults header_auth's user_info before local_anonymous", {
  skip_if_not_installed("ipaddress")
  chain <- auth_chain(
    header_auth_provider(trusted_proxies = c("127.0.0.1")),
    local_anonymous_provider()
  )
  info <- chain$user_info("bob")
  expect_equal(info$kind, "header")
  expect_equal(info$display_name, "bob")
})
