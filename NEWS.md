# debrowser NEWS

For releases prior to 1.31, see the legacy `NEWS` file.

## debrowser 1.41.2 (in development)

### Bug fixes

* **Dropped the `sodium` dependency**, which broke `R CMD check` on the
  Bioconductor Linux builder (nebbiolo2 has no libsodium, so the check failed
  with "Package suggested but not available: 'sodium'" before running any other
  stage). Auth crypto now uses `scrypt` and `openssl` — both already `Imports:`
  of `shinymanager`, and both present on every Bioconductor builder.
  - Password hashing moved from libsodium argon2id to `scrypt::hashPassword()`,
    the same primitive shinymanager itself stores.
  - Per-user AI key encryption moved from libsodium secretbox to AES-256-GCM
    with an explicit encrypt-then-MAC HMAC-SHA256 tag. R's `openssl` package
    neither emits nor verifies a GCM tag, so authentication is applied
    explicitly; encryption and MAC subkeys are domain-separated.
  - Existing password hashes and stored AI keys are **not** readable across this
    change — see the migration note below.

### Migration

* Password hashes and encrypted per-user AI keys written by 1.41.1 or earlier
  use libsodium formats and cannot be read by 1.41.2. Any user database created
  during D2 development must be re-created: users need to reset their passwords
  and re-enter their AI provider keys.

## debrowser 1.41.1

### Documentation overhaul

* **Rewrote the user-guide vignette** (`vignettes/DEBrowser.Rmd`) around the
  modernized six-step Data Prep wizard and the current top-level tabs (Main
  Plots, QC Plots, Concordance, Enrichment, Tables). Added coverage for the
  features the old guide missed — batch-correction QC, cross-contrast
  concordance, GO/KEGG + GSEA enrichment, reproducibility exports (R / R
  Markdown / Jupyter / methods paragraph), bookmarking & sharing, theming and
  keyboard shortcuts, and the optional AI interpretation panel.
* **Kept the package small.** The full illustrated user guide — with all
  screenshots and worked examples — lives *outside* the package at
  <https://debrowser.readthedocs.io> (the
  `UMMS-Biocore/debrowser-docs` repo, served by Read the Docs). The vignette is a
  concise, image-free reference that links there, and the README references the
  same externally hosted screenshots, so no images are bundled in the package
  tarball.
* **Rewrote `README.md`** to mirror the modern walkthrough at a shorter
  altitude and point to the online guide.
* Removed the unused `fontawesome` and `RColorBrewer` entries from `Imports`
  (icons come via `shiny::icon()`; no `brewer.pal`/`RColorBrewer::` usage),
  clearing the R CMD check "declared Imports should be used" note.

### UI design-system consolidation (docs/design plans §1–§6)

* **Grid/layout:** collapsed four grid idioms to one primitive
  (`bslib::layout_columns(col_widths=)`) and two card systems to one
  wrapper (`de_card()`, now with a `class=` passthrough) across every
  panel; retired `layout_column_wrap`, hand-rolled `display:grid`, and
  ragged rows. Spacing comes from a `--de-space-*` scale and plot heights
  from `de_plot_h()`. Added `tools/check-grid.sh` to lock the standard in.
* **Color/contrast:** raised light/dark muted text and introduced
  theme-resolved `--de-accent-ink` (accent-as-text) + `--de-ink-on-accent`
  tokens for WCAG-AA contrast; `--de-cyan` is now fill-only.
* **Icons:** Font Awesome only, via `shiny::icon()`. Repaired app-wide FA
  webfont rendering (the Inter UI font was clobbering glyphs), consolidated
  ad-hoc glyphs, and wired the favicon.
* **Loading/motion:** replaced the 1.1 MB boot gif with a CSS conic ring;
  added stepwise `withProgress` detail to the DE run; added
  `--de-transition`, `:focus-visible` rings, `prefers-reduced-motion`, and
  `cursor:not-allowed` affordances; removed the dead `getLoadingMsg`
  overlay and its orphan gifs.
* **Handoff:** added `de_style_guide()` + `inst/extdata/www/style-guide.html`
  (a component gallery in both themes that doubles as a pixel-regression
  baseline) and `DESIGN.md`, the contributor design contract.

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

### Phase B3 — Sane defaults harmonization

* Switched DE cutoff input from fold-change to |log2FC| convention.
  The cutoff numeric inputs are now labelled `padj <=` and `|log2FC| >=`.
* Added `[ Strict ] [ Standard ]` preset buttons above the DE cutoff
  inputs. Strict (padj 0.01, |log2FC| 1) is the default; Standard is
  (padj 0.05, |log2FC| 1). Manual edits clear the preset highlight
  unless the new pair matches a preset exactly.
* Cutoff inputs (DE padj, DE |log2FC|, GO p.adjust) are now
  `numericInput` with bounds + native validation, replacing
  `textInput` widgets that silently produced NaN downstream when
  users typed non-numeric values.
* New helper module `R/fct_cutoffs.R` owns the single source of
  truth for default values and preset definitions:
  `default_cutoffs()`, `cutoff_presets()`, `match_preset()`,
  `log2fc_to_fold()`, `fold_to_log2fc()`,
  `install_cutoff_preset_observers()`. The hardcoded fallback in
  `generateTestData()` now reads from `default_cutoffs()`.
* Internal-only Shiny input rename: `input$foldChange` -> `input$log2fc_cutoff`.
  Public `cutOffSelectionUI` API is unchanged; new exported
  companion `cutOffSelectionServer(id)` wires preset observers
  for the namespaced widget.

### Phase E3.B — Rich report generation + Jupyter + view-in-tab

* **Export dropdown gains three new items**, bringing the total to six:
  - **Rmd source** -- downloads the raw `.Rmd` body (no render).
  - **View HTML in tab** -- renders the Rmd to a tempdir, registers it
    as a Shiny resource path, and opens the rendered HTML in a new
    browser tab via `Shiny.addCustomMessageHandler('debrowser_open_tab',...)`.
  - **Jupyter notebook** -- downloads the same content as a `.ipynb`
    file with R-kernel (`ir`) code cells; opens directly in JupyterLab.
  The pre-existing `Rmd -> HTML` item is renamed to plain `HTML`
  (it always meant "render and download"); the new `View HTML in tab`
  is the in-browser counterpart.
* **`emit_rmd()` now produces a manuscript-style report** mirroring a
  reference Rmd contributed by a user (Haania mouse PA/DMSO study).
  YAML uses `code_folding: hide` so chunks are collapsible in the
  rendered HTML; setup chunk runs `eval = TRUE` so the report includes
  actual plots when rendered. New sections (in order):
  - Library + helper-source chunks
  - `## Methods` (paragraph from Phase E9's `methods_paragraph()`)
  - `## Pipeline` -- load, filter, batch, DE per comparison
  - `## Sample Info` -- `DT::datatable` of metadata
  - `## Quality Control {.tabset}` -- Count distribution / All2All /
    PCA + Scree (all on the all-detected-genes matrix)
  - `## DESeq Analysis {.tabset}` -- one tab per comparison with
    sub-tabs Results / Volcano / MA / Heatmap
  - `## Enrichment` (when configured)
  - `## Session Info {.tabset}` -- Hide / Show
* New pure helpers in `R/fct_export_session.R`: `emit_ipynb(blocks)`
  parses `emit_rmd()` output and converts to `.ipynb` JSON cells.
* New file: `inst/templates/report_helpers.R` (~534 lines) bundling
  the report's plotting functions (`count_distribution`, `all2all`,
  `run_pca`, `pca_plot`, `scree_plot`, `volcano_plot`, `ma_plot`,
  `heatmap_plot`, `getNormalizedMatrix`, `post_processing`,
  `add_alias`, `add_highlights`, `call_significance`). The emitted
  Rmd / Jupyter / .R all `source()` this file from the installed
  package so report styling stays in one place.
* `state_react()` (in `R/server.R`) now surfaces `full_counts` (the
  filter+batch-corrected matrix on all detected genes) and `metadata`
  (the sample-info table) so the QC and Sample Info sections can
  reference the same data DEBrowser sees.

### Phase E12.B — AI interpretation: presets + mount points

* AI interpretation panel widened from `fgseaGSEA`-only to all 6
  Enrichment modes (`enrichGO`, `enrichKEGG`, `enrichDO`,
  `enrichPathway`, `compareCluster`, `fgseaGSEA`). One mount, one
  preset (`summarize_geneset`) works across all modes via per-mode
  payload adapters.
* New AI panel on the **DE Analysis** tab (per-comparison, below the
  results table). Presets: `summarize_geneset`, `suggest_followup`,
  `draft_methods`. Privacy default for this mount: `+ Stats`.
* New AI panel on the **Comparison Concordance** tab (below the
  summary card). Presets: `reconcile_enrichments`, `suggest_followup`,
  `draft_methods`. In-card pathway picker surfaces when one or more
  pathways are enriched in two or more comparisons; selecting one
  triggers cross-comparison fgsea so the prompt sees real NES rows.
* New presets in `inst/templates/`:
  - `ai_reconcile_enrichments.md` — explains a pathway's divergent
    NES across multiple comparisons.
  - `ai_suggest_followup.md` — two-section response: bioinformatic
    next-analyses + wet-lab next-experiments.
  - `ai_draft_methods.md` — journal-style polish of E9's
    deterministic Methods paragraph. Cannot add or remove facts.
* Sanitized markdown response rendering via `commonmark` + `xml2`
  (replaces v1's plain `<pre>`). Strict allow-list: headings, bold,
  italic, lists, code, blockquote, hr. Links rendered as plain text
  (no hallucinated URLs are clickable). Images and scripts stripped.
* Privacy modes adapted per payload shape: `de_table` and
  `concordance` default to `+ Stats`; the `draft_methods` preset
  hides the radio entirely (no genes / stats in payload).
* No new Imports. `commonmark` + `xml2` added to Suggests (both
  already transitively present via `rmarkdown` / `httr2`).
* Streaming responses still deferred.

### Phase E12.A — AI interpretation foundation

* New top-right **Settings** dropdown in the navbar with an AI
  configuration modal: master switch (off by default), provider
  picker (Anthropic / OpenAI / Ollama), dynamic model lookup via
  `ellmer::models_*`, encrypted API-key storage via the OS keychain
  (`keyring` package), and a default privacy mode setting.
* New **AI interpretation** card on the Enrichment tab below the
  Leading Edge card. Renders only when the master switch is on, a
  provider is configured, and (for non-Ollama providers) an API key
  is present. v1 ships one question preset: "Summarize this gene
  set's biology", attached to the currently-selected fgsea pathway's
  leading-edge genes.
* Privacy modes per call (default: Symbols only):
  - **Symbols only** -- gene symbols of the leading edge.
  - **+ Stats** -- also log2FoldChange and adjusted p-value per gene.
  - **+ Stats + Enrichment** -- also the term name, p-value, and
    overlap count of the selected pathway.
  A "What will be sent?" disclosure shows the literal prompt body
  (live preview) and a character count before the user clicks Ask.
* New exported helpers in pure files: `ai_interpret(question, payload,
  privacy_mode, provider_chat, top_n, template_dir)` (`R/fct_ai_interpret.R`),
  `list_models(provider, api_key)` and `ai_chat(provider, model, api_key)`
  (`R/fct_ai_providers.R`). Internal helpers cover settings I/O and
  encrypted key storage (`R/fct_ai_settings.R`).
* New error class hierarchy: `ai_error` extends `simpleError`; subclasses
  `ai_no_key`, `ai_rate_limit`, `ai_network`, `ai_invalid_response`,
  `ai_disabled`. The Shiny module maps each subclass to a friendly
  notification with a recovery hint.
* LLM responses are rendered as plain preformatted text (`tags$pre`);
  no markdown parsing, no HTML execution, no automatic link
  traversal -- defense against untrusted-content patterns in model
  output.
* Three new Suggests gated via `require_pkg`: `ellmer (>= 0.1.0)`,
  `whisker`, `keyring`. R CMD check passes with all three uninstalled
  -- the AI features are gracefully unavailable in that case.
* AI is **disabled by default**. No network calls happen unless the
  user explicitly enables AI features and configures a provider.
* Phase E12.B will extend with the remaining 3 question presets
  (reconcile enrichments, suggest follow-up experiments, draft methods
  narrative) and 2 mount points (DE Analysis tab results, Comparison
  Concordance summary).

### Phase E9 — Methods-paragraph autogen

* Phase E3's Export dropdown now emits a single manuscript-ready methods
  paragraph (~150-250 words) with inline citations and version stamps,
  replacing the previous per-step bullet list. The paragraph appears
  in three places:
  - At the top of the exported `.R` script as a wrapped comment block.
  - In the rendered `.Rmd -> HTML` report's "## Methods" section.
  - In a new **Copy methods text** Export menu item that opens a modal
    with the paragraph in selectable preformatted text plus a
    "Download as .txt" button.
* New exported `methods_paragraph(blocks)` function (in
  `R/fct_methods_text.R`); upgraded internal `methods_sentences()`
  helper now produces citation-rich, version-stamped per-step
  sentences. Both functions are pure (no Shiny dependency) and
  consume the `build_session_blocks()` output from Phase E3.
* New internal `.method_refs` registry maps method keys to
  `list(name, version_pkg, cite)` for nine entries: DEBrowser,
  DESeq2, edgeR, limma, ComBat, ComBat-seq, Harman, fgsea, MSigDB.
  Citations are inline "(Author et al., YEAR)" plain text.
* Soft fallback when a cited package is not installed: citation
  reads "(version unknown)" and a deduplicated `showNotification`
  warns the user. Methods text export never errors on a missing
  version lookup.

### Phase E3 — Reproducibility export

* New top-right **Export** dropdown in the navbar with two items:
  - **R script** -- downloads a runnable `.R` script that reproduces the
    full analytical pipeline (data load -> low-count filter -> batch
    correction -> DE per comparison -> GSEA if loaded). Calls only
    already-exported pure helpers (`filter_low_counts`,
    `apply_batch_correction`, `run_de`, `run_gsea`, `msigdb_pathways`),
    so the script has no Shiny dependency. Sets per-comparison `deN`
    variables in the workspace, writes per-comparison TSVs to
    `./debrowser_results/`, and prints `sessionInfo()` at the end.
  - **Rmd -> HTML** -- renders a self-contained HTML report with the
    same pipeline as code chunks (`eval = FALSE` by default) plus an
    auto-generated Methods paragraph. Gated on the `rmarkdown` package
    being installed; falls back to raw `.Rmd` download if pandoc fails.
* New pure helpers in `R/fct_export_session.R`: `build_session_blocks()`,
  `emit_r_script()`, `emit_rmd()`, `sanitize_label()`. New
  `R/fct_methods_text.R::methods_sentences()` produces the per-step
  prose consumed by both emitters; Phase E9 will upgrade it to a
  citation-rich paragraph generator.
* `enrichmentGmtServer()` return is now `list(pathways, state)` instead
  of just the pathways reactive (additive; consumers extend the
  destructure).
* Both export items are gated by a "Run a DE analysis before exporting"
  notification until DE has been run.
* Frozen `sessionInfo()` of the export-time R session is embedded in
  the `.R` script header for audit reproducibility; live `sessionInfo()`
  is also called at script end.
* Comparison labels with collisions get `_2`, `_3` suffixes in TSV
  filenames; unsafe characters in labels are replaced with underscores.

### Phase E11 — Comparison Concordance tab (top-level)

* New top-level **Comparison Concordance** tab between QC Plots and Enrichment.
  Auto-shown when the user has set up two or more comparisons in CondSelect; hidden for
  single-comparison sessions. Compares the user's existing comparisons against each other
  (no DE re-running — reads `dc()[[i]]$init_data` produced by the main DE pipeline).
* Five cards driven by live `padj` / `lfc` cutoffs:
  - DEG bar (up red rightward / down blue leftward, ordered by total DEG count)
  - Pairwise DEG count heatmap (symmetric `groups x groups` matrix)
  - UpSet plot of significant-gene-set overlap across comparisons
  - Pairwise log2FC scatter with Spearman correlation
  - Pairwise concordance summary table (DT)
* New pure helpers in `R/fct_method_concordance.R`: `concordance_sets()`,
  `concordance_summary()`, `plot_method_upset()`, `plot_method_scatter()`,
  `comparison_labels()`, `de_direction_summary()`, `plot_de_direction_bar()`,
  `plot_de_pairwise_heatmap()`, plus `run_de_methods()` for programmatic use.
* `UpSetR` added to Suggests (gated via `require_pkg("UpSetR")`).

### Phase E2.5 — Consolidated Enrichment tab

* The previously-separate **GO Term** and **Enrichment** tabs are
  now a single **Enrichment** tab. The legacy GO Term modes
  (enrichGO / enrichKEGG / Disease / compareClusters / GSEA via
  `clusterProfiler::gseGO`) and the new fgsea-based GSEA share one
  top-level tab. The standalone Enrichment tab introduced in E1
  has been removed; its content is folded in here.
* New radio choice **"GSEA (fgsea / .gmt or MSigDB)"** under the
  Enrichment-method picker. Selecting it reveals the GMT/MSigDB
  picker and Advanced controls (min/max set size, permutations,
  seed) inside the same sidebar that hosts the legacy GO Term
  options.
* Both render styles coexist via conditional panels: the legacy
  modes keep their plot+table tabset; the fgsea mode renders
  results table + enrichment plot + leading edge cards plus a
  multi-comparison NES heatmap when more than one comparison is
  loaded — same widgets the standalone Enrichment tab used.
* `enrichmentUI()` / `enrichmentServer()` (the standalone-tab
  module pair from E1) remain exported as a public API for users
  who want to embed the enrichment tab elsewhere; the consolidated
  panel reuses the smaller `enrichmentGmtServer()` and
  `enrichmentNesHeatmapServer()` building blocks directly.
* `togglePanels()` reverts from a 0..5 loop with backwards-compat
  rule to a clean 0..4 loop, since panel5 no longer exists.

### Phase E2 — MSigDB integration (gene-set source picker)

* The Enrichment tab's gene-set picker now offers **MSigDB** as a
  sibling source to manual `.gmt` upload. Pick a species (the 20
  species `msigdbr` ships, including human, mouse, rat, fly, yeast,
  zebrafish, C. elegans, and more), a top-level collection
  (Hallmark, Curated, Ontology, Cell type, ...), and an optional
  subcollection (e.g. `CP:KEGG`, `GO:BP`). Click "Load gene sets"
  to pull the named-list of pathways into the running GSEA session.
* New pure helper `msigdb_pathways(species, collection,
  subcollection)` in `R/fct_gsea.R` wraps `msigdbr::msigdbr()` and
  reshapes its long-format tibble into the same named-list-of-
  character-vectors shape `gmt_to_pathways()` returns, so all
  downstream code (run_gsea, NES heatmap, leading edge) is
  source-agnostic. Errors from msigdbr (unknown species, unknown
  collection, empty result) are normalized to the
  `empty_input` classed condition.
* `msigdbr` added to `Suggests` (~50MB local install but no
  install-time network — Bioc-friendly). Calls go through
  `require_pkg("msigdbr")` with the install command for users who
  don't have it.
* Per-session in-module cache keyed on
  (species, collection, subcollection) so re-clicking "Load" with
  the same inputs is instant.
* The GO Term tab is unchanged in this release; folding ORA into
  the Enrichment tab as the second method is deferred to E2.5.

### Phase E1 — Enrichment tab (GSEA via fgsea)

* New top-level **Enrichment** tab next to GO Term, driven by
  ranked-list Gene Set Enrichment Analysis. Pre-DE the tab is
  hidden; once DE has run, paste a `.gmt` file (or use the bundled
  `inst/extdata/test-gmt/hallmark-mini.gmt` fixture) and the
  results table populates with NES, padj, leading edge.
* When more than one comparison is loaded, the NES heatmap card
  appears below the results, plotting NES across pathways x
  comparisons (significance stars, axis flip, padj cutoff slider).
* New pure helpers in `R/fct_gsea.R` (`@export`):
  `gmt_to_pathways(path)` (fgsea-gated wrapper around
  `fgsea::gmtPathways`), `run_gsea(de_table, pathways, ...)` (DE
  table -> tidy enrichment data.frame), and
  `nes_heatmap_data(results_by_comparison, sig_only, sig_threshold)`
  (long-format reshape for the heatmap).
* New Shiny modules in `R/mod_enrichment.R`,
  `R/mod_enrichment_gmt.R`, `R/mod_enrichment_nes_heatmap.R`. The
  GMT picker is the integration point Phase E2 will use to add
  MSigDB as a sibling source; the NES heatmap module is the same
  widget Phase E11 will reuse for cross-method comparison.
* `fgsea` added to `Suggests` (Bioconductor); calls go through
  `require_pkg("fgsea")` so users without it installed see the
  install command instead of a stack trace.
* Reference architecture (gsea_analysis shape, NES heatmap card,
  GMT picker layout) adapted from
  https://github.com/nephantes/gsea-explorer (Via Scientific) —
  re-implemented against this package's pure-helper conventions.

### Phase E4 — Sample QC dashboard (always-on cards)

* QC Plots tab now exposes four new cards for raw-count
  sample inspection: **Library Depth** (per-sample total
  counts, with >2-SD outlier flag), **Feature Detection
  Rate** (% of features with non-zero counts per sample),
  **Mitochondrial Read %** (sum of `^MT-`/`^mt-`/`Mt-` rows
  per sample, with empty-state when no MT genes are
  detected), and **Sample Distance Heatmap** (clustered
  Euclidean distance on VST-transformed counts).
* New `R/fct_qc.R` exports the underlying pure helpers
  (`library_depth_summary`, `detection_rate`,
  `mt_pct_per_sample`, `sample_distance_matrix`,
  `flag_outliers_2sd`) so they can be reused outside the
  Shiny app.
* New **Mapping / rRNA Stats** card ships as an empty-state
  stub describing the optional sidecar TSV format
  (`sample`, `mapped_pct`, `rRNA_pct`); the upload handler
  itself lands in a follow-up.
* Cards consume post-filter, post-batch, pre-normalize
  counts via `batch()$BatchEffect()$count` so library-size
  metrics report the correct raw values.
* Three additional post-DE cards (Dispersion, Size factors,
  Cook's outlier flag) are deferred to a follow-up phase
  pending DESeq2 `dds` retention through `prepDataContainer`.

### Phase E4.5 — Post-DE QC cards + dds retention

* `run_deseq2()` gains a `return_dds = FALSE` argument; when
  TRUE it returns `list(res, dds)` so the fitted DESeqDataSet
  is recoverable for downstream QC. Threaded through
  `runDESeq2()`, `runDE()`, `debrowserdeanalysis()`, and
  `prepDataContainer()` (which now stashes a `dds` slot per
  comparison alongside `init_data`). Default behaviour is
  unchanged so existing callers (`generateTestData`,
  per-method tests) keep their data.frame contract.
* QC Plots tab adds three post-DE cards driven by the active
  comparison's `dds`: **Dispersion Estimates** (DESeq2
  `plotDispEsts` of gene-wise / fitted / shrunken values),
  **Size Factors vs Library Size** (scaled bars per sample
  with Spearman ρ in the subtitle), and **Cook's Outlier
  Counts** (per-sample count of high-Cook genes vs the
  vignette threshold `4 / (n_samples - n_params)`).
* New pure helpers in `R/fct_qc.R`:
  `size_factor_library_summary(dds)` and
  `cooks_outlier_summary(dds, threshold = NULL)`. The
  Spearman correlation and active threshold are attached as
  attributes on the returned data.frame.
* Cards render a friendly empty-state alert when no fitted
  `DESeqDataSet` is available (pre-DE, or non-DESeq2 method).
* QC sidebar's "Select Columns" checkboxes now also drive cards
  1-4 (Library Depth, Detection Rate, MT %, Sample Distance) and
  cards 6-7 (Size Factors, Cook's): unchecking a sample hides
  its bar/row across every per-sample card. Card 5 (Dispersion)
  is gene-level so column selection has no effect there. New
  pure helpers `qc_keep_cols(counts, selected)` and
  `qc_keep_meta_rows(meta, selected)` in `R/fct_qc.R`.

### Phase B4 — Friendly errors

* User-facing error messages now follow a consistent "what went wrong + what to do" format with correct severity (red blocks, yellow warns, green/blue empty-result).
* Replaced raw R diagnostics in file-upload errors (separator mismatch, duplicate gene IDs, column/metadata mismatch).
* Empty enrichment results no longer display as red errors — they were a category bug.
* Six hand-rolled "Please install <pkg>" messages in GO/KEGG paths collapsed into the existing `require_pkg()` helper.
* No behavior change beyond message text and notification persistence.

### Phase B3.5 — Sane defaults follow-up

* DESeq2 default test changed from `Wald` to `LRT`, harmonizing the
  pure-helper, parser fallback, test-data, and (where applicable)
  help text with the UI default already in place.
* DESeq2 LFC shrinkage now defaults to `apeglm`. Install via
  `BiocManager::install("apeglm")` if not already available; a
  friendly install message surfaces on first DE run otherwise.
  apeglm remains in `Suggests`, not `Imports`.
* Low-count filter auto-applies on data load (method = Max,
  cutoff = 10 — the previous default values, now applied without
  a Filter click). Click Filter with a different cutoff/method to
  override, or set cutoff = 0 to restore the unfiltered counts.

### User-visible

* Raised `startDEBrowser()` upload limit from 30 MB to 90 MB.
