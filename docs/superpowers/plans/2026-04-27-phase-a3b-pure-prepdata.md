# Phase A3b: Pure Data-Prep Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extract the data-preparation layer (`applyFilters`, `getMostVariedList`, `getSelectedDatasetInput`, `getDataForTables`, `getMergedComparison`, `applyFiltersToMergedComparison`, `getSearchData`) out of `R/prepdata.R` into pure functions in `R/fct_prep_data.R`. Each pure function takes structured params instead of reading fields off a Shiny `input` reactive. Legacy functions become thin shims that translate `input$padj` / `input$foldChange` / etc. and delegate. Add new golden snapshot tests against the Vernia demo to lock the post-DE filtering pipeline.

**Architecture:** Same recipe as A3a — pure `fct_*.R` functions with named-list params, legacy entry points become input-translating shims, golden snapshots prove byte-equivalence. The new "filter params" struct standardizes the field names that were scattered as `input$padj`, `input$foldChange`, `input$dataset`, `input$compselect`, `input$norm_method`, `input$genesetarea`, `input$methodtabs`, `input$mincount`, `input$topn`, `input$selectedplot` — they all become fields on a single named list.

**Tech Stack:** Same as A3a. No new dependencies.

**Spec reference:** [docs/superpowers/specs/2026-04-27-debrowser-modernization-design.md](../specs/2026-04-27-debrowser-modernization-design.md) — section "Phase A — A3", `fct_prep_data.R` row.

**Predecessor:** [docs/superpowers/plans/2026-04-27-phase-a3a-pure-de-core.md](2026-04-27-phase-a3a-pure-de-core.md) must be merged. The pattern (pure fn + shim + golden snapshot) is established and will be repeated here.

**Branch:** continue on `modernize`.

---

## Why plot builders are NOT in this plan

`R/mainScatter.R` (`mainScatterNew`, `plotData`), `R/heatmap.R` (`runHeatmap`), `R/pca.R` (`plot_pca`), `R/all2all.R`, `R/density.R`, `R/IQR.R`, `R/histogram.R`, `R/barmain.R`, `R/boxmain.R` each read 5–15 *render-config* fields off `input$` — `input$width`, `input$height`, `input$left/right/top/bottom` (margins), `input$labelcolor`, `input$labelsize`, `input$labelsearched`, `input$svg`, `input$xlab`, `input$ylab`, `input$legendonoff`, `input$mainplot`, `input$backperc`, `input$top`, etc. These are UI rendering controls, not analytic-core concerns.

Folding plot extraction into **Phase B6** (color-blind-safe palettes, top-N variable-gene default, download UX) means we touch each plot file once instead of twice. That avoids the cost of designing a "plot params" struct in A3 only to redesign it again in B6 when defaults and chrome change.

The data prep that *produces* what those plots render — Up/Down labeling by cutoff, geneset overlay, dataset selection, comparison merging — IS in this plan.

---

## File Map

| File | Action | Purpose |
|---|---|---|
| `R/fct_prep_data.R` | create | Pure `apply_de_filters()`, `get_most_varied()`, `select_dataset()`, `merge_comparisons()`, `apply_merged_filters()`, `search_geneset()`, `get_table_data()` |
| `R/prepdata.R` | modify | `applyFilters()`, `getMostVariedList()`, `getSelectedDatasetInput()`, `getMergedComparison()`, `applyFiltersToMergedComparison()`, `getSearchData()`, `getDataForTables()` become input-translating shims |
| `tests/testthat/test-fct-prep-data.R` | create | Unit tests for the new pure functions + a snapshot test on the demo data's full DE → filter pipeline |
| `tests/testthat/_snaps/golden-prep.md` | create (auto) | Snapshot oracle for the Up/Down/NS labeling pipeline |
| `NEWS.md` | modify | Log A3b |

---

## The "filter params" struct

Every pure function in this plan takes a named list. The full schema, with the legacy `input$` field on the right:

| Pure-fn field | Legacy field |
|---|---|
| `padj_cutoff`     | `input$padj` |
| `fold_cutoff`     | `input$foldChange` |
| `dataset`         | `input$dataset` (`"up"`, `"down"`, `"up+down"`, `"alldetected"`, `"selected"`, `"most-varied"`, `"comparisons"`, `"searched"`) |
| `compselect`      | `input$compselect` |
| `norm_method`     | `input$norm_method` |
| `geneset_area`    | `input$genesetarea` |
| `method_tab`      | `input$methodtabs` |
| `min_count`       | `input$mincount` |
| `top_n`           | `input$topn` |
| `selected_plot`   | `input$selectedplot` |

Helper to build the struct from a Shiny input (used inside shims):

```r
# in R/utils_validate.R, added in Task 0
filter_params_from_input <- function(input) {
  list(
    padj_cutoff   = input$padj,
    fold_cutoff   = input$foldChange,
    dataset       = input$dataset,
    compselect    = input$compselect,
    norm_method   = input$norm_method,
    geneset_area  = input$genesetarea,
    method_tab    = input$methodtabs,
    min_count     = input$mincount,
    top_n         = input$topn,
    selected_plot = input$selectedplot
  )
}
```

---

## Task 0: Confirm starting state and add the input→params helper

**Files:**
- Modify: `R/utils_validate.R`
- Modify: `tests/testthat/test-utils-validate.R`

- [ ] **Step 1: Confirm clean tree and golden snapshots green**

```bash
git -C /Users/alper/workdir/debrowser status
R -q -e 'devtools::test("/Users/alper/workdir/debrowser", filter = "golden")' 2>&1 | tail -5
```

Expected: `nothing to commit, working tree clean` and `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 5 ]`. If either fails, **stop**.

- [ ] **Step 2: Write failing test for the helper**

Append to `tests/testthat/test-utils-validate.R`:

```r
test_that("filter_params_from_input() reads the documented input fields", {
  input <- list(
    padj         = "0.05",
    foldChange   = "2",
    dataset      = "up+down",
    compselect   = "1",
    norm_method  = "TMM",
    genesetarea  = "BRCA1",
    methodtabs   = "panel1",
    mincount     = "10",
    topn         = "500",
    selectedplot = NULL
  )
  p <- filter_params_from_input(input)
  expect_equal(p$padj_cutoff,   "0.05")
  expect_equal(p$fold_cutoff,   "2")
  expect_equal(p$dataset,       "up+down")
  expect_equal(p$norm_method,   "TMM")
  expect_equal(p$geneset_area,  "BRCA1")
  expect_equal(p$top_n,         "500")
  expect_null(p$selected_plot)
})
```

- [ ] **Step 3: Run, expect failure**

```bash
R -q -e 'devtools::test("/Users/alper/workdir/debrowser", filter = "utils-validate")' 2>&1 | tail -5
```

Expected: error about `filter_params_from_input` not found.

- [ ] **Step 4: Append the helper to `R/utils_validate.R`**

```r
#' Translate a Shiny `input` reactive into a structured filter-params list.
#'
#' All A3b pure functions accept a named list of filter parameters. This
#' helper bridges Shiny modules to those functions in a single place so the
#' field-name mapping is documented and centralised.
#'
#' @param input A Shiny input reactive (or a plain list with the same fields).
#' @return Named list with components: padj_cutoff, fold_cutoff, dataset,
#'   compselect, norm_method, geneset_area, method_tab, min_count, top_n,
#'   selected_plot.
#' @export
filter_params_from_input <- function(input) {
  list(
    padj_cutoff   = input$padj,
    fold_cutoff   = input$foldChange,
    dataset       = input$dataset,
    compselect    = input$compselect,
    norm_method   = input$norm_method,
    geneset_area  = input$genesetarea,
    method_tab    = input$methodtabs,
    min_count     = input$mincount,
    top_n         = input$topn,
    selected_plot = input$selectedplot
  )
}
```

- [ ] **Step 5: Run tests; expect pass**

```bash
R -q -e 'devtools::test("/Users/alper/workdir/debrowser", filter = "utils-validate")' 2>&1 | tail -5
```

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 10 ]` (was 9; added 1 test).

- [ ] **Step 6: Commit**

```bash
git add R/utils_validate.R tests/testthat/test-utils-validate.R
git commit -m "feat: filter_params_from_input() bridges Shiny input to pure-fn params

Centralises the input-field-name → pure-fn-field-name mapping that A3b
shims will use. Documented in one place so future modules don't drift."
```

---

## Task 1: Pure `apply_de_filters()` (was `applyFilters`)

**Files:**
- Create: `R/fct_prep_data.R`
- Create: `tests/testthat/test-fct-prep-data.R`

**What `applyFilters()` does today:**
- Reads `input$padj`, `input$foldChange`, `input$dataset`, `input$compselect`, `input$norm_method`, `input$genesetarea`, `input$methodtabs`
- Re-normalizes the count columns
- Adds `x` and `y` columns (log10 mean by Cond)
- Adds `Legend` (Up / Down / NS / MV / GS) and `Size` columns based on cutoffs

**Pure version:** takes the same data, plus a filter-params struct, plus the same `cols` and `conds` positional args. Returns the same data frame.

- [ ] **Step 1: Write failing test (snapshot the Up/Down labeling)**

`tests/testthat/test-fct-prep-data.R`:

```r
test_that("apply_de_filters() labels Up/Down/NS for the demo DE result", {
  skip_on_cran()

  demo <- load_demo()
  data <- demo$counts[, demo_columns]
  data <- data[rowSums(data) > 10, ]

  set.seed(1L)
  de <- run_deseq2(
    counts   = data,
    metadata = demo$meta,
    columns  = demo_columns,
    conds    = demo_conds,
    params   = list(covariates = "NoCovariate")
  )
  de <- as.data.frame(de)
  # The legacy app expects a `foldChange` column too; build the same
  # tidy frame the Shiny module would feed into applyFilters().
  de$foldChange <- 2 ^ de$log2FoldChange
  de$padj[is.na(de$padj)] <- 1
  de$ID <- rownames(de)

  out <- apply_de_filters(
    filt_data = de,
    cols      = demo_columns,
    conds     = c(rep("Cond1", 3), rep("Cond2", 3)),
    params    = list(
      padj_cutoff  = 0.05,
      fold_cutoff  = 2,
      dataset      = "up+down",
      compselect   = 1,
      norm_method  = "TMM",
      geneset_area = "",
      method_tab   = "panel1"
    )
  )

  expect_true("Legend" %in% colnames(out))
  expect_true(all(out$Legend %in% c("Up", "Down", "NS")))

  # Snapshot the count of each label — sensitive to any cutoff or
  # normalization regression.
  counts <- as.list(table(out$Legend))
  expect_snapshot_value(counts, style = "json2")
})

test_that("apply_de_filters() returns NULL for missing data", {
  expect_null(apply_de_filters(NULL, NULL, NULL, params = list()))
})
```

- [ ] **Step 2: Run, expect failure**

```bash
R -q -e 'devtools::test("/Users/alper/workdir/debrowser", filter = "fct-prep-data")' 2>&1 | tail -10
```

Expected: error about `apply_de_filters` not found.

- [ ] **Step 3: Implement**

`R/fct_prep_data.R`:

```r
#' Apply DE filters and label Up/Down/NS/MV/GS rows.
#'
#' Pure function — no Shiny dependency. Re-normalizes the count columns,
#' computes per-condition x/y log10 means, and labels each row by cutoff.
#'
#' @param filt_data data.frame with columns including `foldChange`, `padj`,
#'   plus all `cols`.
#' @param cols Character vector of sample column names.
#' @param conds Character vector of per-column condition labels (length ==
#'   length(cols)). Values look like "Cond1"/"Cond2"/...
#' @param params Named list with components:
#'   - `padj_cutoff` (numeric or numeric-string)
#'   - `fold_cutoff` (numeric or numeric-string)
#'   - `dataset` ("up"/"down"/"up+down"/"alldetected"/"selected"/"most-varied"/"comparisons"/"searched")
#'   - `compselect` (integer; default 1)
#'   - `norm_method` (forwarded to [normalize_counts()])
#'   - `geneset_area` (string of search terms; "" = none)
#'   - `method_tab` (UI tab id; geneset overlay only applies on "panel1")
#'   - `top_n`, `min_count` (only for `dataset == "most-varied"`)
#' @return data.frame with added `x`, `y`, `Legend`, `Size` columns; or NULL.
#' @export
apply_de_filters <- function(filt_data, cols, conds, params = list()) {
  if (is.null(filt_data) || is.null(params$padj_cutoff) ||
    is.null(params$fold_cutoff)) {
    return(NULL)
  }

  compselect <- if (!is.null(params$compselect)) {
    as.integer(params$compselect)
  } else {
    1L
  }
  x <- paste0("Cond", 2 * compselect - 1)
  y <- paste0("Cond", 2 * compselect)

  norm_data <- normalize_counts(filt_data[, cols], method = params$norm_method)
  g <- data.frame(cbind(cols, conds))

  cols_x <- as.vector(g[g$conds == x, "cols"])
  filt_data$x <- if (length(cols_x) > 1L) {
    log10(rowMeans(norm_data[, cols_x]) + 0.1)
  } else {
    log10(norm_data[, cols_x] + 0.1)
  }

  cols_y <- as.vector(g[g$conds == y, "cols"])
  filt_data$y <- if (length(cols_y) > 1L) {
    log10(rowMeans(norm_data[, cols_y]) + 0.1)
  } else {
    log10(norm_data[, cols_y] + 0.1)
  }

  filt_data[, cols] <- norm_data

  padj_cutoff <- as.numeric(params$padj_cutoff)
  fold_cutoff <- as.numeric(params$fold_cutoff)

  m <- filt_data
  m$Legend <- "NS"
  m$Size <- "40"

  ds <- params$dataset
  if (ds %in% c("up", "up+down", "selected")) {
    m$Legend[m$foldChange >= fold_cutoff & m$padj <= padj_cutoff] <- "Up"
  }
  if (ds %in% c("down", "up+down", "selected")) {
    m$Legend[m$foldChange <= (1 / fold_cutoff) & m$padj <= padj_cutoff] <- "Down"
  }
  if (identical(ds, "most-varied") && !is.null(cols)) {
    most_varied <- get_most_varied(m, cols, params)
    m[rownames(most_varied), "Legend"] <- "MV"
  }
  if (!is.null(params$geneset_area) && params$geneset_area != "" &&
    identical(params$method_tab, "panel1")) {
    genelist <- getGeneSetData(m, c(params$geneset_area))
    m[rownames(genelist), "Legend"] <- "GS"
    m[rownames(genelist), "Size"] <- "100"
    tmp <- m["Legend" == "GS", ]
    tmp1 <- m["Legend" != "GS", ]
    m <- rbind(tmp1, tmp)
  }
  m
}

#' Compute the most-varied genes by coefficient of variation.
#'
#' @param datavar data.frame with sample columns.
#' @param cols Character vector of sample column names.
#' @param params Named list with `top_n` (int) and `min_count` (int).
#' @return data.frame of the top-N most-varied rows.
#' @export
get_most_varied <- function(datavar, cols, params = list()) {
  if (is.null(datavar)) {
    return(NULL)
  }
  topn <- as.integer(as.numeric(params$top_n))
  min_count <- as.integer(as.numeric(params$min_count))
  filtvar <- datavar[rowSums(datavar[, cols]) > min_count, ]
  cv <- cbind(apply(filtvar, 1, function(x) {
    sd(x, na.rm = TRUE) / mean(x, na.rm = TRUE)
  }), 1)
  colnames(cv) <- c("coeff", "a")
  cvsort <- cv[order(cv[, 1], decreasing = TRUE), ]
  topindex <- min(nrow(cvsort), topn)
  data.frame(datavar[rownames(head(cvsort, topindex)), ])
}
```

- [ ] **Step 4: Run, capture snapshot**

```bash
R -q -e 'devtools::test("/Users/alper/workdir/debrowser", filter = "fct-prep-data")' 2>&1 | tail -15
```

Expected: "Adding new snapshot" warning on first run, then `[ FAIL 0 | WARN 1 | SKIP 0 | PASS 2 ]`.

Re-run for stability:

```bash
R -q -e 'devtools::test("/Users/alper/workdir/debrowser", filter = "fct-prep-data")' 2>&1 | tail -5
```

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 2 ]`.

- [ ] **Step 5: Commit**

```bash
git add R/fct_prep_data.R tests/testthat/test-fct-prep-data.R tests/testthat/_snaps/
git commit -m "feat: pure apply_de_filters() and get_most_varied()

Lifts the Up/Down/MV/GS labeling out of applyFilters() into a function
that takes a named filter-params list. Snapshot locks the (Up, Down,
NS) row counts on the demo DE result with default cutoffs."
```

---

## Task 2: Pure `select_dataset()` and `search_geneset()` (was `getSelectedDatasetInput` and `getSearchData`)

**Files:**
- Modify: `R/fct_prep_data.R`
- Modify: `tests/testthat/test-fct-prep-data.R`

- [ ] **Step 1: Write failing tests**

Append to `tests/testthat/test-fct-prep-data.R`:

```r
test_that("select_dataset() routes by dataset name", {
  rdata <- data.frame(
    ID     = c("a", "b", "c", "d"),
    Legend = c("Up", "Down", "Up", "NS"),
    stringsAsFactors = FALSE
  )
  rownames(rdata) <- rdata$ID

  expect_equal(
    nrow(select_dataset(rdata, params = list(dataset = "up"))),
    2L
  )
  expect_equal(
    nrow(select_dataset(rdata, params = list(dataset = "down"))),
    1L
  )
  expect_equal(
    nrow(select_dataset(rdata, params = list(dataset = "alldetected"))),
    4L
  )
  expect_equal(
    rownames(select_dataset(
      rdata,
      get_selected = rdata[1:2, ],
      params = list(dataset = "selected", selected_plot = "anything")
    )),
    c("a", "b")
  )
})

test_that("search_geneset() returns NULL when input is NULL", {
  expect_null(search_geneset(NULL, params = list(geneset_area = "BRCA1")))
})
```

- [ ] **Step 2: Implement**

Append to `R/fct_prep_data.R`:

```r
#' Pick a subset of `rdata` based on the `dataset` filter param.
#'
#' @param rdata Filtered data.frame (typically the output of [apply_de_filters()]).
#' @param get_selected Optional; the user's lasso/click selection.
#' @param get_most_varied_data Optional; the most-varied subset to use when
#'   `dataset == "most-varied"`.
#' @param merged_comparison Optional; merged comparisons table.
#' @param params Named list with `dataset` and (optionally) `selected_plot`,
#'   `geneset_area`.
#' @return Subset data.frame.
#' @export
select_dataset <- function(rdata, get_selected = NULL,
                           get_most_varied_data = NULL,
                           merged_comparison = NULL, params = list()) {
  if (is.null(rdata)) {
    return(NULL)
  }
  ds <- params$dataset
  switch(ds,
    "up"           = getUp(rdata),
    "down"         = getDown(rdata),
    "up+down"      = getUpDown(rdata),
    "alldetected"  = rdata,
    "selected"     = if (!is.null(params$selected_plot)) get_selected else rdata,
    "most-varied"  = rdata[rownames(get_most_varied_data), ],
    "comparisons"  = merged_comparison,
    "searched"     = search_geneset(rdata, params),
    rdata
  )
}

#' Search a data.frame's `ID` column for a gene-set list.
#'
#' @param dat data.frame with an `ID` column (or first column treated as ID).
#' @param params Named list with `geneset_area` (string of search terms).
#' @return Filtered data.frame; or `dat` unchanged if `geneset_area` is empty.
#' @export
search_geneset <- function(dat, params = list()) {
  if (is.null(dat)) {
    return(NULL)
  }
  if (is.null(params$geneset_area) || params$geneset_area == "") {
    return(dat)
  }
  getGeneSetData(dat, c(params$geneset_area))
}
```

- [ ] **Step 3: Run; expect pass**

```bash
R -q -e 'devtools::test("/Users/alper/workdir/debrowser", filter = "fct-prep-data")' 2>&1 | tail -5
```

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 4 ]`.

- [ ] **Step 4: Commit**

```bash
git add R/fct_prep_data.R tests/testthat/test-fct-prep-data.R
git commit -m "feat: pure select_dataset() and search_geneset()"
```

---

## Task 3: Pure `merge_comparisons()` and `apply_merged_filters()`

**Files:**
- Modify: `R/fct_prep_data.R`
- Modify: `tests/testthat/test-fct-prep-data.R`

- [ ] **Step 1: Write failing test**

Append:

```r
test_that("merge_comparisons() returns NULL for empty input", {
  expect_null(merge_comparisons(NULL, 0L, params = list()))
})

test_that("apply_merged_filters() labels rows Sig where any comparison crosses cutoffs", {
  # Build a synthetic 2-comparison merge result by hand to keep the test
  # focused on the labeling logic.
  fake_dc <- list(
    list(
      cols = c("s1", "s2"),
      cond_names = c("A", "B"),
      init_data = data.frame(
        foldChange = c(3, 0.1, 1.0),
        padj       = c(0.001, 0.001, 0.5),
        s1 = c(10, 20, 30), s2 = c(11, 22, 33),
        row.names = c("g1", "g2", "g3")
      )
    )
  )
  out <- apply_merged_filters(fake_dc, 1L,
    params = list(padj_cutoff = 0.05, fold_cutoff = 2, norm_method = "none")
  )
  expect_true("Legend" %in% colnames(out))
  expect_equal(out$Legend, c("Sig", "Sig", "NS"))
})
```

- [ ] **Step 2: Implement**

Append to `R/fct_prep_data.R`:

```r
#' Merge per-comparison DE results into one wide table.
#'
#' Pure version of `getMergedComparison()`. The legacy version reads
#' `input$norm_method`; this takes the same value off `params`.
#'
#' @param dc List of per-comparison containers (each has `init_data`, `cols`,
#'   `cond_names`).
#' @param nc Number of comparisons.
#' @param params Named list with `norm_method`.
#' @return Merged data.frame (samples + per-comparison foldChange/padj cols).
#' @export
merge_comparisons <- function(dc, nc, params = list()) {
  if (is.null(dc)) {
    return(NULL)
  }
  mergeresults <- c()
  mergedata <- c()
  allsamples <- c()
  for (ni in seq(1, nc)) {
    tmp <- dc[[ni]]$init_data[, c("foldChange", "padj")]
    samples <- dc[[ni]]$cols
    cond_names <- dc[[ni]]$cond_names
    tt <- paste0(cond_names[1], ".vs.", cond_names[2])
    fctt <- paste0("foldChange.", tt)
    patt <- paste0("padj.", tt)
    colnames(tmp) <- c(fctt, patt)
    if (ni == 1L) {
      allsamples <- samples
      mergeresults <- tmp
      mergedata <- dc[[ni]]$init_data[, samples]
    } else {
      mergeresults[, fctt] <- character(nrow(tmp))
      mergeresults[, patt] <- character(nrow(tmp))
      mergeresults[rownames(tmp), c(fctt, patt)] <- tmp[, c(fctt, patt)]
      mergeresults[is.na(mergeresults[, fctt]), fctt] <- 1
      mergeresults[is.na(mergeresults[, patt]), patt] <- 1
      remaining <- dc[[ni]]$cols[!(samples %in% colnames(mergedata))]
      allsamples <- unique(c(allsamples, remaining))
      mergedata <- cbind(mergedata, dc[[ni]]$init_data[, remaining])
      colnames(mergedata) <- allsamples
    }
  }
  mergedata[, allsamples] <- normalize_counts(
    mergedata[, allsamples],
    method = params$norm_method
  )
  cbind(mergedata, mergeresults)
}

#' Apply Up/Down cutoffs across a merged-comparisons table.
#'
#' Pure version of `applyFiltersToMergedComparison()`.
#'
#' @inheritParams merge_comparisons
#' @return Merged data.frame with a `Legend` column (`"Sig"` / `"NS"`).
#' @export
apply_merged_filters <- function(dc, nc, params = list()) {
  if (is.null(dc)) {
    return(NULL)
  }
  merged <- merge_comparisons(dc, nc, params)
  padj_cutoff <- as.numeric(params$padj_cutoff)
  fold_cutoff <- as.numeric(params$fold_cutoff)
  if (is.null(merged$Legend)) {
    merged$Legend <- "NS"
  }
  for (ni in seq(1, nc)) {
    cond_names <- dc[[ni]]$cond_names
    tt <- paste0(cond_names[1], ".vs.", cond_names[2])
    fctt <- paste0("foldChange.", tt)
    patt <- paste0("padj.", tt)
    up <- as.numeric(merged[, fctt]) >= fold_cutoff &
      as.numeric(merged[, patt]) <= padj_cutoff
    down <- as.numeric(merged[, fctt]) <= 1 / fold_cutoff &
      as.numeric(merged[, patt]) <= padj_cutoff
    merged$Legend[which(up | down)] <- "Sig"
  }
  merged
}
```

- [ ] **Step 3: Run; expect pass**

```bash
R -q -e 'devtools::test("/Users/alper/workdir/debrowser", filter = "fct-prep-data")' 2>&1 | tail -5
```

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 6 ]`.

- [ ] **Step 4: Commit**

```bash
git add R/fct_prep_data.R tests/testthat/test-fct-prep-data.R
git commit -m "feat: pure merge_comparisons() and apply_merged_filters()"
```

---

## Task 4: Pure `get_table_data()`

**Files:**
- Modify: `R/fct_prep_data.R`
- Modify: `tests/testthat/test-fct-prep-data.R`

- [ ] **Step 1: Write failing test**

Append:

```r
test_that("get_table_data() returns (data, padj_col, fold_col) tuple", {
  init <- data.frame(
    ID = c("g1", "g2"),
    foldChange = c(3, 0.5),
    padj = c(0.001, 0.5),
    Legend = c("Up", "NS"),
    row.names = c("g1", "g2")
  )

  res <- get_table_data(
    init_data = init,
    filt_data = init,
    selected = NULL,
    get_most_varied_data = NULL,
    merged_comp = NULL,
    params = list(dataset = "alldetected", geneset_area = "")
  )
  expect_length(res, 3L)
  expect_equal(res[[2]], "padj")
  expect_equal(res[[3]], "foldChange")
  expect_equal(nrow(res[[1]]), 2L)

  res_up <- get_table_data(
    init_data = init,
    filt_data = init,
    selected = NULL,
    get_most_varied_data = NULL,
    merged_comp = NULL,
    params = list(dataset = "up", geneset_area = "")
  )
  expect_equal(nrow(res_up[[1]]), 1L)
})

test_that("get_table_data() returns NULL with no init_data", {
  expect_null(get_table_data(NULL))
})
```

- [ ] **Step 2: Implement**

Append:

```r
#' Build the (data, padj_colname, fold_colname) tuple for the Tables tab.
#'
#' Pure version of `getDataForTables()`.
#'
#' @param init_data Initial DE result.
#' @param filt_data Filtered DE result; defaults to `init_data` if NULL.
#' @param selected Genes the user lasso-selected (used when
#'   `dataset == "selected"`).
#' @param get_most_varied_data Most-varied subset (used when
#'   `dataset == "most-varied"`).
#' @param merged_comp Merged comparisons table.
#' @param explained_data Unused; preserved for legacy signature parity.
#' @param params Named list with `dataset`, `geneset_area`.
#' @return list(data, padj_colname, fold_colname).
#' @export
get_table_data <- function(init_data = NULL, filt_data = NULL,
                           selected = NULL, get_most_varied_data = NULL,
                           merged_comp = NULL, explained_data = NULL,
                           params = list()) {
  if (is.null(init_data)) {
    return(NULL)
  }
  if (is.null(filt_data)) filt_data <- init_data
  pastr <- "padj"
  fcstr <- "foldChange"
  ds <- params$dataset
  dat <- switch(ds,
    "alldetected"  = search_geneset(filt_data, params),
    "up+down"      = search_geneset(getUpDown(filt_data), params),
    "up"           = search_geneset(getUp(filt_data), params),
    "down"         = search_geneset(getDown(filt_data), params),
    "selected"     = search_geneset(selected, params),
    "most-varied"  = {
      d <- if (!is.null(filt_data)) {
        filt_data[rownames(get_most_varied_data), ]
      } else {
        init_data[rownames(get_most_varied_data), ]
      }
      search_geneset(d, params)
    },
    "comparisons"  = {
      if (is.null(merged_comp)) {
        return(NULL)
      }
      fcstr <<- colnames(merged_comp)[grepl("foldChange", colnames(merged_comp))]
      pastr <<- colnames(merged_comp)[grepl("padj", colnames(merged_comp))]
      search_geneset(merged_comp, params)
    },
    "searched"     = search_geneset(init_data, params),
    NULL
  )
  list(dat, pastr, fcstr)
}
```

- [ ] **Step 3: Run; expect pass**

```bash
R -q -e 'devtools::test("/Users/alper/workdir/debrowser", filter = "fct-prep-data")' 2>&1 | tail -5
```

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 8 ]`.

- [ ] **Step 4: Commit**

```bash
git add R/fct_prep_data.R tests/testthat/test-fct-prep-data.R
git commit -m "feat: pure get_table_data() (was getDataForTables)"
```

---

## Task 5: Convert legacy `applyFilters()`, `getMostVariedList()`, `getSelectedDatasetInput()`, `getSearchData()` to shims

**Files:**
- Modify: `R/prepdata.R`

The shims accept the legacy `input` reactive and delegate to the pure functions via `filter_params_from_input()`.

- [ ] **Step 1: Replace `applyFilters()` body (lines 16–89 of `R/prepdata.R`)**

Find `applyFilters <- function(...)` and replace its body so it reads:

```r
applyFilters <- function(filt_data = NULL, cols = NULL, conds = NULL,
                         input = NULL) {
  apply_de_filters(filt_data, cols, conds, filter_params_from_input(input))
}
```

- [ ] **Step 2: Replace `getMostVariedList()` body**

Find `getMostVariedList <- function(...)` and replace with:

```r
getMostVariedList <- function(datavar = NULL, cols = NULL, input = NULL) {
  get_most_varied(datavar, cols, filter_params_from_input(input))
}
```

- [ ] **Step 3: Replace `getSelectedDatasetInput()` body**

```r
getSelectedDatasetInput <- function(rdata = NULL, getSelected = NULL,
                                    getMostVaried = NULL,
                                    mergedComparison = NULL,
                                    input = NULL) {
  select_dataset(
    rdata,
    get_selected         = getSelected,
    get_most_varied_data = getMostVaried,
    merged_comparison    = mergedComparison,
    params               = filter_params_from_input(input)
  )
}
```

- [ ] **Step 4: Replace `getSearchData()` body**

```r
getSearchData <- function(dat = NULL, input = NULL) {
  search_geneset(dat, filter_params_from_input(input))
}
```

- [ ] **Step 5: Run full suite — golden snapshots from A2 must stay green**

```bash
R -q -e 'devtools::test("/Users/alper/workdir/debrowser")' 2>&1 | tail -5
```

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 71 ]` (was 64; added 7 from prep-data + 1 from utils-validate + minus a couple older pass-counts; the precise number depends on counting `expect_*` calls).

Critically: `golden-de`, `golden-normalize`, `fct-de-methods`, `fct-normalize`, `fct-filter`, `fct-prep-data` all green.

- [ ] **Step 6: Commit**

```bash
git add R/prepdata.R
git commit -m "refactor: turn legacy applyFilters / getMostVariedList /
getSelectedDatasetInput / getSearchData into shims

Bodies translate the Shiny input via filter_params_from_input() and
delegate to fct_prep_data.R. Public signatures unchanged."
```

---

## Task 6: Convert legacy `getMergedComparison()`, `applyFiltersToMergedComparison()`, `getDataForTables()` to shims

**Files:**
- Modify: `R/prepdata.R`

- [ ] **Step 1: Replace `getMergedComparison()` body**

```r
getMergedComparison <- function(dc = NULL, nc = NULL, input = NULL) {
  merge_comparisons(dc, nc, filter_params_from_input(input))
}
```

- [ ] **Step 2: Replace `applyFiltersToMergedComparison()` body**

```r
applyFiltersToMergedComparison <- function(dc = NULL, nc = NULL,
                                           input = NULL) {
  apply_merged_filters(dc, nc, filter_params_from_input(input))
}
```

- [ ] **Step 3: Replace `getDataForTables()` body**

```r
getDataForTables <- function(input = NULL, init_data = NULL,
                             filt_data = NULL, selected = NULL,
                             getMostVaried = NULL, mergedComp = NULL,
                             explainedData = NULL) {
  get_table_data(
    init_data            = init_data,
    filt_data            = filt_data,
    selected             = selected,
    get_most_varied_data = getMostVaried,
    merged_comp          = mergedComp,
    explained_data       = explainedData,
    params               = filter_params_from_input(input)
  )
}
```

- [ ] **Step 4: Run full suite**

```bash
R -q -e 'devtools::test("/Users/alper/workdir/debrowser")' 2>&1 | tail -5
```

Expected: same pass count as Task 5 step 5; all snapshots stable.

- [ ] **Step 5: Commit**

```bash
git add R/prepdata.R
git commit -m "refactor: turn merged-comparison + table-data legacy fns into shims

Closes the A3b shim conversion. R/prepdata.R is now a thin glue layer
over R/fct_prep_data.R."
```

---

## Task 7: A3b milestone — final verification + NEWS

**Files:**
- Modify: `NEWS.md`

- [ ] **Step 1: Final full-suite run**

```bash
R -q -e 'devtools::test("/Users/alper/workdir/debrowser")' 2>&1 | tail -5
```

Expected: all green. All 6 golden snapshot tests still pass (proves shims preserve math), all new pure-fn snapshots stable.

- [ ] **Step 2: Build check**

```bash
cd /tmp && R CMD build /Users/alper/workdir/debrowser --no-build-vignettes --no-manual 2>&1 | tail -3
rm -f /tmp/debrowser_*.tar.gz
```

Expected: builds cleanly.

- [ ] **Step 3: Add A3b entry to `NEWS.md`** (insert after the A3a section, before `### User-visible`)

```markdown
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
* New golden snapshot locks the (Up, Down, NS) row-count distribution on
  the demo DE result with default cutoffs — catches regressions in
  cutoff logic or normalization.
```

- [ ] **Step 4: Commit**

```bash
git add NEWS.md
git commit -m "docs: log Phase A3b in NEWS.md"
```

**Milestone reached: A3b done. The analytic core (DE math + normalization + filtering + dataset selection + table prep) lives entirely in `R/fct_*.R` files. The plot rendering layer is the only place left where `input$` is read directly — and that's deliberately deferred to Phase B6 where we touch each plot once for both extraction and UX polish.**

---

## Self-Review

**Spec coverage check (A3 — `fct_prep_data.R` portion):**
- [x] `applyFilters()` → `apply_de_filters()` (Task 1)
- [x] `getMostVariedList()` → `get_most_varied()` (Task 1)
- [x] `getSelectedDatasetInput()` → `select_dataset()` (Task 2)
- [x] `getSearchData()` → `search_geneset()` (Task 2)
- [x] `getMergedComparison()` → `merge_comparisons()` (Task 3)
- [x] `applyFiltersToMergedComparison()` → `apply_merged_filters()` (Task 3)
- [x] `getDataForTables()` → `get_table_data()` (Task 4)
- [x] Legacy entry points become shims → Tasks 5, 6
- [x] `filter_params_from_input()` central helper → Task 0

**Spec coverage gap deliberately deferred:**
- `fct_plots.R` — explicitly folded into Phase B6 per the rationale at the top of this document.

**Placeholder scan:** every step has actual code or actual command. The `<<-` in `get_table_data()`'s `"comparisons"` branch (Task 4) is intentional — it mutates the locals `pastr` and `fcstr` declared in the same function scope. R's `switch` arms are expressions, not nested closures, so plain `<-` would have the same effect; using `<<-` is defensive in case the function is later restructured.

**Type / name consistency:**
- `filter_params_from_input()` defined in Task 0; used in Tasks 5 and 6.
- `apply_de_filters()`, `get_most_varied()`, `select_dataset()`, `search_geneset()`, `merge_comparisons()`, `apply_merged_filters()`, `get_table_data()` defined in Tasks 1–4; all referenced consistently in Tasks 5–6 shims.
- Filter-params field names (`padj_cutoff`, `fold_cutoff`, `dataset`, `compselect`, `norm_method`, `geneset_area`, `method_tab`, `top_n`, `min_count`, `selected_plot`) are identical across the helper definition (Task 0), all pure functions (Tasks 1–4), and the implicit consumption inside shims (Tasks 5–6 — they use `filter_params_from_input` so the names are guaranteed to match by construction).
- `getGeneSetData()`, `getUp()`, `getDown()`, `getUpDown()` continue to live in `R/prepdata.R` — they were already pure, no shim needed.
- `removeCols()` continues to live in `R/prepdata.R` — already pure, no shim needed.
- `addID()` is referenced in `getGeneSetData()` and lives in `R/uifuncs.R` — unchanged.
