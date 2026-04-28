# Phase B1 — bslib chrome + theme swap

**Date:** 2026-04-28
**Branch:** `modernize`
**Predecessors:** A1–A5 (foundation, pure analytics, Shiny modernization, dependency trimming)
**Successors (sketched):** B2 (wizard + condSelect rewrite), B3 (sane defaults), B4 (friendly errors), B5 (onboarding), B6 (plot UX)

## Goal

Replace the `shinydashboard`-based UI shell with `bslib::page_navbar` + per-tab `layout_sidebar`, swap chrome to a Slate + OK-blue theme with a light/dark toggle, and migrate every `shinydashboard::box()` call site to `bslib::card()`. End state: `shinydashboard` is no longer in `Imports`.

This phase is purely cosmetic/structural. No analytical behavior changes. No server-side data flow changes.

## Brainstorm answers

- **Light + dark toggle**, both modes (`bslib::input_dark_mode()` in the navbar).
- **`page_navbar`** (top tabs) over `page_sidebar` — eliminates the duplicative "Data Prep | Discover" sidebar tab switcher.
- **Slate + OK-blue palette** — dark slate navbar (`#0f172a`), OK-blue primary (`#0369a1`), slate-50 sidebar, white cards. Distinctive, plays well with biology plot palettes.
- **Approach #2** — chrome + boxes + CSS audit. Not chrome-only (#1 leaves a half-themed app), not maximum (#3 risks the gating logic just fixed in commit `3f7c1f4`).

## Architecture

Replace `deUI()`'s `dashboardPage(dashboardHeader, dashboardSidebar, dashboardBody)` with:

```r
page_navbar(
  id      = "methodtabs",                     # SAME id as today
  title   = HTML(paste0("DEBrowser <span class='text-muted small'>v",
                        getNamespaceVersion("debrowser"), "</span>")),
  theme   = de_theme(),
  bg      = "#0f172a",
  inverse = TRUE,
  header  = tagList(
    shinyjs::useShinyjs(),
    debrowser::getJSLine(),
    bslib::input_dark_mode(id = "dark_mode", mode = "light")
  ),

  nav_panel("Data Prep",     dataPrepUI()),    # see "Wizard step nav" below
  nav_panel("Main Plots",
    layout_sidebar(sidebar = sidebar(width = 300, mainPlotsSidebarUI()),
                   uiOutput("mainmsgs"), uiOutput("mainpanel"))),
  nav_panel("QC Plots", uiOutput("qcpanel")),
  nav_panel("GO Term",  uiOutput("gopanel")),
  nav_panel("Tables",   DT::dataTableOutput("tables")),

  nav_spacer(),
  nav_item(helpText("Developed by ",
           a("UMMS Biocore.", href = "https://www.umassmed.edu/biocore/",
             target = "_blank")))
)
```

### Per-tab sidebar policy

| Nav panel  | Sidebar?  | What it holds |
|------------|-----------|---------------|
| Data Prep  | Yes (260) | Wizard nav (Upload → Filter → Batch → CondSelect → DE Analysis) + DE Filter (cutOffUI/compselectUI when on DEAnalysis step) |
| Main Plots | Yes (300) | `mainPlotControlsUI("main")` + `downloadSection` + `cutoffSelection` + `leftMenu` (today's "Discover" sidebar tab content) |
| QC Plots   | No        | Plot-internal controls live inside cards |
| GO Term    | No        | (same) |
| Tables     | No        | (same) |

### What disappears

- `tabsetPanel(id = "menutabs", ...)` — the sidebar's "Data Prep | Discover" two-tab switcher. Not referenced by any server observer (grep'd `R/*.R`); safe to drop.
- `dashboardBody`'s `tabsetPanel(id = "methodtabs", type = "tabs", tabPanel(...) x5)` — replaced by the `page_navbar` itself, which receives `id = "methodtabs"` to preserve `input$methodtabs`.
- `dashboardHeader` + the `dbHeader$children[[2]]` injection trick — replaced by `page_navbar`'s `title` arg.

### What stays as-is

- `shinyjs` (loading overlay, heatmap hover, `togglePanels` internals) — kept. Behavior, not chrome.
- `getJSLine()`, `getTabUpdateJS()`, `addResourcePath("www", ...)` — kept.
- The loading overlay (`#loading-debrowser`) and its `inlineCSS` block — kept inline in `deUI()`.
- All UI module functions (`dataLoadUI`, `dataLCFUI`, `batchEffectUI`, `condSelectUI`, `mainPlotControlsUI`, etc.) — internal `box()` calls migrate, but their public surface is unchanged.

### New UI helpers (introduced in B1)

- `dataPrepUI()` — composes the Data Prep tab's wizard nav + per-step content (see "Wizard step nav" below for primitive choice).
- `mainPlotsSidebarUI()` — wraps `mainPlotControlsUI("main")` + `downloadSection` + `cutoffSelection` + `leftMenu` for the Main Plots tab's sidebar.
- `de_theme()` (`R/de_theme.R`).
- `de_card(title, ..., download_id = NULL)` (`R/de_card.R`).

## Components

### `de_theme()`

```r
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
    "navbar-bg"   = "#0f172a",
    "navbar-dark-color"        = "#cbd5e1",
    "navbar-dark-hover-color"  = "#7dd3fc",
    "navbar-dark-active-color" = "#7dd3fc",
    base_font     = bslib::font_google("Inter", local = FALSE),
    heading_font  = bslib::font_google("Inter", local = FALSE)
  )
}
```

Dark mode: `bslib::input_dark_mode(id = "dark_mode", mode = "light")` in the navbar. bslib handles the CSS-var swap. The slate navbar is intentionally dark in both modes (consistent brand surface); the body bg/fg flip automatically.

Plot-level dark theming (plotly/heatmaply/ggplot color flips driven by `input$dark_mode`) is **deferred to Phase B6**. In dark mode, plot bg may stay light — readable, intentionally simple for B1.

### `de_card()` helper

```r
de_card <- function(title, ..., download_id = NULL, full_screen = TRUE) {
  header <- if (is.null(download_id)) {
    bslib::card_header(title)
  } else {
    bslib::card_header(
      class = "d-flex align-items-center",
      title,
      shiny::tags$div(class = "ms-auto",
        shiny::downloadButton(download_id, label = NULL,
          icon = shiny::icon("download"),
          class = "btn-primary btn-sm"))
    )
  }
  bslib::card(header, ..., full_screen = full_screen)
}
```

Used at all 22 `box()` migration sites. Keeps usages consistent and grep-able (`grep de_card R/*.R` finds all card sites).

### `box()` → bslib substitution patterns

| Pattern | Source | Target |
|---------|--------|--------|
| Simple plot box | `box(title, status, solidHeader, collapsible, output)` | `de_card(title, output, full_screen = TRUE)` |
| Collapsible advanced options | `box(title, collapsed = TRUE, ..., width = 12)` | `bslib::accordion(open = FALSE, accordion_panel(title, ...))` |
| Width = N grid layout | `fluidRow(box(width=6,...), box(width=6,...))` | `bslib::layout_columns(col_widths = c(6,6), card(...), card(...))` |
| Box with download button | `box(title, ..., downloadButton("downloadX"))` | `de_card(title, ..., download_id = "downloadX")` |

### CSS audit — `inst/extdata/www/shinydashboard_additional.css` → `debrowser.css`

| Rule | Action | Why |
|------|--------|-----|
| `.content-wrapper`, `.right-side`, `.main-header` | Delete | shinydashboard internals; classes don't exist in bslib |
| `.well`, `.container-fluid`, `html, body { margin/padding 0 !important }` | Delete | bslib supplies sane defaults |
| `.btn`, `.btn-default`, `.btn-file`, `.action-button` | Delete | Bootstrap 5 ships these; current overrides fight the theme |
| `#downloadPlot`, `#downloadData`, `#downloadGOPlot` color rules | Delete | Apply via `class = "btn-primary btn-sm"` instead |
| `#loading-debrowser` (overlay) | Keep, inline | App-specific behavior, already inlined in `deUI()` |
| `#bookmark_saved_output { color: green }`, `#university-name`, `#refresh`, `.removebm`, `.bm_id`, `#past_named_bookmarks`, `#initialmenu`, `#demo`, `#loadmessage`, `.fa-info` | Keep | App-specific positioning, no conflict |
| Commented-out blocks (`li { display: none }`, `.treeview-menu`, `.ggvis-dropdown-toggle`) | Delete | Already dead code |

End state: ~25 lines of genuinely app-specific rules. File renamed to `debrowser.css`. Caution: don't delete in one pass — comment with `/* B1: candidate for removal */` first, remove in a follow-up commit after a smoke-test pass.

### `shinyBS` status

- `bsModal` already replaced in `getTableDetails` (commit `7e275bd`).
- The two remaining calls at `R/funcs.R:520` (KEGG) and `R/uifuncs.R:677` (GeneTable) → **deferred to Phase B2**.

## Module ID & data flow

### Server-side input ids — preservation contract

| Input id | Source today | Source after B1 | Used by |
|----------|--------------|-----------------|---------|
| `input$methodtabs` | `dashboardBody`'s `tabsetPanel(id="methodtabs")` | `page_navbar(id="methodtabs")` | `R/utils_validate.R:94`, `togglePanels()` |
| `input$DataPrep` | `sidebarMenu(id="DataPrep")` | a bslib navset with `id = "DataPrep"` (primitive choice in "Wizard step nav" below) | `R/ui.R:84` JS condition for DE Filter visibility |
| `output$dataready` | server-side | unchanged | `R/ui.R:101` JS condition |

### Input ids that go away

- `input$menutabs` — sidebar's two-tab switcher. Grep'd `R/*.R`: not referenced. Safe to drop.

### `togglePanels()` rewrite — body only, signature preserved

```r
togglePanels <- function(num = NULL, nums = NULL, session = NULL) {
  if (is.null(num)) return(NULL)
  for (i in 0:4) {
    if (i %in% nums) {
      bslib::nav_show("methodtabs", target = paste0("panel", i), session = session)
    } else {
      bslib::nav_hide("methodtabs", target = paste0("panel", i), session = session)
    }
  }
  if (num) {
    bslib::nav_select("methodtabs", selected = paste0("panel", num), session = session)
  }
}
```

All 6 caller sites in `R/server.R` (lines 98, 103, 156, 182, 289, 295) keep working untouched.

### Wizard step nav inside Data Prep tab

Today: `sidebarMenu(id="DataPrep")` with six `menuItem`s + a `conditionalPanel` for DE Filter docked below. The replacement primitive must (a) expose `input$DataPrep` with the same step values (`Intro`, `Upload`, `Filter`, `BatchEffect`, `CondSelect`, `DEAnalysis`), (b) render as a vertical nav on the left, (c) place the active step's content to the right.

Two viable primitives — implementation picks one based on which keeps the existing JS reveal logic simplest:

- **A. `bslib::navset_pill_list(id = "DataPrep", widths = c(3, 9), well = FALSE, ...)`** — bslib-native vertical pill list with adjacent content panels. Self-contained widget. DE Filter renders as part of the `DEAnalysis` `nav_panel`'s content (top of the right column), not as a separate sidebar block. **Visual delta vs the Section 1 mockup:** DE Filter moves from the bottom of the wizard sidebar to the top of the DE Analysis panel content. Acceptable for B1 — same controls, slightly different placement.
- **B. `bslib::layout_columns(col_widths = c(3, 9))` + `bslib::navset_hidden(id = "DataPrep", ...)` in column 2 + custom `actionLink`-based vertical nav in column 1**, wired with `observeEvent` calling `bslib::nav_select("DataPrep", value)`. More flexibility (DE Filter can stay docked under the wizard nav matching the Section 1 mockup) but more wiring.

Both preserve `input$DataPrep` and the six step values used by `R/ui.R:84` and any future server observer. Plan picks one in step 2 of the migration order.

### JS selector audit

`R/funcs.R::getTabUpdateJS()` currently binds `'#startDE, #cs-startDE'` and reveals wizard items via `#DataPrep > li:nth-child(N)` selectors that target the `sidebarMenu` DOM. bslib's nav primitives (whichever is chosen above) emit a different DOM nesting. **Action item in the plan:** re-derive the selector path in the new DOM and update `getTabUpdateJS()` accordingly. Do this immediately after step 2 (shell rewrite); verify by stepping through the wizard manually before continuing.

### JS conditions in `R/ui.R`

All `conditionalPanel(condition = "...")` strings stay verbatim:
- `input.DataPrep == 'DEAnalysis'`
- `output.dataready`
- `input.goDE || input.goDEFromFilter`
- `input.Filter`, `input.Batch`
- `input.methodtabs == 'panel1'`

Same input names → same JS.

## Migration order

The app must be runnable at every commit.

1. **Add bslib + setup primitives.** Add `bslib` (≥ 0.7.0) to `Imports`. Create `R/de_theme.R`, `R/de_card.R`. No call sites changed; tests pass.
2. **Rewrite `deUI()` shell.** Swap `dashboardPage` → `page_navbar` + per-tab `layout_sidebar`. Pick wizard nav primitive (A or B from "Wizard step nav"). Body still calls existing UI modules with internal `box()` calls — looks ugly but boots, all server logic intact.
3. **Re-derive JS selectors in `getTabUpdateJS()`.** New DOM = new selector paths for the wizard step reveal. Manually step through Upload → Filter → Batch → CondSelect → DE Analysis to verify reveal still works.
4. **Migrate `box()` → `de_card()`** one file at a time: `dataLoad.R` (2), `lowcountfilter.R` (3), `batcheffect.R` (4), `condSelect.R` (1), `deprogs.R` (1), `mainScatter.R` (1), `heatmap.R` (1), `boxmain.R` (1), `barmain.R` (1), `histogram.R` (1), `density.R` (1), `IQR.R` (1), `pca.R` (2), `all2all.R` (1), `uifuncs.R` (1). 22 sites total. After each file: `devtools::load_all()` + manual smoke of that tab.
5. **CSS audit.** Apply the keep/delete buckets. Comment with `/* B1: candidate for removal */` first; remove dead rules in a follow-up commit. Rename file to `debrowser.css`, update the link in `deUI()`.
6. **Rewrite `togglePanels()`** body — replace `shinyjs::show/hide` selectors with `bslib::nav_show`/`nav_hide`. All 6 callers untouched.
7. **Wire `input_dark_mode()`.** Add to `page_navbar`'s `header`. Verify dark/light toggle. Note any plot that breaks visibly in dark mode (defer fix to B6 unless trivial).
8. **Drop `shinydashboard` from `Imports`.** Strip `@importFrom shinydashboard ...` from `R/server.R`. Run `R CMD check`.

## Risks

| Risk | Likelihood | Mitigation |
|------|------------|-----------|
| `box(collapsed = TRUE)` sites used `shinyjs::onclick`/`toggleBox` to programmatically toggle the box. `accordion_panel` doesn't expose the same handler. | Medium | Grep `onclick.*box\|toggleBox` in `R/*.R` first. If found, keep `card()` + `shinyjs::toggle()` instead of accordion at those sites. |
| `bslib::nav_show`/`nav_hide` signature differs by bslib version. | Low | Pin `bslib (>= 0.7.0)` in DESCRIPTION. |
| Custom CSS rules marked "delete" turn out to be load-bearing. | Medium | Don't delete in one pass — comment first, remove in follow-up after smoke test. |
| `bslib::input_dark_mode` requires `bslib >= 0.6.0` and Bootstrap 5. | Low | `bs_theme(version = 5)` enforced in `de_theme()`. shinydashboard (BS3) removed in step 8. |
| Wizard sidebar `nav_link` icons require an extra package. | Low | Use `shiny::icon()` (FontAwesome) — already rendering today. No new dep. |
| `dbHeader$children[[2]]` clickable logo doesn't reset the app today; `page_navbar`'s plain title doesn't either. | Negligible | Same behavior, no fix needed. |

## Out of scope (deferred, named for tracking)

- KEGG modal (`R/funcs.R:520`) and GeneTable modal (`R/uifuncs.R:677`) `bsModal → modalDialog` → **B2**.
- Plot-level dark theming (plotly/heatmaply/ggplot color flips driven by `input$dark_mode`) → **B6**.
- Wizard re-design as a true stepper with progress states (not just a nav list) → **B2**.
- `shinytest2` enablement on CI → **B2** (B1 changes top-level IDs; snapshots written here would be discarded).
- The deferred condSelect.R rewrite from Phase A4b → **B2** alongside the wizard work.

## Acceptance criteria

B1 is done when:

- `devtools::test()` reports `[ FAIL 0 | WARN 12 | SKIP 0 | PASS 88 ]` (12 upstream warnings unchanged).
- `devtools::check()` clean (no new errors/warnings/notes).
- `BiocCheck` no new errors.
- `library(debrowser); startDEBrowser()` boots without `library(shinydashboard)` available (verifies `Imports` actually trimmed).
- Manual smoke test passes:
  1. Demo data → Upload → Filter → BatchEffect → CondSelect → DE Analysis end-to-end.
  2. Each of the 5 nav_panels renders and switches without console errors.
  3. DE Filter sidebar block appears only when wizard is on `DEAnalysis`.
  4. After Submit DE, Main Plots / QC / GO / Tables tabs become reachable (verifies `togglePanels`).
  5. Heatmap hover and click still fire.
  6. KEGG modal still opens (verifies B1 didn't break the deferred `bsModal` calls).
  7. Light → dark toggle: every nav_panel renders without unreadable text.
  8. Reload page mid-analysis: loading overlay appears and dismisses normally.
- Visual contract — final implementation matches the layout structure of `.superpowers/brainstorm/97369-1777351847/content/architecture-detail.html` (not pixel-perfect colors).
- `NEWS.md` updated with Phase B1 entry.

## Key files

- `R/ui.R` — `deUI()` shell rewrite (largest single diff).
- `R/de_theme.R` (new) — `de_theme()`.
- `R/de_card.R` (new) — `de_card()`.
- `R/uifuncs.R` — `togglePanels()` body rewrite.
- `R/server.R` — strip `@importFrom shinydashboard`.
- 15 module files with `box()` call sites — see Migration order step 4.
- `inst/extdata/www/shinydashboard_additional.css` → renamed to `debrowser.css`, audited.
- `DESCRIPTION` — add `bslib (>= 0.7.0)` to Imports; remove `shinydashboard`.
- `NEWS.md` — Phase B1 entry.
