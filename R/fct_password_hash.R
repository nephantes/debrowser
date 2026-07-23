# R/fct_password_hash.R
#
# Password hashing for D2.5 shinymanager-backed auth. scrypt's
# hashPassword is the same primitive shinymanager itself stores, with
# library-default cost parameters; the resulting string carries the
# algorithm + salt + cost inline so re-verification needs no
# out-of-band state.
#
# Used by R/fct_signup.R (signup_user) and R/fct_shinymanager_auth.R
# (check_credentials_fn).

#' Hash a plaintext password via scrypt.
#'
#' @param plaintext Character(1). NULL / empty / NA returns NULL.
#' @return Character(1) password hash, or NULL.
#' @keywords internal
#' @noRd
hash_password <- function(plaintext) {
  if (is.null(plaintext)) return(NULL)
  if (length(plaintext) != 1L) return(NULL)
  if (is.na(plaintext)) return(NULL)
  if (!nzchar(plaintext)) return(NULL)
  require_pkg("scrypt", feature = "password hashing")
  scrypt::hashPassword(plaintext)
}

#' Verify a plaintext password against a stored hash.
#'
#' @param plaintext Character(1). NULL / NA / empty returns FALSE.
#' @param hashed Character(1). NULL / NA / empty returns FALSE.
#' @return Logical(1).
#' @keywords internal
#' @noRd
verify_password <- function(plaintext, hashed) {
  if (is.null(plaintext) || is.null(hashed)) return(FALSE)
  if (length(plaintext) != 1L || length(hashed) != 1L) return(FALSE)
  if (is.na(plaintext) || is.na(hashed)) return(FALSE)
  if (!nzchar(plaintext) || !nzchar(hashed)) return(FALSE)
  require_pkg("scrypt", feature = "password hashing")
  # verifyPassword signals on a malformed/foreign hash rather than
  # returning FALSE; a bad stored hash is a failed login, not an error.
  isTRUE(tryCatch(scrypt::verifyPassword(hashed, plaintext),
                  error = function(e) FALSE))
}
