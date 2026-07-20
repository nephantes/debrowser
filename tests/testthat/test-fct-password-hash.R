test_that("hash_password / verify_password: round-trip correct", {
  skip_if_not_installed("sodium")
  pw <- "correct horse battery staple"
  h <- hash_password(pw)
  expect_true(is.character(h))
  expect_true(nzchar(h))
  expect_true(verify_password(pw, h))
})

test_that("verify_password: wrong password returns FALSE", {
  skip_if_not_installed("sodium")
  h <- hash_password("hunter2")
  expect_false(verify_password("hunter3", h))
  expect_false(verify_password("HUNTER2", h))
})

test_that("hash_password: NULL or empty returns NULL", {
  skip_if_not_installed("sodium")
  expect_null(hash_password(NULL))
  expect_null(hash_password(""))
  expect_null(hash_password(NA_character_))
})

test_that("verify_password: NULL/empty/NA inputs return FALSE", {
  skip_if_not_installed("sodium")
  h <- hash_password("hunter2")
  expect_false(verify_password(NULL, h))
  expect_false(verify_password("hunter2", NULL))
  expect_false(verify_password("hunter2", ""))
  expect_false(verify_password(NA_character_, h))
  expect_false(verify_password("hunter2", NA_character_))
})

test_that("hash_password: same input produces different hashes (salt)", {
  skip_if_not_installed("sodium")
  pw <- "hunter2"
  expect_false(identical(hash_password(pw), hash_password(pw)))
})
