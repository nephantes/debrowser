# DEBrowser Modernization — Design Spec

**Date:** 2026-04-27
**Author:** Alper Kucukural (with Claude)
**Status:** Approved for plan-writing
**Branch target:** long-lived `modernize` off `devel`

## Goal

Modernize DEBrowser into a maintainable, fast, biologist-friendly Shiny package while staying BiocCheck-clean. Four phases, executed in order: **A → B → C → D**.

- **A — Code health & modernization:** modular Shiny, pure analytic core, tests, CI
- **B — UX refresh for bench biologists:** `bslib` chrome, quick-start wizard, sane defaults, friendly errors
- **C — Performance & scale:** async DE, caching, heatmap fix, lazy loading
- **D — Reproducibility & deployment:** downloadable reports, bookmarkable state, Docker, pkgdown

## Constraints

- **Hard:** Must stay BiocCheck-clean; must follow Bioconductor release cadence; must be installable via `BiocManager::install("debrowser")` at every milestone.
- **Soft:** Public entry points (`startDEBrowser()`, `startHeatmap()`, `deUI`, `deServer`, `runDE`) keep working as thin compatibility shims even though API is otherwise free to change.
- **Audience:** primary user is a bench biologist with a count matrix and minimal R experience. Optimize for sane defaults, hidden complexity, friendly errors. Power-user knobs available behind an "Advanced" expander.
- **Dep footprint:** preferred small but not strict — OK to add `bslib`, `promises`, `future`, `memoise`, `ComplexHeatmap`, `cachem`.

## Target architecture

```
debrowser/
├── R/
│   ├── run_app.R              # startDEBrowser(focus=); startHeatmap() = deprecated alias
│   ├── app_ui.R               # bslib page + 3-stage progress nav (Data/Analyze/Explore)
│   ├── mod_shell.R            # stage gating, view-mode toggle (Simple/Advanced), help offcanvas
│   ├── app_server.R           # top-level server, wires modules
│   ├── mod_data_load.R        # was dataLoad.R
│   ├── mod_lowcount_filter.R  # was lowcountfilter.R
│   ├── mod_batch_effect.R     # was batcheffect.R
│   ├── mod_cond_select.R      # was condSelect.R (660 LOC → split)
│   ├── mod_de_analysis.R      # was deprogs.R UI
│   ├── mod_main_plots.R       # was mainScatter.R + barmain + boxmain
│   ├── mod_qc_plots.R         # all2all + density + IQR + histogram + pca
│   ├── mod_heatmap.R          # was heatmap.R (782 LOC → split UI vs render)
│   ├── mod_go_panel.R         # gopanel + GOterm
│   ├── mod_tables.R
│   ├── fct_de_methods.R       # PURE: run_deseq2(), run_edger(), run_limma()
│   ├── fct_normalize.R        # PURE: getNormalizedMatrix(), batch correction
│   ├── fct_filter.R           # PURE: low-count filter
│   ├── fct_prep_data.R        # PURE: was prepdata.R logic
│   ├── fct_plots.R            # PURE: ggplot/plotly builders
│   ├── utils_validate.R       # human-friendly validate()/need() messages
│   └── utils_cache.R          # memoise wrappers
├── inst/
│   ├── extdata/               # demo data (unchanged)
│   ├── app/www/               # CSS, JS, images
│   └── reports/               # Quarto report template (Phase D)
├── tests/
│   ├── testthat/              # unit tests for fct_*
│   └── shinytest2/            # UI flow tests
└── .github/workflows/
    ├── R-CMD-check.yaml
    └── bioc-check.yaml
```

### Principles

- **Pure `fct_*` functions** — no Shiny, no `reactive()`. Unit-testable, callable from scripts, easy to memoise.
- **`mod_*` modules** wrap pure functions in reactive UI. Each returns an explicit named `list()` of reactives. No global `reactiveValues` soup.
- **Public API = back-compat shims.** Existing startup scripts continue to work.
- **`bslib` ≥ 0.6** replaces `shinydashboard` chrome.
- **Tests:** `shinytest2` for end-to-end UI; `testthat` 3e for pure functions.

## Phase A — Code health & modernization

**Done when:** tests pass on R-release + R-devel, BiocCheck clean, no file > 400 LOC, no deprecated function calls, CI runs on every push. ~60–70% of total project effort.

### A1 — Repo hygiene

- Add `.Rbuildignore` entries for `viafoundry_errors.log`, `.claude/`, `docs/superpowers/`
- Delete the empty `viafoundry_errors.log`
- Bump `R (>= 4.2)` in `DESCRIPTION`
- Update `RoxygenNote` to current 7.3.x; regenerate man pages
- Add `lintr` + `styler` configs; one-time `styler::style_pkg()` pass
- GitHub Actions: `R-CMD-check` (release + devel), `BiocCheck`, `lintr`, `covr` coverage
- Commit the in-flight 30→90 MB upload bump in `R/startShiny.R`

### A2 — Test scaffolding (before refactor; safety net)

- Migrate `tests/test-*.R` to `tests/testthat/test-*.R`, testthat 3e
- Delete orphaned dead code below `test_that` blocks in `tests/test-deseq.R`
- Capture **golden output snapshots** from current code on the demo data:
  - DESeq2 result table hash
  - edgeR result table hash
  - limma result table hash
  - Normalized matrix hash
  - PCA coordinates
- Add `shinytest2` smoke test: load demo → run DESeq2 → MA plot renders
- These oracles catch regressions during A3/A4 refactors.

### A3 — Extract pure analytic core

Pull math out of UI code into `R/fct_*.R`:

| New file | Pulled from | Public functions |
|---|---|---|
| `fct_de_methods.R` | `deprogs.R`, `funcs.R` | `run_deseq2()`, `run_edger()`, `run_limma()` |
| `fct_normalize.R` | `funcs.R`, `batcheffect.R` | `normalize_counts()`, `apply_batch_correction()` |
| `fct_filter.R` | `lowcountfilter.R` | `filter_low_counts()` |
| `fct_prep_data.R` | `prepdata.R` | data prep helpers |
| `fct_plots.R` | `mainScatter.R`, `heatmap.R`, etc. | ggplot/plotly builders |

Each pure fn takes plain matrix/factors, returns a tidy `data.frame` or plot object. No Shiny dependencies. Each gets unit tests against A2 snapshots. Old functions stay as deprecated shims for one Bioc cycle.

### A4 — Modularize Shiny (smallest first)

1. `mod_data_load.R` ← `dataLoad.R`
2. `mod_lowcount_filter.R` ← `lowcountfilter.R`
3. `mod_batch_effect.R` ← `batcheffect.R`
4. `mod_qc_plots.R` ← `all2all` + `density` + `IQR` + `histogram` + `pca`
5. `mod_main_plots.R` ← `mainScatter` + `barmain` + `boxmain`
6. `mod_cond_select.R` ← `condSelect.R` (split UI vs server vs validation)
7. `mod_de_analysis.R` ← `deprogs.R`
8. `mod_heatmap.R` ← `heatmap.R` (split UI / data prep / render)
9. `mod_go_panel.R` ← `gopanel` + `GOterm`
10. `mod_tables.R`

Each conversion: `moduleServer`, namespaced IDs, explicit `list(...)` reactive return interface, tests stay green.

Cleanup along the way:
- Remove `library("debrowser")` inside `deUI()` (anti-pattern)
- Replace `aes_string()` with `aes(.data[[...]])` (ggplot2 ≥ 3.0 idiom)
- Remove `installpack`/`loadpack` runtime install hacks → declare `Suggests` + `requireNamespace()` checks

### A5 — Slim dependencies

Move rarely-used to `Suggests` and gate with `requireNamespace()`:
- `pathview` → Suggests (KEGG image rendering only)
- `Harman` → Suggests (one of several batch methods)
- `org.Mm.eg.db` → Suggests (mouse-only)
- `apeglm`, `ashr` → Suggests (LFC shrinkage)
- `enrichplot`, `DOSE` → Suggests (GO/pathway optional)

### A risks & mitigations

- *Refactor breaks DE math subtly* → mitigated by A2 golden snapshots
- *Bioc release cadence collides with mid-refactor* → land A1 + A2 as standalone PRs first, then A3/A4 incrementally so the package is always shippable

## Current UX evaluation (added 2026-04-27)

Critical findings from reading the current code path. These motivate Phase B's specific design choices below.

### Upload screen — overwhelms before doing anything

- Two equally-weighted boxes ("Count Data File" + "Metadata File") side by side, each with its own separator radio (Comma/Semicolon/Tab) — biologists must know file formats *before* uploading. Default `\t` while accept list includes `.csv` — mismatch produces cryptic R error.
- Three primary-styled buttons after upload (Upload / Load Demo Vernia / Load Demo Donnard) — no visual hierarchy.
- `stop("Please upload the count file")` (`R/dataLoad.R:158`) — bare R `stop()`.
- Stray `print(dim(ldata$count))` in JSON load path (`R/dataLoad.R:99`) — debug noise in production.
- Column names silently mangled by `gsub("\\s+|\\.|\\-", "_", ...)` — `My Sample 1` becomes `My_Sample_1` with no notice.

### Condition selector — power-user nightmare

- "Condition 1 (Numerator)" / "Condition 2 (Denominator)" — biologists think Treatment vs Control, not numerator/denominator.
- DE method dropdown immediately exposes fitType, betaPrior, testType, shrinkage, normalization, dispersion, etc. — **8–10 dropdowns visible at once** with no guidance.
- Covariate selector always shown, even when there's no batch column.
- `showNotification(..., type="error")` fires during reactive rebuilds (`R/condSelect.R:352, 369, 392, 399, 407`) → red toasts pop during normal interactions, auto-dismiss in 5s.
- Three overlapping code paths (`getConditionSelector`, `getConditionSelectorFromMeta`, `selectConditions`) with dead branches like `if (length(grps) == -1)` (`R/condSelect.R:205`).
- "Add New Comparison" / "Remove" / "Start DE" all visible at once.

### Cutoffs — wrong widget, inconsistent defaults

- `textInput` for `padj` and `foldChange` (`R/deprogs.R:85-86`) — user can type "abc" and silently get NA. Should be `numericInput` with min/max/step.
- Defaults inconsistent: cutOffSelectionUI says padj `0.01` / fold `2`, community standard is 0.05/1.

### Information architecture — guide and workflow share sidebar

- Quick Start Guide subtabs live in the *same sidebar* as workflow steps — confuses "where to work" with "where to read docs".
- Top-level "Data Prep" / "Discover" — no visual indication "Discover" is locked until DE runs.
- Typos in nav: `Anaylsis`, `Assesment` (`R/ui.R:55, 53`).

### Two separate apps for related tasks

- `startDEBrowser()` and `startHeatmap()` are completely separate UIs — no discoverability between them.

### Visual & micro-UX

- Default `shinydashboard` dark-blue chrome looks dated.
- Loading screen: black background + animated GIF spinner.
- CSS hammer: `.content-wrapper { min-height: 3500px !important; }` — huge empty scroll area on small datasets.
- Errors only as auto-dismissing toasts; no persistent error log.
- Reactive rebuild storms on every keystroke (no `bindEvent` discipline).

## Phase B — UX refresh for bench biologists

**Goal:** biologist with a count matrix and zero R experience gets from "I have data" to "here are my up/down genes" in under 5 minutes, no docs. ~20% of total effort.

### Top-level UX changes (drives B1–B6)

1. **Single unified app** — fold separate `startHeatmap()` UI into main app as heatmap tab. `startHeatmap()` becomes deprecated alias for `startDEBrowser(focus = "heatmap")`.
2. **Three-stage shell with visible gating:** `1. Data → 2. Analyze → 3. Explore`. Stages locked until prereqs met; click completed stages to return.
3. **"Treatment vs Control"** language replaces "Numerator/Denominator". Caption: *"log2 fold change = Treatment ÷ Control"*.
4. **Inline validation, not toasts:** errors render as helper text next to offending field. Toasts only for top-level events ("DE run finished").
5. **Persistent error log panel** behind a corner "View errors" button so users can re-read.
6. **Defaults harmonization:** community standard **padj 0.05, |log2FC| ≥ 1**, applied consistently in code/docs/report.
7. **Workflow guide moved out of sidebar:** Quick Start lives in top-bar Help menu with `bslib::offcanvas` slide-out.
8. **Sample-name normalization visible:** show before/after table when names get mangled.

### B1 — `bslib` theme + chrome swap

- Replace `shinydashboard` with `bslib` (`bs_theme(version = 5)`, `page_navbar`, `nav_panel`, `card`)
- Calm modern palette, accessible contrast, single accent color, larger typography
- Use `bs_themer()` during dev; freeze final theme

### B2 — Three-stage shell + Quick Start wizard

Replace the current "Data Prep / Discover" two-tab shell with a **3-stage progress nav** at the top of the page:

```
●━━━━━━━━━━━━━━━○━━━━━━━━━━━━━━━○
1. Data         2. Analyze       3. Explore
[upload+filter] [conds+DE run]   [plots+tables+heatmap+GO]
```

- Each stage is a `bslib::nav_panel`. Stages 2/3 disabled (greyed) until prereqs met. Completed stages get a green checkmark.
- Default landing: **Stage 1**, with a wizard-style flow:
  1. **Upload counts** — single drop zone (no separator radio up front). Auto-detect separator: try `\t`, `,`, `;` in order, pick the one yielding ≥3 numeric columns. Show first-5-row inline preview. Separator chooser only appears if autodetect fails.
  2. **Optional metadata** — secondary drop zone underneath, smaller. If skipped, auto-generate single-batch metadata.
  3. **Try demo data** — single secondary button, not equally weighted with upload.
- **Stage 2**: shows comparison builder with **"Treatment vs Control"** language (not Numerator/Denominator). Caption *"log2 fold change = Treatment ÷ Control"*. Method picker shows only "Method: DESeq2 ▼"; everything else collapses behind "Advanced" accordion (closed by default).
- **Stage 3**: lands on volcano plot with top 10 genes labeled. Sub-nav for Main Plots / QC / Tables / GO / Heatmap.

Existing power-user views (separate Filter, BatchEffect, full DEAnalysis with all knobs) remain accessible from a "View Mode" toggle in the top bar: **Simple** (default, gated 3-stage) ↔ **Advanced** (current tabbed view, all knobs visible). Choice persists per-browser cookie.

### B3 — Sensible defaults + cutoff widget redesign

Auto-applied defaults with one-click "Advanced" expander to override:

| Setting | Default |
|---|---|
| Method | DESeq2 + LRT (project default per NEWS 1.10.1) |
| Low-count filter | rowSums ≥ 10 |
| padj cutoff | **0.05** (was 0.01 — community standard) |
| \|log2FC\| cutoff | **1** (was 2 — community standard) |
| LFC shrinkage | apeglm when applicable |
| Batch correction | off; **auto-prompt if metadata has a column matching `^batch$` (case-insensitive)** |
| Covariate selector | hidden unless metadata has ≥2 non-sample columns |

**Cutoff widget redesign:** replace `textInput` with `numericInput` (min/max/step). Add **preset buttons** above:

- `[ Sensitive: padj 0.10 ]` `[ Default: padj 0.05 ]` `[ Strict: padj 0.01 ]`

Clicking a preset fills both numeric inputs. Manual edits clear the preset highlight.

### B4 — Inline validation + persistent error log

**Inline, not toasts:** errors render as `bslib::tooltip` or red helper text directly under the offending field. Toasts only for cross-cutting events ("DE run finished", "Cache cleared").

Concrete replacements:
- `R/dataLoad.R:158` `stop("Please upload the count file")` → empty-state in dropzone: *"👋 Drop a count matrix here to get started. Don't have one? Try demo data."*
- Decimal counts detected → inline under upload preview: *"This file contains decimals. DEBrowser needs raw integer counts (e.g. from HTSeq, RSEM, featureCounts)."*
- Metadata mismatch → inline under metadata dropzone, with sample list: *"3 samples in your count file aren't in your metadata: `sample_X`, `sample_Y`, `sample_Z`. Fix the metadata or rename samples."*
- Sample-name mangling (`gsub("\\s+|\\.|\\-", "_", ...)`) → modal showing before→after table; user confirms or cancels.
- Wrong separator → autodetect first; only if all 3 fail, show separator radio with helpful caption.
- All `showNotification(..., type="error")` calls in `R/condSelect.R` (lines 352, 369, 392, 399, 407) → debounce + render inline next to the comparison row that produced them.

**Persistent error log:** new `utils_validate.R::log_user_event(level, msg, context)` writes to a `reactiveVal` log. Top-bar shows a small badge with error count. Clicking opens a `bslib::offcanvas` panel with full history (timestamp + message + which input). Survives page navigation within the session.

Removed: stray `print(dim(ldata$count))` (`R/dataLoad.R:99`).

### B5 — Onboarding & empty states

- Replace loading GIF with `bslib` spinner + version + status text. Drop the black-background full-screen overlay.
- Drop the `.content-wrapper { min-height: 3500px !important; }` CSS hack — `bslib` cards size to content.
- Empty plot panels show contextual message: *"Run a DE analysis to see your volcano plot"* with a button that jumps back to Stage 2.
- Inline help tooltips (`bslib::tooltip`) on every parameter — one sentence each, plain language.
- Fix typos in nav: `Anaylsis` → `Analysis`, `Assesment` → `Assessment` (`R/ui.R:55, 53`).
- Quick Start Guide moves from sidebar into top-bar Help menu (`bslib::offcanvas` slide-out from the right). Workflow nav stays clean.
- First-time visitor: subtle 3-step tour overlay (`introjs`-style), dismissable forever via cookie.

### B6 — Plot UX polish

- Volcano/MA: highlight top 10 genes by default; click to toggle labels
- Heatmap: row clustering on by default; top 50 variable genes pre-selected
- Color-blind-safe palettes default (viridis/cividis); current redblue available
- Consistent download UX: PNG/SVG/PDF for plots; CSV/TSV for tables

### B risks

- *Wizard hides things power users want* → wizard is opt-in default; "Skip wizard" persists per-browser
- *`bslib` migration touches every UI file* → that's why B1 lands after A4

## Phase C — Performance & scale

**Goal:** responsive on 60k-gene × 60-sample datasets; DE doesn't freeze UI; heatmaps don't crash browser. ~10% of total effort.

### C1 — Async DE runs

Wrap `fct_de_methods.R` calls in `promises::future_promise()` with `future::plan(multisession)`:
- Run button returns immediately; spinner + progress bar
- User can navigate other tabs while DE runs
- Cancel button kills the worker
- Pure functions from A3 make this trivial

### C2 — Result caching

`memoise::memoise(run_deseq2, cache = cachem::cache_disk(...))`:
- Cache key = `xxhash(counts) + xxhash(conds) + hash(params)`, version-prefixed (`debrowser-1.32-...`) so package upgrade invalidates
- Cache lives at `tools::R_user_dir("debrowser", "cache")`
- "Clear cache" button in advanced settings
- Same for normalization and PCA (deterministic)

### C3 — Heatmap fix (the big offender)

`R/heatmap.R` is 782 LOC, slow, often unreadable on >2k genes:
- Default to top-N variable genes (N=50 from B6); offer 100 / 500 / "all (slow)" toggle
- Switch to `ComplexHeatmap` for static heatmaps (faster, native to Bioc)
- Interactive: keep `plotly` heatmap, downsample with explicit warning above 5k rows ("Showing 5,000 of 12,847 rows — refine selection or pick top-variable")
- Render in `future_promise` so UI stays alive

### C4 — Lazy loading

- Don't `library()` plotly/heatmaply at startup; load on first tab visit
- GO/pathway code (`clusterProfiler`, `enrichplot`, `pathview`) only when GO tab opened
- Falls out of A5 `Suggests` move

### C5 — Profile & fix top hotspots

- `profvis` on standard demo flow + 60k-gene synthetic dataset
- Document baseline (time-to-first-plot, peak memory)
- Fix top 5 hotspots; document new numbers
- Add `bench::mark()` regression test that fails CI if a key path slows >25%

### C6 — Tables & uploads

- `DT::datatable(server = TRUE)` everywhere (some are client-side today)
- Stream-validate uploads instead of loading entire file twice
- Bump max upload to 500 MB with "may be slow" warning over 100 MB

### C risks

- *`future` workers don't see Bioc packages* → explicit `library()` inside worker, or `globals::globalsOf` properly. Standard pattern.
- *Cache hash collisions / stale cache* → fast crypto hash (xxhash via `digest`); version-prefix invalidates on upgrade

## Phase D — Reproducibility & deployment

**Goal:** any analysis reproducible from a single artifact; one-command deploy. ~10% of total effort.

### D1 — Downloadable HTML report

- "Download report" button on Discover page generates self-contained HTML via **Quarto** (or `rmarkdown` fallback)
- Contains: input fingerprints (filename + sha), metadata table, all chosen params (method, cutoffs, batch settings), every plot user generated (volcano, MA, PCA, heatmap, GO), DE result table, `sessionInfo()`
- Template in `inst/reports/debrowser_report.qmd`
- Same template renders headlessly via `debrowser::render_report(state)` for scripting

### D2 — Bookmarkable state

- Re-enable `enableBookmarking("server")` (already imported but unused)
- Each module implements `onBookmark`/`onRestore` properly
- Sharing URL = sharing fully restored analysis state (uploaded data referenced by content hash, not re-uploaded)

### D3 — Dockerfile

- Multi-stage `Dockerfile` based on `bioconductor/bioconductor_docker:RELEASE_3_18`
- Pinned package versions via `renv.lock`
- Image runs `startDEBrowser()` on `0.0.0.0:3838`
- Published to GHCR via the same GitHub Actions workflow from A1
- README one-liner: `docker run -p 3838:3838 ghcr.io/umms-biocore/debrowser:latest`

### D4 — `pkgdown` site

- `pkgdown::build_site()` wired into CI; deploys to GitHub Pages on push to `devel`
- Auto-generated reference, articles for existing vignette, "Quick Start" landing page
- Slim down the README (currently huge — much will move to pkgdown articles)

### D5 — Bioc release prep

- BiocCheck-clean (already a hard constraint)
- Update `NEWS.md` (currently rotted at v1.12.2 despite DESCRIPTION saying 1.30.2 — convert to Markdown)
- Submit for Bioc 3_19 (next release after RELEASE_3_18)
- Tag `v1.32.0` after merge to `devel`

### D risks

- *Quarto adds a system dep* → fall back to `rmarkdown` if Quarto not installed; degrade gracefully
- *Bookmarking with large uploaded files* → store uploads in `cachem` keyed by content hash; bookmark stores hash not bytes

## Sequencing & milestones

Effort in **abstract units** (divide by your actual velocity):

| Phase | Units | Milestone |
|---|---|---|
| A1 | 2 | CI green; lint clean; uncommitted change shipped |
| A2 | 4 | DE/normalize/PCA snapshots locked |
| A3 | 8 | `fct_*.R` files exist with unit tests |
| A4 | 12 | All `mod_*.R` modules; old big files deleted |
| A5 | 2 | Imports trimmed; `Suggests` gates working |
| **A subtotal** | **28** | **Foundation done — package always shippable** |
| B1 | 3 | bslib theme + chrome live; min-height hack gone |
| B2 | 7 | 3-stage shell with gating; auto-detect upload; Simple/Advanced toggle; heatmap unified into main app |
| B3 | 2 | Defaults harmonized (0.05/1); preset buttons; numeric inputs |
| B4 | 3 | Inline validation; persistent error log; toasts removed from condSelect |
| B5 | 2 | Tooltips, typos, empty states, help offcanvas |
| B6 | 2 | Color-safe palettes; download UX |
| **B subtotal** | **19** | **Bench-biologist UX live** |
| C1 | 3 | DE doesn't block UI |
| C2 | 2 | Repeat runs instant |
| C3 | 4 | ComplexHeatmap; downsampling |
| C4 | 1 | Faster startup |
| C5 | 2 | Top-5 hotspots fixed; bench regression test |
| C6 | 1 | Server-side DT |
| **C subtotal** | **13** | **Handles 60k×60 dataset comfortably** |
| D1 | 4 | One-click reproducible report |
| D2 | 2 | URLs restore full state |
| D3 | 2 | One-line deploy |
| D4 | 1 | Docs site live |
| D5 | 1 | Tagged & submitted |
| **D subtotal** | **10** | **Reproducible & deployable** |
| **TOTAL** | **70** | |

## Branching strategy

- All work on long-lived `modernize` branch off `devel`
- Each phase merges to `devel` as a unit so a Bioc release boundary doesn't catch us mid-refactor
- `RELEASE_3_18` only gets backports of bug fixes (per Bioc policy)

## Decision points (re-approval before proceeding)

1. **End of A2** — golden snapshots locked. Real point of no return.
2. **End of A4** — modules done. Big diff; thorough review.
3. **End of B2** — wizard prototype. Test on a real biologist before B3–B6 polish.
4. **End of C3** — heatmap perf; user-visible enough to validate before C4–C6.

## Implementation plans (decomposition)

This spec is a roadmap, not a single implementation plan. It will decompose into **four implementation plans**, one per phase, written and executed sequentially:

1. `2026-04-27-phase-a-code-health-plan.md` — write next, after this spec is approved
2. `2026-XX-XX-phase-b-ux-refresh-plan.md` — written after Phase A merges
3. `2026-XX-XX-phase-c-performance-plan.md` — written after Phase B merges
4. `2026-XX-XX-phase-d-reproducibility-plan.md` — written after Phase C merges

Writing the next plan only after the previous phase merges keeps it grounded in the real (post-refactor) state of the code rather than guessing.

## Out of scope (deliberate)

- Single-cell support (Seurat/SingleCellExperiment) — different audience, would double scope
- Tidyverse migration — base R + existing patterns are fine; not a goal
- Major new analyses beyond what exists (e.g., GSEA improvements, new DE method) — focus is modernization, not feature growth
- API backwards-compatibility beyond shim entry points (per Question 3 answer)
- UI flow backwards-compatibility (per Question 3 answer)
