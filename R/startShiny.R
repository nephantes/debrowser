#' startDEBrowser
#'
#' Starts the DEBrowser to be able to run interactively.
#'
#' @param hosted Logical. When TRUE, enables hosted-mode behaviors:
#'   auth-provider chain, per-user AI settings (D2.6), bookmark
#'   ownership enforcement (D2.3+). Default FALSE preserves the
#'   single-user desktop launch experience. May also be set via
#'   the `DEBROWSER_HOSTED` env var.
#' @param trusted_proxies Character vector of proxy IPs and CIDR
#'   networks (e.g. `c("127.0.0.1", "10.0.0.0/8")`) whose
#'   `X-Forwarded-User` header is trusted as the authenticated user.
#'   Only used when `hosted = TRUE`. Empty by default.
#'
#' @note \code{startDEBrowser}
#' @return the app
#'
#' @examples
#' \dontrun{
#' startDEBrowser()
#' startDEBrowser(hosted = TRUE,
#'                trusted_proxies = c("127.0.0.1", "10.0.0.0/8"))
#' }
#'
#' @export
#'
startDEBrowser <- function(hosted = FALSE,
                           trusted_proxies = character(0)) {
  if (interactive()) {
    # the upload file size limit is 30MB
    options(
      shiny.maxRequestSize = 90 * 1024^2, warn = -1,
      shiny.sanitize.errors = TRUE
    )
    addResourcePath(
      prefix = "demo", directoryPath =
        system.file("extdata", "demo",
          package = "debrowser"
        )
    )
    addResourcePath(
      prefix = "www", directoryPath =
        system.file("extdata", "www",
          package = "debrowser"
        )
    )
    # D2.2: hosted-mode + auth chain. The option flips behavior across
    # downstream modules; the chain is consulted by current_user(session)
    # at every Shiny session start. ensure_data_dir() makes data_dir()
    # ready for users.sqlite (D2.1) before any module touches it.
    #
    # Precedence: explicit `hosted=` arg > getOption("debrowser.hosted")
    # > DEBROWSER_HOSTED env var. We only stamp the option when the
    # caller passed an explicit value, so a deployment relying on
    # `DEBROWSER_HOSTED=1` keeps working with `startDEBrowser()` (no args).
    if (!missing(hosted)) {
      options(debrowser.hosted = isTRUE(hosted))
    }
    ensure_data_dir()
    # D2.5: capture the chain locally so we can both (a) stash it in the
    # option for current_user() to consume per-session and (b) invoke
    # its wrap_app to install shinymanager::secure_app over deUI when
    # hosted-no-proxies mode is active. Without the wrap_app call, the
    # login wall never appears even when shinymanager_auth_provider is
    # in the chain.
    chain <- build_auth_chain(trusted_proxies = trusted_proxies)
    options(debrowser.auth_chain = chain)

    environment(deServer) <- environment()

    app <- shinyApp(
      ui = chain$wrap_app(deUI),
      server = shinyServer(deServer)
    )
    runApp(app)
  }
}

#' startHeatmap
#'
#' Starts the DEBrowser heatmap
#'
#' @note \code{startHeatmap}
#' @return the app
#'
#' @examples
#' startHeatmap()
#'
#' @export
#'
startHeatmap <- function() {
  if (interactive()) {
    # the upload file size limit is 30MB
    options(
      shiny.maxRequestSize = 30 * 1024^2, warn = -1,
      shiny.sanitize.errors = TRUE
    )
    addResourcePath(
      prefix = "demo", directoryPath =
        system.file("extdata", "demo",
          package = "debrowser"
        )
    )
    addResourcePath(
      prefix = "www", directoryPath =
        system.file("extdata", "www",
          package = "debrowser"
        )
    )
    environment(heatmapServer) <- environment()

    app <- shinyApp(
      ui = shinyUI(heatmapUI),
      server = shinyServer(heatmapServer)
    )
    runApp(app)
  }
}
