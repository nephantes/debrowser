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
                                  password, password_confirm,
                                  require_email = TRUE,
                                  accept_terms = NULL,
                                  accept_privacy = NULL,
                                  accept_cookies = NULL) {
  if (is.null(user_id) || !nzchar(trimws(as.character(user_id)))) {
    return("Username is required.")
  }
  if (nchar(user_id) > 64L) {
    return("Username is too long (max 64 chars).")
  }
  if (!grepl("^[A-Za-z0-9_.+-]+$", user_id)) {
    return("Username may only contain letters, digits, and . _ + -")
  }
  email_present <- !is.null(email) && nzchar(trimws(as.character(email)))
  if (require_email && !email_present) {
    return("Email is required for account verification.")
  }
  if (email_present) {
    # Slightly stricter: require a dot in the domain so single-word
    # internal addresses fail (most signup forms expect a public-ish
    # mailbox we can deliver verification to).
    if (!grepl("^[^@[:space:]]+@[^@[:space:]]+\\.[^@[:space:]]+$", email)) {
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
  # Consent: arguments default to NULL so the helper stays compatible
  # with non-Shiny callers (e.g. create_debrowser_user()). When the
  # caller passes the flags, all three must be TRUE.
  if (!is.null(accept_terms) && !isTRUE(accept_terms)) {
    return("You must accept the Terms of Service to create an account.")
  }
  if (!is.null(accept_privacy) && !isTRUE(accept_privacy)) {
    return("You must accept the Privacy Policy to create an account.")
  }
  if (!is.null(accept_cookies) && !isTRUE(accept_cookies)) {
    return("You must accept the Cookie Policy to create an account.")
  }
  NULL
}

#' Insert a new shinymanager user row.
#'
#' Errors on duplicate user_id (SQL unique constraint).
#'
#' @keywords internal
#' @noRd
signup_user <- function(con, user_id, email, password,
                        base_url = NULL,
                        require_verification = TRUE,
                        accept_terms = FALSE,
                        accept_privacy = FALSE,
                        accept_cookies = FALSE) {
  hashed <- hash_password(password)
  if (is.null(hashed)) {
    stop("signup_user: password hashing failed (empty/NULL plaintext).")
  }
  email_norm <- if (is.null(email) || !nzchar(email)) NA_character_ else email

  token <- NA_character_
  expires_at <- NA_integer_
  sent_at <- NA_integer_
  verified_flag <- 1L
  if (isTRUE(require_verification) && !is.na(email_norm)) {
    token <- generate_verify_token()
    expires_at <- default_verify_expiry()
    sent_at <- as.integer(Sys.time())
    verified_flag <- 0L
  }

  now <- as.integer(Sys.time())
  ts_or_na <- function(b) if (isTRUE(b)) now else NA_integer_
  user_db_create_user(con,
                      user_id = user_id,
                      kind = "shinymanager",
                      email = email_norm,
                      hashed_pw = hashed,
                      email_verified = verified_flag,
                      email_verify_token = token,
                      email_verify_expires_at = expires_at,
                      email_verify_sent_at = sent_at,
                      terms_accepted_at = ts_or_na(accept_terms),
                      privacy_accepted_at = ts_or_na(accept_privacy),
                      cookies_accepted_at = ts_or_na(accept_cookies))

  # Side-effect: send the verification email (or log it in console
  # fallback mode). Failure here doesn't roll back the user row -- the
  # admin can call resend_verification_email(user_id) to retry.
  if (isTRUE(require_verification) && !is.na(email_norm)) {
    send_verification_email(email = email_norm,
                            user_id = user_id,
                            token = token,
                            base_url = base_url)
  }

  invisible(list(user_id = user_id,
                 email_verified = as.logical(verified_flag),
                 verify_required = isTRUE(require_verification) &&
                                   !is.na(email_norm)))
}

#' Re-send the verification email for an existing unverified user.
#'
#' Generates a fresh token + 24h expiry and pushes a new send. Safe to
#' call repeatedly -- each call invalidates any previous link.
#'
#' @param user_id Username.
#' @param base_url Optional app base URL (used to build the verify link).
#' @return TRUE on success; errors if user is unknown or already verified.
#' @export
resend_verification_email <- function(user_id, base_url = NULL) {
  con <- user_db_connect()
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  row <- user_db_get_user(con, user_id)
  if (is.null(row)) {
    stop(sprintf("resend_verification_email: no user '%s'.", user_id))
  }
  if (isTRUE(row$email_verified == 1L)) {
    stop(sprintf("User '%s' is already verified.", user_id))
  }
  if (is.na(row$email) || !nzchar(row$email)) {
    stop(sprintf("User '%s' has no email on file.", user_id))
  }
  token <- generate_verify_token()
  expires_at <- default_verify_expiry()
  user_db_set_email_verify_token(con, user_id, token, expires_at)
  send_verification_email(email = row$email, user_id = user_id,
                          token = token, base_url = base_url)
  invisible(TRUE)
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
#' \donttest{
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
#' \donttest{
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
