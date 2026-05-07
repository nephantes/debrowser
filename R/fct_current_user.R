# R/fct_current_user.R
#
# Per-session identity resolution for D2 hosted mode. Composes the
# AuthProvider chain selected by hosted_mode() and per-deployment config,
# memoizes the resolved user_id in session$userData. Consumed by
# bookmark hooks (D2.3+), AI settings (D2.6), and the account UI (D2.4).

#' Build the AuthProvider chain for the current process.
#'
#' Resolves [hosted_mode()] and constructs the appropriate chain:
#' - Non-hosted: a single `local_anonymous_provider()`.
#' - Hosted: `auth_chain(header_auth_provider(trusted_proxies),
#'           local_anonymous_provider())`. Header trust is applied first;
#'   when no upstream proxy injects a user, the chain falls through to
#'   `"local"` so the app remains functional during deployment setup
#'   (shinymanager and OIDC providers slot in at D2.4 / D2.5).
#'
#' @param trusted_proxies See [header_auth_provider()].
#' @keywords internal
#' @noRd
build_auth_chain <- function(trusted_proxies = character(0)) {
  if (!hosted_mode()) {
    return(local_anonymous_provider())
  }
  if (length(trusted_proxies) > 0L) {
    return(auth_chain(
      header_auth_provider(trusted_proxies = trusted_proxies),
      local_anonymous_provider()
    ))
  }
  # Hosted, no proxies => shinymanager provides the login wall.
  auth_chain(
    shinymanager_auth_provider(
      check_credentials_fn = shinymanager_check_credentials_fn()
    ),
    local_anonymous_provider()
  )
}

#' Resolve the current session's user_id, memoized per session.
#'
#' Called from `deServer` and downstream module servers. Returns
#' `NA_character_` only for NULL sessions (test scaffolding); production
#' Shiny sessions always have a `userData` environment.
#'
#' @param session The Shiny session object.
#' @param chain Optional override (defaults to [build_auth_chain()]
#'   with no proxy allowlist — the app's startShiny.R passes the
#'   configured chain via getOption("debrowser.auth_chain") in normal
#'   operation).
#' @keywords internal
#' @noRd
current_user <- function(session,
                         chain = getOption("debrowser.auth_chain",
                                           default = build_auth_chain())) {
  if (is.null(session)) return(NA_character_)
  ud <- session$userData
  if (is.null(ud)) {
    ud <- new.env()
    session$userData <- ud
  }
  if (is.null(ud$debrowser_auth)) {
    ud$debrowser_auth <- list()
  }
  cached <- ud$debrowser_auth$user_id
  if (!is.null(cached)) return(cached)
  uid <- chain$identify(session)
  if (is.null(uid)) uid <- "local"   # safety floor — should never hit
  ud$debrowser_auth$user_id <- uid
  uid
}

#' Clear the per-session user_id memoization. Called after logout so
#' the next current_user(session) re-resolves the auth chain (which
#' should now return NULL from shinymanager and fall through).
#' @keywords internal
#' @noRd
invalidate_user_cache <- function(session) {
  if (is.null(session) || is.null(session$userData)) return(invisible(NULL))
  session$userData$debrowser_auth <- NULL
  invisible(NULL)
}
