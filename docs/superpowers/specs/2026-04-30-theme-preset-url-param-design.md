---
title: Theme preset URL param — playground for trying bslib presets
date: 2026-04-30
status: approved
---

# Theme preset URL param

## Motivation

Current DEBrowser theme ([R/de_theme.R](../../../R/de_theme.R)) is a hand-rolled
Slate + OK-blue palette built directly with `bslib::bs_theme(version = 5, ...)`
— no preset, custom colors, Inter font. The user wants to try other bslib
presets (Bootswatch + bootstrap + shiny) to find a look with smaller / tighter
elements without committing to one.

## Goal

Allow a developer to swap the active preset at runtime via a URL query
parameter:

```
http://127.0.0.1:PORT/?preset=zephyr
http://127.0.0.1:PORT/?preset=yeti
http://127.0.0.1:PORT/?preset=lumen
```

Open several tabs side-by-side to compare. Default URL (no `?preset=`) keeps
the existing custom Slate + OK-blue theme exactly as today.

## Non-goals

- Picking a final preset. This change is exploratory — the playground only.
- Density tuning ("elements too big"). That requires layering `font-size-base`,
  `spacer`, `input-padding-y`, etc. on top of whichever preset wins. Tracked
  as a follow-up after a preset direction is chosen.
- A live in-app preset switcher (`bslib::bs_themer()` or a `selectInput`).
  URL-only is enough for comparison and bookmarking.
- Persisting a preset choice across sessions.

## Design

### File 1 — `R/de_theme.R`

`de_theme()` gains an optional `preset` argument (default `NULL`).

- `preset = NULL` → existing behavior, byte-identical to today (custom bg/fg/
  primary/etc., navbar overrides, Inter font).
- `preset = "<name>"` → playground mode: build with `bslib::bs_theme(version = 5,
  preset = preset, ...)`. **Custom color overrides and navbar overrides are
  dropped** so the preset's own palette is visible. Inter font is kept so
  typography is constant across comparisons.

```r
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
    # ... unchanged ...
  )
}
```

### File 2 — `R/ui.R`

`deUI` is converted to a request-aware function. Shiny calls a UI function
with the incoming HTTP request when the function takes one argument; this
works transparently with `shinyApp(ui = deUI, ...)` and the existing
`startDEBrowser()` entry point.

```r
deUI <- function(req) {
  preset <- shiny::parseQueryString(req$QUERY_STRING)[["preset"]]
  preset <- validate_preset(preset)   # see Validation
  ...
  bslib::page_navbar(
    theme = de_theme(preset = preset),
    ...
  )
}
```

Everything else inside `deUI` is unchanged.

### Validation

Whitelist of accepted preset names (kept as a top-level constant in
`R/de_theme.R` so it lives next to the consumer):

```
bootstrap, shiny,
cerulean, cosmo, cyborg, darkly, flatly, journal, litera, lumen, lux,
materia, minty, morph, pulse, quartz, sandstone, simplex, sketchy, slate,
solar, spacelab, superhero, united, vapor, yeti, zephyr
```

Behavior:

- `preset` not supplied → `NULL`, default theme.
- `preset` supplied and in whitelist → preset applied.
- `preset` supplied and **not** in whitelist → `NULL` (default theme), with a
  `message()` to the R console naming the unknown preset and listing valid
  values. No UI-facing error — silent-ish fallback keeps the playground
  forgiving.

### Roxygen / docs

Update the `de_theme` roxygen block to document the new `preset` parameter
and link the URL-param usage. Update `deUI`'s roxygen note to mention
`?preset=` and that the function now accepts a `request` argument.

## Tests

Add to `tests/testthat/` (one new file or extend an existing theme test if
present):

- `de_theme()` returns a `bs_theme` object (current behavior preserved).
- `de_theme("zephyr")` returns a `bs_theme` object.
- `de_theme("not-a-real-preset")` returns the default `bs_theme` and emits a
  `message()` (capture with `expect_message`).

No shinytest2 / UI test — query-param plumbing is trivial and bslib owns the
rendered output.

## Compatibility

- No external API change. `de_theme()` and `deUI()` are exported, but
  arguments are added with safe defaults.
- No NEWS entry needed (developer-facing playground, not a user feature).
  If a preset is later picked as default, that change gets its own NEWS line.

## Out of scope (follow-ups, not part of this change)

- Compact density tweaks (`font-size-base = "0.9rem"`, `spacer = "0.75rem"`,
  `input-padding-y = "0.25rem"`, `navbar-padding-y = "0.4rem"`).
- Removing or merging custom navbar colors with chosen preset.
- A `DEBROWSER_THEME_PRESET` env var fallback.
- Visible "currently-active preset" indicator in the app.

## Acceptance

- `R CMD check` clean (no new NOTEs / WARNINGs).
- `devtools::test()` green.
- Manual smoke: launch the app, open `?preset=zephyr`, `?preset=lumen`,
  `?preset=cosmo`, `?preset=slate` — each renders without error and looks
  visibly different. Default URL renders identically to pre-change.
