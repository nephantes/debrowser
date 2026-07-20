# 04 — Loading / Busy States — Implementation Plan

Status: proposal · Scope: `debrowser` R/Shiny app
Depends on: Phase 0 design tokens (see `02-color-palette-plan.md`).
Redesign layer is gated on `html[data-debrowser-redesign="1"]` (set by the JS in
`R/ui.R:231-239`). All CSS added by this plan is gated the same way except the
boot overlay (which must paint at t=0, before the flag is set).

---

## 0. Verified current state

| Concern | Where | State |
|---|---|---|
| Boot overlay | `R/ui.R:84-99` (`#loading-debrowser`, inline CSS + `<img initial_loading.gif>`), dismissed `shinyjs::hide("loading-debrowser", anim=TRUE)` at `R/server.R:1175` | **Works**, but `initial_loading.gif` = **1,174,927 bytes (1.12 MB)**, downloaded on every boot. |
| Runtime busy overlay | `getLoadingMsg()` `R/uifuncs.R:482-538`; assigned `output$loading <- renderUI({ getLoadingMsg() })` at `R/server.R:1149-1151` | **Dead code.** `grep` for `uiOutput("loading")` / `htmlOutput("loading")` / `Output("loading")` across `R/` returns **nothing** — there is no placeholder, so it never renders. `debrowser.css:44` also pins `#loadmessage` to `position: relative`, which would break the fixed overlay even if mounted. |
| Orphan asset | `inst/extdata/www/images/loading2.gif` (4,782 B) | **0 references** in `R/` or `inst/`. |
| `withProgress` | ~30 sites, style `"notification"` (e.g. `R/prep_data_container.R:94`, `R/server.R:1453`, `R/heatmap.R:26`, `R/pca.R:76`) | Good; keep. |
| Bare outputs (no feedback) | 4 QC plotly cards + all DT tables (enumerated in §2) | **Gap.** |
| Spinner library | `DESCRIPTION` Imports | **None** (`shinycssloaders`/`shinybusy`/`waiter` absent). |

Token check (`grep` on `inst/extdata/www/debrowser.css`): `--de-grad` (:348),
`--de-grad-soft` (:349), `--de-cyan #5EE6D6` (:343), `--de-bg-2` (:365/:379),
`--de-bg-3` (:366/:380), `--de-r-pill`, `--de-r-sm`, `--de-border`, `--de-text-1`
all **present**. `--de-dur`, `--de-ease`, `--de-accent-ink` are **not yet in the
CSS** (0 matches) — they are Phase 0 deliverables. Every rule below therefore
uses `var(--de-dur, 140ms)` / `var(--de-ease, ease-out)` fallbacks so it works
today and inherits the token when Phase 0 lands.

---

## 1. Decision — dead `getLoadingMsg` overlay: **REMOVE**

### Recommendation: remove the dead gif overlay, replace with per-widget spinners (§2).

Rationale:

- It is unreachable today (no placeholder), so removing it changes **nothing**
  the user sees — zero regression risk.
- It ships two more gifs (`loading_start.gif` 153,797 B + `loading.gif`
  44,827 B) and a full-screen black modal that blocks the whole app on *any*
  reactive flush — the opposite of the redesign's per-widget, non-blocking feel.
- Per-widget spinners (§2) are themeable via CSS tokens; a raster gif is not.

#### Edits (chosen path — REMOVE)

**a. Delete the dead server assignment** — `R/server.R:1149-1151`

Before:
```r
      output$loading <- renderUI({
        getLoadingMsg()
      })
```
After: (delete the three lines)

**b. Delete the dead UI factory** — `R/uifuncs.R:482-538`

Remove the entire `getLoadingMsg <- function(output = NULL) { ... }` definition
and its roxygen block (the `#' getLoadingMsg` header just above line 482). Then
drop its `@export` from `NAMESPACE` (regenerate with `devtools::document()` — do
**not** hand-edit `NAMESPACE`).

**c. Delete orphan + now-unused gifs** — `inst/extdata/www/images/`
```
loading2.gif        # 0 refs (already orphaned)
loading_start.gif   # only ref is getLoadingMsg (deleted in b)
loading.gif         # only refs are getLoadingMsg (deleted in b)
```
(Keep `initial_loading.gif` for now; §5 replaces it.)

#### Alternative (NOT recommended) — mount the overlay

If you would rather resurrect it: add a placeholder in the page body and undo the
CSS override.

- Placeholder — in `R/ui.R`, inside `bslib::page_navbar(...)` header/body region
  near the other top-level `uiOutput`s (siblings of `uiOutput("gopanel")`
  `R/ui.R:676`, `uiOutput("leftMenu")` server-side), add:
  ```r
  shiny::uiOutput("loading")
  ```
- Fix the override — `debrowser.css:44` sets `#loadmessage { position: relative }`,
  which cancels the `position: fixed` the overlay needs. Change to `position: fixed`
  (or delete the block) so the full-screen modal actually covers the viewport.

Tradeoffs:

| | REMOVE (recommended) | MOUNT |
|---|---|---|
| User-visible change | none | new full-screen block on every busy flush |
| Blocking model | non-blocking, per-widget | blocks entire app on any reactive recompute |
| Theming | CSS tokens | raster gif, off-brand |
| Asset weight | −203 KB (3 gifs) | +203 KB kept |
| Failure mode | n/a | `shiny-busy` fires on trivial flushes → constant flashing |

The `shiny-busy` class flips on for *every* reactive recompute, so the mounted
overlay would strobe on trivial interactions — this is exactly the jank §3 and §6
exist to prevent. Remove it.

**Commit:** `chore(loading): remove dead getLoadingMsg overlay + orphan gifs`

---

## 2. Per-widget spinners via `shinycssloaders`

### 2a. Add the dependency — `DESCRIPTION`

Before (Imports, lines 29-64, tail):
```
    shinyjs,
    shinyBS,
    shinyWidgets,
    gplots,
```
After:
```
    shinyjs,
    shinyBS,
    shinyWidgets,
    shinycssloaders (>= 1.0.0),
    gplots,
```
`>= 1.0.0` guarantees the `caption` argument exists. Because every call site uses
the `shinycssloaders::` prefix, no `NAMESPACE` `importFrom` is required — the
`Imports:` entry is enough for `R CMD check` / `BiocCheck`.

### 2b. Set global spinner defaults once — `R/zzz.R` `.onLoad` (extend, ~line 22)

Centralizing the look here means each call site stays terse and the whole app is
restyled from one place.

Before:
```r
  current <- getOption("DT.options", default = list())
  if (is.null(current$dom)) {
    current$dom <- .dt_dom_compact
    options(DT.options = current)
  }
```
After (append inside `.onLoad`):
```r
  current <- getOption("DT.options", default = list())
  if (is.null(current$dom)) {
    current$dom <- .dt_dom_compact
    options(DT.options = current)
  }
  # Loading spinners: single source of truth for type/color/size so every
  # shinycssloaders::withSpinner() call inherits the brand cyan (--de-cyan).
  options(
    spinner.type  = 8,          # thin rotating ring (types are 0-8)
    spinner.color = "#5EE6D6",  # --de-cyan
    spinner.size  = 0.7
  )
```
`withSpinner()`'s real defaults read these options: `type = getOption("spinner.type")`,
`color = getOption("spinner.color")`, `size = getOption("spinner.size")`. Verified
argument surface (`shinycssloaders::withSpinner`):
`ui_element, type, color, size, color.background, custom.css, proxy.height, id,
image, image.width, image.height, hide.ui, caption` — all names used below are real.

### 2c. Wrap the widgets

`withSpinner()` wraps the **UI-side output placeholder**, not the render call.

#### QC card 1 — Library Depth  ·  `R/mod_qc_cards.R:27` (`qcLibraryDepthUI`)

Before:
```r
  de_card(
    title = "Library Depth",
    plotly::plotlyOutput(ns("plot"), height = "500px"),
    helpText(
      "Total counts per sample. Samples flagged red are >2 SD below the mean."
    ),
    download_id = ns("dl")
  )
```
After:
```r
  de_card(
    title = "Library Depth",
    shinycssloaders::withSpinner(
      plotly::plotlyOutput(ns("plot"), height = "500px"),
      color = "#5EE6D6", proxy.height = "500px"
    ),
    helpText(
      "Total counts per sample. Samples flagged red are >2 SD below the mean."
    ),
    download_id = ns("dl")
  )
```
`proxy.height` is set to the plot's own height so the card doesn't collapse-then-
jump while loading (with an explicit `height` on the output shinycssloaders would
otherwise fall back to `"400px"`).

The other three bare QC cards follow the same pattern. Two of them build the
`plotlyOutput` inside a `renderUI` body, so the wrap goes **inside** that
`renderUI`:

- Card 2 — Detection Rate: `R/mod_qc_cards.R:134` (`qcDetectionRateUI`) — wrap in UI factory, same as card 1.
- Card 3 — Mitochondrial % : `R/mod_qc_cards.R:267` — inside `output$body <- renderUI` (`:253`); wrap the `plotly::plotlyOutput(ns("plot"), height = "500px")` there.
- Card 4 — Size Factors: `R/mod_qc_cards.R:536` — inside `output$body <- renderUI` (`:532`); wrap the same way.

#### DT table — main results  ·  `R/ui.R:683`

Before:
```r
      DT::dataTableOutput("tables")
```
After:
```r
      shinycssloaders::withSpinner(
        DT::dataTableOutput("tables"),
        color = "#5EE6D6", proxy.height = "300px"
      )
```
(Render site is `R/server.R:2169`; no server change needed.)

#### Every output to wrap

| # | UI placeholder (edit here) | Render site | Priority |
|---|---|---|---|
| 1 | `R/mod_qc_cards.R:27` plot (Library Depth) | `:64` | **Quick win** |
| 2 | `R/mod_qc_cards.R:134` plot (Detection Rate) | `:167` | **Quick win** |
| 3 | `R/mod_qc_cards.R:267` plot (Mito %, in `renderUI`) | `:271` | **Quick win** |
| 4 | `R/mod_qc_cards.R:536` plot (Size Factors, in `renderUI`) | `:539` | **Quick win** |
| 5 | `R/ui.R:683` `"tables"` (main results) | `:2169` | High |
| 6 | `R/server.R:2020` `"GOGeneTable"` | `:2076` | High |
| 7 | `R/gopanel.R:49` `"fgsea_results_table"` | `R/server.R:1492` | High |
| 8 | `R/gopanel.R:36` `"gotable"` | GO/KEGG render | High |
| 9 | `R/mod_enrichment.R:62` `ns("results_table")` | `:137` | Medium |
| 10 | `R/mod_comparison_concordance.R:85` `ns("summary")` | `:260` | Medium |
| 11 | `R/funcs.R:191` `dataTableOutput(name)` (data assessment) | `R/funcs.R:62` | Medium |
| 12 | `R/funcs.R:272` / `:313` (getTableDetails modal) | `R/funcs.R:242` | Low (modal-gated) |
| 13 | `R/dataLoad.R:526` `ns("sampleDetails")` | dataLoad render | Low (modal-gated) |
| 14 | `R/lowcountfilter.R:121` / `:156` | lowcountfilter render | Low (modal-gated) |
| 15 | `R/batcheffect.R:138` / `:169` | batcheffect render | Low (modal-gated) |

Modal-gated tables (12-15) are lower value: the modal only opens on demand and
the table is usually the only thing in it, so a card-level spinner adds little.
Wrap 1-11 first.

### 2d. Alternative — CSS skeleton shimmer (NOT recommended)

Instead of a spinner, paint a shimmering placeholder using `--de-bg-2`/`--de-bg-3`:

```css
html[data-debrowser-redesign="1"] .de-skeleton {
  min-height: 500px;
  border-radius: var(--de-r-sm, 8px);
  background: linear-gradient(100deg,
    var(--de-bg-2) 30%, var(--de-bg-3) 50%, var(--de-bg-2) 70%);
  background-size: 200% 100%;
  animation: de-shimmer 1.4s var(--de-ease, ease) infinite;
}
@keyframes de-shimmer { to { background-position: -200% 0; } }
```

| | `shinycssloaders` (recommended) | CSS skeleton |
|---|---|---|
| Wiring | wrap output in UI, 0 server changes | must render a skeleton `div` then swap to real output (per-output `renderUI`/`req` gymnastics) |
| Applies to plotly + DT | yes, uniformly | plotly/DT paint their own container — hard to size-match |
| Maintenance | one option block (§2b) | per-output markup |
| Look | on-brand cyan ring | on-brand shimmer, but bespoke each site |

The skeleton looks nice but needs bespoke render plumbing at every one of the 15
sites. Use `shinycssloaders`; keep the shimmer keyframe only for §5's boot screen
text if desired.

**Commit (Quick win subset):** `feat(loading): add shinycssloaders spinners to QC cards + orphan cleanup`
**Commit (rest):** `feat(loading): wrap result DT tables with withSpinner`

---

## 3. Timing rule — no flash-of-spinner, no strobe

Two problems, two fixes:

1. **Flash of spinner** — an op that finishes in <150 ms should never show a
   spinner at all. → **150 ms show-delay (pure CSS).**
2. **Strobe** — an op that finishes at ~180 ms shows a spinner for 30 ms then
   yanks it. → **400 ms minimum visible once shown (small JS).**

`shinycssloaders` has **no** `delay`/`min-time` argument (verified against the
argument list in §2a), so both are implemented in the redesign CSS/JS.

### 3a. 150 ms show-delay — CSS (robust, no JS)

Add to `inst/extdata/www/debrowser.css` (redesign-gated section):

```css
/* Loading spinners: hold invisible for 150ms, then fade in. An op that
   finishes first removes the spinner before it ever paints -> no flash. */
html[data-debrowser-redesign="1"] .shiny-spinner-output-container > .load-container {
  animation: de-spinner-in 120ms var(--de-ease, ease-out) 150ms both;
}
@keyframes de-spinner-in { from { opacity: 0; } to { opacity: 1; } }
```

`animation-fill-mode: both` holds the `from { opacity: 0 }` state during the
150 ms delay, then fades to `opacity: 1` over 120 ms. `shinycssloaders` still
mounts/removes the `.load-container` on recalculating as usual; this only delays
when it becomes *visible*. Nothing to fight in the library internals.

### 3b. 400 ms minimum display — JS ([System], optional polish)

A removed DOM node can't be CSS-animated out, so the floor needs JS. Hook Shiny's
stable output lifecycle events (`shiny:recalculating` / `shiny:recalculated`) —
these are documented Shiny events, independent of the `shinycssloaders` version.
Drop a new static file and register it in the head.

`inst/extdata/www/de_spinner_timing.js`:
```js
// Enforce a 400ms minimum on-screen time for shinycssloaders spinners so a
// spinner that just appeared can't strobe off. Pairs with the CSS below:
// we only toggle data-de-spin; CSS decides opacity.
(function () {
  var DELAY = 150, MIN = 400, state = {};
  function key(el) { return el.id || (el.id = "de-spin-" + Math.random().toString(36).slice(2)); }
  function container(el) { return el.closest && el.closest(".shiny-spinner-output-container"); }

  $(document).on("shiny:recalculating", ".shiny-spinner-output-container > [id]", function () {
    var el = this, c = container(el); if (!c) return;
    var k = key(el); state[k] = state[k] || {};
    state[k].show = setTimeout(function () {
      c.setAttribute("data-de-spin", "on");
      state[k].shownAt = Date.now();
    }, DELAY);
  });

  $(document).on("shiny:recalculated", ".shiny-spinner-output-container > [id]", function () {
    var el = this, c = container(el); if (!c) return;
    var k = key(el), s = state[k] || {};
    clearTimeout(s.show);
    var shownFor = s.shownAt ? Date.now() - s.shownAt : Infinity;
    setTimeout(function () { c.removeAttribute("data-de-spin"); },
               shownFor >= MIN ? 0 : MIN - shownFor);
    delete state[k];
  });
})();
```

Paired CSS (replaces the 3a keyframe rule so the JS attribute drives visibility):
```css
html[data-debrowser-redesign="1"] .shiny-spinner-output-container > .load-container {
  opacity: 0;
  transition: opacity 120ms var(--de-ease, ease-out);
}
html[data-debrowser-redesign="1"] .shiny-spinner-output-container[data-de-spin="on"] > .load-container {
  opacity: 1;
}
```

Register the script in `R/ui.R` next to the other `tags$script(src = "www/...")`
lines (after `R/ui.R:147` `plotly_theme.js`):
```r
        tags$script(src = "www/de_spinner_timing.js"),
```
Note: the DOM structure `shiny-spinner-output-container > .load-container` is the
shinycssloaders wrapper; validate the class name against the installed version
(`>= 1.0.0`) before shipping 3b. **3a alone (pure CSS) removes the worst jank
(flash-of-spinner); ship 3a first and add 3b only if strobe on 150-550 ms ops is
observed in testing.**

**Commit:** `feat(loading): 150ms show-delay + 400ms min-display for spinners`

---

## 4. Stepwise `withProgress` message for the long DE run

The DE loop already uses `withProgress` but emits a single message + one
`incProgress` at the very end (`R/prep_data_container.R:94-117`). Turn it into
real per-comparison, stepwise feedback keyed on the three observable boundaries
inside the loop: prep inputs → fit model → extract results/dds.

Before — `R/prep_data_container.R:91-118`:
```r
  for (i in seq_len(n)) {
    inputs <- prep_comparison_inputs(comparisons_spec[[i]], comparison_idx = i)

    shiny::withProgress(
      message = "Running DE Algorithms",
      detail = inputs$demethod_params,
      value = 0,
      {
        initd <- debrowserdeanalysis(
          paste0("DEResults", i),
          data = data, metadata = metadata,
          columns = inputs$cols, conds = inputs$conds,
          params = unlist(strsplit(inputs$demethod_params, ","))
        )
        if (!is.null(initd$dat()) && nrow(initd$dat()) > 1L) {
          dds_val <- tryCatch(initd$dds(), error = function(e) NULL)
          dclist[[i]] <- list(
            conds = inputs$conds, cols = inputs$cols,
            cond_names = inputs$cond_names,
            init_data = initd$dat(),
            demethod_params = inputs$demethod_params,
            dds = dds_val
          )
        }
        shiny::incProgress(1 / n)
      }
    )
  }
```
After:
```r
  for (i in seq_len(n)) {
    inputs <- prep_comparison_inputs(comparisons_spec[[i]], comparison_idx = i)
    base   <- (i - 1) / n            # fraction consumed by prior comparisons
    step   <- 1 / (n * 3)            # three sub-steps per comparison
    hdr    <- sprintf("DE %d of %d - %s", i, n, inputs$demethod_params)

    shiny::withProgress(
      message = hdr,
      detail = "Normalizing counts...",
      value = base,
      {
        shiny::setProgress(value = base + step, detail = "Fitting model...")
        initd <- debrowserdeanalysis(
          paste0("DEResults", i),
          data = data, metadata = metadata,
          columns = inputs$cols, conds = inputs$conds,
          params = unlist(strsplit(inputs$demethod_params, ","))
        )

        shiny::setProgress(value = base + 2 * step,
                           detail = "Computing contrasts...")
        if (!is.null(initd$dat()) && nrow(initd$dat()) > 1L) {
          dds_val <- tryCatch(initd$dds(), error = function(e) NULL)
          dclist[[i]] <- list(
            conds = inputs$conds, cols = inputs$cols,
            cond_names = inputs$cond_names,
            init_data = initd$dat(),
            demethod_params = inputs$demethod_params,
            dds = dds_val
          )
        }
        shiny::setProgress(value = base + 3 * step, detail = "Done")
      }
    )
  }
```
The three `detail` strings ("Normalizing counts" → "Fitting model" →
"Computing contrasts") map to the three real boundaries we control in the loop,
and the bar advances in thirds within each comparison and across comparisons.
For finer sub-step granularity you would thread a progress callback into
`debrowserdeanalysis()` itself — out of scope here; these three boundaries are
the honest, no-refactor win.

The gradient progress bar (`debrowser.css:1180-1187`
`.progress-bar { background: var(--de-grad) }`) already themes this notification —
no CSS change needed.

**Commit:** `feat(loading): stepwise progress detail for DE run`

---

## 5. Perf — replace the 1.12 MB boot gif with a CSS spinner

`initial_loading.gif` is 1,174,927 bytes fetched on every boot. Replace it with a
zero-byte conic-gradient ring built from the brand colors. The overlay must render
at t=0 (before `debrowser.css` links at `R/ui.R:118` and before the redesign flag
is set), so the spinner lives in the existing inline `<style>` and hardcodes the
cyan→violet stops (mirroring `--de-grad`).

Before — `R/ui.R:84-99`:
```r
      shinyjs::inlineCSS("
        #loading-debrowser {
          position: absolute;
          background: #000000;
          opacity: 0.9;
          z-index: 100;
          left: 0; right: 0;
          height: 100%;
          text-align: center;
          color: #EFEFEF;
        }"),
      tags$div(
        h4(paste0("Loading DEBrowser v", version_label)),
        id = "loading-debrowser",
        tags$img(src = "www/images/initial_loading.gif")
      ),
```
After:
```r
      shinyjs::inlineCSS("
        #loading-debrowser {
          position: absolute;
          inset: 0;
          background: #0B0F1A;
          opacity: 0.97;
          z-index: 100;
          display: flex;
          flex-direction: column;
          align-items: center;
          justify-content: center;
          gap: 18px;
          text-align: center;
          color: #EFEFEF;
        }
        #loading-debrowser .de-boot-spinner {
          width: 54px; height: 54px; border-radius: 50%;
          /* mirrors --de-grad: #5EE6D6 -> #A78BFA */
          background: conic-gradient(from 0deg, #5EE6D6, #A78BFA, #5EE6D6);
          -webkit-mask: radial-gradient(farthest-side, transparent calc(100% - 5px), #000 calc(100% - 4px));
                  mask: radial-gradient(farthest-side, transparent calc(100% - 5px), #000 calc(100% - 4px));
          animation: de-boot-spin .9s linear infinite;
        }
        @keyframes de-boot-spin { to { transform: rotate(360deg); } }"),
      tags$div(
        id = "loading-debrowser",
        tags$div(class = "de-boot-spinner"),
        h4(paste0("Loading DEBrowser v", version_label))
      ),
```
The `mask: radial-gradient(...)` carves a ring out of the conic gradient — a
cyan→violet spinning arc, ~0 bytes. Dismissal is unchanged: `#loading-debrowser`
is still hidden by `shinyjs::hide("loading-debrowser", anim = TRUE)` at
`R/server.R:1175`. After this lands, delete `initial_loading.gif` too
(−1.12 MB; last raster gif in the app).

**Commit:** `perf(loading): replace 1.1MB boot gif with CSS ring spinner`

---

## 6. Where loading feedback matters — guidance

| Show feedback | Why |
|---|---|
| DE run (`prepDataContainer`) | seconds-long; blocking; §4 stepwise progress |
| PCA / heatmap / clustering (`R/pca.R`, `R/heatmap.R`) | heavy compute; already `withProgress` |
| QC cards (library depth, detection, mito %, size factors) | plotly build over full matrix; §2 spinners |
| Result / GO / GSEA / concordance DT tables | large tables, server-side paging; §2 spinners |
| Enrichment run (`R/mod_enrichment.R:170`) | fgsea permutations; already `withProgress` |

| Skip feedback (a spinner here is jank) | Why |
|---|---|
| Instant reactive echoes (labels, counts, badges) | resolve <16 ms; spinner would strobe |
| Toggle/checkbox/radio state, tab switches | pure UI; nothing to compute |
| Text `renderUI` messages (`getStartPlotsMsg`, `getAfterLoadMsg`) | trivial string builds |
| Anything the 150 ms show-delay (§3a) already suppresses | by design, sub-150 ms ops show nothing |

Rule of thumb: wrap an output only when its worst-case compute crosses ~150 ms.
The §3a delay is the safety net — it turns "accidentally wrapped something fast"
into a no-op instead of a flash.

---

## 7. Task list

Legend: **[Quick win]** small, high-value, low-risk · **[Consolidation]** tidy /
centralize · **[System]** new infrastructure.

| # | Task | Label | Files | Commit |
|---|---|---|---|---|
| 1 | Delete orphan gif + wrap the 4 bare QC cards (§2c cards 1-4, §2a dep, §2b options) | **[Quick win]** | `DESCRIPTION`, `R/zzz.R`, `R/mod_qc_cards.R:27,134,267,536`, delete `inst/extdata/www/images/loading2.gif` | `feat(loading): add shinycssloaders spinners to QC cards + orphan cleanup` |
| 2 | Remove dead `getLoadingMsg` + its gifs (§1) | **[Consolidation]** | `R/server.R:1149-1151`, `R/uifuncs.R:482-538`, `NAMESPACE` (via `document()`), delete `loading.gif`,`loading_start.gif` | `chore(loading): remove dead getLoadingMsg overlay + orphan gifs` |
| 3 | Wrap remaining result DT tables (§2c rows 5-11) | **[Consolidation]** | `R/ui.R:683`, `R/server.R:2020`, `R/gopanel.R:36,49`, `R/mod_enrichment.R:62`, `R/mod_comparison_concordance.R:85`, `R/funcs.R:191` | `feat(loading): wrap result DT tables with withSpinner` |
| 4 | 150 ms show-delay CSS (§3a) | **[System]** | `inst/extdata/www/debrowser.css` | `feat(loading): 150ms show-delay for spinners` |
| 5 | 400 ms min-display JS shim (§3b) — optional, after 4 | **[System]** | `inst/extdata/www/de_spinner_timing.js`, `R/ui.R` (script tag + swap CSS) | `feat(loading): 400ms min-display strobe guard` |
| 6 | Stepwise DE progress detail (§4) | **[System]** | `R/prep_data_container.R:91-118` | `feat(loading): stepwise progress detail for DE run` |
| 7 | Boot gif → CSS ring (§5) + delete `initial_loading.gif` | **[Quick win]** | `R/ui.R:84-99`, delete `initial_loading.gif` | `perf(loading): replace 1.1MB boot gif with CSS ring spinner` |

Suggested order: **1 → 7 → 2 → 3 → 4 → 6 → 5** (visible wins first, dead-code
removal once nothing references it, timing polish last). Bump `DESCRIPTION`
`Version:` and add a `NEWS` entry per the repo's convention when landing task 1.

Net asset delta once all tasks land: **−1.38 MB** (`initial_loading.gif` 1.12 MB
+ `loading_start.gif` 150 KB + `loading.gif` 44 KB + `loading2.gif` 4.8 KB),
replaced by ~2 KB of CSS/JS.
