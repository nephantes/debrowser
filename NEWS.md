# debrowser NEWS

For releases prior to 1.31, see the legacy `NEWS` file.

## debrowser 1.31.2 (in development)

### Phase A1 — foundation modernization

* Bumped minimum R version to 4.2 and `RoxygenNote` to 7.3.x.
* Added `lintr` and `styler` configs; one-time formatting pass.
* Added GitHub Actions for R-CMD-check (R-release + R-devel),
  BiocCheck, lintr, and `covr` coverage (codecov).
* Extended `.Rbuildignore` for docs, CI, lint, and dev configs.
* Removed stale empty `viafoundry_errors.log` from the repo.

### Phase A2 — test scaffolding + golden snapshots

* Migrated `tests/test-*.R` to the `testthat` 3e layout under
  `tests/testthat/`, with shared helpers in `helper-debrowser.R`.
* Added golden snapshot tests for DESeq2, edgeR, limma,
  `getNormalizedMatrix()`, and PCA coordinates on the demo data —
  these are the safety net for Phase A3+ refactors.
* Added a `shinytest2` smoke-test scaffold (CI-skipped until A4
  stabilises module IDs).
* Fixed silent Treat/Control inversion in the migrated DESeq2 test.

### Phase A3a — pure analytic core (DE + normalize + filter)

* Added `R/fct_de_methods.R` with `run_deseq2()`, `run_edger()`,
  `run_limma()`, `run_de()` — pure functions taking structured
  (named-list) params instead of legacy comma-string params. No Shiny
  dependency.
* Added `R/fct_normalize.R` with `normalize_counts()` and pure
  `apply_batch_correction()` (Combat / CombatSeq / Harman). Batch /
  treatment column names are now arguments instead of `input$` lookups.
* Added `R/fct_filter.R` with `filter_low_counts()` (max / mean / cpm).
* Added `R/utils_validate.R` with `de_error()` — structured `stop()`
  raising classed conditions so callers dispatch on class, not message
  text.
* Legacy `runDE()`, `runDESeq2()`, `runEdgeR()`, `runLimma()`,
  `getNormalizedMatrix()`, `correctCombat()`, `correctHarman()` are now
  thin shims that translate input/comma-string params and delegate.
  Their signatures are unchanged so existing callers and scripts keep
  working.
* Fixed silent "Repeated column names found in count matrix" warning
  in the limma path (legacy code set all column names to factor levels;
  removing it does not affect results).
* `debrowserlowcountfilter` module's filter observer shrinks from ~20
  lines to 9 by delegating to `filter_low_counts()`.

### Phase A3b — pure data-prep functions

* Added `R/fct_prep_data.R` with `apply_de_filters()`, `get_most_varied()`,
  `select_dataset()`, `search_geneset()`, `merge_comparisons()`,
  `apply_merged_filters()`, `get_table_data()` — pure functions that take
  a structured filter-params list.
* Added `filter_params_from_input()` in `utils_validate.R` to centralise
  the Shiny-input → pure-fn-params field-name mapping (e.g. `input$padj`
  → `params$padj_cutoff`, `input$genesetarea` → `params$geneset_area`).
* Legacy `applyFilters()`, `getMostVariedList()`, `getSelectedDatasetInput()`,
  `getSearchData()`, `getMergedComparison()`, `applyFiltersToMergedComparison()`,
  `getDataForTables()` are now thin shims that delegate to
  `R/fct_prep_data.R`. Public signatures unchanged.
* New golden snapshot locks the (Up=551, Down=864, NS=13941) row-count
  distribution on the demo DE result with default cutoffs (padj 0.05,
  fold 2) — catches regressions in cutoff logic or normalization.

### Phase A4a + A4c — Shiny API modernization

* Migrated all 13 modules from the deprecated `callModule()` API to
  `moduleServer()` (Shiny 1.5+ idiom): `debrowserdataload`,
  `debrowserlowcountfilter`, `debrowserbatcheffect`, `debrowserhistogram`,
  `debrowserpcaplot`, `debrowserIQRplot`, `debrowserdensityplot`,
  `debrowserall2all`, `debrowserheatmap`, `debrowsermainplot`,
  `debrowserbarmainplot`, `debrowserboxmainplot`, `debrowserdeanalysis`.
  Public function signatures changed from `(input, output, session, …)`
  to `(id, …)` to match the modern Shiny convention.
* Removed the `library("debrowser")` self-import inside `deUI()` —
  was a no-op at best and a side-effect at worst.
* Replaced the runtime `installpack()` / `loadpack()` package-loading
  helpers with standard `requireNamespace(pkg, quietly = TRUE)` checks
  in `R/GOterm.R`. Deleted `R/installpack.R` and its exported functions
  (`installpack`, `loadpack`).
* Dropped the unused `aes_string` import (deprecated in ggplot2 3.0).
* `condSelect.R` is deliberately left untouched — full rewrite folded
  into Phase B2 alongside the three-stage-shell wizard redesign.

### Phase A5 — slim dependencies

* Moved seven rarely-used packages from `Imports:` to `Suggests:` so a
  fresh install pulls a smaller dependency graph: `Harman`, `pathview`,
  `org.Mm.eg.db`, `apeglm`, `ashr`, `enrichplot`, `DOSE`.
* Added `require_pkg(pkg, feature)` helper in `R/utils_validate.R`
  that raises a `debrowser_error` of class `missing_suggested_pkg`
  with the install command when a Suggested package is needed but
  unavailable.
* Gated every direct call site:
  - `Harman::harman()` / `Harman::reconstructData()` — `harman_correct()`
  - `DESeq2::lfcShrink(type="apeglm"/"ashr")` — `run_deseq2()`
  - `enrichplot::dotplot()` / `enrichplot::gseaplot()` — `gopanel.R`,
    `GOterm.R::compareClust`, `server.R` GSEA render path
  - `DOSE::enrichDO()` — `getEnrichDO()` (the `compareCluster(fun = "enrichDO")`
    branch in `compareClust()` keeps its existing in-place `requireNamespace`
    gate)
  - `pathview::pathview()` — already gated in `drawKEGG()`; now namespaced
* Stripped the corresponding `@import` / `@importFrom` lines from
  `R/server.R` and `R/GOterm.R`; NAMESPACE no longer pulls these
  packages at load time.

### Phase B1 — bslib chrome + theme swap

* Replaced `shinydashboard::dashboardPage` shell with `bslib::page_navbar`
  and per-tab `bslib::layout_sidebar`. Top navbar now hosts five sections
  (Data Prep / Main Plots / QC Plots / GO Term / Tables) plus a
  light/dark toggle (`bslib::input_dark_mode`).
* Theme: Slate (`#0f172a`) navbar + OK-blue (`#0369a1`) primary,
  Bootstrap 5, Inter typography. New `de_theme()` helper.
* Migrated all 22 `shinydashboard::box()` call sites to `bslib::card`
  via a new `de_card()` helper (with optional download button in the
  header). Wide layout containers use raw `bslib::card`; narrow widget
  cards use `de_card`.
* DE Filter (cutoff + comparison-selector controls) moved from the
  sidebar into a card at the top of the DE Analysis wizard panel.
* Migrated all 24 `shinydashboard::menuItem()` collapsible widget
  containers to `bslib::accordion` + `bslib::accordion_panel` (in
  R/IQR.R, R/barmain.R, R/all2all.R, R/density.R, R/boxmain.R,
  R/plotSize.R, R/mainScatter.R, R/heatmap.R, R/uifuncs.R).
* Replaced `getTabUpdateJS()`'s shinydashboard `.sidebar-menu` jQuery
  with server-side `bslib::nav_show`/`nav_hide` observers in `deServer`.
  Same trigger button ids, same behavior.
* `togglePanels()` body rewritten to `bslib::nav_show`/`nav_hide`/
  `nav_select`. Function signature unchanged — all callers untouched.
* The standalone heatmap app (`startHeatmap()`) shell `heatmapUI()`
  also migrated to `bslib::page_navbar` with the same Slate + OK-blue
  theme; controls now live in the Heatmap tab's `layout_sidebar`.
* `de_card()` defaults to `full_screen = FALSE` to avoid bslib's
  expand-overlay interfering with htmlwidget click handlers.
* CSS file `shinydashboard_additional.css` audited and renamed to
  `debrowser.css`; shrunk from 145 to ~30 lines of app-specific
  positioning rules.
* Dropped `shinydashboard` from `Imports`. Added `bslib (>= 0.7.0)`.
  Added explicit `@importFrom shiny tagList req` to compensate for
  symbols previously pulled through shinydashboard's dependency chain.
* Dark-mode plot theming (plotly/heatmaply/ggplot color flips) deferred
  to Phase B6.

### Phase B2.5 — Comparison Selection wizard rewrite

* Rewrote `R/condSelect.R` (≈900 LOC monolith) into three focused files:
  `R/fct_condselect.R` (pure helpers + validation predicates),
  `R/mod_condselect.R` (`condSelectUI` + `condSelectServer` module), and
  `R/prep_data_container.R` (the DE runner with a structured signature).
* New module API: `condSelectUI(id)` and `condSelectServer(id, data, metadata)`.
  Returns `list(n_comparisons, start_de, is_ready, comparisons_spec)`.
* `prepDataContainer()` signature changed from
  `(data, counter, input, meta)` to `(data, metadata, comparisons_spec)`.
  The leaky `condselect$input` boundary in `R/server.R` is gone.
* UX: single-comparison default with "Add another comparison" footer for
  multi-comparison; editable per-side Treatment/Control labels with metadata-
  driven defaults; reference-word direction heuristic
  (`control|ctrl|wt|wildtype|...`) with always-visible swap button;
  per-method advanced settings + covariates collapsed by default;
  inline non-toast validation messages (`.text-warning` / `.text-danger`).
* Internal `conds` codes (`"Cond1"`/`"Cond2"`) preserved so
  `R/fct_de_methods.R`, `R/fct_prep_data.R`, `R/deprogs.R`, `R/barmain.R`,
  and downstream plotting need no changes.
* Removed exports (no known external callers): `debrowsercondselect`,
  `debrowsercondselectServer`, `selectedInput`, `getSelectInputBox`,
  `getMetaSelector`, `getGroupSelector`, `getConditionSelector`,
  `getConditionSelectorFromMeta`, `getMethodDetails`, `getCovariateDetails`,
  `selectConditions`, `get_conditions_given_selection`, `getSampleNames`.
* New tests: `test-condselect-helpers.R` (helpers), `test-condselect-validation.R`
  (predicates), `test-prepdatacontainer.R` (`prep_comparison_inputs` purity).
  Total +73 assertions (126 → 199 PASS).

### User-visible

* Raised `startDEBrowser()` upload limit from 30 MB to 90 MB.
