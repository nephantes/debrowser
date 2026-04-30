# Valid bslib preset names (Bootstrap 5 + Bootswatch + shiny default).
# Used by `de_theme()` to validate the `preset` argument and by the URL-
# param playground in `deUI()`. See `?bslib::bs_theme` for the source list.
.de_theme_presets <- c(
  "bootstrap", "shiny",
  "cerulean", "cosmo", "cyborg", "darkly", "flatly", "journal", "litera",
  "lumen", "lux", "materia", "minty", "morph", "pulse", "quartz",
  "sandstone", "simplex", "sketchy", "slate", "solar", "spacelab",
  "superhero", "united", "vapor", "yeti", "zephyr"
)

#' de_theme
#'
#' DEBrowser bslib theme — Slate + OK-blue, Bootstrap 5, Inter typography.
#' Used as the `theme` argument to `bslib::page_navbar()` in [deUI()].
#'
#' @return a `bs_theme` object
#' @examples
#' x <- de_theme()
#' @export
de_theme <- function() {
  bslib::bs_theme(
    version       = 5,
    bg            = "#ffffff",
    fg            = "#0f172a",
    primary       = "#0369a1",
    secondary     = "#64748b",
    success       = "#16a34a",
    danger        = "#dc2626",
    warning       = "#d97706",
    info          = "#0891b2",
    "navbar-bg"                 = "#0f172a",
    "navbar-dark-color"         = "#cbd5e1",
    "navbar-dark-hover-color"   = "#7dd3fc",
    "navbar-dark-active-color"  = "#7dd3fc",
    base_font     = bslib::font_google("Inter", local = FALSE),
    heading_font  = bslib::font_google("Inter", local = FALSE)
  )
}
