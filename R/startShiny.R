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
#' @param port Integer TCP port to bind. Default `3838` matches the
#'   shiny-server convention so bookmark URLs stay stable across
#'   restarts (essential for `?_state_id_=...` links the user copies
#'   from the share modal). Pass `NULL` to let Shiny pick a random
#'   free port (legacy behavior).
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
                           trusted_proxies = character(0),
                           port = 3838) {
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

    # D2.3 / D2.5 fix: enableBookmarking + bookmark-store path MUST be
    # set BEFORE shinyApp() is constructed -- Shiny captures the bookmark
    # path at app-init time, not per-session.
    #
    # ROOT CAUSE (D2.5 audit): Shiny's save/load path is NOT controlled by
    # the bookmarkStore shinyOption value -- that option only holds the store
    # TYPE ("server", "url", or "disable"). The actual directory is derived
    # from getShinyOption("appDir", default = getwd()), which is captured by
    # captureAppOptions() as getwd() at shinyApp() construction time and
    # cannot be overridden via shinyOptions(bookmarkStore = <path>).
    #
    # The previous code set bookmarkStore to a path string, then immediately
    # called enableBookmarking("server") which OVERWROTE it with "server".
    # The net effect was that saves and loads both fell through to the
    # loadInterfaceLocal / saveInterfaceLocal defaults using getwd(), not
    # data_dir() -- so bookmarks landed in the working directory instead of
    # the user's data directory, and restores failed with "Bookmarked state
    # directory does not exist."
    #
    # FIX: set save.interface and load.interface shinyOptions to custom
    # closures that use data_dir(). These keys are NOT captured or reset by
    # captureAppOptions(), so they persist across the full app lifecycle and
    # are consulted FIRST by both saveShinySaveState() and
    # RestoreContext$loadStateQueryString() before falling through to the
    # default local-file implementations.
    shiny::enableBookmarking("server")
    local({
      bm_dir <- file.path(data_dir(), "shiny_bookmarks")
      shiny::shinyOptions(
        save.interface = function(id, callback) {
          state_dir <- file.path(bm_dir, id)
          if (!dir.exists(state_dir)) {
            dir.create(state_dir, recursive = TRUE, showWarnings = FALSE)
          }
          callback(state_dir)
        },
        load.interface = function(id, callback) {
          callback(file.path(bm_dir, id))
        }
      )
    })
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
    # `port = NULL` lets Shiny pick a free port (legacy); explicit
    # integer pins the port for stable bookmark URLs.
    if (is.null(port)) {
      runApp(app)
    } else {
      runApp(app, port = as.integer(port))
    }
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
