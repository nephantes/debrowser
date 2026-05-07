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
