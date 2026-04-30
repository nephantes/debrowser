# Phase B3 — Sane defaults harmonization + cutoff widget redesign

**Date:** 2026-04-30
**Branch:** `modernize`
**Predecessor:** B2.5 (condSelect rewrite), shipped at `4832d8b`
**Successor:** B4 (friendly errors)

## Context

The original B3 entry in `2026-04-27-debrowser-modernization-design.md` (lines 230–248) bundled seven items: cutoff defaults, `numericInput` widget redesign, preset buttons, DE method default, low-count filter default, LFC shrinkage, batch auto-prompt, covariate auto-hide. Those last five interact with the wizard (B2b), condSelect (B2.5), and DE call paths in ways that deserve their own brainstorms.

This spec re-scopes B3 to the cutoff portion only — items 1–3 of the original list — so it stays a clean pure-functional phase that closes the cutoff story without touching DE call paths. Items 4–7 are deferred to follow-up phases (likely Phase F E5 and post-modernization sweeps).

## Goals

1. **Harmonized defaults across all DE-cutoff sites.** Single source of truth in a new `R/fct_cutoffs.R` helper. Today's defaults are hardcoded at four sites (`R/deprogs.R:90-91`, `R/uifuncs.R:232-233`, `R/uifuncs.R:112`, `R/mainScatter.R:412-413`); after B3 they all read from `default_cutoffs()`.
2. **`textInput` → `numericInput` widget upgrade.** Closes the "user types `abc`, gets silent NaN downstream" foot-gun. Applies to all three cutoff fields (DE padj, DE log2FC, GO `gopvalue`).
3. **Strict / Standard preset buttons** above the DE cutoff inputs. One-click stringency selection. Page loads with Strict pre-selected (matches the codebase's existing 0.01 default).
4. **Switch from fold-change to |log2FC| convention** at the UI layer. Matches volcano Y-axis and the language of every modern paper. Internal pipeline (`R/fct_prep_data.R`) keeps fold-change semantics; conversion happens at one boundary.

## Decisions made during brainstorm (2026-04-30)

| ID | Decision | Rationale |
|---|---|---|
| Q1 | Re-scope B3 to cutoffs only (items 1–3); defer method/filter/LFC-shrinkage/batch/covariate to follow-ups | Pure-functional scope; no DE call-path churn; smaller regression surface |
| Q2 | Two presets: `[ Strict 0.01 ] [ Standard 0.05 ]`; drop the 0.10 "Sensitive" tier | Less choice-paralysis; 0.10 is borderline-misleading for non-statisticians |
| Q3 | Switch UI to log2FC convention (label `|log2FC| ≥`, default `1`) | Matches volcano Y-axis; legacy "foldChange" label is a bench-biologist trap |
| Q4 | Both presets share `|log2FC| ≥ 1`; only padj differs | Single-axis presets are easier to explain; lab-specific FC pairing is what manual editing is for |
| Q5 | DE cutoffs get presets; `gopvalue` only gets `numericInput` upgrade (no presets) | GO ORA significance is a different statistical context — preset metaphor doesn't transfer |
| Q6 | New pure helper `R/fct_cutoffs.R` with `default_cutoffs()`, `cutoff_presets()`, `match_preset()`, `log2fc_to_fold()`, `fold_to_log2fc()` | Centralised, unit-testable, replaces 8 hardcoded values across 4 files |
| Q7 | Rename `input$foldChange` → `input$log2fc_cutoff`; update all readers | Variable name matches user-facing convention; bookmarking isn't wired so no break |
| Q8 | `shinyWidgets::radioGroupButtons` for preset bar | Existing dep; built-in selected/unselected styling; one-line clear-on-manual-edit |
| Q9 | Permissive numeric bounds (`min=0`, `max=1` for padj/gopvalue, `max=NA` for log2FC) | Avoid frustrating dead-end for legitimate large-FC cases; Shiny native validation guards non-numeric input |
| Q10 | Helper-only test scope (`tests/testthat/test-cutoffs.R`) | Logic lives in helpers; UI/shinytest2 baselines are out of scope (B2c baselines are pending review) |

## Architecture

```
R/fct_cutoffs.R                  (NEW — pure helpers, ~40 LOC)
  default_cutoffs()              -> list(padj=0.01, log2fc=1, gopvalue=0.01)
  cutoff_presets()               -> data.frame(name, label, padj, log2fc)
  match_preset(padj, log2fc)     -> "strict" | "standard" | NA_character_
  log2fc_to_fold(x)              -> 2^x
  fold_to_log2fc(x)              -> log2(x)

R/uifuncs.R                      (MODIFIED — sidebar/global widget)
  textInput("padj", ...)         -> numericInput("padj", ...)
  textInput("foldChange", ...)   -> numericInput("log2fc_cutoff", ...)
                                    + radioGroupButtons("cutoff_preset", ...)
  textInput("gopvalue", ...)     -> numericInput("gopvalue", ...)

R/deprogs.R                      (MODIFIED — per-plot widget)
  cutOffSelectionUI(id)          -> numericInput + preset bar (namespaced)
  cutOffSelectionServer(id)      -> NEW; wires preset <-> numeric sync
  applyFiltersNew(input, ...)    -> reads input$log2fc_cutoff,
                                    converts via log2fc_to_fold()

R/mainScatter.R                  (MODIFIED — hardcoded fallback)
  prepDataForQA()                -> reads default_cutoffs() instead of literals

R/utils_validate.R               (MODIFIED — input collection)
  collect_run_inputs()           -> renames fold_cutoff field
                                    reads input$log2fc_cutoff

R/server.R                       (MODIFIED — registers new server)
  cutOffSelectionUI(...)         -> + cutOffSelectionServer(same id)

R/fct_prep_data.R                (UNCHANGED — params$fold_cutoff stays
                                  fold-change-numeric; conversion happens
                                  upstream in collect_run_inputs)
```

## Helper module API

```r
# R/fct_cutoffs.R

#' Default DE significance cutoffs.
#'
#' Single source of truth for the values that populate cutoff
#' inputs and the prepDataForQA() fallback.
#'
#' @return Named list: padj, log2fc, gopvalue.
#' @export
default_cutoffs <- function() {
  list(padj = 0.01, log2fc = 1, gopvalue = 0.01)
}

#' Cutoff preset table.
#'
#' Each row defines a one-click preset. log2fc is shared across
#' presets by design — only padj differs.
#'
#' @return data.frame with columns: name, label, padj, log2fc.
#' @export
cutoff_presets <- function() {
  data.frame(
    name   = c("strict", "standard"),
    label  = c("Strict (0.01)", "Standard (0.05)"),
    padj   = c(0.01, 0.05),
    log2fc = c(1,    1),
    stringsAsFactors = FALSE
  )
}

#' Identify which preset a (padj, log2fc) pair matches, if any.
#'
#' @return single character ("strict"|"standard") or NA_character_.
#' @export
match_preset <- function(padj, log2fc, tol = 1e-9) {
  if (!is_finite_scalar(padj) || !is_finite_scalar(log2fc)) {
    return(NA_character_)
  }
  presets <- cutoff_presets()
  hit <- which(
    abs(presets$padj   - padj)   < tol &
    abs(presets$log2fc - log2fc) < tol
  )
  if (length(hit) == 1L) presets$name[hit] else NA_character_
}

#' Convert |log2FC| cutoff to fold-change cutoff.
#' @export
log2fc_to_fold <- function(x) 2^x

#' Convert fold-change cutoff to |log2FC|.
#' @export
fold_to_log2fc <- function(x) log2(x)

# Internal predicate: length-1, finite, non-NA numeric.
is_finite_scalar <- function(x) {
  is.numeric(x) && length(x) == 1L && is.finite(x)
}
```

**Decisions baked in:**
- `default_cutoffs()` returns a *list* — easier to extend later (e.g., `lfc_shrinkage_alpha`).
- `cutoff_presets()` returns a data frame so the UI iterates over rows declaratively.
- `match_preset()` uses a tolerance because `numericInput` round-trips floats via JSON; strict equality occasionally fails on `0.01 == 0.01`.
- `log2fc_to_fold` / `fold_to_log2fc` are tiny but named — makes conversion sites self-documenting.
- `is_finite_scalar` is private; same predicate as `is_nonblank` in `R/fct_condselect.R` but for numerics. Intentional small duplication over coupling unrelated modules.

## UI rewiring

### Global cutoff widget — `R/uifuncs.R:227-237`

```r
bslib::accordion_panel(
  " Filter",
  shinyWidgets::radioGroupButtons(
    "cutoff_preset",
    label    = NULL,
    choices  = setNames(cutoff_presets()$name, cutoff_presets()$label),
    selected = "strict",
    size     = "sm",
    justified = TRUE
  ),
  numericInput("padj",
    label = "padj ≤",
    value = default_cutoffs()$padj,
    min = 0, max = 1, step = 0.01
  ),
  numericInput("log2fc_cutoff",
    label = "|log2FC| ≥",
    value = default_cutoffs()$log2fc,
    min = 0, step = 0.5
  ),
  compselect
)
```

### Per-plot cutoff widget — `R/deprogs.R:86-93`

`cutOffSelectionUI(id)` gets the same three-element layout (preset bar + two numeric inputs) but namespaced via `ns()`. New server-side companion `cutOffSelectionServer(id)` wires the preset → numeric sync and manual-edit-clears-preset behavior, and is called from `R/server.R` wherever `cutOffSelectionUI` is rendered.

### Preset sync observers (server-side, both global and namespaced)

```r
# Preset click -> fill numeric inputs
observeEvent(input$cutoff_preset, ignoreInit = TRUE, {
  preset <- cutoff_presets()
  row <- preset[preset$name == input$cutoff_preset, ]
  updateNumericInput(session, "padj",          value = row$padj)
  updateNumericInput(session, "log2fc_cutoff", value = row$log2fc)
})

# Manual edit -> clear preset highlight if values no longer match a preset
observeEvent(c(input$padj, input$log2fc_cutoff), ignoreInit = TRUE, {
  matched <- match_preset(input$padj, input$log2fc_cutoff)
  current <- isolate(input$cutoff_preset)
  desired <- if (is.na(matched)) character(0) else matched
  if (!identical(current, desired)) {
    updateRadioGroupButtons(session, "cutoff_preset", selected = desired)
  }
})
```

The `isolate(input$cutoff_preset)` guard + `!identical(current, desired)` check prevents the two observers from firing each other in a loop. `ignoreInit = TRUE` on both stops the page-load click cascade.

### gopvalue upgrade — `R/uifuncs.R:112`

```r
numericInput("gopvalue",
  label = "p.adjust ≤",
  value = default_cutoffs()$gopvalue,
  min = 0, max = 1, step = 0.01
)
```

No preset bar.

### prepDataForQA fallback — `R/mainScatter.R:412-413`

```r
defaults <- default_cutoffs()
padj_cutoff       <- defaults$padj
foldChange_cutoff <- log2fc_to_fold(defaults$log2fc)
```

### Reader migration

| File | Line | Before | After |
|---|---|---|---|
| `R/utils_validate.R` | 88-89 | `padj_cutoff = input$padj, fold_cutoff = input$foldChange` | `padj_cutoff = input$padj, fold_cutoff = log2fc_to_fold(input$log2fc_cutoff)` |
| `R/deprogs.R` | 113-114 | `as.numeric(input$foldChange)` | `log2fc_to_fold(input$log2fc_cutoff)` |

`R/fct_prep_data.R` is unchanged — its `params$fold_cutoff` semantics remain fold-change-numeric.

### `cutOffSelectionUI` callsite registration — `R/server.R:294`

Single callsite at `server.R:294`:

```r
output$cutOffUI <- renderUI({
  cutOffSelectionUI(paste0("DEResults", compsel()))
})
```

The new server registration must be co-located. Because the id is dynamic (`compsel()` reactive), the server registration belongs in an `observeEvent(compsel(), ...)` that calls `cutOffSelectionServer(paste0("DEResults", compsel()))` whenever `compsel()` changes. Implementation detail to verify during plan execution: `moduleServer` registration is idempotent for the same id but creates duplicate observers across different ids — track active ids to deregister stale ones, or rely on Shiny's session-scoped GC.

## Acceptance criteria

1. `R CMD check` 0E/0W/0N (parity with B2.5 baseline at HEAD `4832d8b`).
2. `devtools::test()` passes; new `tests/testthat/test-cutoffs.R` contributes ≥ 15 tests.
3. Manual smoke checklist:
   - **Global widget:** Sidebar shows `[ Strict ] [ Standard ]` button bar with Strict pre-selected; numeric inputs read `0.01` / `1`; clicking Standard fills `0.05` / `1`; manually changing padj to `0.025` clears the preset highlight; clicking Strict re-fills.
   - **Per-plot widget:** Same behavior inside the DE Results plot module.
   - **DE end-to-end:** Vernia demo → load → filter → batch → condselect → DE. Volcano colors Up/Down/NS using the new cutoff inputs.
   - **gopvalue:** GO term tab accepts `numericInput` instead of `textInput`; typing `abc` triggers Shiny's native validation rather than a downstream NaN.
   - **prepDataForQA fallback:** With no user input present, the QA legend uses padj=0.01 / fc=2.
4. No `input$foldChange` references remain anywhere outside of comments/NEWS.
5. No observer loop on global or namespaced widget when toggling preset and editing numerics rapidly (verified manually).

## Test scope (per Q10)

**`tests/testthat/test-cutoffs.R` (NEW, ~15 tests)**

- `default_cutoffs()` returns three named numerics with values matching spec (`0.01, 1, 0.01`).
- `cutoff_presets()` returns 2 rows; both have `log2fc == 1`; `padj` is `0.01` and `0.05`; `name` is `c("strict","standard")`.
- `match_preset()`:
  - exact-match cases for both presets
  - tolerance case (`0.01 + 1e-12` still matches strict)
  - non-match → `NA_character_`
  - `NA` / `NULL` / `NaN` / `Inf` / length-2 vector inputs → `NA_character_` (5 separate guards)
- `log2fc_to_fold` / `fold_to_log2fc` round-trip: `fold_to_log2fc(log2fc_to_fold(1.5))` ≈ 1.5; identity at `log2fc=1 ↔ fc=2`.

**`tests/testthat/test-prepdata-units.R` (UPDATED)**

If existing tests construct `params$fold_cutoff` directly, they continue to use fold-change semantics — no test change needed there. Add one test exercising the conversion path: build a `list(padj_cutoff = 0.01, fold_cutoff = log2fc_to_fold(1))` and verify `apply_de_filters` results match the existing `fold_cutoff = 2` test.

No UI tests; no shinytest2 baseline regen.

## Migration & backwards compat

- **No bookmarking** is wired (verified via `grep "enableBookmarking" R/` — appears only in roxygen `@importFrom`). Renaming `input$foldChange` → `input$log2fc_cutoff` does not break persisted state.
- **NEWS.md** entry for B3:
  - "Switched DE cutoff input from fold-change to |log2FC| convention."
  - "Added Strict / Standard preset buttons; Strict (padj 0.01, |log2FC| 1) is the default."
  - "Cutoff inputs are now `numericInput` with bounds + native validation."
  - "Hardcoded cutoffs in `prepDataForQA()` now read from `default_cutoffs()`."
- **No deprecation shim** for `input$foldChange` — internal-only Shiny input, not part of the public R API. `cutOffSelectionUI`/`cutOffSelectionServer` are exported but the input names inside them are implementation detail.

## Files in scope

- `R/fct_cutoffs.R` (new)
- `R/uifuncs.R` (modify lines ~112, 232-233; add preset bar)
- `R/deprogs.R` (modify lines 86-93, 113-114; add `cutOffSelectionServer`)
- `R/mainScatter.R` (modify lines 412-413)
- `R/utils_validate.R` (modify lines 88-89)
- `R/server.R` (call `cutOffSelectionServer(id)` co-located with `cutOffSelectionUI(id)` at line 294)
- `NAMESPACE` (regenerate — exports `default_cutoffs`, `cutoff_presets`, `match_preset`, `log2fc_to_fold`, `fold_to_log2fc`, `cutOffSelectionServer`)
- `man/*.Rd` (regenerate)
- `NEWS.md` (B3 entry)
- `tests/testthat/test-cutoffs.R` (new)
- `tests/testthat/test-prepdata-units.R` (one added test)

## Risks / known unknowns

- **`cutOffSelectionServer` is new.** Per-plot preset wiring needs registration at the single callsite. The id is dynamic via `compsel()`, so registration must happen inside an `observeEvent(compsel(), ...)` or equivalent. Watch for stale module instances accumulating across `compsel()` changes.
- **Observer loop risk.** Two observers (preset → numerics, numerics → preset) are guarded with `ignoreInit + !identical` but should get explicit manual verification after implementation. Worst-case mitigation: gate the numeric-edit observer with `req(!is.null(input$cutoff_preset))` plus a 250ms `debounce`.
- **Unused code surface.** `cutOffSelectionUI` is rendered at one site (`R/server.R:294`); confirmed via grep. No dead callsites to absorb.

## Out of scope (explicit)

- Method default (DESeq2 + LRT) — original B3 item, deferred. Touches DE call paths.
- Low-count filter default (rowSums ≥ 10) — original B3 item, deferred. Touches `R/lowcountfilter.R` which is its own module.
- LFC shrinkage default (apeglm) — original B3 item, deferred. Per-method behavior.
- Batch correction auto-prompt — original B3 item, deferred. Coupled to wizard (B2b) flow.
- Covariate selector auto-hide — original B3 item, deferred. Coupled to condSelect (B2.5) and wizard.
- shinytest2 baseline regeneration — out of scope; B2c's baselines are still pending review per `phase_b2c_handoff.md`.

## Plan order

Single sub-plan; this spec maps directly to one implementation plan written next via the `superpowers:writing-plans` skill. Suggested commit boundaries:

1. New helper module + tests (`R/fct_cutoffs.R`, `tests/testthat/test-cutoffs.R`)
2. `prepDataForQA()` fallback migration (`R/mainScatter.R`)
3. `utils_validate.R` reader migration
4. `R/deprogs.R` namespaced widget + `cutOffSelectionServer`
5. `R/uifuncs.R` global widget + preset bar
6. `R/server.R` server registration at the dynamic callsite
7. NAMESPACE / man / NEWS regeneration
