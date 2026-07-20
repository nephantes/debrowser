# 03 — Iconography Unification Plan

**Scope:** Collapse the five icon families currently in DEBrowser down to **one** — Font Awesome — with a small, explicitly documented set of pure-CSS Unicode exceptions. Pin the Font Awesome version so glyph-name choices stop being a coin-flip.

**Status:** Plan only. No source files are edited by this document. Every code block below is a proposed Before/After for a follow-up implementation pass.

**Companion doc:** `docs/design/02-color-palette-plan.md` introduces the `--de-space-*` spacing tokens referenced in §4. Those tokens do **not** exist in `debrowser.css` yet (verified: `grep -n "de-space" inst/extdata/www/debrowser.css` returns nothing), so the CSS helper in §4 ships with literal fallbacks and will inherit the tokens once 02 lands.

**Commit convention:** every task below lists a subject line. When actually committing, keep the conventional-commit subject and append the repo's standard trailer:

```
Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
```

---

## 0. Verified environment facts (why FA6 is what actually renders)

These were measured in this checkout, not assumed:

| Check | Command | Result |
|---|---|---|
| Shiny version | `packageVersion("shiny")` | `1.13.0` |
| bslib version | `packageVersion("bslib")` | `0.10.0` |
| fontawesome version | `packageVersion("fontawesome")` | `0.5.3` (installed, **not** in DESCRIPTION) |
| Which FA webfont `shiny::icon()` attaches | `htmltools::findDependencies(shiny::icon("download"))` | `font-awesome 6.5.2` |
| FA version the `fontawesome` pkg bundles | `fontawesome::fa_html_dependency()$version` | `6.5.2` |

Two consequences that drive every decision here:

1. **The rendered glyph set is Font Awesome 6.5.2**, supplied by the `fontawesome` R package (pulled in transitively by shiny/bslib). Whichever `fontawesome` version resolves at install time decides which FA the browser gets — today it happens to be 6.5.2, but nothing in `DESCRIPTION` guarantees FA6 over FA5. That is the coin-flip §1 fixes.

2. **`shiny::icon()` auto-normalizes FA5 alias names to FA6 canonical classes.** Measured:

   ```
   shiny::icon("info-circle")      -> <i class="fas fa-circle-info" ...>
   shiny::icon("file-alt")         -> <i class="far fa-file-lines" ...>
   shiny::icon("external-link-alt")-> <i class="fas fa-up-right-from-square" ...>
   shiny::icon("check-circle")     -> <i class="far fa-circle-check" ...>
   ```

   So the FA5-vs-FA6 name worry the author flagged at `R/mod_export.R:77-79` is **already moot for anything routed through `shiny::icon()`** — Shiny rewrites the class to the FA6 canonical form regardless of the string you pass. The real fragility lives in (a) **hand-written `<i class='fa fa-…'>`** that bypasses this normalization, and (b) **CSS selectors that target a specific FA class name** (see the Help-chip trap in Task C2).

---

## 1. DECISION — standardize on Font Awesome 6, and pin it

**Chosen family: Font Awesome (v6, free — solid + regular).**

Rationale:
- It is already the **majority** family (13 distinct `shiny::icon()` names across the app) and is **already loaded** on every page via the html dependency Shiny attaches to `shiny::icon()`. Zero new runtime assets.
- The other four families (hand-written `<i>`, Bootstrap-Icons SVG, Unicode/entity glyphs, raster PNG/GIF) are each used in only a handful of places and can be folded into FA or explicitly quarantined as documented exceptions.
- Lowest friction, no new bundle, no CSP concerns (FA ships with bslib), consistent metrics/baseline with the rest of the chrome.

### 1.1 Pin the version — exact `DESCRIPTION` edit

Add `fontawesome` to `Imports` with a floor that guarantees **FA6** (the `fontawesome` 0.5.x line bundles Font Awesome 6.x; 0.4.x bundled FA5). This turns "whatever resolves" into "at least FA6", so names like `square-plus` / `circle-check` / `up-right-from-square` are guaranteed present and the FA5/FA6 ambiguity disappears.

**Before** (`DESCRIPTION`, Imports block, lines 29–64 — tail shown):

```
    plotly,
    heatmaply,
    bslib (>= 0.7.0),
    htmltools
```

**After:**

```
    plotly,
    heatmaply,
    bslib (>= 0.7.0),
    htmltools,
    fontawesome (>= 0.5.0)
```

Notes:
- `fontawesome (>= 0.5.0)` bundles FA `>= 6.1.1`. Every FA name proposed in this plan was verified present in the installed `fontawesome 0.5.3` (FA 6.5.2) — see the Appendix.
- This is a **floor**, not an exact pin. If you want byte-for-byte reproducibility of the rendered glyphs across machines, additionally record the resolved `fontawesome` version in `renv.lock` / the Bioconductor build snapshot. A hard `==` pin in `DESCRIPTION` is discouraged for a Bioconductor package (BiocCheck penalizes over-tight version constraints).

### 1.2 How to verify which FA version renders

Two independent checks — run either after changing dependencies:

```r
# (a) Which webfont does shiny::icon() attach right now?
htmltools::findDependencies(shiny::icon("download"))[[1]][c("name","version")]
#> $name "font-awesome"   $version "6.5.2"

# (b) Which FA does the fontawesome package bundle?
fontawesome::fa_metadata()$version        # or fontawesome::fa_html_dependency()$version
```

In the browser (DevTools): inspect any `<i class="fas fa-…">` and confirm the computed `font-family` is `"Font Awesome 6 Free"` (weight 900 = solid `fas`, weight 400 = regular `far`). If you ever see `"Font Awesome 5 Free"`, the floor did not take effect.

---

## 2. Glyph mapping table — every non-FA glyph → its FA6 equivalent

All target names were verified to resolve in the installed FA 6.5.2 (`fontawesome::fa(<name>)` succeeds) unless the Notes say otherwise.

| # | Current (family, glyph, file:line) | Target FA name | Notes |
|---|---|---|---|
| M1 | Bootstrap-Icons SVG — moon — `R/ui.R:721-726` | `moon` | Renders `far fa-moon`. Keep the `de-theme-icon de-theme-icon-moon` classes on the `<i>` so CSS toggle at `debrowser.css:327-330` still matches. See Task C3. |
| M2 | Bootstrap-Icons SVG — sun — `R/ui.R:729-734` | `sun` | Renders `fas fa-sun`. Keep `de-theme-icon de-theme-icon-sun` classes. Task C3. |
| M3 | Bootstrap-Icons SVG mask — padlock — `debrowser.css:3033-3034` (`.wiz-step.de-pill-locked::after`) | `lock` | Pure-CSS `::after`; convert the SVG `mask` to the FA webfont codepoint `content:"\f023"; font-family:"Font Awesome 6 Free"; font-weight:900`. `\f023` = FA6 solid `lock`. Task C4. |
| M4 | Unicode entity — `&#10515;` ⤓ (down-arrow-to-bar) — `R/dataLoad.R:425` (Count-Data drop tile) | `file-arrow-up` | Semantically an **upload** dropzone, so `file-arrow-up` (fas) reads better than the current download-looking arrow. Faithful geometric alt = `circle-down`. **Do NOT use `arrow-down-to-bracket` — verified MISSING in FA 6.5.2** (`fontawesome::fa("arrow-down-to-bracket")` errors). Task C5. |
| M5 | Unicode entity — `&#8862;` ⊞ (squared-plus) — `R/dataLoad.R:443` (Metadata drop tile) | `square-plus` | Verified OK. Faithful to the ⊞ metaphor ("add metadata"). Alt: `circle-plus`. Task C5. |
| M6 | CSS content — `✓` (`\2713` / literal) — `debrowser.css:61,67,728,800,2630,3012` | *keep `✓` (sanctioned exception)* | These are pure-CSS `::before`/`::after` **state markers** (wizard done/skipped, selectize `.selected`, drop `.has-file`) with no element to hang an `<i>` on. Keep the literal `✓` as **the one sanctioned non-FA status glyph**; do NOT sprinkle FA private-use codepoints across CSS. Remove the *conceptual* duplicate by making FA `circle-check` the single success glyph in **R-rendered** UI (Task C6). Justification in §2.1. |
| M7 | FA `check-circle` (R-rendered success) — `R/mod_enrichment_gmt.R:225` | `circle-check` | Already normalizes to `far fa-circle-check`; renaming the source string is cosmetic (FA6-canonical). Keep as the single FA success glyph. Task C6. |
| M8 | Legal-page chip — `§` — `inst/extdata/www/legal/{privacy,cookies,terms}.html:31/34/45` | *keep `§` (sanctioned exception)* | Standalone static HTML that does **not** load the FA webfont (own legal CSS). FA equivalent would be `section` (verified OK) but only after adding the FA stylesheet to those pages — not worth it. Documented exception. |
| M9 | Legal-page back link — `&larr;` ← — `legal/{privacy,cookies,terms}.html:30/33/44` | *keep `←` (sanctioned exception)* | Same rationale as M8. FA equivalent = `arrow-left`. Documented exception. |
| M10 | CSS content — `▾` / `▴` (disclosure caret) — `debrowser.css:1395/1397` | *keep (sanctioned exception)* | Pure-CSS `details > summary::after` decorative caret. FA equiv `chevron-down`/`chevron-up`. Decorative-only; keep Unicode. |
| M11 | CSS content — `→` (continue cue) — `debrowser.css:4257/4366` | *keep (sanctioned exception)* | Pure-CSS decorative CTA arrow. FA equiv `arrow-right`. Keep Unicode. |
| M12 | Hand-written `<i class='fa fa-info-circle'>` — Help chip — `R/funcs.R:497` | `info-circle` **(keep this exact class)** | This one is a **trap**: `shiny::icon("info-circle")` emits `fa-circle-info`, but the CSS at `debrowser.css:1634/1639/1656` targets `.fa-info-circle`. Converting to `shiny::icon()` silently breaks the chip's color styling unless the CSS is updated too. See Task C2. |
| M13 | Hand-written dynamic `<i class='fa fa-<str>'>` — `R/funcs.R:407`, fed invalid `"show"` at `R/funcs.R:294` | `eye` | `fa-show` is not a glyph → renders nothing. Fix the feed (Task Q1) and route the button through `shiny::icon()` (Task C1). |

### 2.1 Why `✓` stays in CSS instead of becoming FA

You cannot place a Font Awesome `<i>` inside a CSS `content:` string. The only way to "unify" the pure-CSS ticks onto FA is to write the FA private-use codepoint plus font-family into every rule, e.g.:

```css
content: "\f00c";                 /* FA6 'check' */
font-family: "Font Awesome 6 Free";
font-weight: 900;
```

That was considered and **rejected** because it (1) makes six decorative, non-interactive state markers hard-depend on the FA webfont actually loading, (2) couples CSS to FA's private-use codepoints (stable within a major version but invisible/brittle to future editors), and (3) buys no user-visible benefit over a literal `✓`. Decision: **`✓` (and the small decorative set `▾ ▴ →`, plus the standalone legal pages `§ ←`) are sanctioned non-FA glyphs.** Everything **rendered from R** uses Font Awesome. The success-metaphor duplication is resolved by making `circle-check` the *only* FA success glyph (Task C6), living in a different rendering layer than the CSS `✓` state markers.

---

## 3. Per-file edit list

Tasks are labelled **[Quick win]** (isolated, low-risk, ship first), **[Consolidation]** (family folded into FA), or **[System]** (dependency/policy). Order within the doc is roughly the recommended execution order.

### Q1 — [Quick win] Fix the invalid `fa-show` icon on the "Show Data" button

`R/funcs.R:294` passes `icon = "show"` into `actionButtonDE()`, whose string branch (`R/funcs.R:407`) builds `<i class='fa fa-show'>` — not a real glyph, renders as empty space next to the label.

**Before** (`R/funcs.R:294`):

```r
      actionButtonDE(trigger_id, "Show Data", styleclass = "primary", icon = "show")
```

**After:**

```r
      actionButtonDE(trigger_id, "Show Data", styleclass = "primary", icon = "eye")
```

`fa-eye` (verified OK) reads as "view/show". This is the minimal one-word fix; Task C1 upgrades it further.

**Commit:** `fix(icons): replace invalid fa-show with fa-eye on Show Data button`

---

### Q2 — [Quick win] Wire the favicon into `<head>`

`inst/extdata/www/favicon.ico` exists but is referenced nowhere (verified: `grep -rn favicon R inst` → no hits). `addResourcePath("www", …)` at `R/ui.R:23-26` already maps `www/ → inst/extdata/www/`, so `www/favicon.ico` resolves. Add the link inside the head block that already holds the `debrowser.css` `<link>` (`R/ui.R:100-129`), right after that stylesheet link.

**Before** (`R/ui.R:118-130`):

```r
        tags$link(
          rel = "stylesheet", type = "text/css",
          href = paste0(
            "www/debrowser.css?v=",
            tryCatch(
              as.integer(file.info(system.file(
                "extdata", "www", "debrowser.css", package = "debrowser"
              ))$mtime),
              error = function(e) version_label
            )
          )
        ),
        tags$script(src = "www/dropzone.js"),
```

**After:**

```r
        tags$link(
          rel = "stylesheet", type = "text/css",
          href = paste0(
            "www/debrowser.css?v=",
            tryCatch(
              as.integer(file.info(system.file(
                "extdata", "www", "debrowser.css", package = "debrowser"
              ))$mtime),
              error = function(e) version_label
            )
          )
        ),
        tags$link(rel = "icon", type = "image/x-icon", href = "www/favicon.ico"),
        tags$script(src = "www/dropzone.js"),
```

**Commit:** `feat(icons): wire favicon.ico into <head>`

---

### Q3 — [Quick win] Delete orphan raster assets

Verified zero references (`grep -rn "delete_button" R inst` and `grep -rn "loading2" R inst` → no hits):

- `inst/extdata/www/images/delete_button.png`
- `inst/extdata/www/images/loading2.gif`

```sh
git rm inst/extdata/www/images/delete_button.png \
       inst/extdata/www/images/loading2.gif
```

Keep the other rasters — they are live: `logo.png` (`R/uifuncs.R:557`), `initial_loading.gif` (`R/ui.R:98`), `loading_start.gif` (`R/uifuncs.R:489`), `loading.gif` (`R/uifuncs.R:490`), plus dynamically generated KEGG/pathview PNGs. Those are branding/data imagery, out of scope for icon unification.

**Commit:** `chore(icons): remove orphan raster assets delete_button.png, loading2.gif`

---

### S1 — [System] Pin `fontawesome` in `DESCRIPTION`

Apply the §1.1 edit (add `fontawesome (>= 0.5.0)` to `Imports`). Then regenerate docs/collate if your workflow requires and run `R CMD check` / `BiocCheck` to confirm no new NOTE. Verify with §1.2.

**Commit:** `build(icons): pin fontawesome (>= 0.5.0) to lock Font Awesome 6 rendering`

---

### C1 — [Consolidation] Route the "Show Data" button through `shiny::icon()`

`actionButtonDE()` already accepts a `shiny.tag` icon and short-circuits the hand-written string path (`R/funcs.R:404-405`). Passing a `shiny::icon()` object means the button gets FA6-normalized classes and a proper `aria-label`, and never touches the legacy `<i class='fa fa-…'>` branch. (Builds on Q1.)

**Before** (`R/funcs.R:294`, post-Q1):

```r
      actionButtonDE(trigger_id, "Show Data", styleclass = "primary", icon = "eye")
```

**After:**

```r
      actionButtonDE(trigger_id, "Show Data", styleclass = "primary",
                     icon = shiny::icon("eye"))
```

The string branch at `R/funcs.R:407` stays for backward-compat (external sub-apps may call `actionButtonDE(icon = "eye")`), but all **in-repo** callers should pass `shiny::icon(...)`. Grep guard for regressions: `grep -rn "actionButtonDE(" R | grep -i 'icon *= *"'`.

**Commit:** `refactor(icons): pass shiny::icon() to actionButtonDE Show Data button`

---

### C2 — [Consolidation] Retire the hand-written Help-chip `<i>` (mind the CSS hook)

`R/funcs.R:487-500` (`getHelpButton()`) builds a raw `<a>` HTML string containing `<i class="fa fa-info-circle" aria-hidden="true">`. The chip's color/size styling depends on the CSS selector `.de-help-btn .fa-info-circle` at `debrowser.css:1634`, `:1639`, `:1656`.

**The trap:** `shiny::icon("info-circle")` emits `fas fa-circle-info` (FA6-canonical), which the `.fa-info-circle` selector will **not** match — converting naively silently drops the chip styling.

Two safe paths — pick one:

**Option A (recommended, smallest diff): keep the hand-written `<i>` as-is.** It already uses a valid, aria-hidden, FA-rendering glyph whose class matches the CSS. Document it in the code comment as an *intentional* raw-HTML exception (the chip is a plain external nav with no Shiny input id — see the existing comment at `R/funcs.R:484-486`). Net change: a one-line comment noting "class must stay `fa-info-circle` to match debrowser.css:1634". No behavior change.

**Option B (full FA routing): convert to `shiny::icon()` AND migrate the CSS selectors.**

Before (`R/funcs.R:497`):

```r
    "<i class=\"fa fa-info-circle\" aria-hidden=\"true\"></i>",
```

After — rebuild the chip with `htmltools` tags so the icon is a real `shiny::icon()`:

```r
    # (within an htmltools::tags$a(...) rebuild of the chip)
    shiny::icon("info-circle", class = "de-help-ico", `aria-hidden` = "true"),
```

…and update the three CSS rules so they target the emitted FA6 class **or** the stable custom hook. Simplest: add a `de-help-ico` class hook and retarget CSS to it (future-proof against FA renames):

```css
/* debrowser.css:1634 — Before */
.de-help-btn .fa-info-circle { font-size: 13px; line-height: 1; color: #0ea5e9; }
/* After */
.de-help-btn .de-help-ico { font-size: 13px; line-height: 1; color: #0ea5e9; }
```

(Apply the same rename at `debrowser.css:1639` and `:1656`.)

Given the risk/reward, **Option A** is the recommended ship; keep Option B for a later CSS-hardening pass.

**Commit (Option A):** `docs(icons): mark Help-chip <i> as intentional FA raw-HTML exception`
**Commit (Option B):** `refactor(icons): route Help chip through shiny::icon() + de-help-ico CSS hook`

---

### C3 — [Consolidation] Replace the moon/sun inline SVG with FA icons

`R/ui.R:721-735` hand-draws two Bootstrap-Icons-geometry SVGs for the dark-mode toggle. The CSS at `debrowser.css:327-330` shows/hides them by the classes `.de-theme-icon-moon` / `.de-theme-icon-sun`. Replacing the SVGs with `shiny::icon()` works **as long as those two classes stay on the `<i>`** — verified that `shiny::icon("moon", class = "de-theme-icon de-theme-icon-moon")` emits `<i class="far fa-moon de-theme-icon de-theme-icon-moon" …>`, so the existing selectors still match. No CSS selector change required; add one size rule (the SVGs were 18px, the `<i>` inherits font-size).

**Before** (`R/ui.R:720-735`):

```r
        # Shown in light mode; clicking switches to dark.
        tags$svg(
          class = "de-theme-icon de-theme-icon-moon",
          xmlns = "http://www.w3.org/2000/svg",
          viewBox = "0 0 16 16", width = "18", height = "18",
          fill = "currentColor", `aria-hidden` = "true",
          tags$path(d = "M6 .278a.77.77 0 0 1 .08.858 7.2 7.2 0 0 0-.878 3.46c0 4.021 3.278 7.277 7.318 7.277q.792-.001 1.533-.16a.79.79 0 0 1 .81.316.73.73 0 0 1-.031.893A8.35 8.35 0 0 1 8.344 16C3.734 16 0 12.286 0 7.71 0 4.266 2.114 1.312 5.124.06A.75.75 0 0 1 6 .278")
        ),
        # Shown in dark mode; clicking switches to light.
        tags$svg(
          class = "de-theme-icon de-theme-icon-sun",
          xmlns = "http://www.w3.org/2000/svg",
          viewBox = "0 0 16 16", width = "18", height = "18",
          fill = "currentColor", `aria-hidden` = "true",
          tags$path(d = "M8 11a3 3 0 1 1 0-6 3 3 0 0 1 0 6m0 1a4 4 0 1 0 0-8 4 4 0 0 0 0 8M8 0a.5.5 0 0 1 .5.5v2a.5.5 0 0 1-1 0v-2A.5.5 0 0 1 8 0m0 13a.5.5 0 0 1 .5.5v2a.5.5 0 0 1-1 0v-2A.5.5 0 0 1 8 13m8-5a.5.5 0 0 1-.5.5h-2a.5.5 0 0 1 0-1h2a.5.5 0 0 1 .5.5M3 8a.5.5 0 0 1-.5.5h-2a.5.5 0 0 1 0-1h2A.5.5 0 0 1 3 8m10.657-5.657a.5.5 0 0 1 0 .707l-1.414 1.415a.5.5 0 1 1-.707-.708l1.414-1.414a.5.5 0 0 1 .707 0m-9.193 9.193a.5.5 0 0 1 0 .707L3.05 13.657a.5.5 0 0 1-.707-.707l1.414-1.414a.5.5 0 0 1 .707 0m9.193 2.121a.5.5 0 0 1-.707 0l-1.414-1.414a.5.5 0 0 1 .707-.707l1.414 1.414a.5.5 0 0 1 0 .707M4.464 4.465a.5.5 0 0 1-.707 0L2.343 3.05a.5.5 0 1 1 .707-.707l1.414 1.414a.5.5 0 0 1 0 .708")
        )
```

**After:**

```r
        # Shown in light mode; clicking switches to dark.
        shiny::icon("moon",
          class = "de-theme-icon de-theme-icon-moon",
          `aria-hidden` = "true"),
        # Shown in dark mode; clicking switches to light.
        shiny::icon("sun",
          class = "de-theme-icon de-theme-icon-sun",
          `aria-hidden` = "true")
```

The enclosing `<button id="dark_mode_toggle">` already carries `aria-label="Toggle dark mode"` (`R/ui.R:718`), so `aria-hidden="true"` on the icons is correct (decorative; the button is labeled).

**CSS follow-up** — the SVGs were 18px; the `<i>` inherits the toggle's font-size. Add one rule near `debrowser.css:327-330` to preserve the size (does not change the show/hide selectors):

```css
.de-theme-toggle .de-theme-icon { font-size: 18px; line-height: 1; }
```

Verification after the edit: toggle dark mode and confirm exactly one icon shows in each state (the `display:none/inline-block` rules at `debrowser.css:327-330` still key off `.de-theme-icon-moon` / `.de-theme-icon-sun`, both present on the `<i>`).

**Commit:** `refactor(icons): replace moon/sun inline SVG with FA icons in theme toggle`

---

### C4 — [Consolidation] Convert the locked-step padlock SVG mask to the FA webfont

`debrowser.css:3026-3035` (`.wiz-step.de-pill-locked::after`) paints a padlock via an inline-SVG `mask`. Replace with the FA6 solid `lock` codepoint `\f023` on the FA webfont (already loaded app-wide because `shiny::icon()` is used elsewhere on the page).

**Before** (`debrowser.css:3026-3035`):

```css
html[data-debrowser-redesign="1"] .wiz-step.de-pill-locked::after {
  content: "";
  position: absolute;
  right: 12px;
  top: 50%; transform: translateY(-50%);
  width: 10px; height: 10px;
  background: var(--de-text-3);
  -webkit-mask: url("data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 16 16'><path d='M11 7V5a3 3 0 0 0-6 0v2H4v8h8V7zm-5 0V5a2 2 0 0 1 4 0v2H6z' fill='black'/></svg>") center/contain no-repeat;
          mask: url("data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 16 16'><path d='M11 7V5a3 3 0 0 0-6 0v2H4v8h8V7zm-5 0V5a2 2 0 0 1 4 0v2H6z' fill='black'/></svg>") center/contain no-repeat;
}
```

**After:**

```css
html[data-debrowser-redesign="1"] .wiz-step.de-pill-locked::after {
  content: "\f023";                       /* FA6 solid 'lock' */
  font-family: "Font Awesome 6 Free";
  font-weight: 900;                        /* required for the solid face */
  font-size: 11px;
  color: var(--de-text-3);
  position: absolute;
  right: 12px;
  top: 50%; transform: translateY(-50%);
  line-height: 1;
}
```

Note: this is a pure-CSS pseudo-element using the FA *webfont*, which is the sanctioned way to render FA where no `<i>` can be inserted (contrast with the `✓` state markers, which we deliberately leave as Unicode per §2.1 — the lock is different because it is an FA-family metaphor with no simple Unicode equivalent, so folding it onto FA removes a whole family/asset). Verify by locking a wizard step and inspecting the `::after` computed style shows `font-family: "Font Awesome 6 Free"`.

**Commit:** `refactor(icons): render locked wizard-step padlock via FA6 webfont (\f023)`

---

### C5 — [Consolidation] Replace the drop-tile Unicode glyphs with FA icons

`R/dataLoad.R:425` and `:443` place Unicode entities inside `.de-drop-ic` tiles. Swap to `shiny::icon()`. The tile CSS (`debrowser.css:2558-2568`) sizes the box to 36×36 with `font-size:18px`; FA's `<i>` overrides the `JetBrains Mono` `font-family` with its own, so the mono setting is harmless.

**Before** (`R/dataLoad.R:424-425`, Count-Data tile):

```r
            div(class = "de-drop",
              div(class = "de-drop-ic", HTML("&#10515;")),  # up arrow ⤳
```

**After:**

```r
            div(class = "de-drop",
              div(class = "de-drop-ic",
                  shiny::icon("file-arrow-up", `aria-hidden` = "true")),
```

**Before** (`R/dataLoad.R:442-443`, Metadata tile):

```r
            div(class = "de-drop",
              div(class = "de-drop-ic", HTML("&#8862;")),  # square+dot ⌗
```

**After:**

```r
            div(class = "de-drop",
              div(class = "de-drop-ic",
                  shiny::icon("square-plus", `aria-hidden` = "true")),
```

Notes:
- `file-arrow-up` communicates "upload a file here" better than the old down-arrow (a dropzone is an upload). Faithful-to-original alternative: `circle-down`.
- `aria-hidden="true"` is correct — each tile has a visible text title (`.de-drop-title` "Count Data" / "Metadata").
- **Do not** use `arrow-down-to-bracket` — verified MISSING in the pinned FA (Appendix).

**Commit:** `refactor(icons): replace drop-tile Unicode glyphs with FA file-arrow-up / square-plus`

---

### C6 — [Consolidation] Single success glyph; document the `✓` exception

Make FA `circle-check` the one success glyph in R-rendered UI, and record `✓` as the sanctioned pure-CSS status marker (no code change to the CSS `✓` rules).

**Before** (`R/mod_enrichment_gmt.R:225`):

```r
          shiny::icon("check-circle"), " ", st$msg
```

**After:**

```r
          shiny::icon("circle-check"), " ", st$msg
```

(Output is identical `far fa-circle-check` either way — this makes the source name FA6-canonical and de-duplicates the "which success icon?" question.) Pair with the sibling error glyph already at `R/mod_enrichment_gmt.R:230` (`circle-exclamation`, already FA6-canonical — leave it).

Then add a short **Iconography exceptions** note (e.g. a comment block at the top of the `✓` section in `debrowser.css:59-70`) declaring: *"`✓` (U+2713) is the sanctioned non-FA status glyph for pure-CSS pseudo-element state markers (wizard done/skipped, selectize `.selected`, drop `.has-file`). All R-rendered success states use FA `circle-check`. Do not introduce other Unicode status glyphs."*

**Commit:** `refactor(icons): canonicalize success glyph to FA circle-check; document CSS ✓ exception`

---

### C7 — [Consolidation, optional] Canonicalize the Export-menu FA5 alias names

Now that FA6 is pinned, the hedge comment at `R/mod_export.R:77-79` is obsolete (`shiny::icon()` normalizes regardless). Purely cosmetic source cleanup — the emitted classes are already FA6-canonical today.

**Before** (`R/mod_export.R:77-86`):

```r
  # Icon names chosen to work in both FA5 and FA6 (avoid FA6-only names
  # like arrow-up-right-from-square / file-lines / file-export which
  # render as a fallback "bars" glyph in FA5).
  list(
    shiny::tags$li(mk_download("download_r",       "R script",        "file-code")),
    shiny::tags$li(mk_download("download_rmd_src", "Rmd source",      "file-alt")),
    shiny::tags$li(mk_download("download_rmd",     "HTML",            "download")),
    shiny::tags$li(mk_action  ("view_html_tab",    "View HTML in tab", "external-link-alt")),
    shiny::tags$li(mk_download("download_ipynb",   "Jupyter notebook", "book")),
    shiny::tags$li(mk_action  ("show_methods",     "Copy methods text","clipboard"))
  )
```

**After:**

```r
  # FA6 is pinned in DESCRIPTION (fontawesome >= 0.5.0); shiny::icon()
  # normalizes any alias to the FA6 canonical class, so we use the
  # FA6 names directly. See docs/design/03-iconography-plan.md.
  list(
    shiny::tags$li(mk_download("download_r",       "R script",         "file-code")),
    shiny::tags$li(mk_download("download_rmd_src", "Rmd source",       "file-lines")),
    shiny::tags$li(mk_download("download_rmd",     "HTML",             "download")),
    shiny::tags$li(mk_action  ("view_html_tab",    "View HTML in tab", "arrow-up-right-from-square")),
    shiny::tags$li(mk_download("download_ipynb",   "Jupyter notebook", "book")),
    shiny::tags$li(mk_action  ("show_methods",     "Copy methods text","clipboard"))
  )
```

(`file-lines` and `arrow-up-right-from-square` both verified OK. `file-code`, `download`, `book`, `clipboard` are already canonical.) Low priority — ship after the higher-value tasks.

**Commit:** `style(icons): use FA6 canonical names in Export menu; drop FA5/FA6 hedge`

---

### C8 — [System, doc-only] Record the legal-page and decorative-CSS exceptions

No source edit beyond documentation. In this plan (and optionally a one-line comment in each legal HTML) record that `§`/`←` in `legal/{privacy,cookies,terms}.html` and the decorative CSS glyphs `▾ ▴ →` are sanctioned non-FA exceptions because the legal pages don't load the FA webfont and the CSS glyphs are non-interactive decoration. This closes the audit: after C1–C7, every **R-rendered** glyph is FA; the only remaining non-FA glyphs are the enumerated, justified exceptions.

**Commit:** `docs(icons): record legal-page and decorative-CSS glyph exceptions`

---

## 4. Sizing & spacing rules

Consistent metrics so icons sit on the text baseline and never jump between contexts.

| Context | Icon size | How |
|---|---|---|
| Inline with body text / in buttons / menu items | **16px** | Default — FA `<i>` inherits `1em`; body is 16px. No override needed inline. |
| Section / card headers | **20px** | Add sizing class `de-ico-20` (below). |
| Empty-state / zero-data illustrations | **24px** | Add sizing class `de-ico-24`. |

Rules:
- **Vertical centering:** the icon+label container must be `display: inline-flex; align-items: center;`. The redesign `.btn` already does exactly this (`debrowser.css:533`: `display: inline-flex; align-items: center; gap: 6px;`) — reuse that pattern, don't reinvent it.
- **Icon→label gap:** `6px`. Already correct on `.btn` (`debrowser.css:533`). For non-button icon+label pairs, use the helper below.
- **Accessibility:**
  - *Meaningful* icon (conveys info not otherwise in text): let `shiny::icon(name)` supply its `aria-label` (it does by default, e.g. `aria-label="download icon"`), or pass an explicit `aria-label`.
  - *Decorative* icon (label text already says it — buttons, drop tiles, theme toggle): pass `` `aria-hidden` = "true" `` so screen readers skip it. `shiny::icon()` forwards extra attributes to the `<i>` (verified).

### 4.1 CSS helper

Add near the top of the redesign layer (e.g. after `debrowser.css:358`). Uses the `--de-space-*` tokens from `docs/design/02-color-palette-plan.md` with literal fallbacks so it works before that plan lands:

```css
/* Iconography helper — one system for icon sizing + icon/label pairs.
   --de-space-* tokens come from docs/design/02-color-palette-plan.md;
   fallbacks keep this working until those tokens exist. */
.de-ico            { display: inline-flex; align-items: center; line-height: 1; }
.de-ico--label     { gap: var(--de-space-2, 6px); }   /* icon + text pair   */
.de-ico-16         { font-size: 16px; }                /* inline default     */
.de-ico-20         { font-size: 20px; }                /* section headers    */
.de-ico-24         { font-size: 24px; }                /* empty states       */
```

Usage example (section header with a 20px icon and a 6px gap to its label):

```r
shiny::tags$span(
  class = "de-ico de-ico--label de-ico-20",
  shiny::icon("flask", `aria-hidden` = "true"),
  "Method"
)
```

Buttons need no helper — the redesign `.btn` already carries `inline-flex / align-items:center / gap:6px`.

---

## 5. Task index

| Task | Label | Files | One-liner |
|---|---|---|---|
| Q1 | Quick win | `R/funcs.R:294` | `fa-show` → `eye` |
| Q2 | Quick win | `R/ui.R:118-130` | wire `favicon.ico` in `<head>` |
| Q3 | Quick win | `inst/extdata/www/images/` | delete 2 orphan assets |
| S1 | System | `DESCRIPTION` | pin `fontawesome (>= 0.5.0)` |
| C1 | Consolidation | `R/funcs.R:294` | Show-Data button → `shiny::icon("eye")` |
| C2 | Consolidation | `R/funcs.R:497` (+CSS) | Help chip: keep class **or** migrate CSS hook |
| C3 | Consolidation | `R/ui.R:721-735` (+CSS) | moon/sun SVG → FA icons |
| C4 | Consolidation | `debrowser.css:3026-3035` | padlock SVG mask → FA `\f023` |
| C5 | Consolidation | `R/dataLoad.R:425,443` | drop-tile glyphs → FA |
| C6 | Consolidation | `R/mod_enrichment_gmt.R:225` (+CSS doc) | single FA success glyph; doc `✓` |
| C7 | Consolidation (opt) | `R/mod_export.R:77-86` | FA6-canonical Export names |
| C8 | System (doc) | this file / legal HTML | record sanctioned exceptions |

**Suggested order:** Q1 → Q2 → Q3 (ship immediately) → S1 (unblocks name guarantees) → C1 → C3 → C4 → C5 → C6 → C2 → C7 → C8.

---

## Appendix — FA name verification (installed `fontawesome` 0.5.3 / FA 6.5.2)

Verified with `fontawesome::fa(<name>)` (errors ⇒ MISSING). All **proposed target** names resolve:

```
moon                   OK        square-plus            OK
sun                    OK        circle-plus            OK
lock                   OK        circle-down            OK
file-arrow-up          OK        check / circle-check   OK
arrow-up-from-bracket  OK        check-circle (alias)   OK
file-lines             OK        section                OK
arrow-up-right-from-square OK    eye                    OK
up-right-from-square   OK        info-circle (alias)    OK
file-code              OK        circle-info            OK
download               OK        circle-exclamation     OK
book / clipboard       OK        table / table-cells    OK

arrow-down-to-bracket  MISSING   <-- DO NOT PROPOSE
```

FA5/FA6 name notes (how to check a name yourself):
- Run `fontawesome::fa("<name>")` — an error means it is not in the pinned metadata; a returned SVG means it renders.
- To see what class Shiny will emit (FA6 canonicalization): `as.character(shiny::icon("<name>"))`. Examples confirmed: `info-circle → fa-circle-info`, `file-alt → fa-file-lines`, `external-link-alt → fa-up-right-from-square`, `check-circle → fa-circle-check`. This is why CSS that targets an FA class name (e.g. `.fa-info-circle`, `debrowser.css:1634`) must be checked whenever a hand-written `<i>` is converted to `shiny::icon()` (Task C2).
