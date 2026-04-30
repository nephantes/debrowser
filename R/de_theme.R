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
#' DEBrowser bslib theme. Default behavior: hand-rolled Slate + OK-blue
#' palette with Inter typography on Bootstrap 5. When `preset` is supplied
#' (e.g. `"zephyr"`, `"lumen"`, `"cosmo"`), returns a preset-only theme so
#' the chosen preset's palette is visible — custom color overrides are
#' dropped; Inter font is kept so typography stays constant across
#' comparisons. Used as the `theme` argument to `bslib::page_navbar()` in
#' [deUI()]. The URL-param playground (`?preset=NAME`) wires this up.
#'
#' @param preset Optional bslib preset name. One of `.de_theme_presets`.
#'   `NULL` (default) returns the standard custom theme.
#' @return a `bs_theme` object
#' @examples
#' x <- de_theme()
#' y <- de_theme(preset = "zephyr")
#' @export
de_theme <- function(preset = NULL) {
  if (!is.null(preset)) {
    return(bslib::bs_theme(
      version      = 5,
      preset       = preset,
      base_font    = bslib::font_google("Inter", local = FALSE),
      heading_font = bslib::font_google("Inter", local = FALSE)
    ))
  }
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
