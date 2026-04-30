# Phase B2.5 — `condSelect.R` Rewrite Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rewrite `R/condSelect.R` (≈900 LOC monolith) into three focused files (`R/fct_condselect.R`, `R/mod_condselect.R`, `R/prep_data_container.R`) implementing a single-comparison-default wizard with editable Treatment/Control labels, reference-word direction heuristic + swap, advanced model settings collapsed, inline non-toast validation, and a closed module boundary.

**Architecture:** Pure helpers (TDD-tested) → `prepDataContainer` rewrite (consumes structured `comparisons_spec`) → module UI/server (per-comparison card factory + accordion tail) → server.R call-site swap → delete legacy file + NAMESPACE/man cleanup. Internal `Cond1`/`Cond2` `conds` vector is unchanged so all downstream consumers (`fct_prep_data.R`, `fct_de_methods.R`, `barmain.R`, `deprogs.R`) need zero edits.

**Tech Stack:** R 4.x, Shiny modules (`moduleServer`), bslib (`accordion`, `accordion_panel`, `card`), shinyjs (`toggleState` — already in Imports), testthat 3.

**Spec:** [docs/superpowers/specs/2026-04-29-phase-b2-5-condselect-rewrite-design.md](../specs/2026-04-29-phase-b2-5-condselect-rewrite-design.md)

---

## File Structure

| File | Action | Role |
|---|---|---|
| `R/fct_condselect.R` | **Create** | Pure helpers: `infer_control_level`, `default_side_labels`, `halve_sample_names`, `compute_cond_names`, `build_demethod_params_string`, predicate functions, `validate_comparison` |
| `R/mod_condselect.R` | **Create** | `condSelectUI(id)`, `condSelectServer(id, data, metadata)`, internal `comparisonCardUI`, `comparisonCardServer` factory |
| `R/prep_data_container.R` | **Create** | `prepDataContainer(data, metadata, comparisons_spec)` extracted with new signature |
| `R/condSelect.R` | **Delete** | Replaced by the three files above |
| `R/server.R` | **Modify** | Lines 225-228, 239-242 (`debrowsercondselectServer` → `condSelectServer`); lines 247-265 (`prepDataContainer` call site) |
| `NAMESPACE` | **Modify (regen)** | Removes the helpers' exports; adds `condSelectUI`, `condSelectServer` |
| `man/*.Rd` | **Modify (regen)** | Old `man/get*.Rd` deleted; new `man/condSelectUI.Rd`, `man/condSelectServer.Rd`, `man/prepDataContainer.Rd` |
| `NEWS.md` | **Modify** | Add B2.5 entry |
| `tests/testthat/test-condselect-helpers.R` | **Create** | Pure helper tests |
| `tests/testthat/test-condselect-validation.R` | **Create** | Predicate tests |
| `tests/testthat/test-prepdatacontainer.R` | **Create** | `prepDataContainer` integration tests with synthetic specs |

---

## Pre-flight Verification

- [ ] **Pre-1: Verify clean baseline**

```bash
cd /Users/alper/workdir/debrowser
git status --porcelain
```
Expected: only the pre-existing roxygen-doc and `.Rbuildignore` modifications listed in the B2c handoff (unrelated, do **not** stage them in any task below).

- [ ] **Pre-2: Verify HEAD is the spec commit**

```bash
git log --oneline -1
```
Expected: `b3e8102 phase B2.5 spec: condSelect.R rewrite + Treatment/Control language` (or one or two later commits if other work intervened).

- [ ] **Pre-3: Snapshot current test count for regression baseline**

```bash
Rscript -e 'devtools::test()' 2>&1 | tail -10
```
Expected: `[ FAIL 0 | WARN 12 | SKIP 1 | PASS 126 ]` (B2c baseline).

---

## Task 1: `infer_control_level()` reference-word heuristic

**Files:**
- Create: `R/fct_condselect.R`
- Test: `tests/testthat/test-condselect-helpers.R`

- [ ] **Step 1: Write the failing test**

Create `tests/testthat/test-condselect-helpers.R` with:

```r
# tests/testthat/test-condselect-helpers.R

test_that("infer_control_level picks reference-shaped level", {
  expect_equal(infer_control_level(c("KO", "WT")), "WT")
  expect_equal(infer_control_level(c("Drug", "DMSO")), "DMSO")
  expect_equal(infer_control_level(c("Treated", "Control")), "Control")
  expect_equal(infer_control_level(c("ctrl", "test")), "ctrl")
  expect_equal(infer_control_level(c("vehicle", "compoundA")), "vehicle")
  expect_equal(infer_control_level(c("Day7", "Day0")), "Day0")
  expect_equal(infer_control_level(c("0h", "24h")), "0h")
})

test_that("infer_control_level falls back to alphabetical when no match", {
  expect_equal(infer_control_level(c("Tumor", "Normal")), "Normal")
  expect_equal(infer_control_level(c("Z", "A")), "A")
  expect_equal(infer_control_level(c("groupB", "groupA")), "groupA")
})

test_that("infer_control_level falls back to alphabetical when ambiguous", {
  # Both look like references — alphabetical wins.
  expect_equal(infer_control_level(c("control", "wt")), "control")
})

test_that("infer_control_level is anchored (avoids substring matches)", {
  # 'controllab' should NOT match 'control'.
  expect_equal(infer_control_level(c("controllab", "tester")), "controllab") # alphabetical
})

test_that("infer_control_level is case-insensitive", {
  expect_equal(infer_control_level(c("WILDTYPE", "MUTANT")), "WILDTYPE")
})
```

- [ ] **Step 2: Run test to verify it fails**

```bash
Rscript -e 'devtools::test(filter = "condselect-helpers")'
```
Expected: errors saying `could not find function "infer_control_level"`.

- [ ] **Step 3: Create `R/fct_condselect.R` with `infer_control_level()`**

```r
# R/fct_condselect.R
#
# Pure helpers for the comparison-selection wizard. No Shiny dependency.
# Tested in tests/testthat/test-condselect-helpers.R and
# tests/testthat/test-condselect-validation.R.

.CONTROL_REGEX <- paste0(
  "(?i)^(",
  paste(c(
    "control", "ctrl", "wt", "wildtype", "wild_type",
    "vehicle", "dmso", "untreated", "mock", "ref",
    "naive", "baseline", "0h", "day0"
  ), collapse = "|"),
  ")$"
)

#' Infer the control-side level for a 2-level metadata column.
#'
#' Matches each level (case-insensitive, anchored) against a small list of
#' reference-shaped words. If exactly one level matches, returns it. Otherwise
#' falls back to alphabetical order so the result is always deterministic.
#'
#' @param levels character vector of metadata-column levels (≥ 2 expected).
#' @return character(1) — the level chosen as control.
#' @noRd
infer_control_level <- function(levels) {
  matches <- grepl(.CONTROL_REGEX, levels, perl = TRUE)
  if (sum(matches) == 1) {
    return(levels[matches])
  }
  sort(levels)[1]
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
Rscript -e 'devtools::test(filter = "condselect-helpers")'
```
Expected: 5 test_that blocks, all PASS.

- [ ] **Step 5: Commit**

```bash
git add R/fct_condselect.R tests/testthat/test-condselect-helpers.R
git commit -m "phase B2.5.1: infer_control_level heuristic + tests"
```

---

## Task 2: `default_side_labels()`

**Files:**
- Modify: `R/fct_condselect.R` (append)
- Test: `tests/testthat/test-condselect-helpers.R` (append)

- [ ] **Step 1: Write the failing test**

Append to `tests/testthat/test-condselect-helpers.R`:

```r
test_that("default_side_labels uses level names when meta column is set", {
  result <- default_side_labels(meta_column = "Cell Type",
                                treatment_level = "KO",
                                control_level   = "WT")
  expect_equal(result, c(treatment = "KO", control = "WT"))
})

test_that("default_side_labels falls back to Treatment/Control when no meta", {
  result <- default_side_labels(meta_column = NA_character_,
                                treatment_level = NA_character_,
                                control_level   = NA_character_)
  expect_equal(result, c(treatment = "Treatment", control = "Control"))
})

test_that("default_side_labels handles partial NA gracefully", {
  # Defensive: if only one level is NA (shouldn't happen but be safe), fall back.
  result <- default_side_labels(meta_column = "Cell Type",
                                treatment_level = "KO",
                                control_level   = NA_character_)
  expect_equal(result, c(treatment = "Treatment", control = "Control"))
})
```

- [ ] **Step 2: Run test to verify it fails**

```bash
Rscript -e 'devtools::test(filter = "condselect-helpers")'
```
Expected: `could not find function "default_side_labels"`.

- [ ] **Step 3: Implement `default_side_labels()` in `R/fct_condselect.R`**

Append:

```r
#' Compute initial side labels for a comparison.
#'
#' Returns a named character(2) `c(treatment = ..., control = ...)`. When
#' a metadata column with two non-NA levels is supplied, the level names are
#' used directly. Otherwise falls back to the literal "Treatment" / "Control".
#'
#' @noRd
default_side_labels <- function(meta_column, treatment_level, control_level) {
  if (!is.na(meta_column) && !is.na(treatment_level) && !is.na(control_level)) {
    return(c(treatment = treatment_level, control = control_level))
  }
  c(treatment = "Treatment", control = "Control")
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
Rscript -e 'devtools::test(filter = "condselect-helpers")'
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add R/fct_condselect.R tests/testthat/test-condselect-helpers.R
git commit -m "phase B2.5.2: default_side_labels helper + tests"
```

---

## Task 3: `halve_sample_names()` (port `getSampleNames`)

**Files:**
- Modify: `R/fct_condselect.R` (append)
- Test: `tests/testthat/test-condselect-helpers.R` (append)

- [ ] **Step 1: Write the failing test**

Append:

```r
test_that("halve_sample_names splits sample list into two halves", {
  result <- halve_sample_names(c("s1", "s2", "s3", "s4", "s5", "s6"))
  expect_equal(result$treatment, c("s1", "s2", "s3"))
  expect_equal(result$control,   c("s4", "s5", "s6"))
})

test_that("halve_sample_names handles odd-count by giving control the extra", {
  # Today's getSampleNames floor()s the cut so part 1 gets the smaller half.
  # New behavior preserves that exactly.
  result <- halve_sample_names(c("s1", "s2", "s3", "s4", "s5"))
  expect_equal(result$treatment, c("s1", "s2"))
  expect_equal(result$control,   c("s3", "s4", "s5"))
})

test_that("halve_sample_names returns empty halves for empty input", {
  result <- halve_sample_names(character(0))
  expect_equal(result$treatment, character(0))
  expect_equal(result$control,   character(0))
})

test_that("halve_sample_names returns NULL on NULL input", {
  expect_null(halve_sample_names(NULL))
})
```

- [ ] **Step 2: Run test to verify it fails**

```bash
Rscript -e 'devtools::test(filter = "condselect-helpers")'
```
Expected: `could not find function "halve_sample_names"`.

- [ ] **Step 3: Implement `halve_sample_names()` in `R/fct_condselect.R`**

Append:

```r
#' Halve a sample-name vector into default treatment / control halves.
#'
#' Preserves the exact behavior of the legacy `getSampleNames(cnames, part)`:
#' the first half (length floor(n/2)) is assigned to treatment, the rest to
#' control.
#'
#' @param sample_names character vector of column names from the count matrix.
#' @return list with components `treatment` and `control`, or NULL on NULL input.
#' @noRd
halve_sample_names <- function(sample_names) {
  if (is.null(sample_names)) return(NULL)
  n <- length(sample_names)
  if (n == 0L) return(list(treatment = character(0), control = character(0)))
  cut <- floor(n / 2L)
  list(
    treatment = if (cut >= 1L) sample_names[seq_len(cut)] else character(0),
    control   = if (cut + 1L <= n) sample_names[(cut + 1L):n] else character(0)
  )
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
Rscript -e 'devtools::test(filter = "condselect-helpers")'
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add R/fct_condselect.R tests/testthat/test-condselect-helpers.R
git commit -m "phase B2.5.3: halve_sample_names helper + tests"
```

---

## Task 4: `compute_cond_names()`

**Files:**
- Modify: `R/fct_condselect.R` (append)
- Test: `tests/testthat/test-condselect-helpers.R` (append)

- [ ] **Step 1: Write the failing test**

Append:

```r
test_that("compute_cond_names extracts the two display labels in order", {
  spec <- list(treatment_label = "Drug 24h", control_label = "DMSO")
  expect_equal(compute_cond_names(spec), c("Drug 24h", "DMSO"))
})
```

- [ ] **Step 2: Run test to verify it fails**

```bash
Rscript -e 'devtools::test(filter = "condselect-helpers")'
```
Expected: `could not find function "compute_cond_names"`.

- [ ] **Step 3: Implement `compute_cond_names()` in `R/fct_condselect.R`**

Append:

```r
#' Extract the user-visible label vector from a comparison spec.
#'
#' This is the single source of truth that flows into `cond_names` for plot
#' legends, table column prefixes, etc.
#'
#' @noRd
compute_cond_names <- function(spec) {
  c(spec$treatment_label, spec$control_label)
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
Rscript -e 'devtools::test(filter = "condselect-helpers")'
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add R/fct_condselect.R tests/testthat/test-condselect-helpers.R
git commit -m "phase B2.5.4: compute_cond_names helper + tests"
```

---

## Task 5: `build_demethod_params_string()` — must reproduce today's exact format

This is the critical correctness step. The downstream `R/fct_de_methods.R` parses these strings positionally; one mismatch breaks DE entirely.

**Files:**
- Modify: `R/fct_condselect.R` (append)
- Test: `tests/testthat/test-condselect-helpers.R` (append)

- [ ] **Step 1: Write the failing test**

Append:

```r
test_that("build_demethod_params_string reproduces today's DESeq2 format", {
  s <- build_demethod_params_string(
    de_method = "DESeq2",
    method_params = list(
      fitType = "parametric", betaPrior = FALSE,
      testType = "LRT", shrinkage = "None"
    ),
    covariates = character(0)
  )
  expect_equal(s, "DESeq2,NoCovariate,parametric,FALSE,LRT,None")
})

test_that("build_demethod_params_string handles single covariate", {
  s <- build_demethod_params_string(
    de_method = "DESeq2",
    method_params = list(
      fitType = "parametric", betaPrior = FALSE,
      testType = "LRT", shrinkage = "None"
    ),
    covariates = "batch"
  )
  expect_equal(s, "DESeq2,batch,parametric,FALSE,LRT,None")
})

test_that("build_demethod_params_string handles multiple covariates with pipe sep", {
  s <- build_demethod_params_string(
    de_method = "DESeq2",
    method_params = list(
      fitType = "parametric", betaPrior = FALSE,
      testType = "LRT", shrinkage = "None"
    ),
    covariates = c("batch", "donor")
  )
  expect_equal(s, "DESeq2,batch|donor,parametric,FALSE,LRT,None")
})

test_that("build_demethod_params_string reproduces today's EdgeR format", {
  s <- build_demethod_params_string(
    de_method = "EdgeR",
    method_params = list(
      edgeR_normfact = "TMM", dispersion = "0", edgeR_testType = "exactTest"
    ),
    covariates = character(0)
  )
  expect_equal(s, "EdgeR,NoCovariate,TMM,0,exactTest")
})

test_that("build_demethod_params_string reproduces today's Limma format", {
  s <- build_demethod_params_string(
    de_method = "Limma",
    method_params = list(
      limma_normfact = "TMM", limma_fitType = "ls", normBetween = "none"
    ),
    covariates = character(0)
  )
  expect_equal(s, "Limma,NoCovariate,TMM,ls,none")
})
```

- [ ] **Step 2: Run test to verify it fails**

```bash
Rscript -e 'devtools::test(filter = "condselect-helpers")'
```
Expected: `could not find function "build_demethod_params_string"`.

- [ ] **Step 3: Implement `build_demethod_params_string()` in `R/fct_condselect.R`**

Append:

```r
#' Serialize a comparison's DE method + params + covariates into the comma-
#' separated string that `R/fct_de_methods.R` and `R/deprogs.R` parse
#' positionally. Reproduces the legacy `prepDataContainer` format byte-for-byte.
#'
#' Schema by method:
#'   DESeq2: "DESeq2,<covariate>,<fitType>,<betaPrior>,<testType>,<shrinkage>"
#'   EdgeR:  "EdgeR,<covariate>,<edgeR_normfact>,<dispersion>,<edgeR_testType>"
#'   Limma:  "Limma,<covariate>,<limma_normfact>,<limma_fitType>,<normBetween>"
#'
#' Where `<covariate>` is the pipe-joined covariate column names, or the
#' literal string "NoCovariate" when empty (legacy convention).
#'
#' @noRd
build_demethod_params_string <- function(de_method, method_params, covariates) {
  cov_str <- if (length(covariates) == 0L) {
    "NoCovariate"
  } else {
    paste(covariates, collapse = "|")
  }
  switch(de_method,
    "DESeq2" = paste(
      "DESeq2", cov_str,
      method_params$fitType, method_params$betaPrior,
      method_params$testType, method_params$shrinkage,
      sep = ","
    ),
    "EdgeR" = paste(
      "EdgeR", cov_str,
      method_params$edgeR_normfact, method_params$dispersion,
      method_params$edgeR_testType,
      sep = ","
    ),
    "Limma" = paste(
      "Limma", cov_str,
      method_params$limma_normfact, method_params$limma_fitType,
      method_params$normBetween,
      sep = ","
    ),
    stop("Unknown de_method: ", de_method)
  )
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
Rscript -e 'devtools::test(filter = "condselect-helpers")'
```
Expected: 13 test_that blocks across all helpers so far PASS.

- [ ] **Step 5: Commit**

```bash
git add R/fct_condselect.R tests/testthat/test-condselect-helpers.R
git commit -m "phase B2.5.5: build_demethod_params_string + tests"
```

---

## Task 6: Validation predicates — error-severity (sample sides + labels + meta)

**Files:**
- Modify: `R/fct_condselect.R` (append)
- Create: `tests/testthat/test-condselect-validation.R`

- [ ] **Step 1: Write the failing test**

Create `tests/testthat/test-condselect-validation.R`:

```r
# tests/testthat/test-condselect-validation.R

# Helper to build a baseline-valid manual-mode spec for tests below.
mk_spec <- function(...) {
  base <- list(
    meta_column       = NA_character_,
    treatment_level   = NA_character_,
    control_level     = NA_character_,
    treatment_samples = c("s1", "s2"),
    control_samples   = c("s3", "s4"),
    treatment_label   = "Treatment",
    control_label     = "Control",
    de_method         = "DESeq2",
    method_params     = list(
      fitType = "parametric", betaPrior = FALSE,
      testType = "LRT", shrinkage = "None"
    ),
    covariates        = character(0)
  )
  modifyList(base, list(...))
}

# Synthetic metadata for predicate tests.
mk_meta <- function() {
  data.frame(
    sample = c("s1", "s2", "s3", "s4"),
    cond   = c("KO", "KO", "WT", "WT"),
    batch  = c("A",  "B",  "A",  "B"),
    stringsAsFactors = FALSE
  )
}

test_that("validate_comparison: baseline-valid spec yields no error records", {
  records <- validate_comparison(mk_spec(), mk_meta())
  errors <- Filter(function(r) r$severity == "error", records)
  expect_length(errors, 0)
})

test_that("validate_comparison: empty treatment side -> error", {
  records <- validate_comparison(mk_spec(treatment_samples = character(0)), mk_meta())
  errors <- Filter(function(r) r$severity == "error", records)
  expect_true(any(vapply(errors, function(r) r$field == "treatment_samples", logical(1))))
})

test_that("validate_comparison: empty control side -> error", {
  records <- validate_comparison(mk_spec(control_samples = character(0)), mk_meta())
  errors <- Filter(function(r) r$severity == "error", records)
  expect_true(any(vapply(errors, function(r) r$field == "control_samples", logical(1))))
})

test_that("validate_comparison: overlap between sides -> error", {
  records <- validate_comparison(
    mk_spec(treatment_samples = c("s1", "s2"), control_samples = c("s2", "s3")),
    mk_meta()
  )
  errors <- Filter(function(r) r$severity == "error", records)
  expect_true(any(vapply(errors, function(r) r$field == "samples_disjoint", logical(1))))
})

test_that("validate_comparison: empty treatment label -> error", {
  records <- validate_comparison(mk_spec(treatment_label = ""), mk_meta())
  errors <- Filter(function(r) r$severity == "error", records)
  expect_true(any(vapply(errors, function(r) r$field == "treatment_label", logical(1))))
})

test_that("validate_comparison: empty control label -> error", {
  records <- validate_comparison(mk_spec(control_label = ""), mk_meta())
  errors <- Filter(function(r) r$severity == "error", records)
  expect_true(any(vapply(errors, function(r) r$field == "control_label", logical(1))))
})

test_that("validate_comparison: meta column with < 2 distinct levels -> error", {
  bad_meta <- mk_meta()
  bad_meta$cond <- c("KO", "KO", "KO", "KO")
  records <- validate_comparison(
    mk_spec(meta_column = "cond", treatment_level = "KO", control_level = "KO"),
    bad_meta
  )
  errors <- Filter(function(r) r$severity == "error", records)
  expect_true(any(vapply(errors, function(r) r$field == "meta_levels", logical(1))))
})

test_that("validate_comparison: treatment_level == control_level -> error", {
  records <- validate_comparison(
    mk_spec(meta_column = "cond", treatment_level = "KO", control_level = "KO"),
    mk_meta()
  )
  errors <- Filter(function(r) r$severity == "error", records)
  expect_true(any(vapply(errors, function(r) r$field == "level_distinct", logical(1))))
})
```

- [ ] **Step 2: Run test to verify it fails**

```bash
Rscript -e 'devtools::test(filter = "condselect-validation")'
```
Expected: `could not find function "validate_comparison"`.

- [ ] **Step 3: Implement error predicates + composite skeleton in `R/fct_condselect.R`**

Append:

```r
.rec <- function(field, ok, message = NULL, severity = "error") {
  list(field = field, ok = ok, message = message, severity = severity)
}

#' Compose all validation predicates for a comparison spec.
#'
#' Returns a list of validation records (one per check that produced a
#' result). Records are `list(field, ok, message, severity)`. Fields:
#' "treatment_samples", "control_samples", "samples_disjoint",
#' "treatment_label", "control_label", "meta_levels", "level_distinct",
#' "covariate_<name>".
#'
#' @noRd
validate_comparison <- function(spec, metadata) {
  records <- list()

  # Error-severity predicates.
  records[[length(records) + 1]] <- if (length(spec$treatment_samples) >= 1) {
    .rec("treatment_samples", TRUE)
  } else {
    .rec("treatment_samples", FALSE,
         "Treatment side has no samples selected.", "error")
  }

  records[[length(records) + 1]] <- if (length(spec$control_samples) >= 1) {
    .rec("control_samples", TRUE)
  } else {
    .rec("control_samples", FALSE,
         "Control side has no samples selected.", "error")
  }

  overlap <- intersect(spec$treatment_samples, spec$control_samples)
  records[[length(records) + 1]] <- if (length(overlap) == 0) {
    .rec("samples_disjoint", TRUE)
  } else {
    .rec("samples_disjoint", FALSE,
         paste0("Sample(s) appear on both sides: ",
                paste(overlap, collapse = ", "), "."), "error")
  }

  records[[length(records) + 1]] <- if (nzchar(spec$treatment_label)) {
    .rec("treatment_label", TRUE)
  } else {
    .rec("treatment_label", FALSE,
         "Treatment label is empty.", "error")
  }

  records[[length(records) + 1]] <- if (nzchar(spec$control_label)) {
    .rec("control_label", TRUE)
  } else {
    .rec("control_label", FALSE,
         "Control label is empty.", "error")
  }

  # Meta-path-only predicates.
  if (!is.na(spec$meta_column) && spec$meta_column %in% colnames(metadata)) {
    levels_present <- unique(metadata[[spec$meta_column]])
    levels_present <- levels_present[!is.na(levels_present) & nzchar(levels_present)]

    records[[length(records) + 1]] <- if (length(levels_present) >= 2) {
      .rec("meta_levels", TRUE)
    } else {
      .rec("meta_levels", FALSE,
           paste0("Metadata column `", spec$meta_column,
                  "` has fewer than 2 distinct levels."), "error")
    }

    if (!is.na(spec$treatment_level) && !is.na(spec$control_level)) {
      records[[length(records) + 1]] <- if (
        spec$treatment_level != spec$control_level
      ) {
        .rec("level_distinct", TRUE)
      } else {
        .rec("level_distinct", FALSE,
             "Treatment and Control must be different levels.", "error")
      }
    }
  }

  records
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
Rscript -e 'devtools::test(filter = "condselect-validation")'
```
Expected: 8 test_that blocks PASS.

- [ ] **Step 5: Commit**

```bash
git add R/fct_condselect.R tests/testthat/test-condselect-validation.R
git commit -m "phase B2.5.6: validate_comparison error-severity predicates"
```

---

## Task 7: Validation predicates — covariate warnings

**Files:**
- Modify: `R/fct_condselect.R` (extend `validate_comparison`)
- Modify: `tests/testthat/test-condselect-validation.R` (append)

- [ ] **Step 1: Write the failing test**

Append to `tests/testthat/test-condselect-validation.R`:

```r
test_that("covariate with NA in selected samples -> warning", {
  meta <- mk_meta()
  meta$batch[1] <- NA  # s1 has NA batch
  records <- validate_comparison(mk_spec(covariates = "batch"), meta)
  warnings <- Filter(function(r) r$severity == "warning", records)
  expect_true(any(vapply(warnings,
    function(r) r$field == "covariate_batch", logical(1))))
})

test_that("covariate with < 2 unique values in selected samples -> warning", {
  meta <- mk_meta()
  meta$batch <- c("A", "A", "A", "A")  # all same
  records <- validate_comparison(mk_spec(covariates = "batch"), meta)
  warnings <- Filter(function(r) r$severity == "warning", records)
  expect_true(any(vapply(warnings,
    function(r) r$field == "covariate_batch", logical(1))))
})

test_that("covariate confounded with treatment -> warning", {
  meta <- mk_meta()
  # batch perfectly correlated with treatment side: A on treatment, B on control.
  meta$batch <- c("A", "A", "B", "B")
  records <- validate_comparison(mk_spec(covariates = "batch"), meta)
  warnings <- Filter(function(r) r$severity == "warning", records)
  expect_true(any(vapply(warnings,
    function(r) r$field == "covariate_batch", logical(1))))
})

test_that("covariate equal to meta_column -> warning", {
  records <- validate_comparison(
    mk_spec(meta_column = "cond", treatment_level = "KO",
            control_level = "WT", covariates = "cond"),
    mk_meta()
  )
  warnings <- Filter(function(r) r$severity == "warning", records)
  expect_true(any(vapply(warnings,
    function(r) r$field == "covariate_cond", logical(1))))
})

test_that("baseline-valid covariate (well-balanced, no NA) yields no warning", {
  meta <- mk_meta()
  # batch crosses treatment cleanly.
  meta$batch <- c("A", "B", "A", "B")
  records <- validate_comparison(mk_spec(covariates = "batch"), meta)
  warnings <- Filter(function(r) r$severity == "warning", records)
  expect_length(warnings, 0)
})
```

- [ ] **Step 2: Run test to verify it fails**

```bash
Rscript -e 'devtools::test(filter = "condselect-validation")'
```
Expected: covariate-warning expectations all fail (the 5 new tests).

- [ ] **Step 3: Extend `validate_comparison()` with covariate predicates**

Replace the closing `records` line at the end of `validate_comparison()` with the block below (i.e., insert just before the existing final `records`):

```r
  # Covariate predicates (severity = warning, advisory only).
  selected_samples <- c(spec$treatment_samples, spec$control_samples)
  treatment_marker <- c(rep("Treat", length(spec$treatment_samples)),
                       rep("Control", length(spec$control_samples)))

  for (cov in spec$covariates) {
    if (!cov %in% colnames(metadata)) next  # silently skip; should not happen

    msg <- NULL

    # 1. Equal to meta column?
    if (!is.na(spec$meta_column) && cov == spec$meta_column) {
      msg <- paste0("Covariate `", cov, "` is the comparison column itself.")
    }

    # 2. NA in selected samples?
    if (is.null(msg)) {
      cov_vals <- metadata[[cov]][match(selected_samples, metadata[[1]])]
      if (any(is.na(cov_vals))) {
        msg <- paste0("Covariate `", cov, "` has NA in selected samples.")
      } else if (length(unique(cov_vals)) < 2) {
        # 3. < 2 unique values?
        msg <- paste0("Covariate `", cov,
                      "` has fewer than 2 distinct values in selected samples.")
      } else {
        # 4. Confounded? (each level of cov should appear in both sides)
        ct <- table(cov_vals, treatment_marker)
        if (any(ct == 0)) {
          msg <- paste0("Covariate `", cov,
                        "` is confounded with treatment (some levels appear ",
                        "on only one side).")
        }
      }
    }

    if (!is.null(msg)) {
      records[[length(records) + 1]] <- .rec(
        paste0("covariate_", cov), FALSE, msg, "warning"
      )
    }
  }

```

(The function still ends with `records`; do not remove that line.)

- [ ] **Step 4: Run test to verify it passes**

```bash
Rscript -e 'devtools::test(filter = "condselect-validation")'
```
Expected: 13 test_that blocks PASS.

- [ ] **Step 5: Commit**

```bash
git add R/fct_condselect.R tests/testthat/test-condselect-validation.R
git commit -m "phase B2.5.7: validate_comparison covariate warning predicates"
```

---

## Task 8: `prepDataContainer` rewrite — single-comparison manual path

**Files:**
- Create: `R/prep_data_container.R`
- Test: `tests/testthat/test-prepdatacontainer.R`

- [ ] **Step 1: Write the failing test**

Create `tests/testthat/test-prepdatacontainer.R`:

```r
# tests/testthat/test-prepdatacontainer.R
#
# `prepDataContainer` is a Shiny-coupled function (uses `withProgress`,
# `debrowserdeanalysis`). These tests use the demo data fixtures and
# `shiny::isolate({ ... })` to run the reactive parts in a non-reactive context.

test_that("prepDataContainer runs single-comparison manual path with demo data", {
  skip_if_not_installed("DESeq2")
  fix <- load_demo()  # tests/testthat/helper-debrowser.R

  spec <- list(list(
    meta_column       = NA_character_,
    treatment_level   = NA_character_,
    control_level     = NA_character_,
    treatment_samples = c("exper_rep1", "exper_rep2", "exper_rep3"),
    control_samples   = c("control_rep1", "control_rep2", "control_rep3"),
    treatment_label   = "Treatment",
    control_label     = "Control",
    de_method         = "DESeq2",
    method_params     = list(
      fitType = "parametric", betaPrior = FALSE,
      testType = "Wald", shrinkage = "None"
    ),
    covariates        = character(0)
  ))

  result <- shiny::isolate(
    prepDataContainer(fix$counts, fix$meta, spec)
  )

  expect_type(result, "list")
  expect_length(result, 1L)

  entry <- result[[1]]
  expect_named(entry, c("conds", "cols", "cond_names",
                        "init_data", "demethod_params"))
  expect_equal(entry$cond_names, c("Treatment", "Control"))
  expect_equal(unique(entry$conds), c("Cond1", "Cond2"))
  expect_equal(entry$cols, c("exper_rep1", "exper_rep2", "exper_rep3",
                             "control_rep1", "control_rep2", "control_rep3"))
  expect_equal(entry$demethod_params,
               "DESeq2,NoCovariate,parametric,FALSE,Wald,None")
  expect_true(nrow(entry$init_data) > 0L)
})
```

- [ ] **Step 2: Run test to verify it fails**

```bash
Rscript -e 'devtools::test(filter = "prepdatacontainer")'
```
Expected: function not found, OR conflict with existing `prepDataContainer` in `R/condSelect.R` that has the old `(data, counter, input, meta)` signature — the test will fail because positional args don't match.

- [ ] **Step 3: Create `R/prep_data_container.R` with new-signature `prepDataContainer`**

```r
# R/prep_data_container.R
#
# Extracted and rewritten from R/condSelect.R. The new signature is
#   prepDataContainer(data, metadata, comparisons_spec)
# where `comparisons_spec` is a list of per-comparison spec lists (see
# R/mod_condselect.R / docs/superpowers/specs/2026-04-29-...md). The legacy
# 4-arg signature was `prepDataContainer(data, counter, input, meta)`.

#' Run DE per comparison and return the downstream `dclist` payload.
#'
#' @param data count matrix (rows = features, cols = samples).
#' @param metadata sample-metadata data.frame; first column is the sample id.
#' @param comparisons_spec list of per-comparison spec lists with components
#'   `treatment_samples`, `control_samples`, `treatment_label`,
#'   `control_label`, `de_method`, `method_params`, `covariates`,
#'   `meta_column` (NA_character_ when manual mode).
#' @return list of length `length(comparisons_spec)` with components
#'   `conds`, `cols`, `cond_names`, `init_data`, `demethod_params` per
#'   comparison. Returns NULL if no comparison produced usable results.
#' @export
prepDataContainer <- function(data, metadata, comparisons_spec) {
  if (is.null(data) || length(comparisons_spec) == 0L) {
    return(NULL)
  }

  dclist <- list()
  n <- length(comparisons_spec)

  for (i in seq_len(n)) {
    spec <- comparisons_spec[[i]]
    cols <- c(spec$treatment_samples, spec$control_samples)
    conds <- c(
      rep("Cond1", length(spec$treatment_samples)),
      rep("Cond2", length(spec$control_samples))
    )
    cond_names <- compute_cond_names(spec)
    demethod_params <- build_demethod_params_string(
      spec$de_method, spec$method_params, spec$covariates
    )
    params <- unlist(strsplit(demethod_params, ","))

    shiny::withProgress(
      message = "Running DE Algorithms",
      detail = demethod_params,
      value = 0,
      {
        initd <- debrowserdeanalysis(
          paste0("DEResults", i),
          data = data, metadata = metadata,
          columns = cols, conds = conds, params = params
        )
        if (!is.null(initd$dat()) && nrow(initd$dat()) > 1L) {
          dclist[[i]] <- list(
            conds = conds, cols = cols, cond_names = cond_names,
            init_data = initd$dat(),
            demethod_params = demethod_params
          )
        }
        shiny::incProgress(1 / n)
      }
    )
  }

  if (length(dclist) < 1L) return(NULL)
  dclist
}
```

- [ ] **Step 4: Temporarily disable the legacy `prepDataContainer` in `R/condSelect.R`**

The legacy file still defines `prepDataContainer` and will conflict with the new one when the package is loaded. Comment out lines 801-895 of `R/condSelect.R` (the entire `prepDataContainer <- function(data = NULL, counter = NULL, input = NULL, meta = NULL) { ... }` block) by wrapping in `if (FALSE) { ... }`. The whole `R/condSelect.R` is deleted in Task 19; this is a temporary measure to get tests green during Tasks 8-18.

```r
# R/condSelect.R, replace the existing prepDataContainer definition with:

if (FALSE) {  # B2.5: legacy prepDataContainer disabled; replaced by R/prep_data_container.R. File deleted at end of B2.5.
prepDataContainer <- function(data = NULL, counter = NULL,
                              input = NULL, meta = NULL) {
  # ... (existing body, kept as a reference until task 19)
  ...
}
}
```

(For convenience: `sed -i '' 's/^prepDataContainer <- function(data = NULL, counter = NULL,$/if (FALSE) {\nprepDataContainer <- function(data = NULL, counter = NULL,/' R/condSelect.R` then add a closing `}` after the existing block's closing `}`. Verify by re-reading.)

- [ ] **Step 5: Regenerate docs and run test**

```bash
Rscript -e 'devtools::document()' 2>&1 | tail -10
Rscript -e 'devtools::test(filter = "prepdatacontainer")' 2>&1 | tail -20
```
Expected: regen succeeds; test PASSes.

- [ ] **Step 6: Commit**

```bash
git add R/prep_data_container.R R/condSelect.R man/prepDataContainer.Rd tests/testthat/test-prepdatacontainer.R
git commit -m "phase B2.5.8: prepDataContainer rewrite (single-comparison manual path)"
```

---

## Task 9: `prepDataContainer` — meta path produces metadata-derived `cond_names`

**Files:**
- Modify: `tests/testthat/test-prepdatacontainer.R` (append)

The metadata path is special: `cond_names` should be the user's labels (which default to the metadata level names via `default_side_labels`). This is captured by Task 8's existing `compute_cond_names` call — but worth a regression test that demonstrates "Drug" / "DMSO" labels propagate cleanly.

- [ ] **Step 1: Write the failing test**

Append to `tests/testthat/test-prepdatacontainer.R`:

```r
test_that("prepDataContainer carries user labels (meta path) into cond_names", {
  skip_if_not_installed("DESeq2")
  fix <- load_demo()

  spec <- list(list(
    meta_column       = "treatment",  # depends on demo metadata schema
    treatment_level   = "exper",
    control_level     = "control",
    treatment_samples = c("exper_rep1", "exper_rep2", "exper_rep3"),
    control_samples   = c("control_rep1", "control_rep2", "control_rep3"),
    treatment_label   = "Drug 24h",   # user-edited
    control_label     = "DMSO",       # user-edited
    de_method         = "DESeq2",
    method_params     = list(
      fitType = "parametric", betaPrior = FALSE,
      testType = "Wald", shrinkage = "None"
    ),
    covariates        = character(0)
  ))

  result <- shiny::isolate(prepDataContainer(fix$counts, fix$meta, spec))
  expect_equal(result[[1]]$cond_names, c("Drug 24h", "DMSO"))
})
```

- [ ] **Step 2: Run test to verify it passes already**

(`compute_cond_names` already extracts the labels regardless of mode — this test should pass without code change. If it does not, debug `compute_cond_names`.)

```bash
Rscript -e 'devtools::test(filter = "prepdatacontainer")'
```
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add tests/testthat/test-prepdatacontainer.R
git commit -m "phase B2.5.9: prepDataContainer meta-path label regression test"
```

---

## Task 10: `prepDataContainer` — multi-comparison

**Files:**
- Modify: `tests/testthat/test-prepdatacontainer.R` (append)

- [ ] **Step 1: Write the failing test**

Append:

```r
test_that("prepDataContainer runs N comparisons and returns N dclist entries", {
  skip_if_not_installed("DESeq2")
  fix <- load_demo()

  one_spec <- function(label_t, label_c) list(
    meta_column       = NA_character_,
    treatment_level   = NA_character_,
    control_level     = NA_character_,
    treatment_samples = c("exper_rep1", "exper_rep2", "exper_rep3"),
    control_samples   = c("control_rep1", "control_rep2", "control_rep3"),
    treatment_label   = label_t,
    control_label     = label_c,
    de_method         = "DESeq2",
    method_params     = list(
      fitType = "parametric", betaPrior = FALSE,
      testType = "Wald", shrinkage = "None"
    ),
    covariates        = character(0)
  )

  spec <- list(one_spec("A", "B"), one_spec("C", "D"))
  result <- shiny::isolate(prepDataContainer(fix$counts, fix$meta, spec))

  expect_length(result, 2L)
  expect_equal(result[[1]]$cond_names, c("A", "B"))
  expect_equal(result[[2]]$cond_names, c("C", "D"))
})
```

- [ ] **Step 2: Run test to verify it passes**

```bash
Rscript -e 'devtools::test(filter = "prepdatacontainer")'
```
Expected: PASS (the loop over `seq_len(n)` already supports N > 1).

- [ ] **Step 3: Commit**

```bash
git add tests/testthat/test-prepdatacontainer.R
git commit -m "phase B2.5.10: prepDataContainer multi-comparison test"
```

---

## Task 11: Module UI — `condSelectUI(id)` skeleton

**Files:**
- Create: `R/mod_condselect.R`

The module UI is the static skeleton. Comparison cards and accordion tail are rendered dynamically by the server via `uiOutput("comparison_panels")`.

- [ ] **Step 1: Create `R/mod_condselect.R` with the UI scaffold**

```r
# R/mod_condselect.R
#
# Comparison-Selection wizard module. Replaces the legacy
# debrowsercondselectServer / condSelectUI in R/condSelect.R.
# Pure helpers live in R/fct_condselect.R; the DE runner in
# R/prep_data_container.R.

#' Comparison-Selection wizard UI.
#' @param id module namespace id.
#' @export
condSelectUI <- function(id) {
  ns <- shiny::NS(id)
  de_card(
    title = "Comparison Selection",
    shiny::uiOutput(ns("comparison_panels")),
    shiny::fluidRow(
      shiny::column(
        12,
        actionButtonDE(ns("add_btn"), "Add another comparison",
                       styleclass = "primary"),
        actionButtonDE(ns("rm_btn"), "Remove last", styleclass = "primary"),
        getHelpButton("method",
                      "http://debrowser.readthedocs.io/en/master/deseq/deseq.html"),
        actionButtonDE(ns("startDE"), "Start DE", styleclass = "primary")
      )
    )
  )
}
```

- [ ] **Step 2: Sanity check — package builds with new file**

```bash
Rscript -e 'devtools::load_all()' 2>&1 | tail -10
```
Expected: load succeeds (no `condSelectServer` defined yet — that's Task 12).

- [ ] **Step 3: Commit**

```bash
git add R/mod_condselect.R
git commit -m "phase B2.5.11: condSelectUI scaffold"
```

---

## Task 12: Module server — outer skeleton with reactive `comparisons_spec()`

The outer module server holds the per-comparison rv list, renders the panels via `uiOutput`, and exposes the public reactives. Per-card observers are added in Tasks 13-17.

**Files:**
- Modify: `R/mod_condselect.R` (append)

- [ ] **Step 1: Append `condSelectServer` skeleton**

```r
#' Comparison-Selection wizard server.
#'
#' @param id module namespace id (must match the id passed to `condSelectUI`).
#' @param data count matrix.
#' @param metadata sample-metadata data.frame; first column is the sample id.
#'
#' @return list with `n_comparisons`, `start_de`, `is_ready`, `comparisons_spec`.
#' @export
condSelectServer <- function(id, data = NULL, metadata = NULL) {
  if (is.null(data)) return(NULL)

  shiny::moduleServer(id, function(input, output, session) {
    ns <- session$ns

    # Per-comparison state lives in this list; each entry is a reactiveValues
    # holding the comparison spec components. Indexed by comparison id (1..N).
    comparisons <- shiny::reactiveValues()

    # Counter; mirror of length(reactiveValuesToList(comparisons)).
    n_comparisons <- shiny::reactiveVal(0L)

    # --- Helpers (closures over `data`, `metadata`, `session`) -------

    new_comparison <- function(idx) {
      sn <- colnames(data)
      halves <- halve_sample_names(sn)
      labels <- default_side_labels(NA_character_, NA_character_, NA_character_)
      comparisons[[as.character(idx)]] <- shiny::reactiveValues(
        meta_column       = NA_character_,
        treatment_level   = NA_character_,
        control_level     = NA_character_,
        treatment_samples = halves$treatment,
        control_samples   = halves$control,
        treatment_label   = unname(labels["treatment"]),
        control_label     = unname(labels["control"]),
        de_method         = "DESeq2",
        method_params     = list(
          fitType = "parametric", betaPrior = FALSE,
          testType = "LRT",       shrinkage = "None"
        ),
        covariates        = character(0)
      )
    }

    rm_comparison <- function(idx) {
      comparisons[[as.character(idx)]] <- NULL
    }

    snapshot_spec <- function(rv) {
      list(
        meta_column       = rv$meta_column,
        treatment_level   = rv$treatment_level,
        control_level     = rv$control_level,
        treatment_samples = rv$treatment_samples,
        control_samples   = rv$control_samples,
        treatment_label   = rv$treatment_label,
        control_label     = rv$control_label,
        de_method         = rv$de_method,
        method_params     = rv$method_params,
        covariates        = rv$covariates
      )
    }

    # --- Initialize first comparison -----------------------------------

    new_comparison(1L)
    n_comparisons(1L)

    # --- Add / remove observers ---------------------------------------

    shiny::observeEvent(input$add_btn, {
      idx <- n_comparisons() + 1L
      new_comparison(idx)
      n_comparisons(idx)
    })

    shiny::observeEvent(input$rm_btn, {
      idx <- n_comparisons()
      if (idx > 1L) {
        rm_comparison(idx)
        n_comparisons(idx - 1L)
      }
    })

    # --- Render comparison panels (placeholder; Task 13 fills in) ----

    output$comparison_panels <- shiny::renderUI({
      n <- n_comparisons()
      if (n < 1L) return(NULL)
      shiny::tagList(
        lapply(seq_len(n), function(i) {
          comparisonCardUI(ns, i, comparisons[[as.character(i)]], data, metadata)
        })
      )
    })

    # --- Public reactives ---------------------------------------------

    comparisons_spec <- shiny::reactive({
      n <- n_comparisons()
      lapply(seq_len(n), function(i) {
        snapshot_spec(comparisons[[as.character(i)]])
      })
    })

    is_ready <- shiny::reactive({
      specs <- comparisons_spec()
      if (length(specs) == 0L) return(FALSE)
      records <- lapply(specs, validate_comparison, metadata = metadata)
      all(vapply(records, function(rs) {
        !any(vapply(rs, function(r) r$severity == "error", logical(1)))
      }, logical(1)))
    })

    # Toggle Start DE button enabled/disabled.
    shiny::observe({
      shinyjs::toggleState(id = "startDE", condition = is_ready())
    })

    list(
      n_comparisons    = n_comparisons,
      start_de         = shiny::reactive(input$startDE),
      is_ready         = is_ready,
      comparisons_spec = comparisons_spec
    )
  })
}
```

- [ ] **Step 2: Stub `comparisonCardUI` so the package loads**

Append to `R/mod_condselect.R`:

```r
# Per-comparison card UI. Filled in across Tasks 13-17.
#
# @param ns parent module's NS function (so card widgets get the module's namespace).
# @param i comparison index (1..N).
# @param rv per-comparison reactiveValues.
# @param data count matrix (for sample-name choices).
# @param metadata metadata data.frame (for meta-column choices).
comparisonCardUI <- function(ns, i, rv, data, metadata) {
  shiny::div(
    style = "border:1px solid #ddd; border-radius:6px; padding:10px; margin-bottom:10px;",
    shiny::h5(paste0("Comparison ", i, " (placeholder)"))
  )
}
```

- [ ] **Step 3: Sanity load**

```bash
Rscript -e 'devtools::load_all()' 2>&1 | tail -10
```
Expected: load succeeds.

- [ ] **Step 4: Commit**

```bash
git add R/mod_condselect.R
git commit -m "phase B2.5.12: condSelectServer skeleton + reactive contract"
```

---

## Task 13: Per-comparison card UI — manual path widgets

Render the manual-mode widgets: meta-column dropdown ("None"), two side cards (label + sample picker each), DE method picker, swap button, and a placeholder for "Advanced model settings" (filled in Task 16).

**Files:**
- Modify: `R/mod_condselect.R` (replace `comparisonCardUI` stub)

- [ ] **Step 1: Replace the `comparisonCardUI` stub**

```r
comparisonCardUI <- function(ns, i, rv, data, metadata) {
  if (is.null(rv)) return(NULL)
  iid <- function(name) ns(paste0(name, "_", i))
  sample_choices <- colnames(data)
  meta_choices <- if (!is.null(metadata) && ncol(metadata) > 1L) {
    c("None — pick samples manually" = NA_character_,
      stats::setNames(colnames(metadata)[-1], colnames(metadata)[-1]))
  } else {
    c("None — pick samples manually" = NA_character_)
  }

  card_title <- shiny::reactive({
    paste0("Comparison ", i, ": ",
           rv$treatment_label, " vs ", rv$control_label)
  })

  bslib::card(
    bslib::card_header(shiny::textOutput(iid("title"), inline = TRUE)),
    bslib::card_body(
      shiny::fluidRow(shiny::column(
        12,
        shiny::selectInput(iid("meta_column"),
          label = "Group by metadata column",
          choices = meta_choices,
          selected = if (is.na(rv$meta_column)) NA_character_ else rv$meta_column)
      )),
      shiny::fluidRow(
        shiny::column(5,
          shiny::div(class = "side-card",
            shiny::h6("Treatment"),
            # Level dropdown rendered conditionally (Task 14).
            shiny::uiOutput(iid("treatment_level_ui")),
            shiny::textInput(iid("treatment_label"),
              label = "Label", value = rv$treatment_label),
            shiny::selectInput(iid("treatment_samples"),
              label = "Samples", choices = sample_choices,
              selected = rv$treatment_samples, multiple = TRUE)
          )
        ),
        shiny::column(2,
          shiny::div(style = "text-align:center; padding-top:60px;",
            actionButtonDE(iid("swap"), "Swap", styleclass = "primary",
                           icon = shiny::icon("arrows-left-right"))
          )
        ),
        shiny::column(5,
          shiny::div(class = "side-card",
            shiny::h6("Control"),
            shiny::uiOutput(iid("control_level_ui")),
            shiny::textInput(iid("control_label"),
              label = "Label", value = rv$control_label),
            shiny::selectInput(iid("control_samples"),
              label = "Samples", choices = sample_choices,
              selected = rv$control_samples, multiple = TRUE)
          )
        )
      ),
      shiny::fluidRow(shiny::column(
        4,
        shiny::selectInput(iid("de_method"),
          label = "DE method",
          choices = c("DESeq2", "EdgeR", "Limma"),
          selected = rv$de_method)
      )),
      bslib::accordion(
        open = FALSE, multiple = FALSE,
        bslib::accordion_panel(
          title = "Advanced model settings",
          shiny::uiOutput(iid("advanced_ui"))  # filled by Task 16
        )
      ),
      shiny::uiOutput(iid("validation_msgs"))   # filled by Task 17
    )
  )
}
```

- [ ] **Step 2: Wire card-title text output and bind sample / label state in the server**

Inside `condSelectServer`'s `moduleServer(...)` body, after the existing `output$comparison_panels` renderUI, add a per-comparison observer factory. Append:

```r
    # Per-comparison observers: bind widgets to rv. Each comparison gets a
    # fresh set when added; previous observers persist (their inputs vanish
    # from the namespace harmlessly when the card is removed).
    install_card_observers <- function(i) {
      iid <- function(name) paste0(name, "_", i)

      # Title.
      output[[iid("title")]] <- shiny::renderText({
        rv <- comparisons[[as.character(i)]]
        paste0("Comparison ", i, ": ",
               rv$treatment_label, " vs ", rv$control_label)
      })

      # Side labels (textInput -> rv).
      shiny::observeEvent(input[[iid("treatment_label")]], {
        rv <- comparisons[[as.character(i)]]; if (is.null(rv)) return()
        rv$treatment_label <- input[[iid("treatment_label")]]
      }, ignoreInit = TRUE)
      shiny::observeEvent(input[[iid("control_label")]], {
        rv <- comparisons[[as.character(i)]]; if (is.null(rv)) return()
        rv$control_label <- input[[iid("control_label")]]
      }, ignoreInit = TRUE)

      # Side sample pickers (selectInput multiple -> rv).
      shiny::observeEvent(input[[iid("treatment_samples")]], {
        rv <- comparisons[[as.character(i)]]; if (is.null(rv)) return()
        rv$treatment_samples <- input[[iid("treatment_samples")]] %||% character(0)
      }, ignoreInit = TRUE, ignoreNULL = FALSE)
      shiny::observeEvent(input[[iid("control_samples")]], {
        rv <- comparisons[[as.character(i)]]; if (is.null(rv)) return()
        rv$control_samples <- input[[iid("control_samples")]] %||% character(0)
      }, ignoreInit = TRUE, ignoreNULL = FALSE)

      # DE method.
      shiny::observeEvent(input[[iid("de_method")]], {
        rv <- comparisons[[as.character(i)]]; if (is.null(rv)) return()
        rv$de_method <- input[[iid("de_method")]]
      }, ignoreInit = TRUE)

      # Meta column (manual-vs-meta toggle; auto-fill handled in Task 14).
      shiny::observeEvent(input[[iid("meta_column")]], {
        rv <- comparisons[[as.character(i)]]; if (is.null(rv)) return()
        v <- input[[iid("meta_column")]]
        rv$meta_column <- if (is.null(v) || identical(v, "NA") || is.na(v)) NA_character_ else v
      }, ignoreInit = TRUE, ignoreNULL = FALSE)
    }

    # Install observers for the seed card.
    install_card_observers(1L)

    # Re-install when add_btn fires (Task 12 created the rv; here we wire it).
    shiny::observeEvent(input$add_btn, {
      install_card_observers(n_comparisons())
    }, ignoreInit = TRUE)
```

Add a NULL-coalescing helper near the top of the moduleServer body:

```r
    `%||%` <- function(a, b) if (is.null(a)) b else a
```

- [ ] **Step 3: Sanity load + interactive smoke (no automated test)**

```bash
Rscript -e 'devtools::load_all()' 2>&1 | tail -10
```
Expected: clean load, no warnings about missing functions.

- [ ] **Step 4: Commit**

```bash
git add R/mod_condselect.R
git commit -m "phase B2.5.13: comparisonCardUI manual path + label/sample observers"
```

---

## Task 14: Meta path — level pickers + auto-fill

When the user picks a metadata column, render two `selectInput`s ("Level" picker per side), default-assign Treatment/Control via `infer_control_level`, and auto-fill samples + labels.

**Files:**
- Modify: `R/mod_condselect.R` (extend `install_card_observers` and per-card UI)

- [ ] **Step 1: Add level-picker render + auto-fill observer to `install_card_observers`**

Append inside `install_card_observers <- function(i) { ... }`:

```r
      # Level pickers — rendered only when meta_column is not NA.
      output[[iid("treatment_level_ui")]] <- shiny::renderUI({
        rv <- comparisons[[as.character(i)]]
        if (is.null(rv) || is.na(rv$meta_column)) return(NULL)
        levels_present <- unique(metadata[[rv$meta_column]])
        levels_present <- levels_present[!is.na(levels_present) & nzchar(levels_present)]
        shiny::selectInput(session$ns(iid("treatment_level")),
          label = "Level",
          choices = levels_present,
          selected = rv$treatment_level)
      })
      output[[iid("control_level_ui")]] <- shiny::renderUI({
        rv <- comparisons[[as.character(i)]]
        if (is.null(rv) || is.na(rv$meta_column)) return(NULL)
        levels_present <- unique(metadata[[rv$meta_column]])
        levels_present <- levels_present[!is.na(levels_present) & nzchar(levels_present)]
        shiny::selectInput(session$ns(iid("control_level")),
          label = "Level",
          choices = levels_present,
          selected = rv$control_level)
      })

      # When meta_column changes, auto-assign default levels and refresh
      # sample lists + labels.
      shiny::observeEvent(comparisons[[as.character(i)]]$meta_column, {
        rv <- comparisons[[as.character(i)]]; if (is.null(rv)) return()
        if (is.na(rv$meta_column)) {
          # Manual mode: keep halve_sample_names defaults.
          halves <- halve_sample_names(colnames(data))
          rv$treatment_level   <- NA_character_
          rv$control_level     <- NA_character_
          rv$treatment_samples <- halves$treatment
          rv$control_samples   <- halves$control
          labels <- default_side_labels(NA_character_, NA_character_, NA_character_)
        } else {
          levels_present <- unique(metadata[[rv$meta_column]])
          levels_present <- levels_present[!is.na(levels_present) & nzchar(levels_present)]
          if (length(levels_present) >= 2L) {
            rv$control_level   <- infer_control_level(levels_present)
            rv$treatment_level <- setdiff(levels_present, rv$control_level)[1]
            sample_col <- colnames(metadata)[1]
            rv$treatment_samples <- metadata[
              metadata[[rv$meta_column]] == rv$treatment_level, sample_col]
            rv$control_samples   <- metadata[
              metadata[[rv$meta_column]] == rv$control_level, sample_col]
            labels <- default_side_labels(rv$meta_column,
              rv$treatment_level, rv$control_level)
          } else {
            labels <- default_side_labels(NA_character_, NA_character_, NA_character_)
          }
        }
        rv$treatment_label <- unname(labels["treatment"])
        rv$control_label   <- unname(labels["control"])
        # Reflect in widgets.
        shiny::updateTextInput(session, iid("treatment_label"), value = rv$treatment_label)
        shiny::updateTextInput(session, iid("control_label"),   value = rv$control_label)
        shiny::updateSelectInput(session, iid("treatment_samples"),
          choices = colnames(data), selected = rv$treatment_samples)
        shiny::updateSelectInput(session, iid("control_samples"),
          choices = colnames(data), selected = rv$control_samples)
      })

      # When the user changes a level picker, refill that side's samples.
      shiny::observeEvent(input[[iid("treatment_level")]], {
        rv <- comparisons[[as.character(i)]]; if (is.null(rv)) return()
        if (is.na(rv$meta_column)) return()
        rv$treatment_level <- input[[iid("treatment_level")]]
        sample_col <- colnames(metadata)[1]
        rv$treatment_samples <- metadata[
          metadata[[rv$meta_column]] == rv$treatment_level, sample_col]
        rv$treatment_label <- rv$treatment_level
        shiny::updateTextInput(session, iid("treatment_label"), value = rv$treatment_label)
        shiny::updateSelectInput(session, iid("treatment_samples"),
          selected = rv$treatment_samples)
      }, ignoreInit = TRUE)

      shiny::observeEvent(input[[iid("control_level")]], {
        rv <- comparisons[[as.character(i)]]; if (is.null(rv)) return()
        if (is.na(rv$meta_column)) return()
        rv$control_level <- input[[iid("control_level")]]
        sample_col <- colnames(metadata)[1]
        rv$control_samples <- metadata[
          metadata[[rv$meta_column]] == rv$control_level, sample_col]
        rv$control_label <- rv$control_level
        shiny::updateTextInput(session, iid("control_label"), value = rv$control_label)
        shiny::updateSelectInput(session, iid("control_samples"),
          selected = rv$control_samples)
      }, ignoreInit = TRUE)
```

- [ ] **Step 2: Sanity load**

```bash
Rscript -e 'devtools::load_all()' 2>&1 | tail -10
```
Expected: clean load.

- [ ] **Step 3: Commit**

```bash
git add R/mod_condselect.R
git commit -m "phase B2.5.14: meta-path level pickers + auto-fill"
```

---

## Task 15: Swap button

Click flips treatment ↔ control across labels, levels, and sample lists. Plot legends and log2FC sign follow because everything reads from `cond_names`.

**Files:**
- Modify: `R/mod_condselect.R` (extend `install_card_observers`)

- [ ] **Step 1: Append swap observer**

Append inside `install_card_observers`:

```r
      shiny::observeEvent(input[[iid("swap")]], {
        rv <- comparisons[[as.character(i)]]; if (is.null(rv)) return()
        # Swap rv state.
        new_t_label <- rv$control_label;    new_c_label <- rv$treatment_label
        new_t_lvl   <- rv$control_level;    new_c_lvl   <- rv$treatment_level
        new_t_smp   <- rv$control_samples;  new_c_smp   <- rv$treatment_samples
        rv$treatment_label   <- new_t_label
        rv$control_label     <- new_c_label
        rv$treatment_level   <- new_t_lvl
        rv$control_level     <- new_c_lvl
        rv$treatment_samples <- new_t_smp
        rv$control_samples   <- new_c_smp
        # Reflect in widgets.
        shiny::updateTextInput(session, iid("treatment_label"), value = rv$treatment_label)
        shiny::updateTextInput(session, iid("control_label"),   value = rv$control_label)
        shiny::updateSelectInput(session, iid("treatment_samples"), selected = rv$treatment_samples)
        shiny::updateSelectInput(session, iid("control_samples"),   selected = rv$control_samples)
      })
```

- [ ] **Step 2: Sanity load**

```bash
Rscript -e 'devtools::load_all()' 2>&1 | tail -10
```
Expected: clean load.

- [ ] **Step 3: Commit**

```bash
git add R/mod_condselect.R
git commit -m "phase B2.5.15: swap-direction button"
```

---

## Task 16: Advanced model settings (method-specific params + covariates)

**Files:**
- Modify: `R/mod_condselect.R` (extend `install_card_observers`)

- [ ] **Step 1: Render the Advanced UI per comparison**

Append inside `install_card_observers`:

```r
      output[[iid("advanced_ui")]] <- shiny::renderUI({
        rv <- comparisons[[as.character(i)]]; if (is.null(rv)) return(NULL)
        method <- rv$de_method
        cov_choices <- if (!is.null(metadata) && ncol(metadata) > 1L) {
          colnames(metadata)[-1]
        } else {
          character(0)
        }
        method_block <- switch(method,
          "DESeq2" = shiny::tagList(
            shiny::selectInput(session$ns(iid("fitType")), "Fit type",
              c("parametric", "local", "mean"),
              selected = rv$method_params$fitType),
            shiny::selectInput(session$ns(iid("betaPrior")), "betaPrior",
              c(FALSE, TRUE),
              selected = rv$method_params$betaPrior),
            shiny::selectInput(session$ns(iid("testType")), "Test type",
              c("LRT", "Wald"),
              selected = rv$method_params$testType),
            shiny::selectInput(session$ns(iid("shrinkage")), "Shrinkage",
              c("None", "apeglm", "ashr", "normal"),
              selected = rv$method_params$shrinkage)
          ),
          "EdgeR" = shiny::tagList(
            shiny::selectInput(session$ns(iid("edgeR_normfact")), "Normalization",
              c("TMM", "RLE", "upperquartile", "none"),
              selected = rv$method_params$edgeR_normfact),
            shiny::textInput(session$ns(iid("dispersion")), "Dispersion",
              value = rv$method_params$dispersion),
            shiny::selectInput(session$ns(iid("edgeR_testType")), "Test type",
              c("exactTest", "glmLRT"),
              selected = rv$method_params$edgeR_testType)
          ),
          "Limma" = shiny::tagList(
            shiny::selectInput(session$ns(iid("limma_normfact")), "Normalization",
              c("TMM", "RLE", "upperquartile", "none"),
              selected = rv$method_params$limma_normfact),
            shiny::selectInput(session$ns(iid("limma_fitType")), "Fit type",
              c("ls", "robust"),
              selected = rv$method_params$limma_fitType),
            shiny::selectInput(session$ns(iid("normBetween")), "Norm. Bet. Arrays",
              c("none", "scale", "quantile", "cyclicloess",
                "Aquantile", "Gquantile", "Rquantile", "Tquantile"),
              selected = rv$method_params$normBetween)
          )
        )
        shiny::tagList(
          method_block,
          shiny::selectInput(session$ns(iid("covariates")),
            label = "Covariates",
            choices = cov_choices,
            selected = rv$covariates,
            multiple = TRUE),
          shiny::uiOutput(session$ns(iid("covariate_msgs")))
        )
      })

      # Method-params observers — install once per method-key. Each writes
      # back into rv$method_params.
      shiny::observe({
        rv <- comparisons[[as.character(i)]]; if (is.null(rv)) return()
        m <- rv$de_method
        if (m == "DESeq2") {
          if (!is.null(input[[iid("fitType")]]))
            rv$method_params$fitType <- input[[iid("fitType")]]
          if (!is.null(input[[iid("betaPrior")]]))
            rv$method_params$betaPrior <- as.logical(input[[iid("betaPrior")]])
          if (!is.null(input[[iid("testType")]]))
            rv$method_params$testType <- input[[iid("testType")]]
          if (!is.null(input[[iid("shrinkage")]]))
            rv$method_params$shrinkage <- input[[iid("shrinkage")]]
        } else if (m == "EdgeR") {
          if (!is.null(input[[iid("edgeR_normfact")]]))
            rv$method_params$edgeR_normfact <- input[[iid("edgeR_normfact")]]
          if (!is.null(input[[iid("dispersion")]]))
            rv$method_params$dispersion <- input[[iid("dispersion")]]
          if (!is.null(input[[iid("edgeR_testType")]]))
            rv$method_params$edgeR_testType <- input[[iid("edgeR_testType")]]
        } else if (m == "Limma") {
          if (!is.null(input[[iid("limma_normfact")]]))
            rv$method_params$limma_normfact <- input[[iid("limma_normfact")]]
          if (!is.null(input[[iid("limma_fitType")]]))
            rv$method_params$limma_fitType <- input[[iid("limma_fitType")]]
          if (!is.null(input[[iid("normBetween")]]))
            rv$method_params$normBetween <- input[[iid("normBetween")]]
        }
      })

      # When the method changes, reset method_params to that method's defaults
      # so we don't carry stale fields from another method.
      shiny::observeEvent(input[[iid("de_method")]], {
        rv <- comparisons[[as.character(i)]]; if (is.null(rv)) return()
        m <- input[[iid("de_method")]]
        rv$method_params <- switch(m,
          "DESeq2" = list(fitType = "parametric", betaPrior = FALSE,
                          testType = "LRT",       shrinkage = "None"),
          "EdgeR"  = list(edgeR_normfact = "TMM", dispersion = "0",
                          edgeR_testType = "exactTest"),
          "Limma"  = list(limma_normfact = "TMM", limma_fitType = "ls",
                          normBetween = "none")
        )
      }, ignoreInit = TRUE)

      # Covariates.
      shiny::observeEvent(input[[iid("covariates")]], {
        rv <- comparisons[[as.character(i)]]; if (is.null(rv)) return()
        rv$covariates <- input[[iid("covariates")]] %||% character(0)
      }, ignoreInit = TRUE, ignoreNULL = FALSE)
```

- [ ] **Step 2: Sanity load**

```bash
Rscript -e 'devtools::load_all()' 2>&1 | tail -10
```
Expected: clean load.

- [ ] **Step 3: Commit**

```bash
git add R/mod_condselect.R
git commit -m "phase B2.5.16: advanced settings (method params + covariates)"
```

---

## Task 17: Validation messages render

Pure helpers already drive the logic; this task surfaces the records as inline `.text-warning` / `.text-danger` lines in two places (card footer, covariate widget).

**Files:**
- Modify: `R/mod_condselect.R` (extend `install_card_observers`)

- [ ] **Step 1: Render validation messages per card**

Append inside `install_card_observers`:

```r
      output[[iid("validation_msgs")]] <- shiny::renderUI({
        rv <- comparisons[[as.character(i)]]; if (is.null(rv)) return(NULL)
        records <- validate_comparison(snapshot_spec(rv), metadata)
        bad <- Filter(function(r) !r$ok, records)
        if (length(bad) == 0L) return(NULL)
        shiny::tagList(lapply(bad, function(r) {
          cls <- if (r$severity == "error") "text-danger" else "text-warning"
          shiny::tags$div(class = cls,
            shiny::icon(if (r$severity == "error") "circle-exclamation" else "triangle-exclamation"),
            " ", r$message
          )
        }))
      })

      output[[iid("covariate_msgs")]] <- shiny::renderUI({
        rv <- comparisons[[as.character(i)]]; if (is.null(rv)) return(NULL)
        records <- validate_comparison(snapshot_spec(rv), metadata)
        cov_recs <- Filter(
          function(r) startsWith(r$field, "covariate_") && !r$ok,
          records
        )
        if (length(cov_recs) == 0L) return(NULL)
        shiny::tagList(lapply(cov_recs, function(r) {
          shiny::tags$div(class = "text-warning small",
            shiny::icon("triangle-exclamation"), " ", r$message)
        }))
      })
```

- [ ] **Step 2: Sanity load**

```bash
Rscript -e 'devtools::load_all()' 2>&1 | tail -10
```
Expected: clean load.

- [ ] **Step 3: Commit**

```bash
git add R/mod_condselect.R
git commit -m "phase B2.5.17: inline validation message rendering"
```

---

## Task 18: Wire `R/server.R` to use `condSelectServer` + new `prepDataContainer` signature

**Files:**
- Modify: `R/server.R` lines 225-228, 239-242, 247-265

- [ ] **Step 1: Replace `debrowsercondselectServer` calls with `condSelectServer`**

In `R/server.R`, change both occurrences (`R/server.R:225-228` and `R/server.R:239-242`):

```r
# Before
sel(debrowsercondselectServer(
  "cs",
  batch()$BatchEffect()$count, batch()$BatchEffect()$meta
))

# After
sel(condSelectServer(
  "cs",
  batch()$BatchEffect()$count, batch()$BatchEffect()$meta
))
```

`choicecounter$nc <- sel()$cc()` becomes `choicecounter$nc <- sel()$n_comparisons()` (both occurrences). Update both lines.

- [ ] **Step 2: Replace the `prepDataContainer` call site**

Change `R/server.R:260-265`:

```r
# Before
dc_res <- prepDataContainer(
  batch()$BatchEffect()$count,
  sel()$cc(),
  sel()$input,
  batch()$BatchEffect()$meta
)

# After
dc_res <- prepDataContainer(
  batch()$BatchEffect()$count,
  batch()$BatchEffect()$meta,
  sel()$comparisons_spec()
)
```

- [ ] **Step 3: Replace `condSelectUI("cs")` callsite**

Find the existing `condSelectUI` call site (search for `condSelectUI` in `R/`) — today it's the legacy file's UI; it already accepts an `id`. After Task 19 deletes the old file, only our new `condSelectUI(id)` (defined in `R/mod_condselect.R`) is in scope. No change is required at the call site, but verify by grepping after the load_all in step 4.

- [ ] **Step 4: Load + run shinytest2 state smoke**

```bash
Rscript -e 'devtools::load_all(); pkgload::load_all()' 2>&1 | tail -10
Rscript -e 'devtools::test(filter = "app-shinytest2")' 2>&1 | tail -20
```
Expected: state smoke (existing) still passes (skip is OK on macOS without shinytest2 installed); load is clean.

- [ ] **Step 5: Commit**

```bash
git add R/server.R
git commit -m "phase B2.5.18: server.R uses condSelectServer + new prepDataContainer signature"
```

---

## Task 19: Delete `R/condSelect.R`, regenerate NAMESPACE/man/, NEWS.md

**Files:**
- Delete: `R/condSelect.R`
- Modify (regen): `NAMESPACE`, `man/*.Rd`
- Modify: `NEWS.md`

- [ ] **Step 1: Delete the legacy file**

```bash
rm R/condSelect.R
```

- [ ] **Step 2: Regenerate package docs**

```bash
Rscript -e 'devtools::document()' 2>&1 | tail -20
```
Expected: deletes `man/debrowsercondselect.Rd`, `man/debrowsercondselectServer.Rd`, `man/getMethodDetails.Rd`, `man/getCovariateDetails.Rd`, `man/getConditionSelector.Rd`, `man/getConditionSelectorFromMeta.Rd`, `man/selectedInput.Rd`, `man/getSelectInputBox.Rd`, `man/selectConditions.Rd`, `man/getGroupSelector.Rd`, `man/getMetaSelector.Rd`, `man/get_conditions_given_selection.Rd`, `man/getSampleNames.Rd`. Creates `man/condSelectUI.Rd`, `man/condSelectServer.Rd`. `NAMESPACE` loses the corresponding exports.

- [ ] **Step 3: Add NEWS.md entry**

Insert at the top of `NEWS.md` (after the existing first heading):

```markdown
## debrowser 1.99.0 (devel) — Phase B2.5

* Comparison Selection wizard rewritten (`R/condSelect.R` → `R/fct_condselect.R`,
  `R/mod_condselect.R`, `R/prep_data_container.R`).
* New module API: `condSelectUI(id)`, `condSelectServer(id, data, metadata)`.
* `prepDataContainer()` signature changed: now `prepDataContainer(data, metadata,
  comparisons_spec)` where `comparisons_spec` is a list of structured spec
  records. The legacy `(data, counter, input, meta)` form is removed.
* Removed exports (no known external callers): `debrowsercondselect`,
  `debrowsercondselectServer`, `selectedInput`, `getSelectInputBox`,
  `getMetaSelector`, `getGroupSelector`, `getConditionSelector`,
  `getConditionSelectorFromMeta`, `getMethodDetails`, `getCovariateDetails`,
  `selectConditions`, `get_conditions_given_selection`, `getSampleNames`.
* UX: single-comparison default with accordion tail for multi-comparison;
  editable Treatment/Control side labels with metadata-driven defaults;
  reference-word direction heuristic + always-visible swap; advanced model
  settings (per-method params + covariates) collapsed by default; inline
  non-toast validation.
* Internal `conds` codes (`"Cond1"`/`"Cond2"`) preserved so `R/fct_de_methods.R`,
  `R/fct_prep_data.R`, `R/deprogs.R`, `R/barmain.R`, and downstream plotting
  modules need no changes.
```

(Use `1.99.0 (devel)` only if it matches DESCRIPTION's Version; otherwise use whatever the current devel version is. Check `grep '^Version' DESCRIPTION` first and align.)

- [ ] **Step 4: Run full test suite**

```bash
Rscript -e 'devtools::test()' 2>&1 | tail -10
```
Expected: ≥ 155 PASS, 0 FAIL.

- [ ] **Step 5: Run R CMD check**

```bash
Rscript -e 'devtools::check(args = c("--no-manual"), quiet = TRUE, error_on = "never")' 2>&1 | tail -30
```
Expected: 0 new errors/warnings/notes vs baseline (3W + 2N pre-existing).

- [ ] **Step 6: Commit**

```bash
git add R/condSelect.R NAMESPACE man/ NEWS.md
git commit -m "phase B2.5.19: delete legacy condSelect.R; regen docs; NEWS.md"
```

---

## Task 20: Manual smoke checklist + handoff memory

The acceptance gates that can't be automated.

**Files:**
- Create: `/Users/alper/.claude/projects/-Users-alper-workdir-debrowser/memory/phase_b2_5_handoff.md`

- [ ] **Step 1: Run the app and execute the smoke checklist**

```bash
Rscript -e 'devtools::load_all(); debrowser::startDEBrowser()'
```

Run, in order:

1. **Vernia demo (meta path):** click Vernia → Filter → Batch → CondSelect. Verify: meta-column dropdown is populated; picking the column auto-selects sides via heuristic; side labels default to level names; swap button flips direction; volcano renders after Start DE; legend reads `<treatment-label>.vs.<control-label>` (matching the labels the user picked).
2. **No-metadata path:** load a counts file with no metadata file. Verify: meta dropdown shows only "(None)"; sides default to halve_sample_names; labels default to "Treatment"/"Control"; Start DE runs.
3. **Multi-comparison:** add 2 more comparisons; verify they render as closed accordion panels; expand each, configure differently, run Start DE; verify three `DEResults1`, `DEResults2`, `DEResults3` tabs appear.
4. **Covariate flow:** pick a confounded covariate; verify inline yellow `.text-warning` appears under the multi-select; Start DE button stays enabled; DE completes.
5. **Errors:** clear all samples on one side; verify the inline red `.text-danger` message appears; Start DE button is disabled (cursor: not-allowed).
6. **Swap regression:** with the demo, run DE before swap → snapshot a row of `result_table` for a known gene. Click Swap → re-run DE → same gene's log2FoldChange should be the negation of pre-swap (within FP tolerance).
7. **Dark mode:** toggle theme; verify validation messages remain readable.

If any step fails, log it as a deferred-followup (not as a B2.5 reopener unless it's a regression vs B2c).

- [ ] **Step 2: Write handoff memory**

```r
# Use the Write tool to create:
# /Users/alper/.claude/projects/-Users-alper-workdir-debrowser/memory/phase_b2_5_handoff.md
```

Content (frontmatter + body):

```markdown
---
name: Phase B2.5 SHIPPED — condSelect rewrite + Treatment/Control language
description: B2.5 ships condSelect.R rewrite as 3 focused files + new prepDataContainer signature + UX restructure. ~20 commits on top of B2c (b3e8102 spec, bb80593 baseline). Tests ≥ 155, R CMD check clean, manual smoke verified.
type: project
---
## What shipped
[summarize: helpers, validation, prepDataContainer signature change, module rewrite, server wiring, NEWS.md.]

## Manual smoke results (2026-04-29 by user)
[record outcome of the 7 smoke steps above; flag any deferred items.]

## Followups
- (capture any from manual smoke)
- Plot-legend rewrite when cond_names == c("Cond1", "Cond2") (manual no-meta path) — followup phase, not B2.5.

## Next: Phase B3
Sane defaults harmonization (padj 0.05, |log2FC| 1) per phase_e_plan.md.
```

Then add an index entry to `/Users/alper/.claude/projects/-Users-alper-workdir-debrowser/memory/MEMORY.md`:

```
- [Phase B2.5 SHIPPED — condSelect rewrite](phase_b2_5_handoff.md) — <one-line summary>
```

- [ ] **Step 3: Final commit (handoff is in `~/.claude`, not repo, so only repo-side work commits here)**

If any followup edits resulted from manual smoke, commit them; otherwise no commit is needed.

```bash
git status --porcelain
# If clean: end of B2.5. If not: review and commit any tweaks.
```

---

## Self-Review

**Spec coverage check** — every spec section maps to at least one task:

| Spec section | Task(s) |
|---|---|
| Goal / locked decisions | All tasks (Tasks 1-20) |
| File layout (`fct_condselect.R`, `mod_condselect.R`, `prep_data_container.R`) | Tasks 1-7 (helpers); Tasks 8-10 (prep); Tasks 11-17 (module) |
| Removed/renamed exports | Task 19 (delete + regen); NEWS.md entry |
| UI structure (per-card layout, footer, three states, swap, accordion title) | Tasks 11, 13, 14, 15 |
| Reactive contract (`n_comparisons`, `start_de`, `is_ready`, `comparisons_spec`) | Task 12 |
| `prepDataContainer` signature change + downstream contract preserved | Tasks 8, 9, 10 |
| Server.R call-site change | Task 18 |
| Validation predicates (4 error + 4 warning families) | Tasks 6, 7, 17 |
| Reference-word heuristic | Task 1 |
| Tests | Tasks 1-7 (helpers + validation); 8-10 (prepDataContainer); 18 (shinytest2 smoke) |
| Acceptance criteria (test count, R CMD check, manual smoke) | Tasks 19, 20 |
| Followups doc | Task 20 |

**Placeholder scan:** No `TBD`/`TODO`/`fill in details`/`similar to Task N` strings. All test-bodies and impl-bodies fully specified inline.

**Type consistency:**
- `comparisons_spec` field names are identical across all uses (`meta_column`, `treatment_level`, `control_level`, `treatment_samples`, `control_samples`, `treatment_label`, `control_label`, `de_method`, `method_params`, `covariates`).
- `validate_comparison` record shape (`field`, `ok`, `message`, `severity`) consistent across Tasks 6, 7, 17.
- `iid()` closure consistently means `paste0(name, "_", i)` and is wrapped with `session$ns(...)` only when emitted into the UI tree (not when used as `input[[]]` or `output[[]]` keys, where the moduleServer namespace is automatic). Verified across Tasks 13-17.
- Module return list keys (`n_comparisons`, `start_de`, `is_ready`, `comparisons_spec`) match exactly between Task 12 (where they're returned) and Task 18 (where they're consumed in server.R: `sel()$n_comparisons()`, `sel()$start_de()`, `sel()$comparisons_spec()`).

No issues found.
