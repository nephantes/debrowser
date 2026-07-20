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
# stylesheet for these so each tab gets a unique URL -- sidesteps bslib's
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

#' Parse the debrowser_preset value out of an HTTP Cookie header
#'
#' Returns NULL when the cookie is missing or empty. Used by `deUI()` so
#' the preset choice from the navbar picker persists across page reloads.
#'
#' @param cookie_header value of `req$HTTP_COOKIE` (string or NULL).
#' @return a single string (preset name) or NULL.
#' @keywords internal
parse_preset_cookie <- function(cookie_header) {
  if (is.null(cookie_header) || !nzchar(cookie_header)) return(NULL)
  parts <- strsplit(cookie_header, "; *", perl = TRUE)[[1]]
  for (kv in parts) {
    eq <- regexpr("=", kv, fixed = TRUE)
    if (eq < 1) next
    name <- substr(kv, 1, eq - 1)
    if (name == "debrowser_preset") {
      val <- substr(kv, eq + 1, nchar(kv))
      val <- utils::URLdecode(val)
      return(if (nzchar(val)) val else NULL)
    }
  }
  NULL
}

#' Render the navbar preset picker
#'
#' Compact native `<select>` styled with standard Bootstrap classes
#' (`form-select form-select-sm`) -- no custom classes. Sits next to the
#' dark-mode toggle in `deUI()`. The `change` event is wired in JS to
#' write a `debrowser_preset` cookie and reload (see `de_preset_js()`).
#'
#' @param current Currently active preset name, or NULL for default.
#' @return an `htmltools::tag` (`<select>`).
#' @keywords internal
de_preset_picker <- function(current = NULL) {
  mk_opt <- function(value, label, sel) {
    htmltools::tags$option(
      value = value, label,
      selected = if (sel) NA else NULL
    )
  }
  options <- list(mk_opt("", "Default", is.null(current)))
  for (p in .de_bootswatch_presets) {
    options <- c(options, list(mk_opt(p, p, !is.null(current) && current == p)))
  }
  htmltools::tags$select(
    id = "de_preset_picker",
    class = "form-select form-select-sm",
    style = "width:auto;max-width:9rem;background-color:rgba(255,255,255,0.15);color:#fff;border:1px solid rgba(255,255,255,0.25);",
    title = "Theme preset (saved per browser)",
    options
  )
}

#' Tiny JS that wires the preset picker to a cookie
#'
#' On change of `#de_preset_picker`: writes a `debrowser_preset` cookie
#' (1-year expiry, path /) -- or deletes it when the user picks "Default" --
#' strips any `?preset=` from the current URL, and reloads. Uses standard
#' DOM APIs and jQuery's delegated event binding (already in Shiny).
#'
#' @return an `htmltools::tag` (`<script>`).
#' @keywords internal
de_preset_js <- function() {
  htmltools::tags$script(htmltools::HTML(
    "(function(){
       function setCookie(n,v,d){var x=new Date();x.setTime(x.getTime()+d*864e5);
         document.cookie=n+'='+encodeURIComponent(v)+';expires='+x.toUTCString()+';path=/';}
       function delCookie(n){
         document.cookie=n+'=; expires=Thu, 01 Jan 1970 00:00:01 GMT; path=/';}
       $(document).on('change','#de_preset_picker',function(){
         var v=this.value;
         if(v===''){delCookie('debrowser_preset');}
         else{setCookie('debrowser_preset',v,365);}
         var u=new URL(window.location.href);
         u.searchParams.delete('preset');
         window.location.href=u.toString();
       });
     })();"
  ))
}

#' de_theme
#'
#' DEBrowser bslib theme. Default behavior: hand-rolled Slate + OK-blue
#' palette with Inter typography on Bootstrap 5. When `preset` is supplied
#' (e.g. `"zephyr"`, `"lumen"`, `"cosmo"`), returns a bare Bootstrap 5
#' theme with only Inter font applied -- preset-specific colors come from
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
    # OK-blue: the WCAG-AA light-mode a11y fallback for the redesign's cyan
    # gradient (which is fill-only and fails as text). Keep it -- do NOT
    # "unify" it with --de-cyan. See docs/design/02-color-palette-plan.md.
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
