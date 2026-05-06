# R/fct_auth_provider.R
#
# Auth provider abstraction for D2 hosted mode. Each provider is a flat
# list of closures (identify, wrap_app, logout, user_info) plus a name.
# Providers are composed into a chain via auth_chain() (this file,
# below). D2.4 (account UI) consumes the chain via current_user(session).
#
# Three concrete providers ship in D2:
#   - local_anonymous_provider  — non-hosted mode; user_id is "local".
#   - header_auth_provider      — D2.2; trusts X-Forwarded-User from
#                                 configured proxy IPs.
#   - shinymanager_auth_provider — D2.4 (login UI).
#   - oidc_auth_provider         — D2.5 (Google OIDC native).

#' Construct an auth provider.
#'
#' @param name character(1). Used in logs and chain diagnostics.
#' @param identify function(session) returning a user_id (character(1))
#'   or NULL. NULL means "this provider can't identify the request;
#'   fall through to the next chain member".
#' @param wrap_app function(app) returning a wrapped app object.
#'   Default identity. Used by shinymanager-style providers that need
#'   to wrap the entire UI with a login screen.
#' @param logout function(session) returning NULL. Default no-op.
#'   Called when the user clicks "Sign out". The provider is
#'   responsible for clearing whatever session state it owns.
#' @param user_info function(user_id) returning a list with optional
#'   `email`, `display_name`, `kind` fields. Default empty list.
#' @return A list with class `"debrowser_auth_provider"`.
#' @keywords internal
#' @noRd
new_auth_provider <- function(name,
                              identify,
                              wrap_app = function(app) app,
                              logout = function(session) invisible(NULL),
                              user_info = function(user_id) list()) {
  if (!is.character(name) || length(name) != 1L || !nzchar(name)) {
    stop("new_auth_provider: 'name' must be a non-empty character(1).")
  }
  if (!is.function(identify)) {
    stop("new_auth_provider: 'identify' must be a function(session).")
  }
  if (!is.function(wrap_app)) {
    stop("new_auth_provider: 'wrap_app' must be a function(app).")
  }
  if (!is.function(logout)) {
    stop("new_auth_provider: 'logout' must be a function(session).")
  }
  if (!is.function(user_info)) {
    stop("new_auth_provider: 'user_info' must be a function(user_id).")
  }
  structure(
    list(
      name = name,
      identify = identify,
      wrap_app = wrap_app,
      logout = logout,
      user_info = user_info
    ),
    class = "debrowser_auth_provider"
  )
}

#' Predicate: is `x` an auth provider?
#' @keywords internal
#' @noRd
is_auth_provider <- function(x) {
  inherits(x, "debrowser_auth_provider")
}

#' Compose multiple auth providers into one.
#'
#' Walks providers in argument order. `identify` returns the first
#' non-NULL `user_id`. `wrap_app` composes the providers' wrappers
#' inside-out (first arg is OUTERMOST, last is innermost) — so for a
#' chain `auth_chain(outer, inner)`, the rendered app is
#' `outer$wrap_app(inner$wrap_app(app))`. `logout` fans out to every
#' provider. `user_info` returns the first non-empty result.
#'
#' @param ... `auth_provider` objects (constructed via
#'   [new_auth_provider()]).
#' @return A meta-`auth_provider`.
#' @keywords internal
#' @noRd
auth_chain <- function(...) {
  providers <- list(...)
  for (p in providers) {
    if (!is_auth_provider(p)) {
      stop("auth_chain: every argument must be an auth_provider; got ",
           paste(class(p), collapse = "/"))
    }
  }
  if (length(providers) == 0L) {
    stop("auth_chain: at least one auth_provider is required.")
  }

  identify <- function(session) {
    for (p in providers) {
      uid <- tryCatch(p$identify(session),
                      error = function(e) NULL)
      if (!is.null(uid)) return(uid)
    }
    NULL
  }

  wrap_app <- function(app) {
    # Inside-out: last provider wraps first, first provider wraps last.
    for (p in rev(providers)) {
      app <- p$wrap_app(app)
    }
    app
  }

  logout <- function(session) {
    for (p in providers) {
      tryCatch(p$logout(session), error = function(e) NULL)
    }
    invisible(NULL)
  }

  user_info <- function(user_id) {
    for (p in providers) {
      info <- tryCatch(p$user_info(user_id),
                       error = function(e) list())
      if (length(info) > 0L) return(info)
    }
    list()
  }

  names <- vapply(providers, `[[`, character(1), "name")
  chain_name <- sprintf("chain[%s]", paste(names, collapse = ","))

  new_auth_provider(
    name = chain_name,
    identify = identify,
    wrap_app = wrap_app,
    logout = logout,
    user_info = user_info
  )
}
