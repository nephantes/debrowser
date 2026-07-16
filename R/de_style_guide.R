#' Open the DEBrowser design-system style guide
#'
#' Opens the standalone component gallery shipped at
#' `inst/extdata/www/style-guide.html` in the default browser. Every
#' component is rendered from `debrowser.css` in both themes, so it doubles
#' as the client handoff artifact and the visual-regression baseline for the
#' CSS consolidation (see `docs/design/06-handoff-plan.md` and `DESIGN.md`).
#'
#' @param theme one of "light" or "dark" -- sets the initial `data-bs-theme`
#'   via the page's `?theme=` query parameter.
#' @return (invisibly) the path that was opened.
#' @examples
#' \dontrun{
#'   de_style_guide("dark")
#' }
#' @export
de_style_guide <- function(theme = c("light", "dark")) {
  theme <- match.arg(theme)
  path <- system.file("extdata", "www", "style-guide.html", package = "debrowser")
  if (!nzchar(path)) {
    stop("style-guide.html not found in the installed package")
  }
  utils::browseURL(sprintf("%s?theme=%s", path, theme))
  invisible(path)
}
