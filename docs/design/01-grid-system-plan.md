# §1 — Grid / Layout System Plan

> Part of the [DEBrowser UI Improvement Plan](README.md). Sibling plans:
> [§2 Color palette](02-color-palette-plan.md) · [§3 Iconography](03-iconography-plan.md) ·
> [§4 Loading states](04-loading-states-plan.md) · [§5 Hover & cursor](05-hover-cursor-plan.md) ·
> [§6 Handoff & consolidation](06-handoff-plan.md).
>
> **For agentic workers:** this is an independently executable checkbox plan. Preferred
> sub-skill: `superpowers:subagent-driven-development` (fresh subagent per task, review
> between) or `superpowers:executing-plans`. Each task ends with a git commit line.

**Goal.** Today, four grid idioms coexist inside the panels and two card systems fight for
the same job. This plan collapses them to **one** grid primitive, **one** card wrapper, and
**one** spacing source — without changing what already looks right. It is additive: every
change lives inside the existing `html[data-debrowser-redesign="1"]` layer and must survive
the `?redesign=0` fallback.

---

## The standard (read this first)

Four rules. Everything below is just applying them.

1. **One grid primitive: `bslib::layout_columns(col_widths = …)`.**
   Not `column()/fluidRow`, not `bslib::layout_column_wrap(width = 1/2)`, not a hand-rolled
   `div(style="display:grid")`. `layout_columns` maps onto a 12-column Bootstrap grid that
   **cannot be ragged** (it always sums to 12 by construction) and collapses responsively on
   its own.

2. **Allowed width vocabulary (each row sums to 12):**

   | `col_widths` | Use for |
   |---|---|
   | `12` | full-bleed single column (or just omit the grid — a lone element needs no `layout_columns`) |
   | `c(6, 6)` | the canonical 50/50 (plot ‖ table, before ‖ after, x ‖ y selectors) |
   | `c(4, 4, 4)` | equal thirds (a row of 3 compact form controls) |
   | `c(8, 4)` | main ‖ rail (wide content + a narrow controls column) |
   | `c(5, 2, 5)` | symmetric compare with a thin center gutter (before · swap · after) |

   Anything else (`c(3,3)`, `c(1,…)+bare-sibling`, `3+3+3`) is a bug to fix, not a variant to
   keep.

3. **One card = `de_card()`** ([R/de_card.R:17](../../R/de_card.R#L17)). Never raw
   `bslib::card(bslib::card_header(…), bslib::card_body(…))` for the common
   *title + body (+ optional header download)* shape. Raw `bslib::card()` is allowed **only**
   for the documented exceptions in [Task G14](#task-g14--document-the-raw-card-exceptions)
   (custom header content that `de_card()` can't express), and every such site carries a
   one-line comment saying why.

4. **Spacing comes from tokens, never magic pixels.** Use `gap` on the layout /
   `var(--de-space-N)` for any margin/padding you introduce. No `tags$div(style="height:12px")`
   spacers, no inline `margin-top:10px`. The scale (owned by [§2](02-color-palette-plan.md),
   added to the base token block at
   [debrowser.css:342–389](../../inst/extdata/www/debrowser.css#L342)):

   ```
   --de-space-1: 4px   --de-space-2: 8px   --de-space-3: 12px
   --de-space-4: 16px  --de-space-5: 20px  --de-space-6: 24px
   --de-dur: 140ms     --de-ease: cubic-bezier(.2,.6,.2,1)
   ```

**Why `layout_columns` and not `layout_column_wrap`.** `layout_column_wrap(width = 1/2)` is a
*flow* layout — it packs as many equal-width cells per row as fit, so "two 50/50 cards"
silently becomes "three then one" if a third card is ever added, and its cell widths are not
the 12-col vocabulary the rest of the app speaks. `layout_columns(col_widths = c(6,6))` is an
*explicit* 2-up that stays a 2-up.

---

## Global constraints (inherited from [README](README.md#global-constraints))

- **Additive & reversible.** Keep the `html[data-debrowser-redesign="1"]` gate; never break
  `?redesign=0`.
- **Both themes always.** Verify every task in **light and dark** (`T` shortcut).
- **Bioconductor package.** `R/` roxygen and `man/*.Rd` stay in sync — after editing
  `de_card()`'s signature run `devtools::document()` and commit the regenerated `.Rd`. New
  behavior gets a `NEWS.md` line. `R CMD build` / `BiocCheck` must stay clean.
- **House style.** Tokens are `--de-*`; modules use `ns()`; keep each file's existing
  `shiny::` / `bslib::` namespacing convention (the `mod_*.R` files fully qualify; the older
  `uifuncs.R` / `deprogs.R` / `dataLoad.R` do not — match the file you are editing).
- **Verify before "done."** Run the app and look before committing.

---

## How this maps onto the three waves

| Wave | Tasks | Character |
|---|---|---|
| **1 — Quick wins** | G1–G6 | Mechanical, low-risk, independent. Ragged rows, floating siblings, sidebar width. Do in any order. |
| **2 — Consolidation** | G7–G14 | The "one of each" pass. Extend `de_card()`, migrate the 50/50 idioms and the hand-rolled grid, route raw cards through `de_card()`. |
| **3 — System** | G15–G17 | Make it *stay* consolidated. Adopt spacing + plot-height tokens, add the grid lint/check. |

> **Reconciliation note (worklist drift).** The intake worklist cited a floating button at
> `R/uifuncs.R:436`. Reading current source, line 436 is `column(6, getBoxMainPlotUI("boxmain"))`
> inside `getMainPanel()` — a **clean 50/50**, no floating sibling. The real floating-sibling
> sites in current source are `R/deprogs.R` (the `goMain` button, [G4](#task-g4--un-float-the-gomain-button-deprogsr))
> and `R/batcheffect.R` (the batch `tabsetPanel`, [G5](#task-g5--wrap-the-floating-tabsetpanel-batcheffectr)).
> `getMainPanel()` is migrated as a 50/50 in [G9](#task-g9--migrate-the-5050-idioms-to-layout_columns).

---

# Wave 1 — Quick wins (G1–G6)

## Task G1 — Fix the ragged control row in Concordance (`3+3` → `c(6,6)`)

**File:** [R/mod_comparison_concordance.R:43–52](../../R/mod_comparison_concordance.R#L43)
The padj / |log2FC| controls sit in a `fluidRow` of two `column(3)` — the row sums to **6**,
leaving the right half empty and the inputs floating mid-card.

- [ ] Replace the `fluidRow` with a `layout_columns(col_widths = c(6, 6))`.

**Before**
```r
        shiny::fluidRow(
          shiny::column(3,
            shiny::numericInput(ns("padj"), "padj <=",
                                value = 0.05, min = 0, max = 1, step = 0.01)
          ),
          shiny::column(3,
            shiny::numericInput(ns("lfc"), "|log2FC| >=",
                                value = 0, min = 0, step = 0.1)
          )
        )
```

**After**
```r
        bslib::layout_columns(
          col_widths = c(6, 6),
          shiny::numericInput(ns("padj"), "padj <=",
                              value = 0.05, min = 0, max = 1, step = 0.01),
          shiny::numericInput(ns("lfc"), "|log2FC| >=",
                              value = 0, min = 0, step = 0.1)
        )
```

**Verify.** Load the Concordance tab (needs ≥ 2 comparisons). The two inputs now split the
card evenly. Grep confirms the ragged row is gone:
`grep -n "column(3" R/mod_comparison_concordance.R` → no hits.

**Commit.** `git commit -am "fix(grid): concordance padj/lfc row 3+3 -> layout_columns c(6,6)"`

---

## Task G2 — Fix the ragged control row in the NES heatmap (`3+3+3` → `c(4,4,4)`)

**File:** [R/mod_enrichment_nes_heatmap.R:23–37](../../R/mod_enrichment_nes_heatmap.R#L23)
Three `column(3)` controls sum to **9**, leaving a quarter of the row dead.

- [ ] Replace the `fluidRow` with `layout_columns(col_widths = c(4, 4, 4))` (equal thirds).

**Before**
```r
      shiny::fluidRow(
        shiny::column(
          3,
          shiny::checkboxInput(ns("flip_axis"), "Invert axes", FALSE)
        ),
        shiny::column(
          3,
          shiny::checkboxInput(ns("sig_only"), "Significant only", TRUE)
        ),
        shiny::column(
          3,
          shiny::numericInput(ns("sig_threshold"), "padj cutoff", 0.05,
                              min = 0, max = 1, step = 0.01)
        )
      )
```

**After**
```r
      bslib::layout_columns(
        col_widths = c(4, 4, 4),
        shiny::checkboxInput(ns("flip_axis"), "Invert axes", FALSE),
        shiny::checkboxInput(ns("sig_only"), "Significant only", TRUE),
        shiny::numericInput(ns("sig_threshold"), "padj cutoff", 0.05,
                            min = 0, max = 1, step = 0.01)
      )
```

**Verify.** Run GSEA with ≥ 2 comparisons so the NES heatmap card renders; the three controls
now fill the row in even thirds. `grep -n "column(3" R/mod_enrichment_nes_heatmap.R` → no hits.

**Commit.** `git commit -am "fix(grid): NES heatmap controls 3+3+3 -> layout_columns c(4,4,4)"`

---

## Task G3 — Drop the lone `column(6)` around the DE-method selector

**File:** [R/mod_condselect.R:694–700](../../R/mod_condselect.R#L694)
A single `selectInput` is wrapped in `fluidRow(column(6, …))`. The row sums to 6, and the
control already carries `width = "100%"`, so the wrapper only squeezes it into the left half
for no reason. A single element needs no grid (standard rule 2).

- [ ] Delete the `fluidRow`/`column(6)` wrapper; let the `selectInput` sit directly in the
  card body.

**Before**
```r
          shiny::fluidRow(shiny::column(
            6,
            shiny::selectInput(iid("de_method"),
              label = "DE method",
              choices = c("DESeq2", "EdgeR", "Limma"),
              selected = rv$de_method, width = "100%")
          )),
```

**After**
```r
          shiny::selectInput(iid("de_method"),
            label = "DE method",
            choices = c("DESeq2", "EdgeR", "Limma"),
            selected = rv$de_method, width = "100%"),
```

**Verify.** Open CondSelect, expand a comparison's "Differential expression model" card — the
DE-method dropdown spans the card body cleanly, the "Advanced model settings" accordion sits
directly beneath it. `grep -n "column(" R/mod_condselect.R` → only the intended `c(5,2,5)`
`column(5)/column(2)/column(5)` treatment/swap/control row remains (migrated later in G9's
family; see note there).

**Commit.** `git commit -am "fix(grid): drop lone column(6) around de_method selector"`

---

## Task G4 — Un-float the `goMain` button (`deprogs.R`)

**File:** [R/deprogs.R:73–79](../../R/deprogs.R#L73)
Inside `getDEResultsUI()`, the "Go to Main Plots" button is a **bare sibling** of `column(12)`
inside the `fluidRow`, so it renders outside the grid track (floated hard against the row edge,
no gutter).

- [ ] Move the button **inside** the `column(12)` so it lives in the grid.

**Before**
```r
        fluidRow(
          column(
            12,
            uiOutput(ns("DEResults"))
          ),
          actionButtonDE("goMain", "Go to Main Plots", styleclass = "primary")
        )
```

**After**
```r
        fluidRow(
          column(
            12,
            uiOutput(ns("DEResults")),
            actionButtonDE("goMain", "Go to Main Plots", styleclass = "primary")
          )
        )
```

> The redundant `fluidRow`/`column(12)` wrapper and the raw card around it are fully collapsed
> to `de_card()` in [G13](#task-g13--route-remaining-raw-cards-through-de_card). This quick win
> is just the low-risk float fix.

**Verify.** Finish a DE run so the "DE Results" card shows; the button now aligns to the card
body's left edge with normal padding instead of hugging the card border.

**Commit.** `git commit -am "fix(grid): move goMain button inside its grid column"`

---

## Task G5 — Wrap the floating `tabsetPanel` (`batcheffect.R`)

**File:** [R/batcheffect.R:177–179](../../R/batcheffect.R#L177)
The batch-effect "Plots" card opens a `fluidRow` whose first child is a hacky
`column(1, div())` left-indent spacer and whose second child is a bare `tabsetPanel` — the
tabset is not inside any column, so it escapes the grid.

- [ ] Delete the `column(1, div())` spacer and wrap the `tabsetPanel` in a `column(12)`.

**Before**
```r
        fluidRow(
          column(1, div()),
          tabsetPanel(
            id = ns("batchTabs"),
            tabPanel(
              id = ns("PCA"), "PCA",
              # ... PCA / IQR / Density tabPanel bodies unchanged (lines 181-233) ...
            )
          )
        )
```

**After**
```r
        fluidRow(
          column(
            12,
            tabsetPanel(
              id = ns("batchTabs"),
              tabPanel(
                id = ns("PCA"), "PCA",
                # ... PCA / IQR / Density tabPanel bodies unchanged (lines 181-233) ...
              )
            )
          )
        )
```

> The tab bodies themselves already use the `c(5,2,5)` vocabulary
> (`column(5)/column(2)/column(5)`, lines 183–232) — leave them; they are on-standard as
> classic columns and get normalized when the file's cards migrate in G9/G13.

**Verify.** Open Data Prep → Batch effect, run a correction; the PCA/IQR/Density tabset now
starts at the card's left padding (no 1/12 phantom indent) and fills the card width.

**Commit.** `git commit -am "fix(grid): wrap batch tabsetPanel in column(12), drop spacer col"`

---

## Task G6 — Unify the nested sidebar width (280 → 300)

**File:** [R/mod_enrichment.R:31–32](../../R/mod_enrichment.R#L31)
The global shell sidebar is `width = 300` ([ui.R:339](../../R/ui.R#L339)); the Enrichment
module's own `layout_sidebar` uses `width = 280`. Pick one.

- [ ] Change `280` → `300`.

**Before**
```r
    sidebar = bslib::sidebar(
      width = 280,
```

**After**
```r
    sidebar = bslib::sidebar(
      width = 300,
```

**Verify.** `grep -rn "width = 28" R/` → no hits; `grep -rn "sidebar(" R/*.R` shows only
`300` widths for the app sidebars.

> **[System] follow-up (not this task).** `enrichmentUI()` builds a `layout_sidebar` — i.e. a
> **second** sidebar nested inside a page that already owns the global one. In current source
> `enrichmentUI` is not referenced from [R/ui.R](../../R/ui.R) (the live Enrichment navbar tab
> renders `getGoPanel()` via `uiOutput("gopanel")`), so this is latent rather than visible.
> Whether a nav-panel module should ever render its own sidebar under the shell sidebar is an
> architecture call — track it in [§6 Handoff](06-handoff-plan.md), not here. This task only
> removes the width disagreement so that if it is ever mounted it matches.

**Commit.** `git commit -am "fix(grid): unify enrichment sidebar width 280 -> 300"`

---

# Wave 2 — Consolidation (G7–G14)

## Task G7 — Extend `de_card()` with a `class` passthrough (enabler)

**File:** [R/de_card.R:17,35](../../R/de_card.R#L17)
Several raw cards carry a `class` (`de-comparison`, `de-subcard`) that the redesign CSS hooks.
`de_card()` currently drops any class, which blocks migrating those cards. Add a `class`
argument that forwards to `bslib::card()`.

- [ ] Add `class = NULL` to the signature and forward it; document the param.

**Before**
```r
#' @param full_screen logical -- passed through to `bslib::card()`
#'
#' @return a `bslib::card` tagList
#' @examples
#' x <- de_card("Heatmap", shiny::plotOutput("heat"))
#' @export
de_card <- function(title, ..., download_id = NULL, full_screen = FALSE) {
  header <- if (is.null(download_id)) {
    bslib::card_header(title)
  } else {
    bslib::card_header(
      class = "d-flex align-items-center",
      title,
      shiny::tags$div(
        class = "ms-auto",
        shiny::downloadButton(
          download_id,
          label = NULL,
          icon  = shiny::icon("download"),
          class = "btn-primary btn-sm"
        )
      )
    )
  }
  bslib::card(header, ..., full_screen = full_screen)
}
```

**After**
```r
#' @param full_screen logical -- passed through to `bslib::card()`
#' @param class character or NULL -- extra CSS class(es) forwarded to
#'   `bslib::card()` (e.g. "de-subcard", "de-comparison")
#'
#' @return a `bslib::card` tagList
#' @examples
#' x <- de_card("Heatmap", shiny::plotOutput("heat"))
#' @export
de_card <- function(title, ..., download_id = NULL, full_screen = FALSE,
                    class = NULL) {
  header <- if (is.null(download_id)) {
    bslib::card_header(title)
  } else {
    bslib::card_header(
      class = "d-flex align-items-center",
      title,
      shiny::tags$div(
        class = "ms-auto",
        shiny::downloadButton(
          download_id,
          label = NULL,
          icon  = shiny::icon("download"),
          class = "btn-primary btn-sm"
        )
      )
    )
  }
  bslib::card(header, ..., full_screen = full_screen, class = class)
}
```

- [ ] Regenerate the manual page and keep it in the commit:
  ```r
  devtools::document()   # updates man/de_card.Rd
  ```

**Verify.** `R -q -e 'debrowser::de_card("X", shiny::p("y"), class="de-subcard")'` renders a
card whose outer `<div>` carries `card de-subcard`. `git status` shows `man/de_card.Rd` staged.

**Commit.** `git commit -am "feat(de_card): add class passthrough for subcard/comparison hooks"`

---

## Task G8 — Retire `layout_column_wrap(width = 1/2)` (3 sites) → `layout_columns(c(6,6))` + `de_card()`

Three modules use the flow layout `layout_column_wrap(width = 1/2)` around **raw** cards. Fix
the grid and the card in one edit each. The `de_card()` download convention moves the two
"Download" body buttons into their card headers (icon-only, consistent with every other
download in the app; the output IDs are unchanged so the `downloadHandler`s still fire).

### G8a — GO panel fgsea mode
**File:** [R/gopanel.R:44–57](../../R/gopanel.R#L44)

- [ ] Migrate.

**Before**
```r
      bslib::layout_column_wrap(
        width = 1 / 2,
        bslib::card(
          bslib::card_header("Results"),
          bslib::card_body(
            DT::DTOutput("fgsea_results_table"),
            downloadButton("fgsea_download_results", "Download")
          )
        ),
        bslib::card(
          bslib::card_header("Enrichment plot"),
          bslib::card_body(plotOutput("fgsea_enrichment_plot"))
        )
      ),
```

**After**
```r
      bslib::layout_columns(
        col_widths = c(6, 6),
        de_card(
          "Results",
          download_id = "fgsea_download_results",
          DT::DTOutput("fgsea_results_table")
        ),
        de_card(
          "Enrichment plot",
          plotOutput("fgsea_enrichment_plot")
        )
      ),
```

### G8b — Enrichment module
**File:** [R/mod_enrichment.R:57–70](../../R/mod_enrichment.R#L57)

- [ ] Migrate (note the `ns()` on both the download id and the outputs).

**Before**
```r
    bslib::layout_column_wrap(
      width = 1 / 2,
      bslib::card(
        bslib::card_header("Results"),
        bslib::card_body(
          DT::DTOutput(ns("results_table")),
          shiny::downloadButton(ns("download_results"), "Download")
        )
      ),
      bslib::card(
        bslib::card_header("Enrichment plot"),
        bslib::card_body(shiny::plotOutput(ns("enrichment_plot")))
      )
    ),
```

**After**
```r
    bslib::layout_columns(
      col_widths = c(6, 6),
      de_card(
        "Results",
        download_id = ns("download_results"),
        DT::DTOutput(ns("results_table"))
      ),
      de_card(
        "Enrichment plot",
        shiny::plotOutput(ns("enrichment_plot"))
      )
    ),
```

### G8c — Concordance (two stacked 50/50 blocks)
**File:** [R/mod_comparison_concordance.R:55–82](../../R/mod_comparison_concordance.R#L55)

- [ ] Migrate both blocks; also migrate the inner scatter x/y selector `fluidRow` (lines
  75–78) to `layout_columns`. Keep the plot-height literals here — they are tokenized in
  [G16](#task-g16--tokenize-the-hard-coded-plot-heights).

**Before**
```r
    bslib::layout_column_wrap(
      width = 1 / 2,
      bslib::card(
        bslib::card_header("DEGs per comparison (up / down)"),
        bslib::card_body(shiny::plotOutput(ns("deg_bar"), height = "420px"))
      ),
      bslib::card(
        bslib::card_header("Pairwise DEG count heatmap"),
        bslib::card_body(shiny::plotOutput(ns("deg_heatmap"), height = "420px"))
      )
    ),
    bslib::layout_column_wrap(
      width = 1 / 2,
      bslib::card(
        bslib::card_header("Overlap (UpSet)"),
        bslib::card_body(shiny::plotOutput(ns("upset"), height = "420px"))
      ),
      bslib::card(
        bslib::card_header("Pairwise log2FC scatter"),
        bslib::card_body(
          shiny::fluidRow(
            shiny::column(6, shiny::uiOutput(ns("scatter_x_ui"))),
            shiny::column(6, shiny::uiOutput(ns("scatter_y_ui")))
          ),
          shiny::plotOutput(ns("scatter"), height = "360px")
        )
      )
    ),
```

**After**
```r
    bslib::layout_columns(
      col_widths = c(6, 6),
      de_card(
        "DEGs per comparison (up / down)",
        shiny::plotOutput(ns("deg_bar"), height = "420px")
      ),
      de_card(
        "Pairwise DEG count heatmap",
        shiny::plotOutput(ns("deg_heatmap"), height = "420px")
      )
    ),
    bslib::layout_columns(
      col_widths = c(6, 6),
      de_card(
        "Overlap (UpSet)",
        shiny::plotOutput(ns("upset"), height = "420px")
      ),
      de_card(
        "Pairwise log2FC scatter",
        bslib::layout_columns(
          col_widths = c(6, 6),
          shiny::uiOutput(ns("scatter_x_ui")),
          shiny::uiOutput(ns("scatter_y_ui"))
        ),
        shiny::plotOutput(ns("scatter"), height = "360px")
      )
    ),
```

**Verify (G8a–c).** `grep -rn "layout_column_wrap" R/` → **no hits**. Open each surface (GO
Term fgsea mode; Enrichment tab; Concordance tab) in both themes — cards still sit two-up, the
download icon is now in each "Results" header, and downloads still work.

**Commit.** `git commit -am "refactor(grid): layout_column_wrap(1/2) -> layout_columns c(6,6) + de_card (gopanel, enrichment, concordance)"`

---

## Task G9 — Migrate the classic `column(6)/column(6)` 50/50 idioms to `layout_columns`

Three sites use the classic `fluidRow(column(6, …), column(6, …))` 50/50. Where a cell holds
two children, wrap them in a `tagList` (one positional arg per `layout_columns` cell).

### G9a — `getMainPanel()` (main plots grid)
**File:** [R/uifuncs.R:419–442](../../R/uifuncs.R#L419)

**Before**
```r
getMainPanel <- function() {
  list(
    fluidRow(
      column(
        6,
        getMainPlotUI("main")
      ),
      column(
        6,
        getHeatmapUI("heatmap")
      )
    ),
    fluidRow(
      column(
        6,
        getBarMainPlotUI("barmain")
      ),
      column(
        6,
        getBoxMainPlotUI("boxmain")
      )
    )
  )
}
```

**After**
```r
getMainPanel <- function() {
  list(
    bslib::layout_columns(
      col_widths = c(6, 6),
      getMainPlotUI("main"),
      getHeatmapUI("heatmap")
    ),
    bslib::layout_columns(
      col_widths = c(6, 6),
      getBarMainPlotUI("barmain"),
      getBoxMainPlotUI("boxmain")
    )
  )
}
```

### G9b — LCF "Histograms" (before ‖ after)
**File:** [R/lowcountfilter.R:166–178](../../R/lowcountfilter.R#L166)
Each column holds a controls UI **and** a histogram UI — wrap each pair in `tagList`. Also
migrates the raw wrapper card → `de_card()`.

**Before**
```r
      bslib::card(
        bslib::card_header("Histograms"),
        fluidRow(
          column(
            6, histogramControlsUI(ns("beforeFiltering")),
            getHistogramUI(ns("beforeFiltering"))
          ),
          column(
            6, histogramControlsUI(ns("afterFiltering")),
            getHistogramUI(ns("afterFiltering"))
          )
        )
      )
```

**After**
```r
      de_card(
        "Histograms",
        bslib::layout_columns(
          col_widths = c(6, 6),
          tagList(
            histogramControlsUI(ns("beforeFiltering")),
            getHistogramUI(ns("beforeFiltering"))
          ),
          tagList(
            histogramControlsUI(ns("afterFiltering")),
            getHistogramUI(ns("afterFiltering"))
          )
        )
      )
```

### G9c — Upload "Show all options" separator radios
**File:** [R/dataLoad.R:476–479](../../R/dataLoad.R#L476)

**Before**
```r
                fluidRow(
                  column(6, sepRadio(id, "countdataSep")),
                  column(6, sepRadio(id, "metadataSep"))
                )
```

**After**
```r
                bslib::layout_columns(
                  col_widths = c(6, 6),
                  sepRadio(id, "countdataSep"),
                  sepRadio(id, "metadataSep")
                )
```

**Verify (G9a–c).** Main Plots renders volcano ‖ heatmap and barplot ‖ boxplot two-up; LCF
"Histograms" card shows before ‖ after; the Upload "Show all options" accordion shows the two
separator radios side-by-side. `grep -n "column(6" R/uifuncs.R R/dataLoad.R` shows no 50/50
rows remain (the `column(6)` at `getAfterLoadMsg`/`getStartPlotsMsg`/`getStartupMsg` are lone
`column(12)`, untouched).

**Commit.** `git commit -am "refactor(grid): classic column(6)/column(6) -> layout_columns c(6,6) (main panel, LCF histograms, upload seps)"`

---

## Task G10 — Migrate the hand-rolled CSS grid on the upload page

**File:** [R/dataLoad.R:421–461](../../R/dataLoad.R#L421)
The two drop tiles are laid out by an inline `display:grid; grid-template-columns:1fr 1fr;
gap:12px` — a fourth grid idiom. Move to `layout_columns(col_widths = c(6,6))` with a token
gap; keep `class = "de-drop-grid"` only as a styling hook (the tile visuals live on `.de-drop`,
not the grid container).

- [ ] Swap the wrapper `div` for `layout_columns`.

**Before**
```r
          div(class = "de-drop-grid",
              style = "display:grid; grid-template-columns: 1fr 1fr; gap:12px;",
            # Tile 1: Count Data (required)
            div(class = "de-drop",
              # ... tile 1 body unchanged (lines 424-440) ...
            ),
            # Tile 2: Metadata (optional)
            div(class = "de-drop",
              # ... tile 2 body unchanged (lines 442-460) ...
            )
          ),
```

**After**
```r
          bslib::layout_columns(
            col_widths = c(6, 6),
            gap = "var(--de-space-3)",
            class = "de-drop-grid",
            # Tile 1: Count Data (required)
            div(class = "de-drop",
              # ... tile 1 body unchanged (lines 424-440) ...
            ),
            # Tile 2: Metadata (optional)
            div(class = "de-drop",
              # ... tile 2 body unchanged (lines 442-460) ...
            )
          ),
```

- [ ] **Delete the now-conflicting collapse rule** in the CSS. `layout_columns` already stacks
  responsively on narrow viewports, and it drives the container with a 12-col
  `grid-template-columns`; the old `1fr !important` override would fight it. Remove
  [debrowser.css:2534–2539](../../inst/extdata/www/debrowser.css#L2534):

  ```css
  /* Two-column grid responsive: collapse to one column under 880 px */
  @media (max-width: 880px) {
    html[data-debrowser-redesign="1"] .de-drop-grid {
      grid-template-columns: 1fr !important;
    }
  }
  ```

**Verify.** Fresh upload page (pre-upload state): the two drop tiles sit side-by-side with a
12px gutter, and collapse to a single column when the window is narrowed below the `sm`
breakpoint. `grep -rn "display:grid\|display: grid" R/` → **no hits**. Check `?redesign=0`
still renders the tiles (stacked, unstyled) without error.

**Commit.** `git commit -am "refactor(grid): drop tiles hand-rolled display:grid -> layout_columns c(6,6)"`

---

## Task G11 — Route the LCF & Batch-effect wrapper cards through `de_card()`

These two files already use the `c(5,2,5)` vocabulary **inside** a raw wrapper card. Convert
only the wrapper; the inner `layout_columns(col_widths = c(5,2,5))` and the inner `de_card()`s
are already on-standard.

### G11a — Low Count Filtering wrapper
**File:** [R/lowcountfilter.R:113–165](../../R/lowcountfilter.R#L113)

**Before**
```r
      bslib::card(
        bslib::card_header("Low Count Filtering"),
        bslib::layout_columns(
          col_widths = c(5, 2, 5),
          # ... three cells unchanged (lines 117-159) ...
        ),
        # B3.23 -- The next-step CTAs were moved INSIDE the Filtering
        # Methods card above. This empty placeholder kept for visual
        # spacing only; intentionally rendering nothing.
        NULL
      ),
```

**After**
```r
      de_card(
        "Low Count Filtering",
        bslib::layout_columns(
          col_widths = c(5, 2, 5),
          # ... three cells unchanged (lines 117-159) ...
        )
      ),
```
> (The trailing `NULL` placeholder is dropped — `de_card` needs no manual spacer; card gap is
> handled by the layout.)

### G11b — Batch Effect Correction wrapper
**File:** [R/batcheffect.R:130–173](../../R/batcheffect.R#L130)

**Before**
```r
      bslib::card(
        bslib::card_header("Batch Effect Correction and Normalization"),
        bslib::layout_columns(
          col_widths = c(5, 2, 5),
          # ... three cells unchanged (lines 134-172) ...
        )
      ),
```

**After**
```r
      de_card(
        "Batch Effect Correction and Normalization",
        bslib::layout_columns(
          col_widths = c(5, 2, 5),
          # ... three cells unchanged (lines 134-172) ...
        )
      ),
```

- [ ] Also migrate the Batch "Plots" wrapper card
  ([R/batcheffect.R:175](../../R/batcheffect.R#L175)) once G5 has fixed its inner
  `fluidRow`: `bslib::card(bslib::card_header("Plots"), …)` → `de_card("Plots", …)`.

**Verify.** LCF and Batch pages render identically (same header, same 3-column body). Both
cards now show in `grep -n "de_card(" R/lowcountfilter.R R/batcheffect.R` and drop out of the
raw-card grep in [G17](#task-g17--add-the-grid-lintcheck).

**Commit.** `git commit -am "refactor(cards): LCF + batch wrapper cards -> de_card()"`

---

## Task G12 — Migrate the CondSelect comparison card + subcards to `de_card()`

**File:** [R/mod_condselect.R:639–693](../../R/mod_condselect.R#L639)
Depends on [G7](#task-g7--extend-de_card-with-a-class-passthrough-enabler) (`class`
passthrough). The comparison card carries `class = "de-comparison"` and a **dynamic** header
(`textOutput`); the three subcards carry `class = "de-subcard"`.

- [ ] Migrate the outer comparison card (dynamic title as the `title` argument):

**Before**
```r
  bslib::card(
    class = "de-comparison",
    bslib::card_header(shiny::textOutput(iid("title"), inline = TRUE)),
    bslib::card_body(
      bslib::card(
        class = "de-subcard",
        bslib::card_header("Sample grouping"),
        bslib::card_body(
          shiny::selectInput(iid("meta_column"),
            label = "Group by metadata column",
            choices = meta_choices,
            selected = if (is.na(rv$meta_column)) NA_character_ else rv$meta_column,
            width = "100%")
        )
      ),
```

**After**
```r
  de_card(
    shiny::textOutput(iid("title"), inline = TRUE),
    class = "de-comparison",
    de_card(
      "Sample grouping",
      class = "de-subcard",
      shiny::selectInput(iid("meta_column"),
        label = "Group by metadata column",
        choices = meta_choices,
        selected = if (is.na(rv$meta_column)) NA_character_ else rv$meta_column,
        width = "100%")
    ),
```

- [ ] Apply the identical `bslib::card(class="de-subcard", bslib::card_header(X),
  bslib::card_body(Y))` → `de_card(X, class="de-subcard", Y)` swap to the remaining subcards:
  **Treatment** ([:656](../../R/mod_condselect.R#L656)), **Control**
  ([:676](../../R/mod_condselect.R#L676)), and **Differential expression model**
  ([:690](../../R/mod_condselect.R#L690)). The `c(5,2,5)` Treatment/Swap/Control `fluidRow`
  ([:654](../../R/mod_condselect.R#L654)) also converts to
  `layout_columns(col_widths = c(5, 2, 5), …)` (three `tagList`-free cells — each `column` here
  wraps a single subcard, so lift each subcard straight into a positional arg).

**Verify.** CondSelect renders each comparison with the nested subcard styling intact (the
`.de-comparison` / `.de-subcard` CSS still applies because G7 forwards `class`). Add a second
comparison — the dynamic titles still update via `textOutput`.

**Commit.** `git commit -am "refactor(cards): condselect comparison + subcards -> de_card(class=)"`

---

## Task G13 — Route remaining raw cards through `de_card()`

Plain *title + body* raw cards left after G8–G12. Each is the mechanical swap
`bslib::card(bslib::card_header("X"), bslib::card_body(Y))` → `de_card("X", Y)`.

- [ ] **GO panel** ([R/gopanel.R](../../R/gopanel.R)): "Leading edge"
  ([:58](../../R/gopanel.R#L58)) and "AI interpretation" ([:72](../../R/gopanel.R#L72)).
- [ ] **Enrichment module** ([R/mod_enrichment.R:71](../../R/mod_enrichment.R#L71)):
  "Leading edge".
- [ ] **NES heatmap** ([R/mod_enrichment_nes_heatmap.R:19](../../R/mod_enrichment_nes_heatmap.R#L19)):
  the "NES heatmap" card.
- [ ] **Concordance** ([R/mod_comparison_concordance.R](../../R/mod_comparison_concordance.R)):
  "Comparison Concordance" ([:32](../../R/mod_comparison_concordance.R#L32)), "Concordance
  summary (pairwise)" ([:83](../../R/mod_comparison_concordance.R#L83)), and "AI interpretation"
  ([:89](../../R/mod_comparison_concordance.R#L89)).
- [ ] **DE Results** ([R/deprogs.R:71](../../R/deprogs.R#L71)): collapse the redundant
  `fluidRow`/`column(12)` from G4 as you migrate.

**Representative before/after** (NES heatmap — every other site is the same shape):

**Before**
```r
enrichmentNesHeatmapUI <- function(id) {
  ns <- shiny::NS(id)
  bslib::card(
    bslib::card_header("NES heatmap"),
    bslib::card_body(
      shiny::plotOutput(ns("heatmap"), height = "500px"),
      # ... controls layout_columns from G2 ...
    )
  )
}
```

**After**
```r
enrichmentNesHeatmapUI <- function(id) {
  ns <- shiny::NS(id)
  de_card(
    "NES heatmap",
    shiny::plotOutput(ns("heatmap"), height = "500px"),
    # ... controls layout_columns from G2 ...
  )
}
```

**DE Results** ([R/deprogs.R:71–80](../../R/deprogs.R#L71)) — collapse the wrapper from G4:

**Before**
```r
    fluidRow(
      bslib::card(
        bslib::card_header("DE Results"),
        fluidRow(
          column(
            12,
            uiOutput(ns("DEResults")),
            actionButtonDE("goMain", "Go to Main Plots", styleclass = "primary")
          )
        )
      )
    ),
```

**After**
```r
    de_card(
      "DE Results",
      uiOutput(ns("DEResults")),
      actionButtonDE("goMain", "Go to Main Plots", styleclass = "primary")
    ),
```

**Verify.** `grep -rn "bslib::card_header(" R/` returns only the documented exceptions from
[G14](#task-g14--document-the-raw-card-exceptions) (and `de_card.R` itself). Walk the
Enrichment, GO Term, Concordance and DE-Results surfaces in both themes — headers, downloads
and bodies look unchanged.

**Commit.** `git commit -am "refactor(cards): route remaining title+body cards through de_card()"`

---

## Task G14 — Document the raw-card exceptions

A few cards have **custom header content** `de_card()` can't express (it only supports
*title + optional header download*). These stay raw — but each must say so, so the lint in
[G17](#task-g17--add-the-grid-lintcheck) can allowlist them and a future reader doesn't "fix"
them by mistake.

- [ ] **Upload "Inputs" card** ([R/dataLoad.R:411–418](../../R/dataLoad.R#L411)) — header holds
  a `card-title` span **plus** an `ms-auto` file-types badge. Add a comment above it:

  ```r
      # RAW CARD (de_card exception): custom header = title span + file-types
      # badge, which de_card()'s title/download-only header can't express.
      bslib::card(
        bslib::card_header(
          class = "d-flex align-items-center",
          tags$span(class = "card-title", "Inputs"),
          tags$span(class = "ms-auto",
                    style = "font-size:10.5px; padding:2px 8px; ...",
                    ".tsv · .csv · .txt · .csv.gz")
        ),
        # ... body unchanged ...
      )
  ```

- [ ] Audit for any other raw card that survived G8–G13 and either migrate it or annotate it
  the same way. After this task, **every** `bslib::card(` in `R/` is either inside `de_card.R`,
  or `enrichmentUI`/`heatmap.R`'s `layout_sidebar` scaffolding, or carries the
  `# RAW CARD (de_card exception): …` comment.

**Verify.** `grep -rn "bslib::card(" R/ | grep -v de_card.R` — every remaining hit has an
exception comment on the line above (confirm by eye) or is a `layout_sidebar`.

**Commit.** `git commit -am "docs(cards): annotate raw-card de_card() exceptions"`

---

# Wave 3 — System (G15–G17)

## Task G15 — Adopt spacing tokens (kill the manual pixel spacers)

**File:** [R/dataLoad.R](../../R/dataLoad.R)
The upload page uses `tags$div(style="height:12px")` spacers and inline `margin-top` pixels.
Replace stacking spacers with a `gap` container, and inline margins with `var(--de-space-N)`.

### G15a — Post-upload card stack (spacers → gap, + fold in the raw "Sample design" card)
**File:** [R/dataLoad.R:500–529](../../R/dataLoad.R#L500)

**Before**
```r
    conditionalPanel(
      condition = paste0("output['", ns("dataloaded"), "']"),
      div(class = "de-data-workbar",
        uiOutput(ns("statStrip")),
        div(class = "spacer", style = "flex:1"),
        div(class = "de-data-workbar-actions",
            uiOutput(ns("nextButton"))
        )
      ),
      tags$div(style = "height:12px"),
      de_card(
        title = "Preview · count matrix",
        div(class = "de-compact-table",
            style = "overflow:auto; max-height: 280px;",
            tableOutput(ns("countPreview")))
      ),
      tags$div(style = "height:12px"),
      bslib::card(
        bslib::card_header("Sample design"),
        bslib::card_body(
          div(class = "de-compact-table",
              style = "overflow:auto; max-height: 320px;",
              DT::dataTableOutput(ns("sampleDetails")))
        )
      )
    )
```

**After**
```r
    conditionalPanel(
      condition = paste0("output['", ns("dataloaded"), "']"),
      div(
        style = "display:flex; flex-direction:column; gap:var(--de-space-3);",
        div(class = "de-data-workbar",
          uiOutput(ns("statStrip")),
          div(class = "spacer", style = "flex:1"),
          div(class = "de-data-workbar-actions",
              uiOutput(ns("nextButton"))
          )
        ),
        de_card(
          title = "Preview · count matrix",
          div(class = "de-compact-table",
              style = "overflow:auto; max-height: 280px;",
              tableOutput(ns("countPreview")))
        ),
        de_card(
          title = "Sample design",
          div(class = "de-compact-table",
              style = "overflow:auto; max-height: 320px;",
              DT::dataTableOutput(ns("sampleDetails")))
        )
      )
    )
```
> Removes both `height:12px` spacers (gap owns the rhythm now) **and** the last raw card
> (folded into `de_card`, finishing G13 for this file).

### G15b — Inline `margin-top` / `gap` pixels → tokens
**File:** [R/dataLoad.R:465–495](../../R/dataLoad.R#L465). Normalize to the 4px scale
(10px → `--de-space-3` = 12px; 14px → `--de-space-4` = 16px; 8px gap → `--de-space-2`).

**Before**
```r
            div(class = "de-detect-fail-caption",
                style = "margin-top:10px;",
                "Couldn't auto-detect the separator -- pick it under Show all options.")
          ),
          # "Show all options" accordion
          div(style = "margin-top:14px;",
          # ...
          div(class = "de-action-row",
              style = "margin-top:14px; display:flex; align-items:center; gap:8px; flex-wrap:wrap;",
```

**After**
```r
            div(class = "de-detect-fail-caption",
                style = "margin-top:var(--de-space-3);",
                "Couldn't auto-detect the separator -- pick it under Show all options.")
          ),
          # "Show all options" accordion
          div(style = "margin-top:var(--de-space-4);",
          # ...
          div(class = "de-action-row",
              style = "margin-top:var(--de-space-4); display:flex; align-items:center; gap:var(--de-space-2); flex-wrap:wrap;",
```

**Verify.** Upload page (pre- and post-upload) spacing looks unchanged (±2px on the two
normalized margins is intentional). `grep -n "height:12px\|margin-top:1[04]px\|gap:8px\|gap:12px" R/dataLoad.R`
→ **no hits**. Confirm `var(--de-space-*)` resolves under `?redesign=1` and degrades to `0`
(no gap, still valid) under `?redesign=0`.

**Commit.** `git commit -am "refactor(spacing): dataLoad manual pixel spacers -> --de-space-* / gap"`

---

## Task G16 — Tokenize the hard-coded plot heights

Five `plotOutput(height=…)` literals disagree by intent-free magic numbers: `420px` ×3
(concordance), `360px` (scatter), `500px` (NES heatmap). Give them a three-tier source so they
can't drift. Add three tokens to the base block (next to the `--de-space-*` block §2 owns) and
reference them.

- [ ] Add to `html[data-debrowser-redesign="1"]` in
  [debrowser.css:342–389](../../inst/extdata/www/debrowser.css#L342):

  ```css
  /* Plot-height scale — single source for plotOutput(height=) */
  --de-plot-h-sm: 360px;
  --de-plot-h-md: 420px;
  --de-plot-h-lg: 500px;
  ```

- [ ] Replace the literals:

  | File:line | Before | After |
  |---|---|---|
  | [mod_comparison_concordance.R:59](../../R/mod_comparison_concordance.R#L59) | `height = "420px"` | `height = "var(--de-plot-h-md)"` |
  | [mod_comparison_concordance.R:63](../../R/mod_comparison_concordance.R#L63) | `height = "420px"` | `height = "var(--de-plot-h-md)"` |
  | [mod_comparison_concordance.R:70](../../R/mod_comparison_concordance.R#L70) | `height = "420px"` | `height = "var(--de-plot-h-md)"` |
  | [mod_comparison_concordance.R:79](../../R/mod_comparison_concordance.R#L79) | `height = "360px"` | `height = "var(--de-plot-h-sm)"` |
  | [mod_enrichment_nes_heatmap.R:22](../../R/mod_enrichment_nes_heatmap.R#L22) | `height = "500px"` | `height = "var(--de-plot-h-lg)"` |

  (Line numbers are pre-G8/G13; after those refactors the same five `height=` strings live in
  `de_card(...)` bodies — swap them wherever they landed.)

**Verify.** All five plots render at the same pixel heights as before (`var()` resolves to the
literal). Under `?redesign=0` the tokens are undefined, so give each a literal fallback if you
want the non-redesign build to keep exact heights — e.g. `"var(--de-plot-h-md, 420px)"`; use
the fallback form for all five. Resize the window and confirm plots still size (base R / plotly
read the resolved container height at render).

**Commit.** `git commit -am "refactor(grid): tokenize plot heights via --de-plot-h-{sm,md,lg}"`

---

## Task G17 — Add the grid lint/check

Lock the standard in with a grep-based checker so the idioms can't creep back. Real script,
runs in CI or by hand.

- [ ] Create `tools/check-grid.sh`:

```bash
#!/usr/bin/env bash
# tools/check-grid.sh — enforce §1 (grid-system-plan) invariants.
# Exit non-zero if a retired idiom reappears. Run from repo root.
set -u
fail=0
note() { printf '\n== %s ==\n' "$1"; }

note "1) layout_column_wrap must be gone (use layout_columns)"
if grep -rn "layout_column_wrap" R/; then
  echo "FAIL: layout_column_wrap found"; fail=1
fi

note "2) hand-rolled CSS grid must be gone (use layout_columns)"
if grep -rnE "display:\s*grid" R/; then
  echo "FAIL: inline display:grid found in R/"; fail=1
fi

note "3) manual pixel spacers must be gone (use gap / --de-space-*)"
if grep -rnE 'height:\s*[0-9]+px' R/ | grep -v 'max-height'; then
  echo "FAIL: fixed-height spacer div found"; fail=1
fi
if grep -rnE 'margin-top:\s*[0-9]+px|gap:\s*[0-9]+px' R/; then
  echo "FAIL: inline pixel margin/gap found (use var(--de-space-*))"; fail=1
fi

note "4) raw cards must be de_card() or an annotated exception"
raw=$(grep -rn "bslib::card_header(" R/ | grep -v 'R/de_card.R')
while IFS= read -r line; do
  [ -z "$line" ] && continue
  f=${line%%:*}; rest=${line#*:}; n=${rest%%:*}
  prev=$(sed -n "$((n-1))p" "$f")
  echo "$prev" | grep -q 'RAW CARD (de_card exception)' || {
    echo "FAIL: raw card_header without exception comment -> $line"; fail=1; }
done <<< "$raw"

note "5) classic column() inventory (should only be inside kept c(5,2,5) rows)"
grep -rnoE "column\(\s*[0-9]+" R/ | sort | uniq -c | sort -rn

[ "$fail" -eq 0 ] && echo -e "\nGRID CHECK PASSED" || echo -e "\nGRID CHECK FAILED"
exit "$fail"
```

- [ ] `chmod +x tools/check-grid.sh` and wire it into the CI job that already runs
  `R CMD build` (add a step `bash tools/check-grid.sh`). Reference it from
  [§6 Handoff](06-handoff-plan.md) as part of the living style-guide / regression net.

**Verify.** `bash tools/check-grid.sh` prints `GRID CHECK PASSED` on the migrated tree.
Temporarily re-add a `layout_column_wrap` and confirm it prints `FAIL` and exits 1.

**Commit.** `git commit -am "chore(grid): add tools/check-grid.sh lint + CI hook"`

---

# How to check any page against the grid

Two complementary methods: the browser overlay (visual truth) and grep (source truth).

## A. DevTools grid / flex overlay walkthrough

1. Run the app (`R -e 'debrowser::startDEBrowser()'`) and open it in Chrome/Edge. Keep
   `?redesign=1` (default). Repeat the pass in **both** themes (press `T`).
2. Open DevTools → **Elements**. In the DOM, a `layout_columns` renders as
   `<div class="bslib-grid ...">` with an inline `grid-template-columns: repeat(12, ...)`; a
   `layout_column_wrap` renders as `<div class="bslib-grid ... bslib-grid-column-wrap">`. If you
   see the `-column-wrap` variant, it hasn't been migrated.
3. Hover the grid container's node — Chrome shows a **grid** badge next to it. Click the badge
   (or DevTools → **Layout** panel → *Grid overlays* → tick the element) to paint the 12 tracks
   and gutters. Confirm: exactly the expected cells (2 for `c(6,6)`, 3 for `c(4,4,4)`/`c(5,2,5)`),
   even gutters, nothing spilling outside a track.
4. For a card body using flex (`de-data-workbar`, the post-upload stack), click the **flex**
   badge to see the gap. Confirm the rhythm comes from `gap`, not from empty spacer divs — an
   empty `<div style="height:12px">` between cards is the smell you're hunting.
5. Sanity check the standard visually: no element should hug a card edge with zero gutter (a
   floating sibling), and no row should leave a blank track (a ragged row that doesn't sum to
   12). With `layout_columns` both are impossible by construction — so any you find means an
   un-migrated `fluidRow`.
6. Flip to `?redesign=0` and confirm the page still lays out (stacked, unstyled) with no console
   errors — the additive-and-reversible constraint.

## B. Grep commands

```bash
# --- Retired idioms: all four should return NOTHING after Wave 2 ---
grep -rn  "layout_column_wrap" R/                 # flow 50/50 (G8)
grep -rnE "display:\s*grid"     R/                # hand-rolled grid (G10)
grep -rn  "fluidRow"            R/                # classic rows (G1-G5, G9)
#   fluidRow hits that remain must be deliberate + on-standard; there should be none in
#   the migrated files. Any hit is a candidate for column-sum auditing (below).

# --- Column-width inventory: eyeball that each fluidRow's columns sum to 12 ---
grep -rnoE "column\(\s*[0-9]+" R/ | sort | uniq -c | sort -rn
#   After migration the only survivors are the c(5,2,5) rows (5,2,5) if kept as classic
#   columns. Ragged tells: an odd count of 3s, a lone 6, a 1 next to a bare sibling.

# --- Per-file quick sum for a suspicious fluidRow (widths on/near one line) ---
awk '/fluidRow/{r=1} r{n=gensub(/.*column\(([0-9]+).*/,"\\1","g"); if($0 ~ /column\(/) s+=n}
     /\)\)/{if(r){print FILENAME": row sum ~ "s; s=0; r=0}}' R/uifuncs.R
#   Heuristic (multi-line R defeats exact parsing) — trust the DevTools overlay for the
#   authoritative sum; layout_columns makes this check unnecessary once migrated.

# --- Inline margin spacers: should be NOTHING after G15 ---
grep -rnE 'height:\s*[0-9]+px' R/ | grep -v 'max-height'   # spacer divs
grep -rnE 'margin-top:\s*[0-9]+px|gap:\s*[0-9]+px' R/       # inline pixel spacing
grep -rn  'tags\$div(style = "height'   R/                  # the classic spacer div

# --- Card systems: raw cards must be de_card() or an annotated exception ---
grep -rn "de_card("        R/            # the sanctioned wrapper (should be many)
grep -rn "bslib::card_header(" R/        # raw cards; each survivor needs a
                                         # "RAW CARD (de_card exception):" comment (G14)

# --- One command for all of it ---
bash tools/check-grid.sh                 # from G17; PASS/FAIL + exit code
```

**Rule of thumb:** if `tools/check-grid.sh` passes and the DevTools grid overlay shows clean,
evenly-guttered tracks that sum to 12 on every card in both themes, the page is on-grid.

---

## Task index

| Wave | Task | File(s) | Label |
|---|---|---|---|
| 1 | G1 Concordance ragged row | mod_comparison_concordance.R | Quick win |
| 1 | G2 NES heatmap ragged row | mod_enrichment_nes_heatmap.R | Quick win |
| 1 | G3 Lone `column(6)` | mod_condselect.R | Quick win |
| 1 | G4 Un-float `goMain` | deprogs.R | Quick win |
| 1 | G5 Wrap batch tabset | batcheffect.R | Quick win |
| 1 | G6 Sidebar width 280→300 | mod_enrichment.R | Quick win |
| 2 | G7 `de_card(class=)` enabler | de_card.R | Consolidation |
| 2 | G8 `layout_column_wrap`→`layout_columns` | gopanel.R, mod_enrichment.R, mod_comparison_concordance.R | Consolidation |
| 2 | G9 classic 50/50 → `layout_columns` | uifuncs.R, lowcountfilter.R, dataLoad.R | Consolidation |
| 2 | G10 hand-rolled grid → `layout_columns` | dataLoad.R, debrowser.css | Consolidation |
| 2 | G11 LCF/Batch wrapper → `de_card()` | lowcountfilter.R, batcheffect.R | Consolidation |
| 2 | G12 CondSelect cards → `de_card()` | mod_condselect.R | Consolidation |
| 2 | G13 remaining raw cards → `de_card()` | gopanel.R, mod_enrichment*.R, concordance, deprogs.R | Consolidation |
| 2 | G14 annotate raw-card exceptions | dataLoad.R (+audit) | Consolidation |
| 3 | G15 spacing tokens | dataLoad.R | System |
| 3 | G16 plot-height tokens | mod_comparison_concordance.R, mod_enrichment_nes_heatmap.R, debrowser.css | System |
| 3 | G17 grid lint/check | tools/check-grid.sh, CI | System |
