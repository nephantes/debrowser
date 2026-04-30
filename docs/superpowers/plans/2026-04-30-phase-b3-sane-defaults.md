# Phase B3 — Sane defaults harmonization + cutoff widget redesign

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Harmonize DE significance cutoff defaults behind a pure `R/fct_cutoffs.R` helper, replace four `textInput` widgets with `numericInput`, add a Strict/Standard preset bar above the DE cutoffs, and switch the UI from fold-change to |log2FC| convention.

**Architecture:** New helper module owns default values, preset definitions, and unit conversion. UI sites (global sidebar widget in `R/uifuncs.R`, namespaced per-plot widget in `R/deprogs.R`, GO term `gopvalue`, hardcoded fallback in `R/mainScatter.R`) read from helper. Reader sites (`R/utils_validate.R`, `R/deprogs.R::applyFiltersNew`) convert log2FC → fold-change at one boundary. Internal pipeline (`R/fct_prep_data.R`) keeps fold-change semantics — unchanged.

**Tech Stack:** R / Shiny / `shinyWidgets::radioGroupButtons` / `bslib` / testthat / roxygen2

**Spec:** [docs/superpowers/specs/2026-04-30-phase-b3-sane-defaults-design.md](../specs/2026-04-30-phase-b3-sane-defaults-design.md)

**Branch:** `modernize` (continuing from B2.5 head `4832d8b`).

---

## Pre-flight

- [ ] **Step 0.1: Confirm working tree is clean for B3 work**

Run: `git status --short`
Expected: only untracked files in `docs/superpowers/` (B3 spec, prior plans). No `M` lines on `R/`. If R sources show modifications, stop and reconcile before proceeding.

- [ ] **Step 0.2: Verify baseline tests pass**

Run: `Rscript -e 'devtools::test()'`
Expected: `[ FAIL 0 | WARN 0 | SKIP 1 | PASS 213 ]` (B2.5 baseline). The 1 SKIP is the shinytest2 file. If failures appear, stop — fix before proceeding.

- [ ] **Step 0.3: Verify R CMD check baseline**

Run: `Rscript -e 'devtools::check(args = c("--no-manual", "--as-cran"), error_on = "warning")' 2>&1 | tail -30`
Expected: `0 errors | 0 warnings | 0 notes`. If pre-existing warnings/notes appear that didn't exist at B2.5, stop.

---

## Task 1: Pure helpers in `R/fct_cutoffs.R` + tests

**Files:**
- Create: `R/fct_cutoffs.R`
- Test: `tests/testthat/test-cutoffs.R`

This task introduces only pure R functions (no Shiny dependency). All five exports plus one private helper.

- [ ] **Step 1.1: Write failing test file**

Create `tests/testthat/test-cutoffs.R`:

```r
test_that("default_cutoffs returns named list with expected values", {
  d <- default_cutoffs()
  expect_type(d, "list")
  expect_named(d, c("padj", "log2fc", "gopvalue"))
  expect_equal(d$padj, 0.01)
  expect_equal(d$log2fc, 1)
  expect_equal(d$gopvalue, 0.01)
})

test_that("cutoff_presets returns a 2-row data frame with expected schema", {
  p <- cutoff_presets()
  expect_s3_class(p, "data.frame")
  expect_equal(nrow(p), 2L)
  expect_named(p, c("name", "label", "padj", "log2fc"))
  expect_equal(p$name, c("strict", "standard"))
  expect_equal(p$padj, c(0.01, 0.05))
  expect_true(all(p$log2fc == 1))
  expect_match(p$label[1], "Strict")
  expect_match(p$label[2], "Standard")
})

test_that("match_preset returns the strict preset name on exact match", {
  expect_identical(match_preset(0.01, 1), "strict")
})

test_that("match_preset returns the standard preset name on exact match", {
  expect_identical(match_preset(0.05, 1), "standard")
})

test_that("match_preset accepts a small tolerance around preset values", {
  expect_identical(match_preset(0.01 + 1e-12, 1 - 1e-12), "strict")
})

test_that("match_preset returns NA_character_ when the pair matches no preset", {
  expect_identical(match_preset(0.025, 1), NA_character_)
  expect_identical(match_preset(0.01, 0.5), NA_character_)
})

test_that("match_preset returns NA_character_ for NA inputs", {
  expect_identical(match_preset(NA_real_, 1), NA_character_)
  expect_identical(match_preset(0.01, NA_real_), NA_character_)
})

test_that("match_preset returns NA_character_ for NULL inputs", {
  expect_identical(match_preset(NULL, 1), NA_character_)
  expect_identical(match_preset(0.01, NULL), NA_character_)
})

test_that("match_preset returns NA_character_ for non-finite inputs", {
  expect_identical(match_preset(NaN, 1), NA_character_)
  expect_identical(match_preset(Inf, 1), NA_character_)
})

test_that("match_preset returns NA_character_ for length>1 inputs", {
  expect_identical(match_preset(c(0.01, 0.05), 1), NA_character_)
  expect_identical(match_preset(0.01, c(1, 2)), NA_character_)
})

test_that("log2fc_to_fold inverts fold_to_log2fc", {
  expect_equal(log2fc_to_fold(fold_to_log2fc(1.5)), 1.5)
  expect_equal(log2fc_to_fold(fold_to_log2fc(2)),   2)
  expect_equal(log2fc_to_fold(fold_to_log2fc(8)),   8)
})

test_that("log2fc_to_fold maps 1 to 2 and 0 to 1", {
  expect_equal(log2fc_to_fold(1), 2)
  expect_equal(log2fc_to_fold(0), 1)
})

test_that("fold_to_log2fc maps 2 to 1 and 1 to 0", {
  expect_equal(fold_to_log2fc(2), 1)
  expect_equal(fold_to_log2fc(1), 0)
})
```

- [ ] **Step 1.2: Run test file to verify it fails**

Run: `Rscript -e 'devtools::test(filter = "cutoffs")'`
Expected: All 13 tests FAIL with errors of the form `could not find function "default_cutoffs"`.

- [ ] **Step 1.3: Create `R/fct_cutoffs.R` with pure helpers**

```r
#' Default DE significance cutoffs.
#'
#' Single source of truth for the values that populate the DE cutoff
#' inputs and the prepDataForQA() fallback.
#'
#' @return Named list with components: padj, log2fc, gopvalue.
#' @export
default_cutoffs <- function() {
  list(padj = 0.01, log2fc = 1, gopvalue = 0.01)
}

#' Cutoff preset table.
#'
#' Each row defines a one-click preset for the Strict / Standard
#' button bar. log2fc is shared across presets by design -- only
#' padj differs.
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

#' Identify which preset a (padj, log2fc) pair matches.
#'
#' Uses a small numeric tolerance because numericInput round-trips
#' floats via JSON and exact equality occasionally fails.
#'
#' @param padj,log2fc Numeric scalars from the cutoff inputs.
#' @param tol Match tolerance.
#' @return Character scalar ("strict" | "standard") or NA_character_
#'   if either input is invalid or no preset matches.
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
#' @param x Numeric |log2FC| cutoff.
#' @return Fold-change cutoff (2^x).
#' @export
log2fc_to_fold <- function(x) 2^x

#' Convert fold-change cutoff to |log2FC|.
#' @param x Numeric fold-change cutoff.
#' @return |log2FC| cutoff (log2(x)).
#' @export
fold_to_log2fc <- function(x) log2(x)

# Internal: length-1, finite, non-NA, numeric.
is_finite_scalar <- function(x) {
  is.numeric(x) && length(x) == 1L && is.finite(x)
}
```

- [ ] **Step 1.4: Run roxygen to update NAMESPACE + man pages**

Run: `Rscript -e 'devtools::document()'`
Expected: NAMESPACE gains `export(default_cutoffs)`, `export(cutoff_presets)`, `export(match_preset)`, `export(log2fc_to_fold)`, `export(fold_to_log2fc)`. New `man/*.Rd` files appear for the five exports.

- [ ] **Step 1.5: Run cutoffs tests to verify they pass**

Run: `Rscript -e 'devtools::test(filter = "cutoffs")'`
Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 13 ]`.

- [ ] **Step 1.6: Run full test suite to verify no regression**

Run: `Rscript -e 'devtools::test()' 2>&1 | tail -5`
Expected: `[ FAIL 0 | WARN 0 | SKIP 1 | PASS 226 ]` (213 baseline + 13 new).

- [ ] **Step 1.7: Commit**

```bash
git add R/fct_cutoffs.R tests/testthat/test-cutoffs.R NAMESPACE man/default_cutoffs.Rd man/cutoff_presets.Rd man/match_preset.Rd man/log2fc_to_fold.Rd man/fold_to_log2fc.Rd
git commit -m "$(cat <<'EOF'
feat(cutoffs): introduce R/fct_cutoffs.R helper module

Pure R helpers owning the single source of truth for DE significance
cutoff defaults (padj 0.01, |log2FC| 1, GO p.adjust 0.01), the
Strict/Standard preset table, and the log2FC <-> fold-change
conversion functions.

Replaces hardcoded literals scheduled for migration in subsequent
B3 tasks. Includes 13 unit tests covering default values, preset
schema, match_preset tolerance + invalid input guards, and round-trip
identity for the conversion helpers.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: Reactive helper `install_cutoff_preset_observers`

**Files:**
- Modify: `R/fct_cutoffs.R` (append)

This wires the preset-button <-> numeric-input synchronization. Used by both the global widget (in `deServer`) and the per-plot widget (in the new `cutOffSelectionServer`). Centralizing avoids duplicating the observer logic at two call sites.

- [ ] **Step 2.1: Append to `R/fct_cutoffs.R`**

```r
#' Install Shiny observers that synchronise a preset-button input
#' with the (padj, log2fc_cutoff) numeric inputs.
#'
#' Two observers are installed on the supplied session:
#' (1) a click on the `cutoff_preset` radio group fills the two
#'     numeric inputs with that preset's values;
#' (2) a manual edit on either numeric input clears the preset
#'     highlight if the resulting (padj, log2fc) pair no longer
#'     matches any preset (or selects the matching preset if it
#'     happens to match one exactly).
#'
#' The observers guard against echoing each other via an
#' `isolate()` + `!identical()` check on the current radio-group
#' selection. Both use `ignoreInit = TRUE` to avoid the page-load
#' click cascade.
#'
#' @param input,session A Shiny input/session pair (either the
#'   top-level session for the global widget, or a moduleServer
#'   session for the namespaced widget).
#' @return Invisible NULL; observers are installed as a side effect.
#' @export
install_cutoff_preset_observers <- function(input, session) {
  observeEvent(input$cutoff_preset, ignoreInit = TRUE, {
    presets <- cutoff_presets()
    row <- presets[presets$name == input$cutoff_preset, ]
    if (nrow(row) == 1L) {
      updateNumericInput(session, "padj",          value = row$padj)
      updateNumericInput(session, "log2fc_cutoff", value = row$log2fc)
    }
  })

  observeEvent(c(input$padj, input$log2fc_cutoff), ignoreInit = TRUE, {
    matched <- match_preset(input$padj, input$log2fc_cutoff)
    current <- isolate(input$cutoff_preset)
    desired <- if (is.na(matched)) character(0) else matched
    if (!identical(current, desired)) {
      shinyWidgets::updateRadioGroupButtons(
        session, "cutoff_preset", selected = desired
      )
    }
  })

  invisible(NULL)
}
```

- [ ] **Step 2.2: Add `updateNumericInput` to `deServer` `@importFrom shiny`**

Read [R/server.R:14-34](R/server.R#L14-L34) and verify whether `updateNumericInput` is already in the `@importFrom shiny` block. If not, edit `R/server.R` to add `updateNumericInput` to the alphabetised list (it should sort between `updateCheckboxInput` and `updateQueryString`).

If already present (look for the existing `updateTextInput` line — `updateNumericInput` is its peer), no change needed. The file currently has `updateTextInput` listed; add `updateNumericInput` next to it on line 24.

Replace this section in `R/server.R`:

```
#'             h4 img icon updateTabsetPanel updateTextInput  validate
```

with:

```
#'             h4 img icon updateNumericInput updateTabsetPanel updateTextInput  validate
```

- [ ] **Step 2.3: Run document() to refresh man + namespace**

Run: `Rscript -e 'devtools::document()'`
Expected: NAMESPACE gains `export(install_cutoff_preset_observers)`. New `man/install_cutoff_preset_observers.Rd`. NAMESPACE gains `importFrom(shiny,updateNumericInput)` if it wasn't already there.

- [ ] **Step 2.4: Verify package loads cleanly**

Run: `Rscript -e 'devtools::load_all(); cat("OK\n")'`
Expected: clean output ending in `OK`. No errors. Warnings about already-attached packages are fine.

- [ ] **Step 2.5: Commit**

```bash
git add R/fct_cutoffs.R R/server.R NAMESPACE man/install_cutoff_preset_observers.Rd
git commit -m "$(cat <<'EOF'
feat(cutoffs): add install_cutoff_preset_observers helper

Centralises the two observers that sync a [Strict / Standard]
radio-group button bar with the padj + log2fc_cutoff numeric
inputs. Used by both the global cutoff widget (Task 7) and the
per-plot cutOffSelectionServer (Task 6). Guards against
self-echoing via isolate() + !identical() on the current
selection.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: `prepDataForQA()` fallback migration

**Files:**
- Modify: `R/mainScatter.R:412-413`

`prepDataForQA()` builds a quick QA legend independent of user input, hardcoding the cutoffs. Migrate it to read from `default_cutoffs()` so the "fallback Up/Down classification" stays in sync with the user-facing default.

- [ ] **Step 3.1: Replace the hardcoded literals**

Edit `R/mainScatter.R`. Find:

```r
  rdata$padj[is.na(rdata$padj)] <- 1

  padj_cutoff <- 0.01
  foldChange_cutoff <- 2


  rdata$Legend <- "NS"
```

Replace with:

```r
  rdata$padj[is.na(rdata$padj)] <- 1

  defaults <- default_cutoffs()
  padj_cutoff       <- defaults$padj
  foldChange_cutoff <- log2fc_to_fold(defaults$log2fc)

  rdata$Legend <- "NS"
```

- [ ] **Step 3.2: Verify package loads cleanly**

Run: `Rscript -e 'devtools::load_all(); cat("OK\n")'`
Expected: `OK`. No errors.

- [ ] **Step 3.3: Run full test suite**

Run: `Rscript -e 'devtools::test()' 2>&1 | tail -5`
Expected: `[ FAIL 0 | WARN 0 | SKIP 1 | PASS 226 ]`. No regression.

- [ ] **Step 3.4: Commit**

```bash
git add R/mainScatter.R
git commit -m "$(cat <<'EOF'
refactor(mainScatter): read prepDataForQA defaults from helper

Replace hardcoded padj=0.01 / foldChange=2 in prepDataForQA() with
default_cutoffs() + log2fc_to_fold(). Keeps the QA legend in sync
with the user-facing default surface.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: GO `gopvalue` numericInput upgrade

**Files:**
- Modify: `R/uifuncs.R:112`

This is independent of the DE cutoff input rename. No preset bar — only a `textInput` → `numericInput` swap with bounds.

- [ ] **Step 4.1: Replace the textInput**

Edit `R/uifuncs.R`. Find:

```r
  bslib::accordion_panel(
    " Go Term Options",
    textInput("gopvalue", "p.adjust", value = "0.01"),
    getOrganismBox(),
```

Replace with:

```r
  bslib::accordion_panel(
    " Go Term Options",
    numericInput("gopvalue", "p.adjust <=",
      value = default_cutoffs()$gopvalue,
      min = 0, max = 1, step = 0.01
    ),
    getOrganismBox(),
```

- [ ] **Step 4.2: Verify all readers of `input$gopvalue` tolerate numeric**

Run: `grep -n "input\$gopvalue" R/*.R`
Expected: zero or more matches. For each match, verify the consumer either uses the value directly (no `as.numeric()` needed because it's already numeric) or calls `as.numeric()` (which is a no-op on numerics). No code changes required if both forms are present — `as.numeric(0.01)` is `0.01`.

- [ ] **Step 4.3: Verify package loads**

Run: `Rscript -e 'devtools::load_all(); cat("OK\n")'`
Expected: `OK`.

- [ ] **Step 4.4: Run full test suite**

Run: `Rscript -e 'devtools::test()' 2>&1 | tail -5`
Expected: `[ FAIL 0 | WARN 0 | SKIP 1 | PASS 226 ]`.

- [ ] **Step 4.5: Commit**

```bash
git add R/uifuncs.R
git commit -m "$(cat <<'EOF'
refactor(uifuncs): upgrade GO gopvalue textInput to numericInput

Replace plain textInput("gopvalue", ...) with numericInput bounded
to [0, 1] reading the default from default_cutoffs(). Closes the
'user types abc -> silent NaN downstream' foot-gun on the GO term
threshold without changing any DE-cutoff behaviour.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: Conversion-path unit test in `test-fct-prep-data.R`

**Files:**
- Modify: `tests/testthat/test-fct-prep-data.R`

Add a single test that verifies `apply_de_filters` with `fold_cutoff = log2fc_to_fold(1)` produces the same result as `fold_cutoff = 2`. This guards against silent breakage in subsequent reader migrations.

- [ ] **Step 5.1: Read the existing fold_cutoff test for context**

Run: `grep -n "fold_cutoff" tests/testthat/test-fct-prep-data.R`
Expected: at least one match around line 28-29 with `fold_cutoff = 2`. Note the test name and surrounding fixture so the new test can mirror it.

- [ ] **Step 5.2: Append a parity test at the end of the file**

Add to `tests/testthat/test-fct-prep-data.R`:

```r
test_that("apply_de_filters with fold_cutoff = log2fc_to_fold(1) matches fold_cutoff = 2", {
  filt_data <- data.frame(
    foldChange       = c(4, 0.25, 1, 1.5),
    padj             = c(0.001, 0.001, 0.5, 0.001),
    log2FoldChange   = c(2, -2, 0, log2(1.5)),
    pvalue           = c(0.001, 0.001, 0.5, 0.001),
    stat             = c(10, -10, 0, 5)
  )
  base <- list(padj_cutoff = 0.01, fold_cutoff = 2,
               norm_method = "none")
  via_log2fc <- list(padj_cutoff = 0.01,
                     fold_cutoff = log2fc_to_fold(1),
                     norm_method = "none")

  out_base <- apply_de_filters(filt_data, base)
  out_via  <- apply_de_filters(filt_data, via_log2fc)

  expect_equal(out_via$Legend, out_base$Legend)
})
```

- [ ] **Step 5.3: Run the new test**

Run: `Rscript -e 'devtools::test(filter = "fct-prep-data")'`
Expected: all tests pass, including the new one. Count should increase by 1.

- [ ] **Step 5.4: Commit**

```bash
git add tests/testthat/test-fct-prep-data.R
git commit -m "$(cat <<'EOF'
test(fct-prep-data): pin log2fc_to_fold conversion parity

Verify apply_de_filters returns identical Legend assignments when
fold_cutoff is built via log2fc_to_fold(1) versus the literal 2.
Guards the conversion boundary that subsequent reader migrations
will rely on.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: Namespaced path migration — `R/deprogs.R`

**Files:**
- Modify: `R/deprogs.R:86-93` (`cutOffSelectionUI`)
- Modify: `R/deprogs.R:113-114` (`applyFiltersNew`)
- Modify: `R/deprogs.R` (append `cutOffSelectionServer`)

These three changes must land together — a partial commit produces a broken namespaced widget.

- [ ] **Step 6.1: Rewrite `cutOffSelectionUI`**

Edit `R/deprogs.R`. Find:

```r
cutOffSelectionUI <- function(id) {
  ns <- NS(id)
  list(
    getLegendRadio(id),
    textInput(ns("padj"), "padj value cut off", value = "0.01"),
    textInput(ns("foldChange"), "or foldChange", value = "2")
  )
}
```

Replace with:

```r
cutOffSelectionUI <- function(id) {
  ns <- NS(id)
  list(
    getLegendRadio(id),
    shinyWidgets::radioGroupButtons(
      ns("cutoff_preset"),
      label    = NULL,
      choices  = setNames(cutoff_presets()$name, cutoff_presets()$label),
      selected = "strict",
      size     = "sm",
      justified = TRUE
    ),
    numericInput(ns("padj"), "padj <=",
      value = default_cutoffs()$padj,
      min = 0, max = 1, step = 0.01
    ),
    numericInput(ns("log2fc_cutoff"), "|log2FC| >=",
      value = default_cutoffs()$log2fc,
      min = 0, step = 0.5
    )
  )
}
```

- [ ] **Step 6.2: Rewrite `applyFiltersNew` reader**

Edit `R/deprogs.R`. Find:

```r
applyFiltersNew <- function(data = NULL, input = NULL) {
  if (is.null(data)) {
    return(NULL)
  }
  padj_cutoff <- as.numeric(input$padj)
  foldChange_cutoff <- as.numeric(input$foldChange)
```

Replace with:

```r
applyFiltersNew <- function(data = NULL, input = NULL) {
  if (is.null(data)) {
    return(NULL)
  }
  padj_cutoff <- as.numeric(input$padj)
  foldChange_cutoff <- log2fc_to_fold(as.numeric(input$log2fc_cutoff))
```

- [ ] **Step 6.3: Append `cutOffSelectionServer` at the end of `R/deprogs.R`**

Add immediately after the closing brace of `applyFiltersNew` (before `runDE`):

```r
#' cutOffSelectionServer
#'
#' Server-side companion for cutOffSelectionUI. Wires the preset
#' radio-group buttons to the namespaced numeric inputs via
#' install_cutoff_preset_observers.
#'
#' @param id Module id (matches cutOffSelectionUI(id)).
#' @return Invisible NULL.
#'
#' @examples
#' if (FALSE) cutOffSelectionServer("DEResults1")
#'
#' @export
cutOffSelectionServer <- function(id) {
  moduleServer(id, function(input, output, session) {
    install_cutoff_preset_observers(input, session)
    invisible(NULL)
  })
}
```

- [ ] **Step 6.4: Run document() to refresh man/NAMESPACE**

Run: `Rscript -e 'devtools::document()'`
Expected: NAMESPACE gains `export(cutOffSelectionServer)`. New `man/cutOffSelectionServer.Rd`.

- [ ] **Step 6.5: Verify package loads**

Run: `Rscript -e 'devtools::load_all(); cat("OK\n")'`
Expected: `OK`.

- [ ] **Step 6.6: Run full test suite**

Run: `Rscript -e 'devtools::test()' 2>&1 | tail -5`
Expected: `[ FAIL 0 | WARN 0 | SKIP 1 | PASS 227 ]` (226 + 1 from Task 5).

- [ ] **Step 6.7: Commit**

```bash
git add R/deprogs.R NAMESPACE man/cutOffSelectionServer.Rd
git commit -m "$(cat <<'EOF'
feat(deprogs): rewrite cutOffSelectionUI as numericInput + presets

Atomic migration of the namespaced per-plot cutoff widget:
- cutOffSelectionUI(): textInput("foldChange") -> numericInput("log2fc_cutoff")
  + Strict/Standard radioGroupButtons preset bar
  + textInput("padj") -> numericInput("padj")
- applyFiltersNew(): reads input$log2fc_cutoff, converts to
  fold-change via log2fc_to_fold() before classifying Up/Down
- cutOffSelectionServer() (new): moduleServer that installs the
  preset <-> numeric sync observers via install_cutoff_preset_observers

Caller registration of cutOffSelectionServer at server.R:294 is
the next task.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: Global path migration — `R/uifuncs.R` + `R/utils_validate.R` + `R/server.R` deServer wiring

**Files:**
- Modify: `R/uifuncs.R:222-238` (`getCutOffSelection`)
- Modify: `R/utils_validate.R:86-99` (`filter_params_from_input`)
- Modify: `R/server.R` (deServer body — `install_cutoff_preset_observers` call)

These three must land together — partial commit produces a broken global widget.

- [ ] **Step 7.1: Rewrite `getCutOffSelection`**

Edit `R/uifuncs.R`. Find:

```r
getCutOffSelection <- function(nc = 1) {
  compselect <- getCompSelection("compselect", nc)
  list(conditionalPanel(
    (condition <- "input.dataset!='most-varied' &&
        input.methodtabs!='panel0'"),
    bslib::accordion(
      open = FALSE,
      bslib::accordion_panel(
        " Filter",
        # h4("Filter"),
        textInput("padj", "padj", value = "0.01"),
        textInput("foldChange", "foldChange", value = "2"),
        compselect
      )
    )
  ))
}
```

Replace with:

```r
getCutOffSelection <- function(nc = 1) {
  compselect <- getCompSelection("compselect", nc)
  list(conditionalPanel(
    (condition <- "input.dataset!='most-varied' &&
        input.methodtabs!='panel0'"),
    bslib::accordion(
      open = FALSE,
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
        numericInput("padj", "padj <=",
          value = default_cutoffs()$padj,
          min = 0, max = 1, step = 0.01
        ),
        numericInput("log2fc_cutoff", "|log2FC| >=",
          value = default_cutoffs()$log2fc,
          min = 0, step = 0.5
        ),
        compselect
      )
    )
  ))
}
```

- [ ] **Step 7.2: Rewrite `filter_params_from_input`**

Edit `R/utils_validate.R`. Find:

```r
filter_params_from_input <- function(input) {
  list(
    padj_cutoff   = input$padj,
    fold_cutoff   = input$foldChange,
    dataset       = input$dataset,
```

Replace with:

```r
filter_params_from_input <- function(input) {
  list(
    padj_cutoff   = input$padj,
    fold_cutoff   = log2fc_to_fold(as.numeric(input$log2fc_cutoff)),
    dataset       = input$dataset,
```

- [ ] **Step 7.3: Install global preset observers in `deServer`**

Edit `R/server.R`. Find the `output$cutOffUI <- renderUI({` block (around line 293). Insert the observer install **immediately before** that block, inside the `moduleServer` body of `deServer` so `input` and `session` are in scope:

```r
        install_cutoff_preset_observers(input, session)

        output$cutOffUI <- renderUI({
          cutOffSelectionUI(paste0("DEResults", compsel()))
        })
```

Verify with: `grep -n "install_cutoff_preset_observers(input, session)" R/server.R`
Expected: exactly one match.

- [ ] **Step 7.4: Verify package loads**

Run: `Rscript -e 'devtools::load_all(); cat("OK\n")'`
Expected: `OK`.

- [ ] **Step 7.5: Run full test suite**

Run: `Rscript -e 'devtools::test()' 2>&1 | tail -5`
Expected: `[ FAIL 0 | WARN 0 | SKIP 1 | PASS 227 ]`. No regression — these changes affect runtime UI/observers, not pure-function tests.

- [ ] **Step 7.6: Verify no `input$foldChange` references remain**

Run: `grep -rn 'input\$foldChange\b' R/`
Expected: zero matches. All call sites have been migrated.

- [ ] **Step 7.7: Commit**

```bash
git add R/uifuncs.R R/utils_validate.R R/server.R
git commit -m "$(cat <<'EOF'
feat(cutoffs): migrate global cutoff path to log2FC + presets

Atomic migration of the global sidebar cutoff widget:
- getCutOffSelection(): textInput("foldChange") -> numericInput("log2fc_cutoff")
  + Strict/Standard radioGroupButtons preset bar
  + textInput("padj") -> numericInput("padj")
- filter_params_from_input(): reads input$log2fc_cutoff, converts
  to fold-change via log2fc_to_fold() so apply_de_filters keeps
  receiving fold-change semantics it expects
- deServer: install_cutoff_preset_observers(input, session) wires
  the preset <-> numeric synchronisation at the top-level session

input$foldChange is fully retired from R/ sources.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 8: Register `cutOffSelectionServer` at the dynamic callsite

**Files:**
- Modify: `R/server.R` (around line 293)

`cutOffSelectionUI(paste0("DEResults", compsel()))` is rendered by `renderUI` and re-fires whenever `compsel()` changes. The corresponding server registration must be co-located. To avoid registering duplicate observers when `compsel()` flips back to a previously-seen value, track registered ids in a `reactiveValues` registry.

- [ ] **Step 8.1: Add the registry + observer near `output$cutOffUI`**

Edit `R/server.R`. Find:

```r
        install_cutoff_preset_observers(input, session)

        output$cutOffUI <- renderUI({
          cutOffSelectionUI(paste0("DEResults", compsel()))
        })
```

Replace with:

```r
        install_cutoff_preset_observers(input, session)

        cutoff_servers_registered <- reactiveValues()
        output$cutOffUI <- renderUI({
          cutOffSelectionUI(paste0("DEResults", compsel()))
        })
        observeEvent(compsel(), {
          id <- paste0("DEResults", compsel())
          if (is.null(cutoff_servers_registered[[id]])) {
            cutOffSelectionServer(id)
            cutoff_servers_registered[[id]] <- TRUE
          }
        }, ignoreNULL = TRUE)
```

The `reactiveValues` registry guards against duplicate `moduleServer` registration when `compsel()` cycles. First time an id is seen, register; subsequent times, skip.

- [ ] **Step 8.2: Verify package loads**

Run: `Rscript -e 'devtools::load_all(); cat("OK\n")'`
Expected: `OK`.

- [ ] **Step 8.3: Run full test suite**

Run: `Rscript -e 'devtools::test()' 2>&1 | tail -5`
Expected: `[ FAIL 0 | WARN 0 | SKIP 1 | PASS 227 ]`. Unchanged.

- [ ] **Step 8.4: Commit**

```bash
git add R/server.R
git commit -m "$(cat <<'EOF'
feat(server): register cutOffSelectionServer at dynamic callsite

Co-locate cutOffSelectionServer(id) registration with the
cutOffSelectionUI(id) renderUI at server.R:293-area. Track
registered ids in a reactiveValues registry to guard against
duplicate moduleServer instances when compsel() cycles back to
a previously-seen value.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 9: NEWS entry + final R CMD check

**Files:**
- Modify: `NEWS.md`

- [ ] **Step 9.1: Add B3 entry to top of `NEWS.md`**

Read the existing top of `NEWS.md` (Run: `Rscript -e 'cat(readLines("NEWS.md", n = 30), sep = "\n")'`), confirm the most-recent entry is the B2.5 entry, then prepend a new B3 entry above it.

Insert the following block at the top of `NEWS.md` (after the package title line if there is one, before the B2.5 entry otherwise):

```markdown
## Changes in version <NEXT_VERSION>

### Phase B3 — Sane defaults harmonization

- Switched DE cutoff input from fold-change to |log2FC| convention.
  The cutoff numeric inputs are now labelled `padj <=` and `|log2FC| >=`.
- Added `[ Strict ] [ Standard ]` preset buttons above the DE cutoff
  inputs. Strict (padj 0.01, |log2FC| 1) is the default; Standard is
  (padj 0.05, |log2FC| 1). Manual edits clear the preset highlight
  unless the new pair matches a preset exactly.
- Cutoff inputs (DE padj, DE |log2FC|, GO p.adjust) are now
  `numericInput` with bounds + native validation, replacing
  `textInput` widgets that silently produced NaN downstream when
  users typed non-numeric values.
- New helper module `R/fct_cutoffs.R` owns the single source of
  truth for default values and preset definitions:
  `default_cutoffs()`, `cutoff_presets()`, `match_preset()`,
  `log2fc_to_fold()`, `fold_to_log2fc()`,
  `install_cutoff_preset_observers()`. The hardcoded fallback in
  `prepDataForQA()` now reads from `default_cutoffs()`.
- Internal-only Shiny input rename: `input$foldChange` -> `input$log2fc_cutoff`.
  Public `cutOffSelectionUI` API is unchanged; new exported
  companion `cutOffSelectionServer(id)` wires preset observers
  for the namespaced widget.
```

(Replace `<NEXT_VERSION>` with the appropriate version bump per the project's NEWS convention — read the existing entries to match the format.)

- [ ] **Step 9.2: Run R CMD check**

Run: `Rscript -e 'devtools::check(args = c("--no-manual", "--as-cran"), error_on = "warning")' 2>&1 | tail -30`
Expected: `0 errors | 0 warnings | 0 notes` (parity with B2.5 baseline).

- [ ] **Step 9.3: Run full test suite a final time**

Run: `Rscript -e 'devtools::test()' 2>&1 | tail -5`
Expected: `[ FAIL 0 | WARN 0 | SKIP 1 | PASS 227 ]`.

- [ ] **Step 9.4: Verify the rename invariant one more time**

Run: `grep -rn 'input\$foldChange\b\|"foldChange"' R/ --include="*.R"`
Expected: only matches inside data-frame column-name contexts (e.g., `m$foldChange`, `colnames(rdata) <- c(... "foldChange" ...)`) which are internal data-shape labels, not Shiny inputs. No `input$foldChange` reads should remain.

- [ ] **Step 9.5: Commit**

```bash
git add NEWS.md
git commit -m "$(cat <<'EOF'
docs(NEWS): add Phase B3 sane defaults entry

Document the cutoff widget redesign, log2FC convention switch,
Strict/Standard preset buttons, fct_cutoffs.R helper module, and
input$foldChange -> input$log2fc_cutoff rename.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Manual smoke test (post-merge gate)

These steps cannot be automated cheaply (no shinytest2 baseline regen in scope) and must be run by a human after the implementation lands but before the branch is considered B3-complete.

- [ ] **Smoke 1: Global widget — Strict default and preset toggle**

Run: `Rscript -e 'devtools::load_all(); debrowser::startDEBrowser()'`. In the sidebar `Filter` accordion: confirm `[ Strict ] [ Standard ]` button bar with Strict pre-selected; numeric inputs read `0.01` and `1`. Click Standard → padj fills `0.05`, log2FC stays `1`. Click Strict → padj fills `0.01`. Manually change padj to `0.025` → preset highlight clears (neither Strict nor Standard appears active). Type `0.01` back → Strict re-highlights.

- [ ] **Smoke 2: Per-plot widget mirrors global behaviour**

Load Vernia demo → run DE through to volcano. In the DE Results plot module, locate the per-plot cutoff widget. Confirm same `[ Strict ] [ Standard ]` bar, same default values, same toggle/clear behaviour as Smoke 1.

- [ ] **Smoke 3: DE end-to-end**

Vernia demo → load → filter → batch → condselect → DE. Confirm volcano colours Up/Down/NS using the new cutoff inputs. Change global widget to Standard → volcano re-classifies (more genes Up/Down).

- [ ] **Smoke 4: gopvalue numericInput validation**

GO Term tab → `p.adjust <=` field. Type `abc` → Shiny native validation prevents the value from sticking (or shows a red border / blank). Type `0.05` → field accepts.

- [ ] **Smoke 5: prepDataForQA fallback**

Trigger any view that calls `prepDataForQA()` (typically the QA scatter on first load before user-driven cutoffs). Confirm the legend behaves consistent with `padj=0.01, fc=2` (the default).

- [ ] **Smoke 6: No observer loop**

In the global widget, rapidly click Strict, Standard, Strict, Standard 5+ times. Then rapidly edit padj to `0.02`, `0.05`, `0.01`, `0.025`. Confirm UI remains responsive — no infinite-update loop, no browser freeze, no console spam (open browser dev tools).

If any smoke fails, log it as a B3 regression and fix before merge. If a fix requires more than a one-line change, branch a B3.x sub-task on the same plan.

---

## Self-review checklist (run before declaring plan ready)

**1. Spec coverage:**
- ☑ Architecture (spec §Architecture) → Tasks 1, 2, 3, 4, 6, 7, 8
- ☑ Helper API (spec §Helper module API) → Task 1
- ☑ Observer wiring (spec §Preset sync observers) → Task 2
- ☑ UI rewiring global (spec §Global cutoff widget) → Task 7
- ☑ UI rewiring namespaced (spec §Per-plot cutoff widget) → Task 6
- ☑ gopvalue (spec §gopvalue upgrade) → Task 4
- ☑ prepDataForQA fallback → Task 3
- ☑ Reader migration table → Tasks 6 + 7
- ☑ server.R registration → Task 8
- ☑ NEWS entry → Task 9
- ☑ Tests (15 helper + 1 conversion-path) → Tasks 1 + 5
- ☑ Acceptance criteria → Task 9 R CMD check + Smoke 1-6

**2. Placeholder scan:** No "TBD", "TODO", "Add appropriate ...", "Similar to Task N" — all task code is concrete.

**3. Type consistency:**
- `default_cutoffs()` returns a list; readers use `$padj`, `$log2fc`, `$gopvalue` everywhere.
- `cutoff_presets()` returns a data frame with columns `name, label, padj, log2fc`; readers iterate over rows or filter by `name`.
- `log2fc_to_fold(x)` accepts numeric, returns numeric — no overloads.
- Input name `input$log2fc_cutoff` is consistent across UI (Tasks 6 + 7), readers (Tasks 6 + 7), and observer helper (Task 2).
- `install_cutoff_preset_observers(input, session)` signature is consistent across the two callers (Tasks 6 cutOffSelectionServer, Task 7 deServer).

**4. Atomicity check:** Tasks 6 and 7 are flagged as atomic — UI rename + reader rename ship in the same commit so the app is never broken between commits.
