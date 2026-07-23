test_that("validate_signup_input: rejects empty user_id", {
  expect_match(
    validate_signup_input("", "a@b", "pw", "pw"),
    "username", ignore.case = TRUE
  )
})

test_that("validate_signup_input: rejects mismatched passwords", {
  expect_match(
    validate_signup_input("alice", "a@b.org", "pw1", "pw2"),
    "match", ignore.case = TRUE
  )
})

test_that("validate_signup_input: rejects short password", {
  expect_match(
    validate_signup_input("alice", "a@b.org", "1234567", "1234567"),
    "8|length|short", ignore.case = TRUE
  )
})

test_that("validate_signup_input: rejects invalid email shape", {
  expect_match(
    validate_signup_input("alice", "not-an-email", "pw1234567", "pw1234567"),
    "email", ignore.case = TRUE
  )
})

test_that("validate_signup_input: returns NULL for valid input", {
  expect_null(validate_signup_input("alice", "a@b.org",
                                     "pw1234567", "pw1234567"))
})

test_that("signup_user: creates the row + hashed_pw", {
  skip_if_not_installed("scrypt")
  with_test_data_dir({
    ensure_data_dir()
    con <- user_db_connect()
    on.exit(DBI::dbDisconnect(con), add = TRUE)
    signup_user(con, "alice", "a@b.org", "hunter2!")
    row <- user_db_get_user(con, "alice")
    expect_equal(row$user_id, "alice")
    expect_equal(row$kind, "shinymanager")
    expect_equal(row$email, "a@b.org")
    expect_true(verify_password("hunter2!", row$hashed_pw))
  })
})

test_that("signup_user: errors on duplicate user_id", {
  skip_if_not_installed("scrypt")
  with_test_data_dir({
    ensure_data_dir()
    con <- user_db_connect()
    on.exit(DBI::dbDisconnect(con), add = TRUE)
    signup_user(con, "alice", "a@b.org", "pw1234567")
    expect_error(signup_user(con, "alice", "a@b.org", "pw1234567"))
  })
})
