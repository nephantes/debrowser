# R/fct_signup.R
#
# Custom signup flow for D2.5 shinymanager users. shinymanager has its
# own signup UI but it writes to its own SQLite; we want our user_db.
# The form is rendered by mod_account.R; this file holds the
# validation + write helpers.

#' Validate raw form input. Returns NULL on success; a character
#' message on the first failure.
#'
#' @keywords internal
#' @noRd
validate_signup_input <- function(user_id, email,
                                  password, password_confirm) {
  if (is.null(user_id) || !nzchar(trimws(as.character(user_id)))) {
    return("Username is required.")
  }
  if (nchar(user_id) > 64L) {
    return("Username is too long (max 64 chars).")
  }
  if (!grepl("^[A-Za-z0-9_.+-]+$", user_id)) {
    return("Username may only contain letters, digits, and . _ + -")
  }
  if (!is.null(email) && nzchar(trimws(as.character(email)))) {
    if (!grepl("^[^@[:space:]]+@[^@[:space:]]+$", email)) {
      return("Email format is invalid.")
    }
  }
  if (is.null(password) || !nzchar(password)) {
    return("Password is required.")
  }
  if (!identical(password, password_confirm)) {
    return("Passwords do not match.")
  }
  if (nchar(password) < 8L) {
    return("Password must be at least 8 characters long.")
  }
  NULL
}

#' Insert a new shinymanager user row.
#'
#' Errors on duplicate user_id (SQL unique constraint).
#'
#' @keywords internal
#' @noRd
signup_user <- function(con, user_id, email, password) {
  hashed <- hash_password(password)
  if (is.null(hashed)) {
    stop("signup_user: password hashing failed (empty/NULL plaintext).")
  }
  user_db_create_user(con, user_id = user_id,
                      kind = "shinymanager",
                      email = email,
                      hashed_pw = hashed)
  invisible(user_id)
}

#' Create a debrowser user from the R console.
#'
#' Opens \code{users.sqlite}, writes a new \code{kind = "shinymanager"} row,
#' and closes the connection. Use this to bootstrap the first user when
#' running \code{startDEBrowser(hosted = TRUE)} for the first time, since
#' the in-app signup modal lives behind the login wall and is unreachable
#' until you have an account.
#'
#' @param user_id Username for login.
#' @param password Plaintext password (will be hashed via libsodium argon2id).
#' @param email Optional email. Default \code{NA_character_}.
#' @return The created user_id, invisibly.
#' @examples
#' \dontrun{
#' create_debrowser_user("alice", "hunter2!", "alice@example.com")
#' startDEBrowser(hosted = TRUE)  # then log in as alice / hunter2!
#' }
#' @export
create_debrowser_user <- function(user_id, password,
                                  email = NA_character_) {
  err <- validate_signup_input(user_id, email, password, password)
  if (!is.null(err)) stop(err)
  con <- user_db_connect()
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  signup_user(con, user_id = user_id, email = email,
              password = password)
}

#' Reset a debrowser user's password from the R console.
#'
#' Updates the \code{hashed_pw} column for an existing user. Useful when
#' the password is forgotten and there is no admin UI yet.
#'
#' @param user_id Username.
#' @param new_password New plaintext password (hashed before storage).
#' @return TRUE on success; errors if the user does not exist.
#' @examples
#' \dontrun{
#' reset_debrowser_password("alice", "newhunter2!")
#' }
#' @export
reset_debrowser_password <- function(user_id, new_password) {
  if (is.null(user_id) || !nzchar(user_id)) {
    stop("reset_debrowser_password: user_id is required.")
  }
  if (is.null(new_password) || nchar(new_password) < 8L) {
    stop("reset_debrowser_password: password must be at least 8 chars.")
  }
  con <- user_db_connect()
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  row <- user_db_get_user(con, user_id)
  if (is.null(row)) {
    stop(sprintf("reset_debrowser_password: no user '%s'.", user_id))
  }
  hashed <- hash_password(new_password)
  if (is.null(hashed)) {
    stop("reset_debrowser_password: password hashing failed.")
  }
  DBI::dbExecute(con,
    "UPDATE users SET hashed_pw = ? WHERE user_id = ?",
    params = list(hashed, user_id))
  invisible(TRUE)
}
