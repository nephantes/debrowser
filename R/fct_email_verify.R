# R/fct_email_verify.R
#
# Email-verification helpers for the D2.5/D3 hosted-mode signup flow.
#
# Pipeline:
#   1. Signup form passes user+email+password+confirm to validate_signup_input.
#   2. signup_user() generates a token + 24h expiry, stores them on the
#      new users row (email_verified = 0), and calls send_verification_email().
#   3. send_verification_email() delegates to the user-configured
#      `getOption("debrowser.email_sender")` if set; otherwise it logs the
#      verify URL to the R console so the flow works end-to-end without
#      requiring SMTP setup. Admins can wire up blastula / sendmailR /
#      emayili in one line via that option.
#   4. URL ?verify=<token> on the running app triggers
#      consume_email_verify_token() which marks the row verified.
#   5. shinymanager_check_credentials_fn() now refuses login until
#      email_verified == 1, with a helpful error message.

#' Best-effort guess at the app's externally-visible base URL.
#'
#' Used by the signup handler to embed a clickable link in the
#' verification email. Resolution order:
#'   1. `getOption("debrowser.public_url")` -- admin sets this in
#'      production (e.g. https://debrowser.example.org).
#'   2. session$clientData hostname + port + protocol -- the browser
#'      filled this in from window.location; works for everything except
#'      reverse-proxied deployments that strip Host headers.
#'   3. NULL -- caller falls back to a relative `?verify=<token>` URL.
#'
#' @keywords internal
#' @noRd
compose_base_url <- function(session) {
  configured <- getOption("debrowser.public_url", default = NULL)
  if (!is.null(configured) && nzchar(configured)) return(configured)
  cd <- tryCatch(session$clientData, error = function(e) NULL)
  if (is.null(cd)) return(NULL)
  proto <- cd$url_protocol
  host  <- cd$url_hostname
  port  <- cd$url_port
  path  <- cd$url_pathname
  if (is.null(proto) || is.null(host)) return(NULL)
  port_part <- if (!is.null(port) && nzchar(port) &&
                   !(proto == "http:"  && port == "80") &&
                   !(proto == "https:" && port == "443")) {
    paste0(":", port)
  } else ""
  path_part <- if (!is.null(path) && nzchar(path)) sub("/+$", "", path) else ""
  paste0(proto, "//", host, port_part, path_part)
}

#' Generate a URL-safe random token suitable for an email-verification
#' link. 32 random bytes -> 43-char base64url string.
#'
#' Falls back to a less-secure but still unguessable token if `openssl`
#' isn't installed.
#'
#' @keywords internal
#' @noRd
generate_verify_token <- function() {
  if (requireNamespace("openssl", quietly = TRUE)) {
    raw_bytes <- openssl::rand_bytes(32L)
    tok <- openssl::base64_encode(raw_bytes)
  } else {
    # Fallback: 256 bits of randomness from R's PRNG. Worse than openssl
    # but unguessable for practical purposes.
    raw_bytes <- as.raw(sample.int(256L, size = 32L, replace = TRUE) - 1L)
    tok <- paste(format(raw_bytes), collapse = "")
  }
  # Make the token URL-safe (RFC 4648 base64url) and strip padding.
  tok <- gsub("\\+", "-", tok)
  tok <- gsub("/", "_", tok)
  tok <- gsub("=", "", tok)
  tok
}

#' Default token expiry: 24 hours from now, as a Unix timestamp.
#' @keywords internal
#' @noRd
default_verify_expiry <- function(hours = 24L) {
  as.integer(Sys.time()) + as.integer(hours) * 3600L
}

#' Compose and "send" a verification email.
#'
#' "Send" means: if the user set `options(debrowser.email_sender =
#' function(to, subject, body) {...})`, that function is invoked.
#' Otherwise the verification URL is written to the R console with a
#' clearly-marked banner so the admin can copy it out manually.
#'
#' @param email Recipient address (caller validates).
#' @param user_id Display name to include in the message body.
#' @param token The verification token (NOT the full URL).
#' @param base_url App base URL, e.g. `http://127.0.0.1:3838`. If NULL,
#'   the message says "your DEBrowser instance" instead of a clickable
#'   link.
#' @return TRUE on send success (or on console fallback), FALSE on
#'   sender-function error (which the caller may surface to the user).
#' @keywords internal
#' @noRd
send_verification_email <- function(email, user_id, token, base_url = NULL) {
  if (is.null(email) || !nzchar(email)) return(FALSE)

  link <- if (!is.null(base_url) && nzchar(base_url)) {
    sprintf("%s?verify=%s", sub("/+$", "", base_url),
            utils::URLencode(token, reserved = TRUE))
  } else {
    sprintf("?verify=%s", utils::URLencode(token, reserved = TRUE))
  }

  subject <- "Verify your DEBrowser account"
  body <- paste(
    sprintf("Hi %s,", user_id),
    "",
    "Welcome to DEBrowser. To activate your account, please verify your",
    "email address by opening this link in your browser:",
    "",
    link,
    "",
    "The link expires in 24 hours. If you didn't request this account,",
    "you can safely ignore this email.",
    sep = "\n"
  )

  sender <- getOption("debrowser.email_sender", default = NULL)
  if (is.function(sender)) {
    ok <- tryCatch(
      {
        sender(to = email, subject = subject, body = body)
        TRUE
      },
      error = function(e) {
        message("DEBrowser email_sender failed: ", conditionMessage(e))
        FALSE
      }
    )
    return(isTRUE(ok))
  }

  # Console fallback. Helpful in dev; on production, set
  # options(debrowser.email_sender = ...) before startDEBrowser().
  message(
    "\n",
    "============================================================\n",
    "  DEBrowser email verification (console fallback)\n",
    "  To:      ", email, "\n",
    "  User:    ", user_id, "\n",
    "  Subject: ", subject, "\n",
    "  Link:    ", link, "\n",
    "------------------------------------------------------------\n",
    "  Wire `options(debrowser.email_sender = function(to,\n",
    "  subject, body) { ... })` to send real email.\n",
    "============================================================\n"
  )
  TRUE
}

#' Consume a token by marking the matching user row verified.
#'
#' @param token URL-safe token string from `?verify=<token>`.
#' @param now Optional Unix-time override for tests.
#' @return One of `"ok"`, `"unknown_token"`, `"expired"`, `"already_verified"`.
#' @keywords internal
#' @noRd
consume_email_verify_token <- function(token,
                                       now = as.integer(Sys.time())) {
  if (is.null(token) || !nzchar(token)) return("unknown_token")
  con <- tryCatch(user_db_connect(), error = function(e) NULL)
  if (is.null(con)) return("unknown_token")
  on.exit(DBI::dbDisconnect(con), add = TRUE)

  # Pull even already-verified rows so we can disambiguate the user
  # experience: re-clicking a stale link tells them "already verified".
  rows <- DBI::dbGetQuery(con,
    "SELECT user_id, email_verified, email_verify_expires_at
       FROM users WHERE email_verify_token = ? LIMIT 1",
    params = list(token)
  )
  if (nrow(rows) == 0L) {
    # Maybe the token was already consumed; we no longer have a way to
    # disambiguate without storing consumed tokens. Tell the user
    # neutral.
    return("unknown_token")
  }
  row <- as.list(rows[1L, ])
  if (isTRUE(row$email_verified == 1L)) return("already_verified")
  if (!is.na(row$email_verify_expires_at) &&
      row$email_verify_expires_at < now) {
    return("expired")
  }
  user_db_set_email_verified(con, row$user_id)
  "ok"
}
