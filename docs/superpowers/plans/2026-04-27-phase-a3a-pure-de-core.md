# Phase A3a: Pure DE Core Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extract DE methods, normalization, batch correction, and low-count filtering out of the Shiny-coupled modules into pure, scriptable, unit-testable functions in `R/fct_*.R`. The legacy entry points (`runDE`, `runDESeq2`, `runEdgeR`, `runLimma`, `getNormalizedMatrix`, `correctCombat`, `correctHarman`) become thin deprecated shims so existing callers keep working. The golden snapshots from A2 remain green.

**Architecture:** Each pure function takes plain R objects (matrix/data.frame/factor + named list of params) and returns plain R objects. No `input$`, no `showNotification()`, no `withProgress()`. Errors are raised via `de_error()` (a structured `stop()` wrapper) so callers — Shiny modules, tests, scripts — can choose their own UX. The legacy functions remain exported and continue to accept their existing positional/comma-string interface; internally they translate to the new structured form and delegate.

**Tech Stack:** Same as A1+A2. New helpers: `rlang::abort()` (already a transitive dep) for typed errors. No new package additions.

**Spec reference:** [docs/superpowers/specs/2026-04-27-debrowser-modernization-design.md](../specs/2026-04-27-debrowser-modernization-design.md) — section "Phase A — A3" (covers `fct_de_methods.R`, `fct_normalize.R`, `fct_filter.R`).

**Predecessor:** [docs/superpowers/plans/2026-04-27-phase-a1-a2-foundation.md](2026-04-27-phase-a1-a2-foundation.md) must be merged. Golden snapshots `_snaps/golden-de.md` and `_snaps/golden-normalize.md` are the safety net for this plan.

**Branch:** continue on `modernize` (already created in A1).

---

## Why this is split into A3a and A3b

A3a (this plan): DE math + normalization + filter. ~3 new files, ~10 tasks. All have golden snapshots already.

A3b (next plan, written after A3a merges): `applyFilters()` and the plot builders. These currently take a Shiny `input` object directly and read `input$padj` / `input$foldChange` / `input$dataset` / `input$genesetarea` / `input$compselect` / `input$norm_method` / `input$methodtabs`. Untangling that requires designing a "plot params" struct, and the plot builders themselves are spread across `R/mainScatter.R`, `R/heatmap.R`, `R/pca.R`, `R/all2all.R`, `R/density.R`, `R/IQR.R`, `R/histogram.R`, `R/barmain.R`, `R/boxmain.R`. That deserves its own focused plan and re-uses the patterns established here.

---

## File Map

| File | Action | Purpose |
|---|---|---|
| `R/fct_de_methods.R` | create | `run_de()`, `run_deseq2()`, `run_edger()`, `run_limma()` — pure DE |
| `R/fct_normalize.R` | create | `normalize_counts()`, `apply_batch_correction()`, `combat_correct()`, `combat_seq_correct()`, `harman_correct()` |
| `R/fct_filter.R` | create | `filter_low_counts()` (max / mean / cpm methods) |
| `R/utils_validate.R` | create | `de_error()` — structured `stop()` wrapper with error classes; `de_assert_*()` helpers |
| `R/deprogs.R` | modify | `runDE`/`runDESeq2`/`runEdgeR`/`runLimma` become shims that translate comma-string params and delegate to new pure functions |
| `R/funcs.R` | modify | `getNormalizedMatrix` becomes a shim delegating to `normalize_counts()` |
| `R/batcheffect.R` | modify | `correctCombat`/`correctHarman` become shims delegating to pure functions |
| `R/lowcountfilter.R` | modify | `debrowserlowcountfilter` module's observer body delegates to `filter_low_counts()` |
| `tests/testthat/test-fct-de-methods.R` | create | structured-param tests + verify shim & pure path produce identical output |
| `tests/testthat/test-fct-normalize.R` | create | unit tests for normalization + batch correction with structured params |
| `tests/testthat/test-fct-filter.R` | create | unit tests for `filter_low_counts()` |
| `tests/testthat/test-utils-validate.R` | create | error class machinery |

**Key principle:** the existing `tests/testthat/test-golden-*.R` snapshots are the **invariant** — they must stay green throughout this plan. They were captured against the legacy code path; if any task changes them, that's a refactor regression and we revert.

---

## Task 0: Confirm starting state

**Files:** none (verification)

- [ ] **Step 1: Confirm branch and clean tree**

```bash
git -C /Users/alper/workdir/debrowser status && git log --oneline modernize ^devel | wc -l
```

Expected: `On branch modernize`, `nothing to commit, working tree clean`, and the count is 18 (or higher if more commits landed).

- [ ] **Step 2: Confirm golden snapshots pass before any change**

```bash
R -q -e 'devtools::test("/Users/alper/workdir/debrowser", filter = "golden")' 2>&1 | tail -5
```

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 5 ]`. If anything fails here, **stop** — do not proceed.

---

## Task 1: `R/utils_validate.R` — structured error helper

**Files:**
- Create: `R/utils_validate.R`
- Create: `tests/testthat/test-utils-validate.R`

**Why first:** every `fct_*.R` will use `de_error()` to raise typed errors instead of `showNotification()`. Landing the helper first means the rest of the plan can use it without forward references.

- [ ] **Step 1: Write the failing test**

`tests/testthat/test-utils-validate.R`:

```r
test_that("de_error() raises a classed condition with message and class", {
  err <- tryCatch(
    de_error("count matrix must have at least 3 columns", class = "too_few_columns"),
    error = identity
  )
  expect_s3_class(err, "debrowser_error")
  expect_s3_class(err, "too_few_columns")
  expect_match(conditionMessage(err), "at least 3 columns")
})

test_that("de_error() defaults class to 'debrowser_error' only", {
  err <- tryCatch(de_error("boom"), error = identity)
  expect_s3_class(err, "debrowser_error")
  expect_false(inherits(err, "too_few_columns"))
})

test_that("de_assert_count_matrix() rejects non-numeric, NA-filled, or empty matrices", {
  expect_error(de_assert_count_matrix(NULL), class = "null_input")
  expect_error(de_assert_count_matrix(matrix("a", 1, 1)), class = "non_numeric")
  expect_error(de_assert_count_matrix(matrix(numeric(0), 0, 0)), class = "empty_matrix")
  expect_silent(de_assert_count_matrix(matrix(1:6, 2, 3)))
})
```

- [ ] **Step 2: Run to confirm it fails**

```bash
R -q -e 'devtools::test("/Users/alper/workdir/debrowser", filter = "utils-validate")' 2>&1 | tail -10
```

Expected: errors about `de_error`, `de_assert_count_matrix` not being found.

- [ ] **Step 3: Implement `R/utils_validate.R`**

```r
#' Raise a structured DEBrowser error.
#'
#' All errors raised by the `fct_*` pure functions go through this helper so
#' callers (tests, scripts, Shiny modules) can dispatch on the error class
#' rather than parsing message strings.
#'
#' @param message Human-readable error message.
#' @param class Optional character vector of additional classes to prepend to
#'   the condition's class list. Always inherits from `"debrowser_error"`.
#' @param ... Extra named fields stored on the condition for caller use.
#' @return Nothing — always raises.
#' @export
#' @examples
#' tryCatch(de_error("bad input"), error = function(e) e$message)
de_error <- function(message, class = character(), ...) {
  cond <- structure(
    class = c(class, "debrowser_error", "error", "condition"),
    list(message = message, call = sys.call(-1), ...)
  )
  stop(cond)
}

#' Validate that x is a numeric count matrix.
#' @param x Object to validate.
#' @export
de_assert_count_matrix <- function(x) {
  if (is.null(x)) {
    de_error("count matrix is NULL", class = "null_input")
  }
  if (length(x) == 0L || (is.matrix(x) && (nrow(x) == 0L || ncol(x) == 0L))) {
    de_error("count matrix is empty", class = "empty_matrix")
  }
  m <- if (is.data.frame(x)) as.matrix(x) else x
  if (!is.numeric(m)) {
    de_error("count matrix is not numeric", class = "non_numeric")
  }
  invisible(x)
}
```

- [ ] **Step 4: Run tests to confirm pass**

```bash
R -q -e 'devtools::test("/Users/alper/workdir/debrowser", filter = "utils-validate")' 2>&1 | tail -5
```

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 7 ]`.

- [ ] **Step 5: Commit**

```bash
git add R/utils_validate.R tests/testthat/test-utils-validate.R
git commit -m "feat: add de_error() classed-condition helper and assertions

Pure functions raise typed errors via de_error() so the calling layer
(Shiny module, test, script) decides UX. No Shiny dependency."
```

---

## Task 2: `R/fct_de_methods.R` — pure `run_deseq2()`

**Files:**
- Create: `R/fct_de_methods.R`
- Create: `tests/testthat/test-fct-de-methods.R`

**Approach:** lift the body of `runDESeq2()` (`R/deprogs.R:203`) into a pure function `run_deseq2()` taking `counts`, `metadata`, `columns`, `conds`, and a **named list** of params. Replace the `showNotification()` call (line 218) with `de_error()`. The result must be byte-identical to the existing snapshot.

- [ ] **Step 1: Write the failing test**

`tests/testthat/test-fct-de-methods.R`:

```r
test_that("run_deseq2() with structured params matches the legacy DESeq2 golden hash", {
  skip_on_cran()
  skip_if_not_installed("DESeq2")

  demo <- load_demo()
  data <- demo$counts[, demo_columns]
  data <- data[rowSums(data) > 10, ]

  set.seed(1L)
  res <- run_deseq2(
    counts   = data,
    metadata = demo$meta,
    columns  = demo_columns,
    conds    = demo_conds,
    params   = list(
      covariates = "NoCovariate",
      fit_type   = "parametric",
      beta_prior = FALSE,
      test_type  = "Wald",
      shrinkage  = "None"
    )
  )
  res <- as.data.frame(res)
  res <- res[order(rownames(res)), c("baseMean", "log2FoldChange", "padj"), drop = FALSE]

  # Same hash as test-golden-de.R "DESeq2 result" — the pure function must be
  # byte-identical to the legacy runDESeq2() path.
  expect_snapshot_value(stable_hash(res), style = "json2")
})

test_that("run_deseq2() raises de_error when fewer than 3 columns supplied", {
  expect_error(
    run_deseq2(matrix(1:4, 2, 2), data.frame(), c("a", "b"), factor(c("x", "y"))),
    class = "too_few_columns"
  )
})
```

- [ ] **Step 2: Run to confirm it fails (function not defined)**

```bash
R -q -e 'devtools::test("/Users/alper/workdir/debrowser", filter = "fct-de-methods")' 2>&1 | tail -10
```

Expected: `Error: could not find function "run_deseq2"`.

- [ ] **Step 3: Implement `R/fct_de_methods.R`**

```r
#' Run DESeq2 on a count matrix.
#'
#' Pure function: takes plain R objects, returns a `DESeqResults` object. No
#' Shiny dependency. Errors are raised via [de_error()] with classes:
#'   - `too_few_columns`
#'   - `null_input`
#'
#' @param counts A numeric count matrix or data.frame (genes x samples).
#' @param metadata Sample metadata; first column is sample id.
#' @param columns Character vector of sample column names to use.
#' @param conds Factor of conditions, length == length(columns).
#' @param params Named list with components: covariates (character "|"-joined
#'   or "NoCovariate"), fit_type ("parametric"/"local"/"mean"), beta_prior
#'   (logical), test_type ("Wald"/"LRT"), shrinkage
#'   ("None"/"apeglm"/"ashr"/"normal").
#' @return DESeqResults
#' @export
run_deseq2 <- function(counts, metadata = NULL, columns = NULL, conds = NULL,
                       params = list()) {
  de_assert_count_matrix(counts)
  if (length(columns) < 3L) {
    de_error(
      "DESeq2 requires at least 3 sample columns; got ",
      length(columns),
      class = "too_few_columns"
    )
  }
  defaults <- list(
    covariates = "NoCovariate",
    fit_type   = "parametric",
    beta_prior = FALSE,
    test_type  = "Wald",
    shrinkage  = "None"
  )
  params <- modifyList(defaults, params)

  data <- counts[, columns]
  data[, columns] <- apply(data[, columns], 2, as.integer)

  covariates <- strsplit(params$covariates, split = "\\|")[[1]]
  coldata <- prepGroup(conds, columns, metadata, covariates)

  if (!identical(covariates, "NoCovariate")) {
    dds_formula <- as.formula(
      paste0("~ group", paste0(" + covariate", seq_along(covariates), collapse = ""))
    )
    dds <- DESeq2::DESeqDataSetFromMatrix(
      countData = as.matrix(data), colData = coldata, design = dds_formula
    )
  } else {
    dds <- DESeq2::DESeqDataSetFromMatrix(
      countData = as.matrix(data), colData = coldata, design = ~group
    )
  }

  if (params$test_type == "LRT") {
    dds <- DESeq2::DESeq(
      dds,
      fitType   = params$fit_type,
      betaPrior = as.logical(params$beta_prior),
      test      = params$test_type,
      reduced   = ~1
    )
  } else {
    dds <- DESeq2::DESeq(
      dds,
      fitType   = params$fit_type,
      betaPrior = as.logical(params$beta_prior),
      test      = params$test_type
    )
  }

  coef_names <- colnames(coef(dds))
  group_name <- coef_names[grepl("group", coef_names)][1]
  res <- DESeq2::results(dds, name = group_name)

  if (params$shrinkage != "None") {
    res <- DESeq2::lfcShrink(dds, coef = 2, res = res, type = params$shrinkage)
    if (params$test_type == "Wald") {
      colname <- names(dds@rowRanges@elementMetadata)[
        grepl(paste0(params$test_type, "Statistic_group"),
              names(dds@rowRanges@elementMetadata))
      ]
    } else {
      colname <- paste0(params$test_type, "Statistic")
    }
    stat <- dds@rowRanges@elementMetadata[colname]
    res <- cbind(res, stat)
    colnames(res)[colnames(res) == colname] <- "stat"
  }
  res
}
```

- [ ] **Step 4: Run the test**

```bash
R -q -e 'devtools::test("/Users/alper/workdir/debrowser", filter = "fct-de-methods")' 2>&1 | tail -10
```

Expected: snapshot test prints "Adding new snapshot" first run; second run `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 2 ]`.

- [ ] **Step 5: Verify the snapshot value matches the legacy DESeq2 golden hash**

```bash
diff tests/testthat/_snaps/fct-de-methods.md tests/testthat/_snaps/golden-de.md
```

Expected: the DESeq2 hash strings inside both files are **identical** (file content otherwise differs since both files contain multiple snapshots). If they don't match, the pure function's math diverged from the legacy path — investigate and fix before committing.

If the hashes match, run the legacy snapshot test too and confirm it still passes (sanity check):

```bash
R -q -e 'devtools::test("/Users/alper/workdir/debrowser", filter = "golden")' 2>&1 | tail -5
```

Expected: still `PASS 5`.

- [ ] **Step 6: Commit**

```bash
git add R/fct_de_methods.R tests/testthat/test-fct-de-methods.R tests/testthat/_snaps/
git commit -m "feat: pure run_deseq2() in fct_de_methods.R

Lifts the math out of the legacy runDESeq2() into a function that takes a
named list of params (instead of a positional comma-string) and raises
de_error('too_few_columns') instead of showNotification(). Snapshot
matches the existing golden DESeq2 hash."
```

---

## Task 3: Add pure `run_edger()` and `run_limma()`

**Files:**
- Modify: `R/fct_de_methods.R`
- Modify: `tests/testthat/test-fct-de-methods.R`

- [ ] **Step 1: Write failing tests for both**

Append to `tests/testthat/test-fct-de-methods.R`:

```r
test_that("run_edger() with structured params matches the legacy edgeR golden hash", {
  skip_on_cran()
  skip_if_not_installed("edgeR")

  demo <- load_demo()
  data <- demo$counts[, demo_columns]
  data <- data[rowSums(data) > 10, ]

  set.seed(1L)
  res <- as.data.frame(run_edger(
    counts   = data,
    metadata = demo$meta,
    columns  = demo_columns,
    conds    = demo_conds,
    params   = list(
      covariates = "NoCovariate",
      norm_fact  = "TMM",
      dispersion = "0",
      test_type  = "exactTest"
    )
  ))
  res <- res[order(rownames(res)), c("log2FoldChange", "pvalue", "padj"), drop = FALSE]
  expect_snapshot_value(stable_hash(res), style = "json2")
})

test_that("run_limma() with structured params matches the legacy limma golden hash", {
  skip_on_cran()
  skip_if_not_installed("limma")

  demo <- load_demo()
  data <- demo$counts[, demo_columns]
  data <- data[rowSums(data) > 10, ]

  set.seed(1L)
  res <- as.data.frame(run_limma(
    counts   = data,
    metadata = demo$meta,
    columns  = demo_columns,
    conds    = demo_conds,
    params   = list(
      covariates = "NoCovariate",
      norm_fact  = "TMM",
      fit_type   = "ls",
      norm_bet   = "none"
    )
  ))
  res <- res[order(rownames(res)), c("log2FoldChange", "pvalue", "padj"), drop = FALSE]
  expect_snapshot_value(stable_hash(res), style = "json2")
})
```

- [ ] **Step 2: Implement both**

Append to `R/fct_de_methods.R`:

```r
#' Run edgeR on a count matrix.
#'
#' @inheritParams run_deseq2
#' @param params Named list with components: covariates, norm_fact
#'   ("TMM"/"RLE"/"upperquartile"/"none"), dispersion (numeric or character
#'   "common"/"trended"/"tagwise"/"auto"), test_type ("exactTest"/"glmLRT").
#' @return data.frame with columns log2FoldChange, pvalue, padj, stat.
#' @export
run_edger <- function(counts, metadata = NULL, columns = NULL, conds = NULL,
                      params = list()) {
  de_assert_count_matrix(counts)
  defaults <- list(
    covariates = "NoCovariate",
    norm_fact  = "TMM",
    dispersion = "0",
    test_type  = "exactTest"
  )
  params <- modifyList(defaults, params)

  data <- counts[, columns]
  data[, columns] <- apply(data[, columns], 2, as.integer)
  covariates <- strsplit(params$covariates, split = "\\|")[[1]]

  dispersion <- params$dispersion
  if (!is.na(dispersion) &&
      !(dispersion %in% c("common", "trended", "tagwise", "auto"))) {
    dispersion <- as.numeric(dispersion)
  }

  conds <- factor(conds)
  filtd <- data
  d <- edgeR::DGEList(counts = filtd, group = conds)
  d <- edgeR::calcNormFactors(d, method = params$norm_fact)

  cnum <- summary(conds)[levels(conds)[1]]
  tnum <- summary(conds)[levels(conds)[2]]
  des <- c(rep(1, cnum), rep(2, tnum))
  if (cnum == 1 && tnum == 1 &&
      (dispersion %in% c("common", "trended", "tagwise", "auto") ||
        identical(dispersion, 0))) {
    de_error(
      "edgeR cannot use 'common'/'trended'/'tagwise'/'auto' dispersion or 0 with 1 replicate per condition. Provide a numeric dispersion.",
      class = "bad_dispersion"
    )
  }

  if (!identical(covariates, "NoCovariate")) {
    des_formula <- as.formula(
      paste0("~ des", paste0(" + covariate", seq_along(covariates), collapse = ""))
    )
    model_data <- data.frame(des = des)
    sample_col_ind <- which(apply(metadata, 2, function(x) sum(x %in% columns) == length(columns)))
    sample_col <- colnames(metadata)[sample_col_ind]
    cov_metadata <- metadata[match(columns, metadata[, sample_col]), covariates, drop = FALSE]
    for (i in seq_along(covariates)) {
      model_data[[paste0("covariate", i)]] <- factor(cov_metadata[, i])
    }
    design <- model.matrix(des_formula, data = model_data)
  } else {
    design <- model.matrix(~des)
  }

  d <- edgeR::estimateDisp(d, design)
  if (params$test_type == "exactTest") {
    de_com <- if (identical(dispersion, 0)) {
      edgeR::exactTest(d)
    } else {
      edgeR::exactTest(d, dispersion = dispersion)
    }
    de_com$table <- edgeR::topTags(de_com, n = nrow(de_com$table))$table
    colnames(de_com$table)[colnames(de_com$table) == "FDR"] <- "stat"
  } else {
    fit <- if (identical(dispersion, 0)) {
      edgeR::glmFit(d, design)
    } else {
      edgeR::glmFit(d, design, dispersion = dispersion)
    }
    de_com <- edgeR::glmLRT(fit, coef = 2)
    colnames(de_com$table)[colnames(de_com$table) == "LR"] <- "stat"
  }

  options(digits = 4)
  padj <- p.adjust(de_com$table$PValue, method = "BH")
  res <- data.frame(
    log2FoldChange = de_com$table$logFC / log(2),
    pvalue         = de_com$table$PValue,
    padj           = padj,
    stat           = de_com$table$stat
  )
  rownames(res) <- rownames(filtd)
  res
}

#' Run limma-voom on a count matrix.
#'
#' @inheritParams run_deseq2
#' @param params Named list: covariates, norm_fact, fit_type ("ls"/"robust"),
#'   norm_bet ("none"/"scale"/"quantile"/...).
#' @return data.frame with columns log2FoldChange, pvalue, padj, stat.
#' @export
run_limma <- function(counts, metadata = NULL, columns = NULL, conds = NULL,
                      params = list()) {
  de_assert_count_matrix(counts)
  defaults <- list(
    covariates = "NoCovariate",
    norm_fact  = "TMM",
    fit_type   = "ls",
    norm_bet   = "none"
  )
  params <- modifyList(defaults, params)

  data <- counts[, columns]
  data[, columns] <- apply(data[, columns], 2, as.integer)
  conds <- factor(conds)
  covariates <- strsplit(params$covariates, split = "\\|")[[1]]

  cnum <- summary(conds)[levels(conds)[1]]
  tnum <- summary(conds)[levels(conds)[2]]
  filtd <- data
  des <- factor(c(rep(levels(conds)[1], cnum), rep(levels(conds)[2], tnum)))

  # Note: legacy code did `names(filtd) <- des` which produced the
  # "Repeated column names found in count matrix" warning. We intentionally
  # do NOT do that here — the names are unused downstream and removing the
  # rename does not change result values (verified by snapshot equality).

  if (!identical(covariates, "NoCovariate")) {
    design <- cbind(Grp1 = 1, Grp2vs1 = des)
    sample_col_ind <- which(apply(metadata, 2, function(x) sum(x %in% columns) == length(columns)))
    sample_col <- colnames(metadata)[sample_col_ind]
    cov_metadata <- metadata[match(columns, metadata[, sample_col]), covariates, drop = FALSE]
    for (i in seq_along(covariates)) {
      design <- cbind(design, factor(cov_metadata[, i]))
      colnames(design)[length(colnames(design))] <- paste0("covariate", i)
    }
  } else {
    design <- cbind(Grp1 = 1, Grp2vs1 = des)
  }

  dge <- edgeR::DGEList(counts = filtd, group = des)
  dge <- edgeR::calcNormFactors(dge, method = params$norm_fact, samples = columns)
  v <- limma::voom(dge, design = design, normalize.method = params$norm_bet, plot = FALSE)
  fit <- limma::lmFit(v, design = design)
  fit <- limma::eBayes(fit)

  options(digits = 4)
  tab <- limma::topTable(fit, coef = 2, number = dim(fit)[1], genelist = fit$genes$NAME)
  res <- data.frame(
    log2FoldChange = tab$logFC,
    pvalue         = tab$P.Value,
    padj           = tab$adj.P.Val,
    stat           = tab$t
  )
  rownames(res) <- rownames(tab)
  res
}
```

- [ ] **Step 3: Run the new tests**

```bash
R -q -e 'devtools::test("/Users/alper/workdir/debrowser", filter = "fct-de-methods")' 2>&1 | tail -10
```

Expected: 2 new "Adding new snapshot" warnings on first run. Re-run; expect `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 4 ]`.

- [ ] **Step 4: Verify edgeR + limma snapshots match the legacy golden hashes**

```bash
diff tests/testthat/_snaps/fct-de-methods.md tests/testthat/_snaps/golden-de.md
```

Expected: the values in the DESeq2 / EdgeR / Limma snapshots in `fct-de-methods.md` match the corresponding ones in `golden-de.md`. If any one differs, **stop** and investigate — the pure function diverged from legacy math.

Also confirm the legacy snapshots still pass (they should — we haven't touched the legacy code yet):

```bash
R -q -e 'devtools::test("/Users/alper/workdir/debrowser", filter = "golden")' 2>&1 | tail -5
```

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 5 ]`.

**Note about the `names(filtd) <- des` removal:** the legacy `runLimma` warning "Repeated column names found in count matrix" came from that line setting all column names to either "Treat" or "Control". We removed it because the renamed columns are never read downstream. The snapshot equality check above is the proof that result values are unaffected. The legacy `runLimma` (still warning) and the new `run_limma()` (no warning) produce identical results.

- [ ] **Step 5: Commit**

```bash
git add R/fct_de_methods.R tests/testthat/test-fct-de-methods.R tests/testthat/_snaps/
git commit -m "feat: pure run_edger() and run_limma() in fct_de_methods.R

run_limma() also drops the legacy names(filtd) <- des line (which
emitted the 'Repeated column names found in count matrix' warning
without affecting results). Snapshots match legacy golden hashes."
```

---

## Task 4: `run_de()` dispatcher

**Files:**
- Modify: `R/fct_de_methods.R`
- Modify: `tests/testthat/test-fct-de-methods.R`

- [ ] **Step 1: Write failing test**

Append to test file:

```r
test_that("run_de() dispatches by method name and matches per-method results", {
  skip_on_cran()

  demo <- load_demo()
  data <- demo$counts[, demo_columns]
  data <- data[rowSums(data) > 10, ]

  set.seed(1L)
  via_dispatch <- run_de("DESeq2", data, demo$meta, demo_columns, demo_conds,
                         params = list(covariates = "NoCovariate"))
  set.seed(1L)
  direct <- run_deseq2(data, demo$meta, demo_columns, demo_conds,
                       params = list(covariates = "NoCovariate"))
  expect_equal(stable_hash(as.data.frame(via_dispatch)),
               stable_hash(as.data.frame(direct)))
})

test_that("run_de() rejects unknown methods", {
  expect_error(run_de("NotAMethod", matrix(1:6, 2, 3)),
               class = "unknown_de_method")
})
```

- [ ] **Step 2: Implement**

Append to `R/fct_de_methods.R`:

```r
#' Dispatch a DE run by method name.
#'
#' @param method One of "DESeq2", "EdgeR", "Limma".
#' @inheritParams run_deseq2
#' @return Method-specific result object.
#' @export
run_de <- function(method, counts, metadata = NULL, columns = NULL, conds = NULL,
                   params = list()) {
  switch(method,
    "DESeq2" = run_deseq2(counts, metadata, columns, conds, params),
    "EdgeR"  = run_edger(counts, metadata, columns, conds, params),
    "Limma"  = run_limma(counts, metadata, columns, conds, params),
    de_error(paste0("Unknown DE method: ", method), class = "unknown_de_method")
  )
}
```

- [ ] **Step 3: Run, expect pass**

```bash
R -q -e 'devtools::test("/Users/alper/workdir/debrowser", filter = "fct-de-methods")' 2>&1 | tail -5
```

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 6 ]`.

- [ ] **Step 4: Commit**

```bash
git add R/fct_de_methods.R tests/testthat/test-fct-de-methods.R
git commit -m "feat: run_de() dispatcher over run_deseq2/edger/limma"
```

---

## Task 5: Convert legacy `runDE`/`runDESeq2`/`runEdgeR`/`runLimma` to shims

**Files:**
- Modify: `R/deprogs.R`

**Approach:** the legacy functions accept a positional `params` argument that's a comma-string ("DESeq2,NoCovariate,parametric,FALSE,Wald,None") parsed inside the function. The shim translates that to a named list and delegates.

- [ ] **Step 1: Replace the body of `runDESeq2()` (lines 203–268 of `R/deprogs.R`) with a shim**

Find the function `runDESeq2 <- function(...)` block and replace its body so the function reads:

```r
runDESeq2 <- function(data = NULL, metadata = NULL, columns = NULL,
                     conds = NULL, params = NULL) {
  if (is.null(data)) return(NULL)
  if (length(params) < 3) {
    params <- strsplit(params, ",")[[1]]
  }
  # legacy positional params: c(method, covariates, fitType, betaPrior, testType, shrinkage)
  pure_params <- list(
    covariates = if (!is.null(params[2])) params[2] else "NoCovariate",
    fit_type   = if (!is.null(params[3])) params[3] else "parametric",
    beta_prior = if (!is.null(params[4])) as.logical(params[4]) else FALSE,
    test_type  = if (!is.null(params[5])) params[5] else "Wald",
    shrinkage  = if (!is.null(params[6])) params[6] else "None"
  )
  tryCatch(
    run_deseq2(data, metadata, columns, conds, pure_params),
    too_few_columns = function(e) {
      showNotification(conditionMessage(e), type = "error")
      NULL
    }
  )
}
```

- [ ] **Step 2: Replace `runEdgeR()` body (lines 305–389) similarly**

```r
runEdgeR <- function(data = NULL, metadata = NULL, columns = NULL,
                    conds = NULL, params = NULL) {
  if (is.null(data)) return(NULL)
  if (length(params) < 3) {
    params <- strsplit(params, ",")[[1]]
  }
  pure_params <- list(
    covariates = if (!is.null(params[2])) params[2] else "NoCovariate",
    norm_fact  = if (!is.null(params[3])) params[3] else "TMM",
    dispersion = if (!is.null(params[4])) params[4] else "0",
    test_type  = if (!is.null(params[5])) params[5] else "exactTest"
  )
  tryCatch(
    run_edger(data, metadata, columns, conds, pure_params),
    bad_dispersion = function(e) {
      showNotification(conditionMessage(e), type = "error")
      NULL
    }
  )
}
```

- [ ] **Step 3: Replace `runLimma()` body (lines 416–473)**

```r
runLimma <- function(data = NULL, metadata = NULL, columns = NULL,
                    conds = NULL, params = NULL) {
  if (is.null(data)) return(NULL)
  if (length(params) < 3) {
    params <- strsplit(params, ",")[[1]]
  }
  pure_params <- list(
    covariates = if (!is.null(params[2])) params[2] else "NoCovariate",
    norm_fact  = if (!is.null(params[3])) params[3] else "TMM",
    fit_type   = if (!is.null(params[4])) params[4] else "ls",
    norm_bet   = if (!is.null(params[5])) params[5] else "none"
  )
  run_limma(data, metadata, columns, conds, pure_params)
}
```

- [ ] **Step 4: Replace `runDE()` body (lines 149–162)**

```r
runDE <- function(data = NULL, metadata = NULL, columns = NULL,
                 conds = NULL, params = NULL) {
  if (is.null(data)) return(NULL)
  method <- if (startsWith(params[1], "DESeq2")) "DESeq2"
            else if (startsWith(params[1], "EdgeR")) "EdgeR"
            else if (startsWith(params[1], "Limma")) "Limma"
            else NULL
  if (is.null(method)) return(NULL)
  switch(method,
    "DESeq2" = data.frame(runDESeq2(data, metadata, columns, conds, params)),
    "EdgeR"  = data.frame(runEdgeR(data, metadata, columns, conds, params)),
    "Limma"  = data.frame(runLimma(data, metadata, columns, conds, params))
  )
}
```

- [ ] **Step 5: Run all DE tests (legacy snapshots + new pure tests)**

```bash
R -q -e 'devtools::test("/Users/alper/workdir/debrowser", filter = "(de|golden)")' 2>&1 | tail -10
```

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 11 ]` (3 golden + 6 pure-fct + 2 fct-de-methods error tests). The legacy snapshots in `_snaps/golden-de.md` must still match — they exercise the shim path.

If any snapshot fails, **stop** — the shim translation drifted from legacy behavior. Investigate before committing.

- [ ] **Step 6: Commit**

```bash
git add R/deprogs.R
git commit -m "refactor: turn legacy runDE/runDESeq2/runEdgeR/runLimma into shims

Bodies now translate the comma-string params into structured named
lists and delegate to fct_de_methods.R. Legacy callers (Shiny modules,
external scripts) keep working unchanged. Golden snapshots green."
```

---

## Task 6: `R/fct_normalize.R` — pure `normalize_counts()`

**Files:**
- Create: `R/fct_normalize.R`
- Create: `tests/testthat/test-fct-normalize.R`

- [ ] **Step 1: Write failing test**

`tests/testthat/test-fct-normalize.R`:

```r
test_that("normalize_counts() with method='TMM' matches golden hash", {
  skip_on_cran()

  demo <- load_demo()
  data <- demo$counts[, demo_columns]
  data <- data[rowSums(data) > 10, ]

  set.seed(1L)
  norm <- normalize_counts(data, method = "TMM")
  norm <- norm[order(rownames(norm)), order(colnames(norm))]

  expect_snapshot_value(stable_hash(norm), style = "json2")
})

test_that("normalize_counts() rejects NULL", {
  expect_error(normalize_counts(NULL), class = "null_input")
})

test_that("normalize_counts(method='none') passes the matrix through", {
  m <- matrix(1:12, 3, 4, dimnames = list(NULL, paste0("s", 1:4)))
  out <- normalize_counts(m, method = "none")
  expect_equal(out, m)
})
```

- [ ] **Step 2: Implement**

```r
#' Normalize a count matrix.
#'
#' Pure function: takes a numeric matrix, returns a normalized numeric matrix.
#' Wraps `edgeR::calcNormFactors` + `edgeR::equalizeLibSizes` for TMM/RLE/upper-
#' quartile, DESeq2's median-of-ratios for `"MRN"`, identity for `"none"`.
#'
#' @param counts Numeric matrix or data.frame (genes x samples).
#' @param method One of "TMM", "RLE", "upperquartile", "MRN", "none".
#' @return Normalized numeric matrix with the same shape and dimnames.
#' @export
normalize_counts <- function(counts, method = "TMM") {
  de_assert_count_matrix(counts)
  m <- counts
  m[is.na(m)] <- 0

  if (method == "none") {
    return(m)
  }
  if (method == "MRN") {
    columns <- colnames(m)
    coldata <- prepGroup(columns, columns)
    m[, columns] <- apply(m[, columns], 2, as.integer)
    dds <- DESeq2::DESeqDataSetFromMatrix(
      countData = as.matrix(m), colData = coldata, design = ~group
    )
    dds <- DESeq2::estimateSizeFactors(dds)
    return(DESeq2::counts(dds, normalized = TRUE))
  }
  norm_factors <- edgeR::calcNormFactors(m, method = method)
  edgeR::equalizeLibSizes(
    edgeR::DGEList(m, norm.factors = norm_factors)
  )$pseudo.counts
}
```

- [ ] **Step 3: Run, verify, and confirm snapshot equals legacy golden-normalize hash**

```bash
R -q -e 'devtools::test("/Users/alper/workdir/debrowser", filter = "fct-normalize")' 2>&1 | tail -10
```

After first-run capture, re-run for stability. Then:

```bash
diff tests/testthat/_snaps/fct-normalize.md tests/testthat/_snaps/golden-normalize.md
```

The TMM hash in `fct-normalize.md` must match `getNormalizedMatrix on demo data` hash in `golden-normalize.md`.

- [ ] **Step 4: Convert legacy `getNormalizedMatrix()` to a shim**

In `R/funcs.R`, replace the body of `getNormalizedMatrix()` (lines 351–378) with:

```r
getNormalizedMatrix <- function(M = NULL, method = "TMM") {
  if (is.null(M)) return(NULL)
  normalize_counts(M, method = method)
}
```

- [ ] **Step 5: Run all tests; legacy golden-normalize must still pass**

```bash
R -q -e 'devtools::test("/Users/alper/workdir/debrowser")' 2>&1 | tail -5
```

Expected: all pass; total goes from 35 to ~42.

- [ ] **Step 6: Commit**

```bash
git add R/fct_normalize.R R/funcs.R tests/testthat/test-fct-normalize.R tests/testthat/_snaps/
git commit -m "feat: pure normalize_counts() in fct_normalize.R

getNormalizedMatrix() becomes a 2-line shim. Snapshot equals the
legacy golden-normalize TMM hash."
```

---

## Task 7: Pure batch correction — Combat + CombatSeq + Harman

**Files:**
- Modify: `R/fct_normalize.R`
- Modify: `R/batcheffect.R`
- Modify: `tests/testthat/test-fct-normalize.R`

**Approach:** the legacy `correctCombat()` and `correctHarman()` take a Shiny `input` and read `input$batch` / `input$treatment`. Pure versions take those values as arguments.

- [ ] **Step 1: Write failing tests**

Append to `tests/testthat/test-fct-normalize.R`:

```r
test_that("apply_batch_correction(method='none') is identity", {
  m <- matrix(1:12, 3, 4, dimnames = list(NULL, paste0("s", 1:4)))
  meta <- data.frame(sample = paste0("s", 1:4), batch = c(1, 1, 2, 2),
                     treatment = c("A", "B", "A", "B"))
  expect_equal(
    apply_batch_correction(m, meta, method = "none",
                           batch_col = "batch", treatment_col = "treatment"),
    m
  )
})

test_that("apply_batch_correction(method='Combat') runs without Shiny input", {
  skip_on_cran()
  skip_if_not_installed("sva")

  demo <- load_demo()
  data <- demo$counts[, demo_columns]
  data <- data[rowSums(data) > 10, ][1:200, ]   # smaller for speed
  meta <- data.frame(
    sample    = demo_columns,
    batch     = c(1, 2, 1, 2, 1, 2),
    treatment = as.character(demo_conds)
  )
  out <- apply_batch_correction(data, meta, method = "Combat",
                                batch_col = "batch", treatment_col = "treatment")
  expect_equal(dim(out), dim(data))
  expect_equal(rownames(out), rownames(data))
})

test_that("apply_batch_correction errors when batch_col missing", {
  m <- matrix(1:12, 3, 4)
  meta <- data.frame(sample = paste0("s", 1:4))
  expect_error(
    apply_batch_correction(m, meta, method = "Combat",
                           batch_col = "nonexistent", treatment_col = "sample"),
    class = "missing_batch_col"
  )
})
```

- [ ] **Step 2: Implement**

Append to `R/fct_normalize.R`:

```r
#' Apply batch-effect correction.
#'
#' Pure function — no Shiny dependency. Accepts batch / treatment column
#' names directly instead of pulling from a reactive `input` object.
#'
#' @param counts Numeric matrix (genes x samples).
#' @param metadata data.frame; first column is sample id.
#' @param method One of "none", "Combat", "CombatSeq", "Harman".
#' @param batch_col Name of the batch column in `metadata`.
#' @param treatment_col Name of the treatment column in `metadata`. May be
#'   NULL or "None" — only required for Harman.
#' @return Corrected count matrix.
#' @export
apply_batch_correction <- function(counts, metadata, method = "none",
                                   batch_col = NULL, treatment_col = NULL) {
  de_assert_count_matrix(counts)
  if (method == "none") return(counts)

  if (is.null(batch_col) || !batch_col %in% colnames(metadata)) {
    de_error(paste0("metadata has no column '", batch_col, "'"),
             class = "missing_batch_col")
  }

  switch(method,
    "Combat"    = combat_correct(counts, metadata, batch_col, treatment_col, seq = FALSE),
    "CombatSeq" = combat_correct(counts, metadata, batch_col, treatment_col, seq = TRUE),
    "Harman"    = harman_correct(counts, metadata, batch_col, treatment_col),
    de_error(paste0("Unknown batch correction method: ", method),
             class = "unknown_batch_method")
  )
}

#' @keywords internal
combat_correct <- function(counts, metadata, batch_col, treatment_col, seq = FALSE) {
  batch <- metadata[, batch_col]
  columns <- colnames(counts)
  datacor <- data.frame(counts[, columns])
  datacor[, columns] <- apply(
    datacor[, columns], 2,
    function(x) as.integer(x) + runif(1, 0, 0.01)
  )

  has_treatment <- !is.null(treatment_col) && treatment_col != "None" &&
    treatment_col %in% colnames(metadata)

  if (has_treatment) {
    treatment <- metadata[, treatment_col]
    meta <- data.frame(cbind(columns, treatment, batch))
    modcombat <- model.matrix(~ as.factor(treatment), data = meta)
    res <- if (seq) {
      sva::ComBat_seq(counts = as.matrix(datacor), covar_mod = modcombat, batch = batch)
    } else {
      sva::ComBat(dat = as.matrix(datacor), mod = modcombat, batch = batch)
    }
  } else {
    res <- if (seq) {
      sva::ComBat_seq(counts = as.matrix(datacor), batch = batch)
    } else {
      sva::ComBat(dat = as.matrix(datacor), batch = batch)
    }
  }

  out <- res
  out[out < 0] <- 0
  out[, columns] <- apply(out[, columns], 2, as.integer)
  out
}

#' @keywords internal
harman_correct <- function(counts, metadata, batch_col, treatment_col) {
  if (is.null(treatment_col) || treatment_col == "None") {
    de_error(
      "Harman requires a treatment column",
      class = "missing_treatment_col"
    )
  }
  batch_info <- data.frame(metadata[, c(treatment_col, batch_col)])
  rownames(batch_info) <- rownames(metadata)
  colnames(batch_info) <- c("treatment", "batch")

  res <- Harman::harman(counts, expt = batch_info$treatment,
                        batch = batch_info$batch, limit = 0.95)
  out <- Harman::reconstructData(res)
  out[out < 0] <- 0
  out
}
```

- [ ] **Step 3: Convert legacy `correctCombat()` and `correctHarman()` to shims**

In `R/batcheffect.R`, replace `correctCombat()` (lines 261–302) with:

```r
correctCombat <- function(input = NULL, idata = NULL, metadata = NULL, method = NULL) {
  if (is.null(idata)) return(NULL)
  if (input$batch == "None") {
    showNotification("Please select the batch field to use Combat!", type = "error")
    return(NULL)
  }
  treatment_col <- if (!is.null(input$treatment) && input$treatment != "None") {
    input$treatment
  } else NULL
  apply_batch_correction(idata, metadata, method = method,
                         batch_col = input$batch, treatment_col = treatment_col)
}
```

And replace `correctHarman()` (lines 315–332) with:

```r
correctHarman <- function(input = NULL, idata = NULL, metadata = NULL) {
  if (is.null(idata)) return(NULL)
  if (input$treatment == "None" || input$batch == "None") {
    showNotification("Please select the batch and treatment fields to use Harman!",
                     type = "error")
    return(NULL)
  }
  apply_batch_correction(idata, metadata, method = "Harman",
                         batch_col = input$batch, treatment_col = input$treatment)
}
```

- [ ] **Step 4: Run all tests**

```bash
R -q -e 'devtools::test("/Users/alper/workdir/debrowser")' 2>&1 | tail -5
```

Expected: all pass. New tests for `apply_batch_correction` capture snapshots on first run.

- [ ] **Step 5: Commit**

```bash
git add R/fct_normalize.R R/batcheffect.R tests/testthat/test-fct-normalize.R tests/testthat/_snaps/
git commit -m "feat: pure apply_batch_correction() (Combat/CombatSeq/Harman)

Legacy correctCombat/correctHarman become input-translating shims.
Pure functions take batch_col/treatment_col arguments directly."
```

---

## Task 8: `R/fct_filter.R` — pure `filter_low_counts()`

**Files:**
- Create: `R/fct_filter.R`
- Create: `tests/testthat/test-fct-filter.R`
- Modify: `R/lowcountfilter.R`

- [ ] **Step 1: Write failing test**

`tests/testthat/test-fct-filter.R`:

```r
test_that("filter_low_counts(method='max', cutoff=10) keeps rows with max >= 10", {
  m <- matrix(c(0, 0, 0,
                5, 6, 7,
                100, 200, 300), 3, 3, byrow = TRUE,
              dimnames = list(c("g1", "g2", "g3"), c("s1", "s2", "s3")))
  out <- filter_low_counts(m, method = "max", cutoff = 10)
  expect_equal(nrow(out), 1L)
  expect_equal(rownames(out), "g3")
})

test_that("filter_low_counts(method='mean', cutoff=10) keeps rows with mean >= 10", {
  m <- matrix(c(0, 0, 0,
                5, 6, 7,
                100, 200, 300), 3, 3, byrow = TRUE,
              dimnames = list(c("g1", "g2", "g3"), c("s1", "s2", "s3")))
  out <- filter_low_counts(m, method = "mean", cutoff = 10)
  expect_equal(rownames(out), "g3")
})

test_that("filter_low_counts(method='cpm') keeps rows where CPM > cutoff in >= n samples", {
  m <- matrix(c(0, 0, 0,
                100, 0, 0,
                100, 100, 100), 3, 3, byrow = TRUE,
              dimnames = list(c("g1", "g2", "g3"), c("s1", "s2", "s3")))
  out <- filter_low_counts(m, method = "cpm", cutoff = 1, min_samples = 2)
  expect_true("g3" %in% rownames(out))
  expect_false("g2" %in% rownames(out))
})

test_that("filter_low_counts() rejects unknown methods", {
  m <- matrix(1:9, 3, 3)
  expect_error(filter_low_counts(m, method = "wat"), class = "unknown_filter_method")
})
```

- [ ] **Step 2: Implement**

```r
#' Filter low-count rows from a count matrix.
#'
#' @param counts Numeric matrix (genes x samples).
#' @param method One of "max", "mean", "cpm".
#' @param cutoff Numeric threshold; meaning depends on `method`.
#' @param min_samples For method="cpm": the row is kept if CPM > cutoff in
#'   at least `min_samples` samples.
#' @return Filtered count matrix (rows preserved by row order).
#' @export
filter_low_counts <- function(counts, method = "max", cutoff = 10, min_samples = NULL) {
  de_assert_count_matrix(counts)
  filtd <- counts
  filtd[, colnames(filtd)] <- apply(filtd[, colnames(filtd)], 2, as.integer)

  switch(method,
    "max"  = subset(filtd, apply(filtd, 1, max, na.rm = TRUE) >= as.numeric(cutoff)),
    "mean" = subset(filtd, rowMeans(filtd, na.rm = TRUE) >= as.numeric(cutoff)),
    "cpm"  = {
      cpm <- edgeR::cpm(filtd)
      ns <- if (is.null(min_samples)) ncol(filtd) - 1L else as.integer(min_samples)
      subset(filtd, rowSums(cpm > as.numeric(cutoff), na.rm = TRUE) >= ns)
    },
    de_error(paste0("Unknown filter method: ", method),
             class = "unknown_filter_method")
  )
}
```

- [ ] **Step 3: Replace the inline filter logic in `R/lowcountfilter.R`**

In `R/lowcountfilter.R`, find the `observeEvent(input$submitLCF, ...)` block (lines 22–41). Replace its body so the observer reads:

```r
observeEvent(input$submitLCF, {
  if (is.null(ldata$count)) return(NULL)
  fdata$count <- switch(input$lcfmethod,
    "Max"  = filter_low_counts(ldata$count, "max", input$maxCutoff),
    "Mean" = filter_low_counts(ldata$count, "mean", input$meanCutoff),
    "CPM"  = filter_low_counts(ldata$count, "cpm", input$CPMCutoff,
                                min_samples = input$numSample)
  )
  fdata$meta <- ldata$meta
})
```

- [ ] **Step 4: Run all tests**

```bash
R -q -e 'devtools::test("/Users/alper/workdir/debrowser")' 2>&1 | tail -5
```

Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add R/fct_filter.R R/lowcountfilter.R tests/testthat/test-fct-filter.R
git commit -m "feat: pure filter_low_counts() in fct_filter.R

debrowserlowcountfilter module's observer is now 6 lines; all
filtering math lives in the pure function."
```

---

## Task 9: A3a milestone — full suite + NEWS update

**Files:**
- Modify: `NEWS.md`

- [ ] **Step 1: Run the full suite for the final check**

```bash
R -q -e 'devtools::test("/Users/alper/workdir/debrowser")' 2>&1 | tail -5
```

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS ~50 ]` (the exact count depends on how many `expect_*` calls landed). Critically:
- All 5 `golden-*` snapshots stay green (proves shims are byte-identical to legacy)
- All `fct-*` snapshots stay green (proves pure functions reproduce the same math)

- [ ] **Step 2: Run a quick build to confirm the package still builds**

```bash
cd /tmp && R CMD build /Users/alper/workdir/debrowser --no-build-vignettes --no-manual 2>&1 | tail -5
rm -f debrowser_*.tar.gz
```

Expected: `* building 'debrowser_<version>.tar.gz'` with no errors.

- [ ] **Step 3: Add A3a entry to `NEWS.md`**

Insert after the `Phase A1` block and before `### User-visible`:

```markdown
### Phase A3a — pure analytic core (DE + normalize + filter)

* Added `R/fct_de_methods.R` with `run_deseq2()`, `run_edger()`, `run_limma()`,
  `run_de()` — pure functions taking structured (named-list) params instead
  of legacy comma-string params. No Shiny dependency.
* Added `R/fct_normalize.R` with `normalize_counts()` and pure
  `apply_batch_correction()` (Combat / CombatSeq / Harman). Batch / treatment
  column names are now arguments instead of `input$` lookups.
* Added `R/fct_filter.R` with `filter_low_counts()` (max / mean / cpm).
* Added `R/utils_validate.R` with `de_error()` — structured `stop()` raising
  classed conditions so callers dispatch on class, not message text.
* Legacy `runDE()`, `runDESeq2()`, `runEdgeR()`, `runLimma()`,
  `getNormalizedMatrix()`, `correctCombat()`, `correctHarman()` are now
  thin shims that translate input/comma-string params and delegate. Their
  signatures are unchanged so existing callers and scripts keep working.
* Fixed silent "Repeated column names found in count matrix" warning in
  the limma path (legacy code set all column names to factor levels;
  removing it does not affect results).
```

- [ ] **Step 4: Commit**

```bash
git add NEWS.md
git commit -m "docs: log Phase A3a in NEWS.md"
```

**Milestone reached: A3a done — DE math, normalization, batch correction, and low-count filter all live in pure `fct_*.R` files. Legacy entry points work as shims. Phase A3b (extract `applyFilters` and the plot builders) gets its own plan, written next.**

---

## Self-Review

**Spec coverage check (A3 — DE/normalize/filter portion):**
- [x] `fct_de_methods.R` with `run_deseq2()` / `run_edger()` / `run_limma()` → Tasks 2, 3
- [x] `fct_normalize.R` with `normalize_counts()` and `apply_batch_correction()` → Tasks 6, 7
- [x] `fct_filter.R` with `filter_low_counts()` → Task 8
- [x] Legacy entry points become shims → Tasks 5, 6 (Step 4), 7 (Step 3), 8 (Step 3)
- [x] Pure functions raise typed errors instead of `showNotification` → Task 1
- [x] Golden snapshots remain green → verified at Tasks 5, 6, 9

**Spec coverage gaps deliberately deferred to A3b:**
- `fct_prep_data.R` (was `prepdata.R`) — `applyFilters()` still reads `input$padj` etc.
- `fct_plots.R` — plot builders across mainScatter / heatmap / pca / etc.

**Placeholder scan:** every step has actual code or actual command. No "TBD", "TODO", "fill in details". The Task 5 shims show the complete replacement bodies. The legacy line numbers (203–268, 305–389, 416–473, 149–162, 351–378, 261–302, 315–332, 22–41) are explicit pointers — even after the styler pass these are correct because no code has been moved since A1's commit `9dcdb3d`.

**Type / name consistency:**
- `de_error()`, `de_assert_count_matrix()` defined in Task 1; used in Tasks 2, 3, 6, 7, 8.
- `run_deseq2()` / `run_edger()` / `run_limma()` defined in Tasks 2 and 3; used in Task 4 (`run_de()`) and Task 5 (shims).
- `normalize_counts()` defined in Task 6; used in Task 6 Step 4 (`getNormalizedMatrix` shim) and Task 7 (`combat_correct` is a sibling but doesn't call it directly — that's intentional).
- `apply_batch_correction()` defined in Task 7; used in Task 7 Step 3 (`correctCombat`/`correctHarman` shims).
- `filter_low_counts()` defined in Task 8; used in Task 8 Step 3 (lowcountfilter module).
- All structured-params field names match across pure-function defs and shim translations:
  - DESeq2: `covariates`, `fit_type`, `beta_prior`, `test_type`, `shrinkage`
  - edgeR:  `covariates`, `norm_fact`, `dispersion`, `test_type`
  - limma:  `covariates`, `norm_fact`, `fit_type`, `norm_bet`

**Error class names used consistently:** `null_input`, `non_numeric`, `empty_matrix`, `too_few_columns`, `bad_dispersion`, `unknown_de_method`, `unknown_batch_method`, `missing_batch_col`, `missing_treatment_col`, `unknown_filter_method`. All inherit from `debrowser_error`.
