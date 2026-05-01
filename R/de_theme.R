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

# Bootswatch presets only (excludes the two bslib built-ins that don't have
# a CDN equivalent). The URL-param playground in `deUI()` injects the CDN
# stylesheet for these so each tab gets a unique URL — sidesteps bslib's
# global resource-path collision when multiple presets are compiled in one
# Shiny process.
.de_bootswatch_presets <- setdiff(.de_theme_presets, c("bootstrap", "shiny"))

#' Build a bootswatch CDN <link> tag for a given preset
#'
#' Returns NULL when `preset` is NULL, "bootstrap", or "shiny" (no CDN
#' counterpart). Otherwise returns a `<link rel="stylesheet">` pointing at
#' `https://bootswatch.com/5/<preset>/bootstrap.min.css`. Used by `deUI()`.
#'
#' @param preset bslib preset name or NULL.
#' @return an `htmltools::tag` or NULL.
#' @keywords internal
de_bootswatch_link <- function(preset) {
  if (is.null(preset) || !preset %in% .de_bootswatch_presets) return(NULL)
  htmltools::tags$link(
    rel  = "stylesheet",
    href = sprintf("https://bootswatch.com/5/%s/bootstrap.min.css", preset)
  )
}

#' de_theme
#'
#' DEBrowser bslib theme. Default behavior: hand-rolled Slate + OK-blue
#' palette with Inter typography on Bootstrap 5. When `preset` is supplied
#' (e.g. `"zephyr"`, `"lumen"`, `"cosmo"`), returns a bare Bootstrap 5
#' theme with only Inter font applied — preset-specific colors come from
#' the bootswatch CDN stylesheet that `deUI()` injects separately, so
#' each preset URL is unique and tabs don't collide on the same compiled
#' bootstrap.min.css. Used as the `theme` argument to `bslib::page_navbar()`
#' in [deUI()]. The URL-param playground (`?preset=NAME`) wires this up.
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
    if (!preset %in% .de_theme_presets) {
      message(sprintf(
        "de_theme(): unknown preset '%s'. Valid presets: %s. Falling back to default theme.",
        preset, paste(.de_theme_presets, collapse = ", ")
      ))
      preset <- NULL
    }
  }
  if (!is.null(preset)) {
    return(bslib::bs_theme(
      version      = 5,
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
