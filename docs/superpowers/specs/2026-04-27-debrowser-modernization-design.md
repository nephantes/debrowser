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
│   ├── run_app.R              # startDEBrowser(), startHeatmap() — back-compat shims
│   ├── app_ui.R               # bslib-themed page + nav
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

## Phase B — UX refresh for bench biologists

**Goal:** biologist with a count matrix and zero R experience gets from "I have data" to "here are my up/down genes" in under 5 minutes, no docs. ~20% of total effort.

### B1 — `bslib` theme + chrome swap

- Replace `shinydashboard` with `bslib` (`bs_theme(version = 5)`, `page_navbar`, `nav_panel`, `card`)
- Calm modern palette, accessible contrast, single accent color, larger typography
- Use `bs_themer()` during dev; freeze final theme

### B2 — "Quick Start" wizard (default landing)

3-step front door:
1. **Upload** — drag-and-drop counts + metadata, or "Try demo data" button. Auto-detect separator. 5-row inline preview.
2. **Pick conditions** — clean "Group A vs Group B" picker reading metadata columns. Sensible auto-grouping.
3. **Run & view** — one button, runs DESeq2 with sane defaults, jumps to volcano with up/down highlighted and downloadable table.

Existing tabs (Filter / BatchEffect / DEAnalysis / QC / GO) remain accessible as **"Advanced" panels**.

Wizard preference persists per-browser (cookie); "Skip wizard" lands directly on classic tabbed view.

### B3 — Sensible defaults (hide the dials)

Auto-applied with one-click "Advanced" expander to override:

| Setting | Default |
|---|---|
| Method | DESeq2 + LRT (already project default per NEWS 1.10.1) |
| Low-count filter | rowSums ≥ 10 |
| padj cutoff | 0.05 |
| \|log2FC\| cutoff | 1 |
| LFC shrinkage | apeglm when applicable |
| Batch correction | off; prompt if metadata has `batch` column |

### B4 — Friendly errors

Replace `stop()` and silent failures with `validate(need(...))` + human messages:

- `R/dataLoad.R:158` `stop("Please upload the count file")` → "👋 Upload a count matrix to get started. Don't have one? Click 'Try demo data'."
- Decimal counts detected → "Your file looks like it contains normalized values, not raw counts. DEBrowser needs raw integer counts."
- Metadata mismatch → "3 samples in your count file aren't in your metadata: `sample_X`, `sample_Y`, `sample_Z`."

All errors logged structured in one place so we can later add a "Report this issue" link with context.

### B5 — Onboarding & empty states

- Replace loading GIF with `bslib` spinner + version + status text
- Empty plot panels show "Run DE analysis to see results" instead of blank space
- Inline help tooltips (`bslib::tooltip`) on every parameter — one sentence each, no jargon
- "Demo data" button promoted to primary CTA on landing
- Fix typos in tab labels (`Anaylsis` → `Analysis`, `Assesment` → `Assessment` — both in `R/ui.R`)

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
| B1 | 3 | New theme live |
| B2 | 5 | 3-step quick start works on demo |
| B3 | 1 | Knobs hidden; advanced expander |
| B4 | 2 | All `stop()` replaced |
| B5 | 2 | Tooltips, typos, empty states |
| B6 | 2 | Color-safe; download UX |
| **B subtotal** | **15** | **Bench-biologist UX live** |
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
| **TOTAL** | **66** | |

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
