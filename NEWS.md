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

### User-visible

* Raised `startDEBrowser()` upload limit from 30 MB to 90 MB.
