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
    options(debrowser.hosted = isTRUE(hosted))
    ensure_data_dir()
    options(debrowser.auth_chain =
              build_auth_chain(trusted_proxies = trusted_proxies))

    environment(deServer) <- environment()

    app <- shinyApp(
      ui = deUI,
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
