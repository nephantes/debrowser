# Phase B2.5 — Comparison Selection wizard rewrite

**Date:** 2026-04-29
**Status:** Spec, ready for plan
**Predecessor:** B2c (`bb80593`) — wizard polish + cosmetic + shinytest2 scaffold
**Successor:** B3 (sane defaults harmonization: padj 0.05, |log2FC| 1)
**Branch:** `modernize`

## Goal

Rewrite `R/condSelect.R` (≈900 LOC, monolithic, render-with-side-effects, "Numerator/Denominator" labels) into a focused, modular, user-friendly comparison wizard. Functionality preserved exactly — multi-comparison support, metadata-driven flow, manual flow, all three DE methods, covariates. The downstream contract (`conds`/`cols`/`cond_names`/`dclist`) is unchanged so `R/fct_prep_data.R`, `R/fct_de_methods.R`, `R/deprogs.R`, `R/barmain.R`, `R/server.R` (except the `prepDataContainer` call site) and the existing 126 tests need no modification.

The improvements are: (1) user-friendly "Treatment vs Control" labeling editable per side, (2) single-comparison default with accordion tail for multi-comparison, (3) advanced model settings and covariates collapsed by default, (4) inline non-toast validation, (5) reference-word heuristic + always-visible swap for direction, (6) closed module boundary (no more `condselect$input` leak), (7) split into three files with one job each.

## Locked design decisions

1. **Scope** — full rewrite, but the internal `conds` vector (`"Cond1"`/`"Cond2"`) stays as-is. Only the user-facing `cond_names` defaults change on the no-meta path.
2. **Multi-comparison UX** — single comparison panel default; "Add another comparison" reveals an accordion tail.
3. **Side labels** — two `textInput`s per comparison ("Treatment label" / "Control label"). Auto-default to picked metadata level names; fall back to `"Treatment"`/`"Control"` when no meta. User-editable.
4. **DE method disclosure** — DE method dropdown visible (default DESeq2). Method-specific params + covariates inside an `accordion_panel("Advanced model settings", open = FALSE)` per comparison card.
5. **Direction** — reference-word heuristic chooses Control side (case-insensitive regex against `control|ctrl|wt|wildtype|wild_type|vehicle|dmso|untreated|mock|ref|naive|baseline|0h|day0`); alphabetical fallback. Always-visible ⇄ "Swap direction" button.
6. **Validation** — inline `.text-warning` / `.text-danger` messages, no toast spam, no auto-remove of bad covariates, Start DE button disabled (not hidden) when errors are active. Warnings are advisory and do not block Start DE.

## File layout

| File | Role | LOC | Public functions |
|---|---|---|---|
| `R/fct_condselect.R` (new, pure) | Pure helpers, no Shiny dep | ~150 | (all `@noRd`) `infer_control_level(levels) -> character(1)`; `default_side_labels(meta_column, treatment_level, control_level) -> c(treatment, control)` (returns level names when meta set, `c("Treatment", "Control")` when `meta_column == NA`); `halve_sample_names(sample_names) -> list(treatment, control)` (today's `getSampleNames` halving); `compute_cond_names(spec) -> c(spec$treatment_label, spec$control_label)`; `validate_comparison(spec, metadata) -> list of validation records`; `build_demethod_params_string(de_method, method_params, covariates) -> character(1)` |
| `R/mod_condselect.R` (new, module) | `condSelectUI(id)` + `condSelectServer(id, data, metadata)` | ~350 | `condSelectUI`, `condSelectServer` (`@export`) |
| `R/prep_data_container.R` (new) | `prepDataContainer(data, metadata, comparisons_spec)` extracted, signature changed | ~120 | `prepDataContainer` (`@export`) |
| `R/condSelect.R` | Deleted | — | — |

## Removed / renamed exports

The following are removed from `NAMESPACE` (`@export` → `@noRd` or removed entirely):

- `debrowsercondselect` — legacy non-module entry point. Removed entirely. Its only callsite is its own docstring example.
- `selectedInput`, `getSelectInputBox`, `getMetaSelector`, `getGroupSelector`, `getConditionSelector`, `getConditionSelectorFromMeta`, `getMethodDetails`, `getCovariateDetails`, `selectConditions`, `get_conditions_given_selection` — internal renderers/helpers, replaced or refactored into the new module / `fct_condselect.R`.
- `getSampleNames` — renamed `halve_sample_names()`, internal.

The new public surface is exactly three functions: `condSelectUI`, `condSelectServer`, `prepDataContainer`. A `NEWS.md` entry documents the removals.

External-caller risk: a third-party embedding DEBrowser that imports any removed function will break. Mitigation: GitHub + Bioconductor search performed during modernization phase establishes no known external callers; same status here.

## UI structure

The wizard is a single bslib `de_card("Comparison Selection")` containing one fully-expanded "Comparison 1" card by default, with a footer row of action buttons. Adding a second+ comparison reveals a `bslib::accordion(multiple = TRUE)` tail beneath the first card; subsequent comparisons are closed `accordion_panel`s.

### Per-comparison card layout

```
┌── Comparison N: <treatment-label> vs <control-label> ──────────┐
│                                                                │
│  Group by metadata column ▾  [ "(None — pick samples manually)"│
│                                  Cell Type, Treatment, Batch ] │
│                                                                │
│  ┌── Treatment ─────────────┐ ⇄ ┌── Control ─────────────────┐ │
│  │ Level ▾ [KO]             │   │ Level ▾ [WT]               │ │
│  │ Label  [KO          ]    │   │ Label  [WT          ]      │ │
│  │ Samples [s1, s2, s3 ▾]   │   │ Samples [s4, s5, s6 ▾]     │ │
│  └──────────────────────────┘   └────────────────────────────┘ │
│                                                                │
│  DE method ▾ [DESeq2]                                          │
│                                                                │
│  ▸ Advanced model settings  (closed by default)                │
│      ├── Method-specific params (DESeq2/EdgeR/Limma)           │
│      ├── Covariates [multi-select]                             │
│      │     ⚠ Covariate `batch` has NA in s2; cannot include.   │
│      └── Help link                                             │
│                                                                │
│  Validation messages (inline, only when present):              │
│      ⚠ Treatment label is empty                                │
│      ⚠ Sample s2 appears in both sides                         │
└────────────────────────────────────────────────────────────────┘
```

### Footer row (outside all comparison cards)

```
[ + Add another comparison ]   [ - Remove last ]            [ Start DE → ]
```

- `Remove last` is disabled when `n_comparisons() == 1`.
- `Start DE` is disabled (via `shinyjs::toggleState` — already a Suggests dep) when `is_ready()` is `FALSE`. Tooltip explains why.

### Three card states

1. **No metadata column picked** (`meta_column = NA`) — "Level" dropdowns hidden; "Label" defaults `"Treatment"` / `"Control"`; "Samples" pickers auto-populated via `halve_sample_names()`.
2. **Metadata column picked, ≥ 2 levels** — "Level" dropdowns appear with column levels. Initial assignment via `infer_control_level()`. Side labels default to picked level names; sample pickers auto-fill with samples matching each side's level. User can override samples (e.g., to exclude an outlier).
3. **Metadata column with < 2 distinct levels** — inline error in card validation footer; Start DE blocked.

### Swap button (⇄)

Between the two side cards. Click swaps `treatment_samples ↔ control_samples`, `treatment_label ↔ control_label`, `treatment_level ↔ control_level` in the per-comparison rv. log2FC sign and plot legends follow automatically because everything downstream reads `cond_names`.

### Accordion-title binding

Accordion panel titles bind reactively to `paste0("Comparison ", i, ": ", treatment_label, " vs ", control_label)`. Title for Comparison 1 lives on its enclosing card header; same template.

## Reactive contract

`condSelectServer(id, data, metadata)` returns:

```r
list(
  n_comparisons    = reactive(integer),
  start_de         = reactive expression,           # eventReactive on Start DE click
  is_ready         = reactive(logical),             # TRUE iff all comparisons valid (no errors)
  comparisons_spec = reactive(list of per-comparison specs)
)
```

Per-comparison spec:

```r
list(
  meta_column       = character(1) | NA_character_,
  treatment_level   = character(1) | NA_character_,
  control_level     = character(1) | NA_character_,
  treatment_samples = character(),
  control_samples   = character(),
  treatment_label   = character(1),                  # defaults from level / "Treatment"
  control_label     = character(1),                  # defaults from level / "Control"
  de_method         = "DESeq2" | "EdgeR" | "Limma",
  method_params     = list(...),                     # method-specific named list, schema below
  covariates        = character()                    # column names from metadata; empty = none
)
```

`method_params` schema (one of the three, matching today's widget set):

```r
# DESeq2
list(fitType = "parametric"|"local"|"mean",
     betaPrior = TRUE|FALSE,
     testType = "LRT"|"Wald",
     shrinkage = "None"|"apeglm"|"ashr"|"normal")

# EdgeR
list(edgeR_normfact = "TMM"|"RLE"|"upperquartile"|"none",
     dispersion = character(1),                       # numeric-as-text, today's contract
     edgeR_testType = "exactTest"|"glmLRT")

# Limma
list(limma_normfact = "TMM"|"RLE"|"upperquartile"|"none",
     limma_fitType = "ls"|"robust",
     normBetween = "none"|"scale"|"quantile"|"cyclicloess"|
                   "Aquantile"|"Gquantile"|"Rquantile"|"Tquantile")
```

`build_demethod_params_string(de_method, method_params, covariates)` produces today's exact comma-separated string (`"DESeq2,batch,parametric,FALSE,LRT,None"` etc.) so `R/fct_de_methods.R` keeps parsing unchanged.

Stored as `reactiveValues` indexed by integer comparison id. `comparisons_spec()` snapshots all entries to a plain list on each invalidation.

### `prepDataContainer` signature change

```r
# Before
prepDataContainer(data, counter, input, meta)

# After
prepDataContainer(data, metadata, comparisons_spec)
```

`prepDataContainer` no longer reads `input`. It iterates `comparisons_spec`, and for each entry builds the same downstream contract:

- `cols <- c(spec$treatment_samples, spec$control_samples)` — unchanged
- `conds <- c(rep("Cond1", length(treatment_samples)), rep("Cond2", length(control_samples)))` — internal codes unchanged so `R/fct_prep_data.R::apply_de_filters` (which hardcodes `paste0("Cond", 2 * compselect - 1)` etc.) continues to work
- `cond_names <- c(spec$treatment_label, spec$control_label)` — for plot legends and `paste0(cond_names[1], ".vs.", cond_names[2])` column-prefix construction in `R/fct_prep_data.R`
- `demethod_params` comma-encoded string preserved verbatim — built by `build_demethod_params_string(spec$de_method, spec$method_params, spec$covariates)`. `R/fct_de_methods.R` and `R/deprogs.R` need zero changes.

### Call site change in `R/server.R`

```r
# Before
observeEvent(condselect$start_de(), {
  prepDataContainer(data, condselect$cc(), condselect$input, meta)
})

# After
observeEvent(condselect$start_de(), {
  prepDataContainer(data, meta, condselect$comparisons_spec())
})
```

One file, two-line change. The leaky `condselect$input` export goes away.

## Validation

Validation lives in **pure predicates** in `R/fct_condselect.R`. Each takes a comparison spec (and metadata) and returns `list(ok = logical, message = character | NULL, severity = "warning" | "error")`. Predicates are composed into a single `validate_comparison(spec, metadata)` returning a vector of message records.

The module's `comparisonCardServer()` calls this in a single `reactive()` per card; the result drives:

1. **Per-card validation footer** — `uiOutput(ns("validation_msgs_N"))` rendering `.text-warning` / `.text-danger` lines.
2. **Affected-widget badge** — for covariate-specific messages, the same message appears under the covariates widget inside the Advanced accordion.
3. **`is_ready` reactive** — `all(severity != "error")` across all comparisons; controls Start DE button's `disabled` attribute.

### Predicate list

| Predicate | Severity | Behavior on failure |
|---|---|---|
| Treatment side has ≥ 1 sample | error | Block Start DE; inline message |
| Control side has ≥ 1 sample | error | Block Start DE; inline message |
| Treatment & Control sample sets disjoint | error | Block Start DE; inline message |
| Treatment label & Control label both non-empty | error | Block Start DE; inline message |
| When `meta_column` set: column has ≥ 2 distinct levels | error | Block Start DE; inline message |
| When `meta_column` set: `treatment_level ≠ control_level` | error | Block Start DE; inline message |
| Each covariate: no NA in selected samples | warning | Inline message; user deselects manually; **does NOT auto-remove** |
| Each covariate: ≥ 2 unique values in selected samples | warning | Same |
| Each covariate: not confounded with treatment (each level appears in both sides) | warning | Same |
| Each covariate: column ≠ `meta_column` (skipped when `meta_column == NA`) | warning | Same |

If the user clicks Start DE while only warnings are active, DE runs (warnings are advisory). If errors are active, the button is disabled — no validate-on-submit explosion.

**Removed behavior:** silent auto-remove of bad covariates via `updateSelectInput`. The user resolves warnings; the message tells them how.

## Reference-word heuristic

`infer_control_level(levels)` in `R/fct_condselect.R`:

```r
.CONTROL_REGEX <- paste0(
  "(?i)^(",
  paste(c(
    "control", "ctrl", "wt", "wildtype", "wild_type",
    "vehicle", "dmso", "untreated", "mock", "ref",
    "naive", "baseline", "0h", "day0"
  ), collapse = "|"),
  ")$"
)

infer_control_level <- function(levels) {
  matches <- grepl(.CONTROL_REGEX, levels, perl = TRUE)
  if (sum(matches) == 1) {
    return(levels[matches])
  }
  # 0 matches OR ambiguous (≥ 2 matches): alphabetical fallback
  sort(levels)[1]
}
```

Anchored regex (`^...$`) avoids matching `"controllab"` as `"control"`. Case-insensitive. Ambiguity → fallback prevents silently picking the wrong one.

## Testing

| Test file | Purpose | Status |
|---|---|---|
| `tests/testthat/test-condselect-helpers.R` | `infer_control_level`, `default_side_labels`, `halve_sample_names`, `compute_cond_names`, `build_demethod_params_string` | **New** (≥ 15 tests) |
| `tests/testthat/test-condselect-validation.R` | Each predicate + composite `validate_comparison` | **New** (≥ 10 tests) |
| `tests/testthat/test-prepdatacontainer.R` | `prepDataContainer()` with synthetic specs (single + multi comparison; meta + manual paths) | **New** (≥ 4 tests) |
| `tests/testthat/test-app-shinytest2.R` | B2c's existing state smoke ("downstream tabs hidden pre-DE") | Existing — unaffected |
| All other `tests/testthat/test-*.R` | Downstream filter/DE/plot tests | Existing — unaffected |

Target: ≥ 90 % line coverage on `R/fct_condselect.R` (pure helpers — easy). Module + `prepDataContainer` coverage opportunistic via integration; not gated.

## Acceptance criteria

The phase ships when:

1. **Tests:** all existing tests pass (current state: 126/126 + 1 skip). New tests added: ≥ 15 (helpers) + ≥ 10 (validation) + ≥ 4 (prepDataContainer). Total target ≥ 155 PASS.
2. **`R CMD check`:** zero new errors/warnings/notes vs today's baseline (3 W + 2 N pre-existing).
3. **shinytest2 state smoke** still passes; the B2c CI workflow remains green.
4. **Functional parity verified manually** against the Vernia + Donnard demos:
   - Vernia demo → Comparison Selection → meta-driven flow auto-fills levels, side labels, sample lists. log2FC sign matches today's output for the same selections (key regression check; capture a "before" screenshot and a row of the DE result table during smoke).
   - Manual flow with no metadata → halves samples, defaults to "Treatment"/"Control" labels.
   - Multi-comparison: add 2 more comparisons; each runs DE independently; results in 3 separate downstream `DEResults` tabs.
   - Covariate flow: pick a confounded covariate → inline warning shows; Start DE still runs (advisory); DE completes.
   - Swap button: click → labels and log2FC sign flip; downstream plots reflect the swap.
5. **Visual sanity in dark mode:** validation messages readable; swap button discoverable.
6. **`NEWS.md` entry written** documenting removed exports and `prepDataContainer` signature change.
7. **`R/condSelect.R` is deleted** from the working tree (no orphan).

## Followups (deferred)

- Plot-legend rewrite for the manual no-meta path: today downstream plot modules may hardcode "Cond1"/"Cond2" as display strings independent of `cond_names`. If a smoke test reveals any such hardcoding, log it in `phase_b2_5_handoff.md` for a follow-up phase rather than expanding B2.5's scope.
- Direction-default heuristic refinement (more reference words, or a "remember last-used direction" pref) deferred until user feedback.
- Saving/restoring comparison state across sessions (for the URL-load contract) — not part of B2.5.

## Risks

- **Risk:** structured-rv pattern interacts poorly with multiple dynamically-added comparison cards (Shiny has known fragility around dynamically inserting UI that contains nested observers).
  **Mitigation:** use `insertUI`/`removeUI` only for the accordion tail; per-comparison observers are created inside a `comparisonCardServer(card_id, ...)` factory called once per card, with explicit teardown on Remove. Add an integration test that exercises Add/Remove cycles to catch leaks early.

- **Risk:** the "swap button flips log2FC sign" UX is technically right but may confuse users who already understood the picker direction.
  **Mitigation:** swap button shows a small tooltip on hover: "Flip direction (positive log2FC will indicate up in <new-treatment-label>)".

- **Risk:** removing exported helpers breaks an unknown third-party embedder.
  **Mitigation:** documented in NEWS.md; major version bump alignment (this is a breaking-API change inside the modernize branch which has not yet been pushed; appropriate point to break).

## Out of scope (explicit)

- Plot-legend rewrite when `cond_names == c("Cond1", "Cond2")` (manual no-meta path). Deferred.
- Internal rename of `conds` codes (`"Cond1"`/`"Cond2"`). Stays.
- Methods-formula UX ("Design: ~ batch + treatment" surfacing). Deferred to Phase F E5.
- Per-comparison saved presets / recipes. Out of scope.
- LRT / multi-factor designs. Phase F E5.
