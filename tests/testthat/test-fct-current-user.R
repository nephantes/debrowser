make_fake_session_with_userdata <- function(remote_addr = "10.0.0.5",
                                            forwarded_user = "alice") {
  ud <- new.env()
  list(
    userData = ud,
    request = list(
      REMOTE_ADDR = remote_addr,
      HTTP_X_FORWARDED_USER = forwarded_user
    )
  )
}

test_that("build_auth_chain: non-hosted returns just local_anonymous", {
  withr::with_options(list(debrowser.hosted = FALSE), {
    withr::with_envvar(c(DEBROWSER_HOSTED = ""), {
      chain <- build_auth_chain()
      expect_true(is_auth_provider(chain))
      # In non-hosted, every session gets "local"
      s <- make_fake_session_with_userdata()
      expect_equal(chain$identify(s), "local")
    })
  })
})

test_that("build_auth_chain: hosted with header → 'alice'; no header → 'local'", {
  skip_if_not_installed("ipaddress")
  withr::with_options(list(debrowser.hosted = TRUE), {
    chain <- build_auth_chain(trusted_proxies = c("10.0.0.0/8"))
    expect_equal(
      chain$identify(make_fake_session_with_userdata("10.0.0.5", "alice")),
      "alice"
    )
    # Untrusted IP → header is ignored → falls through to local
    expect_equal(
      chain$identify(make_fake_session_with_userdata("8.8.8.8", "alice")),
      "local"
    )
    # No header, trusted IP → falls through to local
    expect_equal(
      chain$identify(make_fake_session_with_userdata("10.0.0.5", "")),
      "local"
    )
  })
})

test_that("current_user: returns chain identify for the session", {
  withr::with_options(list(debrowser.hosted = FALSE), {
    s <- make_fake_session_with_userdata()
    expect_equal(current_user(s), "local")
  })
})

test_that("current_user: memoizes via session$userData", {
  withr::with_options(list(debrowser.hosted = FALSE), {
    s <- make_fake_session_with_userdata()
    expect_equal(current_user(s), "local")
    # Tamper with the cached value to detect memoization on second call
    s$userData$debrowser_auth$user_id <- "memoized"
    expect_equal(current_user(s), "memoized")
  })
})

test_that("current_user: NULL session returns NA_character_", {
  expect_true(is.na(current_user(NULL)))
})

test_that("current_user: handles missing userData by creating it (non-tampering)", {
  withr::with_options(list(debrowser.hosted = FALSE), {
    s <- list(request = list(REMOTE_ADDR = "127.0.0.1"))
    # No userData on the session — current_user should still resolve
    expect_equal(current_user(s), "local")
  })
})

test_that("invalidate_user_cache: clears session$userData$debrowser_auth", {
  s <- list(userData = new.env())
  s$userData$debrowser_auth <- list(user_id = "alice")
  invalidate_user_cache(s)
  expect_null(s$userData$debrowser_auth)
})

test_that("invalidate_user_cache: tolerates NULL session / missing userData", {
  expect_null(invalidate_user_cache(NULL))
  expect_null(invalidate_user_cache(list()))
})

test_that("build_auth_chain: hosted + no proxies => shinymanager + local", {
  withr::with_options(list(debrowser.hosted = TRUE), {
    chain <- build_auth_chain(trusted_proxies = character(0))
    expect_true(is_auth_provider(chain))
    expect_match(chain$name, "shinymanager")
    expect_match(chain$name, "local_anonymous")
  })
})

test_that("build_auth_chain: hosted + proxies => header + local (no shinymanager)", {
  skip_if_not_installed("ipaddress")
  withr::with_options(list(debrowser.hosted = TRUE), {
    chain <- build_auth_chain(trusted_proxies = c("127.0.0.1"))
    expect_match(chain$name, "header_auth")
    expect_false(grepl("shinymanager", chain$name))
  })
})
