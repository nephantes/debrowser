# R/fct_header_auth.R
#
# Reverse-proxy-trust auth provider. Reads the X-Forwarded-User header
# from incoming Shiny session requests, but only when the request
# originates from an IP in `trusted_proxies` (exact match or CIDR
# network). Covers nginx + LDAP, oauth2-proxy + Okta, Apache + Kerberos,
# etc. — any reverse-proxy auth setup that injects an identity header.
#
# Configured at startup via startDEBrowser(trusted_proxies = ...).

#' Construct a header-trust auth provider.
#'
#' @param trusted_proxies Character vector of proxy IPs and/or CIDR
#'   networks (e.g. `c("127.0.0.1", "10.0.0.0/8")`). If empty, the
#'   provider always returns NULL — useful as an opt-out.
#' @keywords internal
#' @noRd
header_auth_provider <- function(trusted_proxies = character(0)) {
  if (!is.character(trusted_proxies)) {
    stop("header_auth_provider: 'trusted_proxies' must be a character vector.")
  }
  trusted_proxies <- trusted_proxies[nzchar(trusted_proxies)]

  identify <- function(session) {
    # Task 6 wires the body. Stub here so the provider is a valid
    # auth_provider object after Task 5; tests that only need the
    # constructor + IP helper pass without identify being functional.
    NULL
  }

  new_auth_provider(
    name = "header_auth",
    identify = identify
  )
}

#' Is `ip` a member of any address or network in `allowlist`?
#'
#' Accepts both exact IPs (`"127.0.0.1"`) and CIDR networks
#' (`"10.0.0.0/8"`) in the allowlist. Returns FALSE for malformed
#' inputs without raising.
#'
#' @param ip character(1). The remote IP to check.
#' @param allowlist character vector. Mix of IPs and CIDRs.
#' @return Logical scalar.
#' @keywords internal
#' @noRd
is_trusted_proxy_ip <- function(ip, allowlist) {
  if (length(allowlist) == 0L) return(FALSE)
  if (length(ip) != 1L || is.na(ip) || !nzchar(ip)) return(FALSE)
  require_pkg("ipaddress", feature = "header-auth IP allowlist")

  parsed_ip <- tryCatch(ipaddress::ip_address(ip),
                        error   = function(e) NULL,
                        warning = function(w) NULL)
  if (is.null(parsed_ip) || is.na(parsed_ip)) return(FALSE)

  for (entry in allowlist) {
    # Try parsing the entry as a CIDR network first; fall back to
    # exact-IP comparison.
    net <- tryCatch(ipaddress::ip_network(entry),
                    error   = function(e) NULL,
                    warning = function(w) NULL)
    if (!is.null(net) && !is.na(net)) {
      if (isTRUE(ipaddress::is_within(parsed_ip, net))) return(TRUE)
      next
    }
    exact <- tryCatch(ipaddress::ip_address(entry),
                      error   = function(e) NULL,
                      warning = function(w) NULL)
    if (!is.null(exact) && !is.na(exact) &&
        isTRUE(parsed_ip == exact)) {
      return(TRUE)
    }
  }
  FALSE
}
