# Phase A1 + A2: Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Establish the foundation (CI, lint, modern R version, golden output snapshots) that the rest of Phase A (A3 extract pure functions, A4 modularize Shiny) will rest on. After this plan ships, the package is always installable and any DE refactor regression is caught by snapshot tests.

**Architecture:** Two independent sub-phases bundled because both are pure scaffolding (no application logic touched).
- **A1** = repo hygiene: lint/style configs, modern R version, GitHub Actions for R-CMD-check + BiocCheck + lintr + coverage, plus shipping the in-flight upload-size bump.
- **A2** = test scaffolding: migrate to `testthat` 3e layout, capture deterministic golden output snapshots (DESeq2 / edgeR / limma / normalization / PCA) on the demo data, set up `shinytest2` with one smoke test.

**Tech Stack:** R 4.2+, testthat 3e, shinytest2, lintr, styler, GitHub Actions (`r-lib/actions`), covr, BiocCheck.

**Spec reference:** [docs/superpowers/specs/2026-04-27-debrowser-modernization-design.md](../specs/2026-04-27-debrowser-modernization-design.md) sections "Phase A — A1" and "Phase A — A2".

**Branch strategy:** All work on `modernize` branched off `devel`. The two design-doc commits currently on `RELEASE_3_18` (`bc1a9c8`, `9032935`) get cherry-picked onto `modernize` in Task 0.

---

## File Map

Files created or modified by this plan:

| File | Action | Purpose |
|---|---|---|
| `.Rbuildignore` | modify | exclude `docs/`, `viafoundry_errors.log`, `.github/`, `.lintr`, dev configs |
| `viafoundry_errors.log` | delete | empty stale debug log |
| `DESCRIPTION` | modify | bump `R (>= 4.2.0)`, `RoxygenNote` to 7.3.2 |
| `R/startShiny.R` | modify | finalize 30→90 MB upload bump (already staged in working tree) |
| `.lintr` | create | lintr config (style-only rules; cyclocomp_linter off for now) |
| `.github/workflows/R-CMD-check.yaml` | create | run R-CMD-check on R-release + R-devel against bioc-devel |
| `.github/workflows/bioc-check.yaml` | create | BiocCheck on PRs |
| `.github/workflows/lint.yaml` | create | lintr report on PR diff |
| `.github/workflows/coverage.yaml` | create | covr coverage to codecov |
| `tests/testthat.R` | create | testthat runner entry point |
| `tests/testthat/test-demo-data.R` | create | (migrated) demo data shape assertions |
| `tests/testthat/test-deseq.R` | create | (migrated, dead code removed) DESeq2 smoke |
| `tests/testthat/test-null.R` | create | (migrated) null-input handling |
| `tests/testthat/test-ui.R` | create | (migrated) panel-construction tests |
| `tests/testthat/test-golden-de.R` | create | golden snapshots for DESeq2/edgeR/limma result hashes |
| `tests/testthat/test-golden-normalize.R` | create | golden snapshots for normalization + PCA coordinates |
| `tests/testthat/_snaps/` | create (auto) | testthat snapshot directory |
| `tests/testthat/helper-debrowser.R` | create | shared test helpers (load demo, hash helpers) |
| `tests/test-demo.R` | delete | superseded by tests/testthat/test-demo-data.R |
| `tests/test-deseq.R` | delete | superseded |
| `tests/test-null.R` | delete | superseded |
| `tests/test-ui.R` | delete | superseded |
| `tests/shinytest2/test-smoke.R` | create | end-to-end: load demo → run DESeq2 → MA renders |
| `tests/shinytest2/setup.R` | create | shinytest2 driver bootstrap |

No application code (`R/*.R` outside `startShiny.R`) is modified by this plan. That's deliberate — A1+A2 is scaffolding only.

---

## Task 0: Branch setup and cherry-pick design docs

**Files:**
- Modify: working tree (branch switch)

- [ ] **Step 1: Stash anything untracked to be safe**

```bash
git -C /Users/alper/workdir/debrowser status --short
```

Expected: `M R/startShiny.R` and `?? viafoundry_errors.log`. The `R/startShiny.R` modification is the upload bump and we want to keep it. The `viafoundry_errors.log` is stale debug and we'll delete it later.

- [ ] **Step 2: Stash the upload-bump diff so we can switch branches cleanly**

```bash
git stash push -u -m "wip: upload-size bump and stale error log" -- R/startShiny.R viafoundry_errors.log
```

Expected: `Saved working directory and index state On RELEASE_3_18: wip: upload-size bump and stale error log`

- [ ] **Step 3: Create `modernize` branch off `devel`**

```bash
git fetch origin
git checkout -b modernize devel
```

Expected: `Switched to a new branch 'modernize'`. If `devel` is behind origin: `git pull --ff-only` first.

- [ ] **Step 4: Cherry-pick the two design-doc commits from RELEASE_3_18**

```bash
git cherry-pick bc1a9c8 9032935
```

Expected: both commits applied cleanly onto `modernize` (they only touch `docs/`).

- [ ] **Step 5: Pop the stash to bring back the upload bump**

```bash
git stash pop
```

Expected: `R/startShiny.R` shows as modified, `viafoundry_errors.log` reappears as untracked.

- [ ] **Step 6: Verify clean state**

```bash
git status
```

Expected:
```
On branch modernize
Changes not staged for commit:
        modified:   R/startShiny.R

Untracked files:
        viafoundry_errors.log
```

No commit yet — Task 1 ships the upload bump.

---

## Task 1: Ship the in-flight upload-size bump

**Files:**
- Modify: `R/startShiny.R:16` (already staged in working tree)

- [ ] **Step 1: Confirm the existing diff**

```bash
git diff R/startShiny.R
```

Expected:
```diff
-        options( shiny.maxRequestSize = 30 * 1024 ^ 2, warn = -1,
+        options( shiny.maxRequestSize = 90 * 1024 ^ 2, warn = -1,
```

- [ ] **Step 2: Commit it**

```bash
git add R/startShiny.R
git commit -m "feat: raise startDEBrowser upload limit to 90MB

Many bulk RNA-seq count matrices exceed 30 MB. Phase C will raise this
further (to 500 MB with a slow-warning) once async upload validation
lands; 90 MB is a safe interim bump.

Refs: docs/superpowers/specs/2026-04-27-debrowser-modernization-design.md (Phase C6)"
```

Expected: one-line commit landed on `modernize`.

---

## Task 2: Delete the stale `viafoundry_errors.log`

**Files:**
- Delete: `viafoundry_errors.log`

- [ ] **Step 1: Confirm it's empty / stale**

```bash
ls -la /Users/alper/workdir/debrowser/viafoundry_errors.log
```

Expected: file size 0 or near-0.

- [ ] **Step 2: Delete and commit**

```bash
rm /Users/alper/workdir/debrowser/viafoundry_errors.log
git add -u viafoundry_errors.log
git commit -m "chore: remove stale empty viafoundry_errors.log"
```

Expected: clean working tree.

---

## Task 3: Update `.Rbuildignore`

**Files:**
- Modify: `.Rbuildignore`

- [ ] **Step 1: Read current contents**

```bash
cat .Rbuildignore 2>/dev/null
```

Expected: existing entries (or empty file). Keep them.

- [ ] **Step 2: Append new ignore patterns**

Add these lines to the end of `.Rbuildignore` (preserve any existing lines above):

```
^docs$
^\.github$
^\.lintr$
^\.aidrift$
^\.claude$
^viafoundry_errors\.log$
^.*\.Rproj$
^\.Rproj\.user$
^README\.md$
^codecov\.yml$
^\.styler_cache$
^renv\.lock$
^renv$
```

- [ ] **Step 3: Verify build still passes the ignore check**

```bash
R CMD build /Users/alper/workdir/debrowser --no-build-vignettes 2>&1 | tail -20
```

Expected: builds to `debrowser_<version>.tar.gz` without warnings about ignored files. If it warns about `docs/`, the regex is wrong. Delete the tarball after.

```bash
rm debrowser_*.tar.gz
```

- [ ] **Step 4: Commit**

```bash
git add .Rbuildignore
git commit -m "chore: extend .Rbuildignore for docs, CI, lint, and dev configs"
```

---

## Task 4: Bump R requirement and Roxygen version in `DESCRIPTION`

**Files:**
- Modify: `DESCRIPTION`

- [ ] **Step 1: Edit `DESCRIPTION`**

Change:
```
Depends:
    R (>= 3.5.0),
```
to:
```
Depends:
    R (>= 4.2.0),
```

Change:
```
RoxygenNote: 7.2.3
```
to:
```
RoxygenNote: 7.3.2
```

Update the `Date:` field to the build date:
```
Date: 2026-04-27
```

- [ ] **Step 2: Regenerate `man/` with current Roxygen**

```bash
R -q -e 'roxygen2::roxygenise(".")'
```

Expected: regenerates `NAMESPACE` and `man/*.Rd`. If diff is non-trivial, inspect — should be cosmetic.

- [ ] **Step 3: Verify package still builds**

```bash
R CMD build . --no-build-vignettes 2>&1 | tail -5
rm debrowser_*.tar.gz
```

Expected: `* building 'debrowser_<version>.tar.gz'` with no errors.

- [ ] **Step 4: Commit**

```bash
git add DESCRIPTION NAMESPACE man/
git commit -m "build: bump R >= 4.2 and RoxygenNote 7.3.2

Drops R 3.5/3.6/4.0/4.1. R 4.2 is the floor supported by Bioconductor
3.18 anyway, so this loses no users."
```

---

## Task 5: Add `.lintr` config

**Files:**
- Create: `.lintr`

- [ ] **Step 1: Create `.lintr` with conservative rules**

```r
linters: linters_with_defaults(
  line_length_linter      = line_length_linter(120L),
  cyclocomp_linter        = NULL,    # too noisy on legacy code; revisit in Phase A4
  object_name_linter      = NULL,    # legacy uses camelCase + snake_case mixed; revisit
  commented_code_linter   = NULL,
  object_usage_linter     = NULL,    # gives false positives in Shiny module callbacks
  indentation_linter      = NULL     # styler will own indentation
)
exclusions: list(
  "tests/testthat/_snaps",
  "man",
  "R/installpack.R"   # planned for removal in A4 — don't churn
)
```

- [ ] **Step 2: Run `lintr` to confirm config loads**

```bash
R -q -e 'lintr::lint_package(".")' 2>&1 | tail -20
```

Expected: a list of style-only warnings (long lines, etc.). No fatal errors. Don't fix any warnings yet — Task 6 (`styler`) will catch most.

- [ ] **Step 3: Commit**

```bash
git add .lintr
git commit -m "ci: add lintr config (conservative for now; tightens in A4)"
```

---

## Task 6: One-time `styler` pass

**Files:**
- Modify: every file under `R/`

- [ ] **Step 1: Install `styler` if not present**

```bash
R -q -e 'if (!requireNamespace("styler", quietly = TRUE)) install.packages("styler", repos = "https://cloud.r-project.org")'
```

- [ ] **Step 2: Run `styler::style_pkg()` with tidyverse style**

```bash
R -q -e 'styler::style_pkg(".", filetype = c("R", "Rmd"))'
```

Expected: output shows files reformatted (`Status` column with `Done`).

- [ ] **Step 3: Sanity-check the diff is style-only**

```bash
git diff --stat R/
```

Expected: many small diffs (whitespace, indentation, quote style) across many files. **Spot-check** one file with `git diff R/startShiny.R` — confirm it's whitespace, no semantic changes.

- [ ] **Step 4: Run existing tests to confirm nothing broke**

```bash
R -q -e 'devtools::test()' 2>&1 | tail -20
```

Expected: same pass/fail as before the pass.

- [ ] **Step 5: Commit as a single style-only commit**

```bash
git add R/
git commit -m "style: run styler::style_pkg() (tidyverse style)

One-time formatting pass. No semantic changes. Future style drift will
be caught by the lintr CI added in the next commit."
```

---

## Task 7: GitHub Actions — R-CMD-check (release + devel)

**Files:**
- Create: `.github/workflows/R-CMD-check.yaml`

- [ ] **Step 1: Create the workflow file**

```yaml
name: R-CMD-check

on:
  push:
    branches: [devel, modernize]
  pull_request:
    branches: [devel]

jobs:
  R-CMD-check:
    runs-on: ${{ matrix.config.os }}
    name: ${{ matrix.config.os }} (${{ matrix.config.r }})

    strategy:
      fail-fast: false
      matrix:
        config:
          - {os: ubuntu-latest, r: 'release', bioc: '3.18'}
          - {os: ubuntu-latest, r: 'devel',   bioc: 'devel'}

    env:
      GITHUB_PAT: ${{ secrets.GITHUB_TOKEN }}
      R_KEEP_PKG_SOURCE: yes

    steps:
      - uses: actions/checkout@v4

      - uses: r-lib/actions/setup-r@v2
        with:
          r-version: ${{ matrix.config.r }}
          use-public-rspm: true

      - uses: r-lib/actions/setup-pandoc@v2

      - name: Install Bioconductor
        run: |
          install.packages("BiocManager")
          BiocManager::install(version = "${{ matrix.config.bioc }}", ask = FALSE, update = FALSE)
        shell: Rscript {0}

      - uses: r-lib/actions/setup-r-dependencies@v2
        with:
          extra-packages: |
            any::rcmdcheck
            any::testthat
          needs: check

      - uses: r-lib/actions/check-r-package@v2
        with:
          args: 'c("--no-manual", "--as-cran")'
          error-on: '"warning"'
```

- [ ] **Step 2: Commit**

```bash
git add .github/workflows/R-CMD-check.yaml
git commit -m "ci: add R-CMD-check workflow (release + devel)"
```

---

## Task 8: GitHub Actions — BiocCheck

**Files:**
- Create: `.github/workflows/bioc-check.yaml`

- [ ] **Step 1: Create the workflow file**

```yaml
name: BiocCheck

on:
  push:
    branches: [devel, modernize]
  pull_request:
    branches: [devel]

jobs:
  bioc-check:
    runs-on: ubuntu-latest
    container: bioconductor/bioconductor_docker:RELEASE_3_18

    steps:
      - uses: actions/checkout@v4

      - name: Install package deps
        run: |
          BiocManager::install(ask = FALSE, update = FALSE)
          install.packages("BiocCheck")
        shell: Rscript {0}

      - name: Run BiocCheck
        run: |
          BiocCheck::BiocCheck(".", `quit-with-status` = TRUE,
                               `no-check-formatting` = FALSE)
        shell: Rscript {0}
```

- [ ] **Step 2: Commit**

```bash
git add .github/workflows/bioc-check.yaml
git commit -m "ci: add BiocCheck workflow"
```

---

## Task 9: GitHub Actions — lintr

**Files:**
- Create: `.github/workflows/lint.yaml`

- [ ] **Step 1: Create the workflow file**

```yaml
name: lintr

on:
  pull_request:
    branches: [devel]

jobs:
  lint:
    runs-on: ubuntu-latest
    env:
      GITHUB_PAT: ${{ secrets.GITHUB_TOKEN }}
    steps:
      - uses: actions/checkout@v4
      - uses: r-lib/actions/setup-r@v2
        with:
          use-public-rspm: true
      - uses: r-lib/actions/setup-r-dependencies@v2
        with:
          extra-packages: any::lintr
      - name: Lint
        run: lintr::lint_package()
        shell: Rscript {0}
        env:
          LINTR_ERROR_ON_LINT: false
```

- [ ] **Step 2: Commit**

```bash
git add .github/workflows/lint.yaml
git commit -m "ci: add lintr workflow (warn-only for now)"
```

---

## Task 10: GitHub Actions — coverage (covr → codecov)

**Files:**
- Create: `.github/workflows/coverage.yaml`
- Create: `codecov.yml`

- [ ] **Step 1: Create workflow**

```yaml
name: coverage

on:
  push:
    branches: [devel, modernize]

jobs:
  coverage:
    runs-on: ubuntu-latest
    container: bioconductor/bioconductor_docker:RELEASE_3_18

    steps:
      - uses: actions/checkout@v4
      - name: Install deps
        run: |
          BiocManager::install(ask = FALSE, update = FALSE)
          install.packages(c("covr", "xml2"))
        shell: Rscript {0}
      - name: Run coverage
        run: |
          cov <- covr::package_coverage(quiet = FALSE, clean = FALSE)
          covr::to_cobertura(cov, "coverage.xml")
        shell: Rscript {0}
      - uses: codecov/codecov-action@v4
        with:
          files: coverage.xml
          fail_ci_if_error: false
```

- [ ] **Step 2: Create `codecov.yml`** (Bioconductor packages: don't fail on unchanged files)

```yaml
coverage:
  status:
    project:
      default:
        target: auto
        threshold: 1%
    patch:
      default:
        target: 70%
        threshold: 5%
comment:
  layout: "reach, diff, flags, files"
  behavior: default
  require_changes: false
```

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/coverage.yaml codecov.yml
git commit -m "ci: add covr coverage workflow (codecov)"
```

---

## Task 11: A1 milestone — push and verify CI green

**Files:** none (verification only)

- [ ] **Step 1: Push the branch**

```bash
git push -u umms modernize
```

(Use `umms` remote — that's the GitHub repo per `DESCRIPTION` URL. Bioconductor `origin` doesn't run GitHub Actions.)

- [ ] **Step 2: Wait for CI**

Visit `https://github.com/UMMS-Biocore/debrowser/actions` and confirm:
- `R-CMD-check` (release + devel) — both green or only acceptable WARNINGs from existing code
- `BiocCheck` — green or only legacy WARNINGs
- `lintr` — runs, may report style warnings (acceptable)
- `coverage` — runs, posts a baseline number

- [ ] **Step 3: Document the baseline coverage in `NEWS.md`**

Coverage will be low (~10–20%); that's fine — A2 raises it. Just record the starting point.

```bash
echo "" >> NEWS.md
echo "## debrowser 1.31.0 (in development)" >> NEWS.md
echo "" >> NEWS.md
echo "* Foundation modernization (Phase A1): R >= 4.2, lintr/styler, GitHub Actions for R-CMD-check + BiocCheck + lintr + covr." >> NEWS.md
echo "* Upload limit raised from 30 MB to 90 MB." >> NEWS.md
```

If `NEWS.md` doesn't exist (the file is currently `NEWS`), create it with a header pointing to the legacy `NEWS`:

```bash
test -f NEWS.md || cat > NEWS.md <<'EOF'
# debrowser NEWS

For releases prior to 1.31, see the legacy `NEWS` file.

EOF
```

- [ ] **Step 4: Commit `NEWS.md`**

```bash
git add NEWS.md
git commit -m "docs: start NEWS.md for the 1.31 modernization cycle"
git push umms modernize
```

**Milestone reached: A1 done — CI green, lint config in place, baseline coverage recorded.**

---

## Task 12: Migrate tests to `tests/testthat/` layout (testthat 3e)

**Files:**
- Create: `tests/testthat.R`
- Create: `tests/testthat/test-demo-data.R`, `test-deseq.R`, `test-null.R`, `test-ui.R`
- Create: `tests/testthat/helper-debrowser.R`
- Delete: `tests/test-demo.R`, `tests/test-deseq.R`, `tests/test-null.R`, `tests/test-ui.R`
- Modify: `DESCRIPTION` (`Config/testthat/edition: 3`)

- [ ] **Step 1: Create `tests/testthat.R` runner**

```r
# This file is part of the standard setup for testthat.
# It is recommended that you do not modify it.
#
# Where should you do additional test configuration?
# Learn more about the roles of various files in:
# * https://r-pkgs.org/testing-design.html#sec-tests-files-overview
# * https://testthat.r-lib.org/articles/special-files.html

library(testthat)
library(debrowser)

test_check("debrowser")
```

- [ ] **Step 2: Create the helper**

`tests/testthat/helper-debrowser.R`:

```r
# Shared helpers for debrowser tests.

#' Load the bundled Vernia demo dataset and metadata as a list.
load_demo <- function() {
  load(system.file("extdata", "demo", "demodata.Rda", package = "debrowser"))
  list(counts = demodata, meta = metadatatable)
}

#' Stable hash of a numeric matrix or data frame for snapshot tests.
#' Coerces to numeric, rounds to 6 dp to absorb FPU noise, then digests.
stable_hash <- function(x) {
  if (is.data.frame(x)) x <- as.matrix(x[vapply(x, is.numeric, logical(1))])
  x <- round(x, 6L)
  digest::digest(x, algo = "xxhash64")
}

#' The 6-column control/exper subset used in tests/test-deseq.R.
demo_columns <- c(
  "exper_rep1", "exper_rep2", "exper_rep3",
  "control_rep1", "control_rep2", "control_rep3"
)

#' The condition factor for that subset.
demo_conds <- factor(c("Treat", "Treat", "Treat", "Control", "Control", "Control"))
```

- [ ] **Step 3: Migrate `test-demo.R` → `tests/testthat/test-demo-data.R`**

```r
test_that("bundled demo data has the expected shape and a known cell value", {
  load(system.file("extdata", "demo", "demodata.Rda", package = "debrowser"))

  expect_s3_class(demodata, "data.frame")
  expect_equal(demodata[29311, 2], 2)
  expect_equal(demodata[29311, 5], 7.1)
  expect_equal(demodata[29311, 6], 6)
  expect_null(demodata[1, 7])
})
```

- [ ] **Step 4: Migrate `test-deseq.R` → `tests/testthat/test-deseq.R` (keep only the test, drop the dead code below it)**

```r
test_that("runDE with DESeq2 produces a result on the demo data", {
  demo <- load_demo()
  data <- subset(as.data.frame(demo$counts[, demo_columns]), rowSums(.data) > 10)

  params <- c("DESeq2", "NoCovariate", "parametric", FALSE, "Wald", "None")
  deseqrun <- runDE(data, demo$meta, demo_columns, demo_conds, params)

  expect_true(exists("deseqrun"))
  expect_true(nrow(deseqrun) > 100)
  expect_true(all(c("padj", "log2FoldChange") %in% colnames(as.data.frame(deseqrun))))
})
```

(Note: the orphaned `rdata <-` block in the old `test-deseq.R` does not get migrated — it never ran assertions and was effectively dead code.)

- [ ] **Step 5: Migrate `test-null.R` → `tests/testthat/test-null.R`**

```r
test_that("passing NULL to public functions returns NULL safely", {
  expect_null(compareClust())
  expect_null(getGOPlots(NULL, NULL))
  expect_null(runDE(NULL))
  expect_null(plot_pca(NULL))
})
```

- [ ] **Step 6: Migrate `test-ui.R` → `tests/testthat/test-ui.R`**

```r
test_that("panel-builder helpers return shiny tags without error", {
  expect_silent(QCPanel <- getQCPanel())
  expect_true(exists("QCPanel"))
  expect_equal(QCPanel[[1]][[1]], "div")

  expect_silent(downloads <- getDownloadSection())
  expect_true(exists("downloads"))
  expect_equal(downloads[[1]][[1]], "div")

  expect_silent(getMain <- getMainPanel())
  expect_true(exists("getMain"))
  expect_equal(getMain[[1]][[1]], "div")

  expect_silent(getStart <- getStartupMsg())
  expect_true(exists("getStart"))
  expect_equal(getStart[[1]][[1]], "div")

  expect_silent(getAfter <- getAfterLoadMsg())
  expect_true(exists("getAfter"))
  expect_equal(getAfter[[1]][[1]], "div")

  expect_silent(getGO <- getGoPanel())
  expect_true(exists("getGO"))
  expect_equal(getGO[[1]][[1]], "div")
})
```

- [ ] **Step 7: Delete the old top-level test files**

```bash
git rm tests/test-demo.R tests/test-deseq.R tests/test-null.R tests/test-ui.R
```

- [ ] **Step 8: Add testthat 3e config and `digest` to Suggests in `DESCRIPTION`**

Edit `DESCRIPTION`. Find the `Suggests:` line and ensure it reads:

```
Suggests: testthat (>= 3.2.0),
    rmarkdown,
    knitr,
    digest
```

Add (anywhere after `VignetteBuilder`):

```
Config/testthat/edition: 3
```

- [ ] **Step 9: Run the migrated test suite**

```bash
R -q -e 'devtools::test()' 2>&1 | tail -30
```

Expected: 4 test files run; same number of passing assertions as before (~9 across the four files). No failures.

- [ ] **Step 10: Commit**

```bash
git add tests/testthat/ tests/testthat.R DESCRIPTION
git commit -m "test: migrate tests to testthat 3e layout

- Move tests/test-*.R into tests/testthat/ as test-*.R
- Add tests/testthat.R runner and helper-debrowser.R
- Drop dead post-test_that() block from old test-deseq.R
- Add Config/testthat/edition: 3 and digest to Suggests"
```

---

## Task 13: Golden snapshots — DESeq2

**Files:**
- Create: `tests/testthat/test-golden-de.R`

This is the safety net for A3/A4. We hash the DE result table on the demo data and snapshot the hash; any future refactor that changes the math fails this test loudly.

- [ ] **Step 1: Write the failing test**

```r
test_that("DESeq2 result on demo data matches golden hash", {
  skip_on_cran()
  skip_if_not_installed("DESeq2")

  demo <- load_demo()
  data <- demo$counts[, demo_columns]
  data <- data[rowSums(data) > 10, ]

  params <- c("DESeq2", "NoCovariate", "parametric", FALSE, "Wald", "None")

  set.seed(1L)
  res <- runDE(data, demo$meta, demo_columns, demo_conds, params)
  res <- as.data.frame(res)

  # Sort to make the hash invariant to row-order shuffles introduced by
  # internal DESeq2 changes; only values matter.
  res <- res[order(rownames(res)), c("baseMean", "log2FoldChange", "padj"), drop = FALSE]

  expect_snapshot_value(stable_hash(res), style = "json2")
})
```

- [ ] **Step 2: Run to capture the snapshot**

```bash
R -q -e 'devtools::test(filter = "golden-de")' 2>&1 | tail -20
```

Expected: first run says "Adding new snapshot" — that's the snapshot being written. The test passes (snapshots auto-pass on first creation).

- [ ] **Step 3: Verify snapshot file exists**

```bash
ls tests/testthat/_snaps/golden-de/
cat tests/testthat/_snaps/golden-de/*.json2 | head -5
```

Expected: a `.json2` file containing the xxhash64 hex string.

- [ ] **Step 4: Run the test a second time and confirm it passes (no new snapshot)**

```bash
R -q -e 'devtools::test(filter = "golden-de")' 2>&1 | tail -10
```

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 1 ]`. No "Adding new snapshot" message.

- [ ] **Step 5: Commit**

```bash
git add tests/testthat/test-golden-de.R tests/testthat/_snaps/
git commit -m "test: lock golden hash for DESeq2 demo result

Hashes (baseMean, log2FoldChange, padj) sorted by gene id. This is the
A3/A4 safety net: any refactor that changes the math fails loudly."
```

---

## Task 14: Golden snapshots — edgeR and limma

**Files:**
- Modify: `tests/testthat/test-golden-de.R`

- [ ] **Step 1: Add edgeR test**

Append to `tests/testthat/test-golden-de.R`:

```r
test_that("EdgeR result on demo data matches golden hash", {
  skip_on_cran()
  skip_if_not_installed("edgeR")

  demo <- load_demo()
  data <- demo$counts[, demo_columns]
  data <- data[rowSums(data) > 10, ]

  params <- c("EdgeR", "NoCovariate", "TMM", "0", "exactTest")

  set.seed(1L)
  res <- as.data.frame(runDE(data, demo$meta, demo_columns, demo_conds, params))
  res <- res[order(rownames(res)), c("logFC", "PValue", "FDR"), drop = FALSE]

  expect_snapshot_value(stable_hash(res), style = "json2")
})
```

- [ ] **Step 2: Add limma test**

Append:

```r
test_that("Limma result on demo data matches golden hash", {
  skip_on_cran()
  skip_if_not_installed("limma")

  demo <- load_demo()
  data <- demo$counts[, demo_columns]
  data <- data[rowSums(data) > 10, ]

  params <- c("Limma", "NoCovariate", "TMM", "ls", "none")

  set.seed(1L)
  res <- as.data.frame(runDE(data, demo$meta, demo_columns, demo_conds, params))
  res <- res[order(rownames(res)), c("logFC", "P.Value", "adj.P.Val"), drop = FALSE]

  expect_snapshot_value(stable_hash(res), style = "json2")
})
```

- [ ] **Step 3: Run to capture both new snapshots**

```bash
R -q -e 'devtools::test(filter = "golden-de")' 2>&1 | tail -20
```

Expected: 2 "Adding new snapshot" messages. All 3 tests pass.

- [ ] **Step 4: Re-run; confirm stable**

```bash
R -q -e 'devtools::test(filter = "golden-de")' 2>&1 | tail -10
```

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 3 ]`.

- [ ] **Step 5: Commit**

```bash
git add tests/testthat/test-golden-de.R tests/testthat/_snaps/golden-de/
git commit -m "test: lock golden hashes for edgeR and limma demo results"
```

---

## Task 15: Golden snapshots — normalization + PCA

**Files:**
- Create: `tests/testthat/test-golden-normalize.R`

- [ ] **Step 1: Write the normalization snapshot test**

```r
test_that("getNormalizedMatrix on demo data matches golden hash", {
  skip_on_cran()

  demo <- load_demo()
  data <- demo$counts[, demo_columns]
  data <- data[rowSums(data) > 10, ]

  set.seed(1L)
  norm <- getNormalizedMatrix(data)
  norm <- norm[order(rownames(norm)), order(colnames(norm))]

  expect_snapshot_value(stable_hash(norm), style = "json2")
})
```

- [ ] **Step 2: Write the PCA snapshot test**

```r
test_that("plot_pca on demo normalized data matches golden coordinates", {
  skip_on_cran()

  demo <- load_demo()
  data <- demo$counts[, demo_columns]
  data <- data[rowSums(data) > 10, ]
  norm <- getNormalizedMatrix(data)

  set.seed(1L)
  pca <- prcomp(t(log2(norm + 1)))
  coords <- pca$x[, c("PC1", "PC2")]
  coords <- coords[order(rownames(coords)), ]

  expect_snapshot_value(stable_hash(coords), style = "json2")
})
```

- [ ] **Step 3: Run, capture, and verify**

```bash
R -q -e 'devtools::test(filter = "golden-normalize")' 2>&1 | tail -15
```

Expected: 2 new snapshots, then both tests pass on second run.

```bash
R -q -e 'devtools::test(filter = "golden-normalize")' 2>&1 | tail -10
```

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 2 ]`.

- [ ] **Step 4: Commit**

```bash
git add tests/testthat/test-golden-normalize.R tests/testthat/_snaps/golden-normalize/
git commit -m "test: lock golden hashes for normalization and PCA on demo data"
```

---

## Task 16: shinytest2 smoke test

**Files:**
- Create: `tests/shinytest2/setup.R`
- Create: `tests/shinytest2/test-smoke.R`
- Modify: `DESCRIPTION` (`Suggests: shinytest2`)

- [ ] **Step 1: Add shinytest2 to Suggests**

In `DESCRIPTION`, add `shinytest2` to the `Suggests:` block:

```
Suggests: testthat (>= 3.2.0),
    rmarkdown,
    knitr,
    digest,
    shinytest2
```

- [ ] **Step 2: Create `tests/shinytest2/setup.R`**

```r
# Minimal driver for the DEBrowser app, suitable for shinytest2.
# Returns a function() that yields the Shiny app object — shinytest2's
# AppDriver$new() accepts this.

debrowser_app <- function() {
  shiny::shinyApp(
    ui = debrowser::deUI(),
    server = function(input, output, session) {
      debrowser::deServer(input, output, session)
    }
  )
}
```

- [ ] **Step 3: Create the smoke test**

`tests/shinytest2/test-smoke.R`:

```r
library(testthat)
library(shinytest2)
source(testthat::test_path("../shinytest2/setup.R"))

test_that("loading demo data and running DESeq2 renders the MA plot", {
  skip_on_cran()
  skip_on_ci()  # turn on once Phase A4 stabilises module IDs
  skip_if_not_installed("shinytest2")

  app <- AppDriver$new(
    debrowser_app(),
    name = "smoke-demo-deseq2",
    timeout = 120000
  )
  on.exit(app$stop(), add = TRUE)

  # Stage 1: load demo data
  app$click("load-demo")
  app$wait_for_idle(timeout = 30000)

  # Move to DE analysis
  app$click("load-Filter")
  app$wait_for_idle()
  app$click("Filter")
  app$wait_for_idle()

  # Run with default DESeq2 params
  app$click("startDE")
  app$wait_for_idle(timeout = 60000)

  # Switch to Main Plots and confirm something rendered
  app$set_inputs(methodtabs = "panel1")
  app$wait_for_idle()

  expect_true(length(app$get_html("#main-mainplot")) > 0)
})
```

- [ ] **Step 4: Run locally to confirm the test infrastructure loads**

```bash
R -q -e 'testthat::test_file("tests/shinytest2/test-smoke.R")' 2>&1 | tail -15
```

Expected: test is **skipped** (`skip_on_ci()` is `FALSE` locally? — depends. If the test attempts to run, it will likely fail because module IDs differ from what's hardcoded. That's expected for now — Phase A4 stabilises IDs and we re-enable.)

The point of this task is to land the *infrastructure* (driver, file layout, dependency declaration), not to have the test passing yet.

- [ ] **Step 5: Add a README in `tests/shinytest2/` documenting the deferred-enablement state**

`tests/shinytest2/README.md`:

```markdown
# shinytest2 end-to-end tests

These tests are currently **skipped on CI** because the legacy app uses
ad-hoc input IDs that change as we refactor (Phase A4). They will be
re-enabled once modules have stable namespaced IDs.

To run locally:

    R -q -e 'testthat::test_file("tests/shinytest2/test-smoke.R")'
```

- [ ] **Step 6: Commit**

```bash
git add tests/shinytest2/ DESCRIPTION
git commit -m "test: add shinytest2 smoke-test scaffold (CI-skipped until A4)

End-to-end driver lands now so Phase A4 module migrations can flip the
skip off as IDs stabilise."
```

---

## Task 17: A2 milestone — push, verify, and tag

**Files:** none (verification only)

- [ ] **Step 1: Run the full test suite locally one more time**

```bash
R -q -e 'devtools::test()' 2>&1 | tail -25
```

Expected: all 4 migrated tests + 5 golden snapshot tests pass; shinytest2 skipped. Output ends with `[ FAIL 0 | WARN 0 | SKIP 1 | PASS 9 ]` (or similar — exact pass count depends on individual `expect_*` calls).

- [ ] **Step 2: Push**

```bash
git push umms modernize
```

- [ ] **Step 3: Verify CI is still green**

Visit GitHub Actions. Confirm:
- `R-CMD-check` (release + devel) green
- `BiocCheck` green
- `lintr` runs (warnings OK)
- `coverage` runs and reports a higher number than the A1 baseline

- [ ] **Step 4: Open a draft PR `modernize` → `devel`**

```bash
gh pr create --draft --base devel --head modernize \
  --title "Phase A1+A2: foundation (CI, lint, golden snapshots)" \
  --body "$(cat <<'EOF'
## Summary
Foundation sub-phases of the modernization roadmap. No application
code changed beyond the upload-size bump.

- A1: lintr+styler configs, R >= 4.2, RoxygenNote 7.3.2, GitHub
  Actions for R-CMD-check (release + devel), BiocCheck, lintr, covr.
- A2: testthat 3e migration, golden snapshot tests for DESeq2 / edgeR /
  limma / normalization / PCA, shinytest2 scaffold.

Spec: docs/superpowers/specs/2026-04-27-debrowser-modernization-design.md
Plan: docs/superpowers/plans/2026-04-27-phase-a1-a2-foundation.md

## Test plan
- [x] devtools::test() passes locally
- [x] R-CMD-check green on R-release and R-devel
- [x] BiocCheck green
- [x] Golden snapshots locked

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

(Draft PR — not for merge yet. Becomes the umbrella for review at the A4 decision point.)

**Milestone reached: A2 done — golden snapshots locked. This is the "real point of no return" decision point in the spec. Phase A3 (extract pure functions) gets its own plan, written next.**

---

## Self-Review

**Spec coverage check (A1):**
- [x] `.Rbuildignore` extended → Task 3
- [x] Delete empty `viafoundry_errors.log` → Task 2
- [x] Bump `R (>= 4.2)` → Task 4
- [x] Update `RoxygenNote` to 7.3.x → Task 4
- [x] `lintr` + `styler` configs → Tasks 5, 6
- [x] GitHub Actions: R-CMD-check, BiocCheck, lintr, covr → Tasks 7–10
- [x] Commit upload-size bump → Task 1

**Spec coverage check (A2):**
- [x] Migrate to `tests/testthat/test-*.R` testthat 3e → Task 12
- [x] Delete orphaned dead code in `test-deseq.R` → Task 12, Step 4 note
- [x] Golden DESeq2 result hash → Task 13
- [x] Golden edgeR result hash → Task 14
- [x] Golden limma result hash → Task 14
- [x] Golden normalized matrix hash → Task 15
- [x] Golden PCA coordinates → Task 15
- [x] shinytest2 smoke test (load demo → DESeq2 → MA renders) → Task 16

**Placeholder scan:** no TBD/TODO; every step has the actual code or command. Task 16's shinytest2 test is intentionally `skip_on_ci()` — that's a real (documented) deferral, not a placeholder.

**Type/name consistency:** `load_demo()`, `stable_hash()`, `demo_columns`, `demo_conds` defined in helper (Task 12) and referenced in Tasks 13/14/15. `runDE()`, `getNormalizedMatrix()`, `plot_pca()`, `compareClust()`, `getGOPlots()`, `getQCPanel()`, etc. all match existing exports in current code (verified against `R/funcs.R` and `R/deprogs.R`).

**Branch flow:** Task 0 establishes `modernize` off `devel` and cherry-picks the existing spec commits; all subsequent tasks land there. No work touches `RELEASE_3_18`.
