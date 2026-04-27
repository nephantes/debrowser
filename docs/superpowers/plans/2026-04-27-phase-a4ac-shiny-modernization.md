# Phase A4a + A4c: Shiny API Modernization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Migrate the existing 13 modules from Shiny's deprecated `callModule()` API to `moduleServer()` (the modern Shiny 1.5+ idiom), strip the `library("debrowser")` self-reference inside `deUI()`, replace the runtime `installpack()`/`loadpack()` package-loading hacks with proper `Suggests` + `requireNamespace()` checks, and drop the dead `aes_string` import line. After this plan ships, the only structural cleanup left in Phase A is condSelect.R's full rewrite — which is deliberately deferred to Phase B2 where the new three-stage shell will redesign it anyway.

**Architecture:** Pure refactor. No analytic logic touched. Every change is mechanical and locally verifiable: each module follows an identical pattern (function signature change + `moduleServer(id, function(input, output, session) { … })` wrapper); each call site changes from `callModule(name, "id", args)` to `name("id", args)`. The `installpack` removal swaps imperative side-effect code for declarative `requireNamespace()` guards. Existing golden snapshot and unit tests are the regression-detection net.

**Tech Stack:** Shiny ≥ 1.5 (`moduleServer`), `requireNamespace()` for soft-dep checks. No new dependencies.

**Spec reference:** [docs/superpowers/specs/2026-04-27-debrowser-modernization-design.md](../specs/2026-04-27-debrowser-modernization-design.md) — section "Phase A — A4" cleanup items: `library("debrowser")` removal, `aes_string` deprecation, `installpack`/`loadpack` removal. Module migration is the umbrella under which these land.

**Predecessor:** [docs/superpowers/plans/2026-04-27-phase-a3b-pure-prepdata.md](2026-04-27-phase-a3b-pure-prepdata.md) must be merged. Branch: `modernize`.

---

## Why condSelect is NOT in this plan

`R/condSelect.R` (660 LOC) is the only file in the repo that's *not* already a module — its `debrowsercondselect()` function is wired in `server.R` as plain functions (not `callModule`). Its docstring even says "This is not a module."

Untangling it is a real design problem, not a mechanical refactor:

- Three overlapping code paths: `getConditionSelector()`, `getConditionSelectorFromMeta()`, `selectConditions()`.
- Dead branches: `if (length(grps) == -1)` at `R/condSelect.R:213` (length is non-negative; this can never execute).
- Reactive rebuild storm: every `showNotification(..., type = "error")` call (lines 360, 377, 400, 407, 415) fires during normal interaction.
- Phase B2 (three-stage shell wizard) will redesign the entire condition-picker UX with "Treatment vs Control" language.

Doing the modularization here, then redesigning in B2, would be wasted work. So condSelect is folded into B2 (or its own A4b plan) — not this one.

---

## Inventory of changes

### Modules to migrate (13)

| Function | File | Used at call site(s) |
|---|---|---|
| `debrowserdataload` | `R/dataLoad.R` | `R/server.R:127`, `R/heatmap.R:778` |
| `debrowserlowcountfilter` | `R/lowcountfilter.R` | `R/server.R:133` |
| `debrowserbatcheffect` | `R/batcheffect.R` | `R/server.R:139` |
| `debrowserhistogram` | `R/histogram.R` | `R/lowcountfilter.R:61, 65` |
| `debrowserpcaplot` | `R/pca.R` | `R/batcheffect.R:70, 76`; `R/server.R:340` |
| `debrowserIQRplot` | `R/IQR.R` | `R/batcheffect.R:71, 77`; `R/server.R:344, 345` |
| `debrowserdensityplot` | `R/density.R` | `R/batcheffect.R:72, 78`; `R/server.R:347, 348` |
| `debrowserall2all` | `R/all2all.R` | `R/server.R:338` |
| `debrowserheatmap` | `R/heatmap.R` | `R/server.R:342, 367`; `R/heatmap.R:800` |
| `debrowsermainplot` | `R/mainScatter.R` | `R/server.R:360` |
| `debrowserbarmainplot` | `R/barmain.R` | `R/server.R:393` |
| `debrowserboxmainplot` | `R/boxmain.R` | `R/server.R:397` |
| `debrowserdeanalysis` | `R/deprogs.R` | `R/condSelect.R:769` |

### Anti-patterns to fix

- `R/ui.R:24`: `library("debrowser")` inside `deUI()` — the module is loading itself. Self-import is a no-op at best, anti-pattern at worst.
- `R/installpack.R`: the entire `installpack()` / `loadpack()` pair — runtime side-effect package loading. Replace with `requireNamespace(pkg, quietly = TRUE)` checks at call sites.
- `R/GOterm.R`: 7 sites call `installpack()` (lines 25, 62, 102, 146, 342, 366, 447). Each becomes a `requireNamespace()` guard.
- `R/server.R:37`: `aes_string` listed in `@importFrom ggplot2`. The function is deprecated since ggplot2 3.0. `grep`ping confirms it's only in the @importFrom line — never actually called. Drop it.

---

## The migration recipe

For each module, the pattern is identical:

**Before:**
```r
debrowserdataload <- function(input = NULL, output = NULL, session = NULL,
                              nextpagebutton = NULL) {
  if (is.null(input)) return(NULL)
  ldata <- reactiveValues(count = NULL, meta = NULL)
  # … rest of body …
  list(load = loadeddata)
}
```
Called as: `callModule(debrowserdataload, "load", "Filter")`

**After:**
```r
debrowserdataload <- function(id, nextpagebutton = NULL) {
  moduleServer(id, function(input, output, session) {
    ldata <- reactiveValues(count = NULL, meta = NULL)
    # … rest of body unchanged …
    list(load = loadeddata)
  })
}
```
Called as: `debrowserdataload("load", "Filter")`

**Critical detail:** the existing body of every module already uses `input$x`, `output$y`, `session$ns()`. After wrapping in `moduleServer(id, function(input, output, session) { … })`, those references resolve correctly *without any internal changes*. The only edits are:
1. The function signature (drop `input/output/session`, take `id` first).
2. Wrap the body in `moduleServer(id, function(input, output, session) { … })`.
3. Drop the leading `if (is.null(input)) return(NULL)` guard (`moduleServer` doesn't run server bodies until the module is actually instantiated).

**Critical detail #2:** `moduleServer()` returns the value of the function it wraps. So `list(load = loadeddata)` flows through unchanged.

---

## File Map

| File | Action | Purpose |
|---|---|---|
| `R/dataLoad.R` | modify | Convert `debrowserdataload` to `moduleServer` |
| `R/lowcountfilter.R` | modify | Convert `debrowserlowcountfilter`; update internal `callModule(debrowserhistogram, …)` call |
| `R/batcheffect.R` | modify | Convert `debrowserbatcheffect`; update 6 internal `callModule(...)` calls |
| `R/histogram.R` | modify | Convert `debrowserhistogram` |
| `R/pca.R` | modify | Convert `debrowserpcaplot` |
| `R/IQR.R` | modify | Convert `debrowserIQRplot` |
| `R/density.R` | modify | Convert `debrowserdensityplot` |
| `R/all2all.R` | modify | Convert `debrowserall2all` |
| `R/heatmap.R` | modify | Convert `debrowserheatmap`; update 1 internal `callModule(debrowserdataload, …)` call |
| `R/mainScatter.R` | modify | Convert `debrowsermainplot` |
| `R/barmain.R` | modify | Convert `debrowserbarmainplot` |
| `R/boxmain.R` | modify | Convert `debrowserboxmainplot` |
| `R/deprogs.R` | modify | Convert `debrowserdeanalysis` |
| `R/server.R` | modify | Update 13 `callModule()` call sites; drop `aes_string` from `@importFrom` |
| `R/condSelect.R` | modify | Update 1 `callModule(debrowserdeanalysis, …)` call (file otherwise untouched — A4b will rewrite it) |
| `R/ui.R` | modify | Remove `library("debrowser")` line |
| `R/GOterm.R` | modify | Replace `installpack(org)` with `requireNamespace(org, quietly = TRUE)` checks |
| `R/installpack.R` | delete | Functions replaced everywhere |
| `man/installpack.Rd` | delete | Stale doc |
| `man/loadpack.Rd` | delete | Stale doc |
| `tests/shinytest2/test-smoke.R` | modify | Remove `skip_on_ci()` — module IDs are now stable |
| `NEWS.md` | modify | Log A4ac |

---

## Task 0: Confirm starting state

**Files:** none (verification)

- [ ] **Step 1: Confirm clean tree and full suite green**

```bash
git -C /Users/alper/workdir/debrowser status
R -q -e 'devtools::test("/Users/alper/workdir/debrowser")' 2>&1 | tail -5
```

Expected: `nothing to commit, working tree clean` and `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 88 ]`. If either fails, **stop**.

- [ ] **Step 2: Confirm 26 callModule sites and the helper inventory**

```bash
grep -rn "callModule" /Users/alper/workdir/debrowser/R/ | grep -v "@importFrom\|callModule callModule" | wc -l
grep -rn "installpack\|loadpack" /Users/alper/workdir/debrowser/R/ | grep -v "^/Users/alper/workdir/debrowser/R/installpack.R" | wc -l
grep -n "aes_string" /Users/alper/workdir/debrowser/R/server.R
```

Expected: `26` callModule sites, `7` installpack call sites (in `R/GOterm.R`), the `@importFrom ggplot2 aes aes_string …` line in `R/server.R:37`. If counts differ, **stop and re-investigate** — the inventory is the basis of every other task in this plan.

---

## Task 1: Convert leaf modules (no inner `callModule` calls)

**Files:**
- Modify: `R/dataLoad.R`, `R/histogram.R`, `R/pca.R`, `R/IQR.R`, `R/density.R`, `R/all2all.R`, `R/mainScatter.R`, `R/barmain.R`, `R/boxmain.R`

**Why "leaf" first:** these 9 modules don't call `callModule` from inside themselves. Migrating them first means call-site updates in Task 4 are mechanical because the module signatures match the new pattern.

For EACH file in the list above, do this 2-step edit:

**Edit pattern:**

Find the function definition that looks like:
```r
debrowserNAME <- function(input = NULL, output = NULL, session = NULL, ARG1 = NULL, ARG2 = NULL) {
  if (is.null(input)) return(NULL)
  BODY
}
```

Replace with:
```r
debrowserNAME <- function(id, ARG1 = NULL, ARG2 = NULL) {
  moduleServer(id, function(input, output, session) {
    BODY
  })
}
```

Note three exact differences only:
1. Signature: `function(id, ARG1 = NULL, ARG2 = NULL)` (drop `input/output/session`, prepend `id`).
2. Body wrapper: `moduleServer(id, function(input, output, session) { … })`.
3. Drop the `if (is.null(input)) return(NULL)` guard line.

**Per-file specifics:**

- [ ] **Step 1: `R/dataLoad.R` line 17**

`debrowserdataload`'s args (after migration): `function(id, nextpagebutton = NULL)`. The body's references to `session$ns()`, `input$xxx`, `output$xxx` are unchanged.

- [ ] **Step 2: `R/histogram.R` line 34**

`debrowserhistogram`'s args: `function(id, data = NULL)`.

- [ ] **Step 3: `R/pca.R` line 36**

`debrowserpcaplot`'s args: `function(id, pcadata = NULL, metadata = NULL)`.

- [ ] **Step 4: `R/IQR.R` line 16**

`debrowserIQRplot`'s args: `function(id, data = NULL)`.

- [ ] **Step 5: `R/density.R` line 34**

`debrowserdensityplot`'s args: `function(id, data = NULL)`.

- [ ] **Step 6: `R/all2all.R`**

Open and inspect to confirm the function name and signature; make the same conversion.

- [ ] **Step 7: `R/mainScatter.R` line 19**

`debrowsermainplot`'s args: `function(id, data = NULL, cond_names = NULL)`.

- [ ] **Step 8: `R/barmain.R` line 20**

`debrowserbarmainplot`'s args (preserve any extra args present in the original): `function(id, data = NULL, …)`. Read the file first to confirm the full signature.

- [ ] **Step 9: `R/boxmain.R` line 38**

`debrowserboxmainplot`'s args: same idea. Read first.

- [ ] **Step 10: After all 9 files are converted, confirm the package still loads and tests pass**

```bash
R -q -e 'pkgload::load_all("/Users/alper/workdir/debrowser")' 2>&1 | tail -5
R -q -e 'devtools::test("/Users/alper/workdir/debrowser")' 2>&1 | tail -5
```

Expected: load succeeds; tests still `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 88 ]`. The module *signatures* changed but no call sites use the modules yet (call sites get updated in Task 4), so unit tests don't exercise the new signatures.

- [ ] **Step 11: Commit**

```bash
git add R/dataLoad.R R/histogram.R R/pca.R R/IQR.R R/density.R R/all2all.R R/mainScatter.R R/barmain.R R/boxmain.R
git commit -m "refactor: migrate 9 leaf modules to moduleServer() (Shiny 1.5+)

debrowserdataload, debrowserhistogram, debrowserpcaplot,
debrowserIQRplot, debrowserdensityplot, debrowserall2all,
debrowsermainplot, debrowserbarmainplot, debrowserboxmainplot.

Mechanical conversion only: signature now takes id first, body
wrapped in moduleServer(). Behavior unchanged. Call sites get
updated in a later commit."
```

---

## Task 2: Convert nested modules (those with inner `callModule` calls)

**Files:**
- Modify: `R/lowcountfilter.R`, `R/batcheffect.R`, `R/heatmap.R`

These modules invoke OTHER modules from inside their server bodies. Since Task 1 converted those targets to the new signature, the inner calls have to update simultaneously.

- [ ] **Step 1: `R/lowcountfilter.R`**

Convert `debrowserlowcountfilter` (line 17) to `moduleServer` per the recipe in Task 1. Then update the two internal calls:

Find:
```r
callModule(debrowserhistogram, "beforeFiltering", ldata$count)
```
Change to:
```r
debrowserhistogram("beforeFiltering", ldata$count)
```

Find:
```r
callModule(debrowserhistogram, "afterFiltering", filtereddata()$count)
```
Change to:
```r
debrowserhistogram("afterFiltering", filtereddata()$count)
```

- [ ] **Step 2: `R/batcheffect.R`**

Convert `debrowserbatcheffect` (line 17) to `moduleServer`. Then update the 6 internal calls:

```r
# Before -> After (inside the observe() block around lines 70-78):
callModule(debrowserpcaplot, "beforeCorrectionPCA", ldata$count, ldata$meta)
# becomes
debrowserpcaplot("beforeCorrectionPCA", ldata$count, ldata$meta)
```

Apply the same transform to all 6 internal calls (lines 70-78 in the pre-migration file, but line numbers will shift after the wrapping):

- `callModule(debrowserpcaplot, "beforeCorrectionPCA", ldata$count, ldata$meta)` → `debrowserpcaplot("beforeCorrectionPCA", ldata$count, ldata$meta)`
- `callModule(debrowserIQRplot, "beforeCorrectionIQR", ldata$count)` → `debrowserIQRplot("beforeCorrectionIQR", ldata$count)`
- `callModule(debrowserdensityplot, "beforeCorrectionDensity", ldata$count)` → `debrowserdensityplot("beforeCorrectionDensity", ldata$count)`
- `callModule(debrowserpcaplot, "afterCorrectionPCA", batcheffectdata()$count, batcheffectdata()$meta)` → `debrowserpcaplot("afterCorrectionPCA", batcheffectdata()$count, batcheffectdata()$meta)`
- `callModule(debrowserIQRplot, "afterCorrectionIQR", batcheffectdata()$count)` → `debrowserIQRplot("afterCorrectionIQR", batcheffectdata()$count)`
- `callModule(debrowserdensityplot, "afterCorrectionDensity", batcheffectdata()$count)` → `debrowserdensityplot("afterCorrectionDensity", batcheffectdata()$count)`

- [ ] **Step 3: `R/heatmap.R`**

Convert `debrowserheatmap` (line 17) to `moduleServer` per the recipe. Then update the 2 internal calls (around lines 778, 800):

- `callModule(debrowserdataload, "load", "Submit")` → `debrowserdataload("load", "Submit")`
- `callModule(debrowserheatmap, "heatmap", expdata())` → `debrowserheatmap("heatmap", expdata())`

- [ ] **Step 4: Run tests**

```bash
R -q -e 'devtools::test("/Users/alper/workdir/debrowser")' 2>&1 | tail -5
```

Expected: still `PASS 88`. The unit tests don't instantiate Shiny modules — they only verify the helpers and pure functions still work. The shinytest2 smoke is still skipped.

- [ ] **Step 5: Commit**

```bash
git add R/lowcountfilter.R R/batcheffect.R R/heatmap.R
git commit -m "refactor: migrate nested modules to moduleServer()

debrowserlowcountfilter, debrowserbatcheffect, debrowserheatmap.
Their internal calls (debrowserhistogram, debrowserpcaplot,
debrowserIQRplot, debrowserdensityplot, debrowserdataload,
debrowserheatmap) updated from callModule(name, id, ...) to
name(id, ...) form."
```

---

## Task 3: Convert `debrowserdeanalysis` and update its single caller

**Files:**
- Modify: `R/deprogs.R`, `R/condSelect.R`

`debrowserdeanalysis` is called from one place: `R/condSelect.R:769`. condSelect itself stays untouched (deferred to A4b/B2) — we only update the one inner `callModule(debrowserdeanalysis, ...)` line so it matches the new signature.

- [ ] **Step 1: Convert `debrowserdeanalysis` in `R/deprogs.R` (line 19)**

Apply the standard recipe. The body's `callModule(debrowserdataload, …)` does NOT exist here, so this is a leaf-style conversion. The signature becomes:

```r
debrowserdeanalysis <- function(id, data = NULL, metadata = NULL,
                                columns = NULL, conds = NULL, params = NULL) {
  moduleServer(id, function(input, output, session) {
    # original body
  })
}
```

- [ ] **Step 2: Update the call in `R/condSelect.R:769`**

Find:
```r
initd <- callModule(debrowserdeanalysis, paste0("DEResults", i),
  data = data, metadata = meta,
  columns = cols, conds = conds, params = params
)
```

Replace with:
```r
initd <- debrowserdeanalysis(paste0("DEResults", i),
  data = data, metadata = meta,
  columns = cols, conds = conds, params = params
)
```

- [ ] **Step 3: Run tests**

```bash
R -q -e 'devtools::test("/Users/alper/workdir/debrowser")' 2>&1 | tail -5
```

Expected: still `PASS 88`.

- [ ] **Step 4: Commit**

```bash
git add R/deprogs.R R/condSelect.R
git commit -m "refactor: migrate debrowserdeanalysis to moduleServer()

Updates the one caller in condSelect.R:769. condSelect.R itself stays
untouched (deferred to A4b/B2 for full rewrite)."
```

---

## Task 4: Update all `callModule()` call sites in `R/server.R`

**Files:**
- Modify: `R/server.R`

The 13 module functions all have the new signature now. server.R is the last place using the old `callModule()` form.

- [ ] **Step 1: Replace each call site**

For each pair below, replace the left side with the right side in `R/server.R`:

| Before | After |
|---|---|
| `callModule(debrowserdataload, "load", "Filter")` | `debrowserdataload("load", "Filter")` |
| `callModule(debrowserlowcountfilter, "lcf", updata()$load())` | `debrowserlowcountfilter("lcf", updata()$load())` |
| `callModule(debrowserbatcheffect, "batcheffect", filtd()$filter())` | `debrowserbatcheffect("batcheffect", filtd()$filter())` |
| `callModule(debrowserall2all, "all2all", normdat(), input$cex)` | `debrowserall2all("all2all", normdat(), input$cex)` |
| `callModule(debrowserpcaplot, "qcpca", normdat(), batch()$BatchEffect()$meta)` | `debrowserpcaplot("qcpca", normdat(), batch()$BatchEffect()$meta)` |
| `callModule(debrowserheatmap, "heatmapQC", normdat())` | `debrowserheatmap("heatmapQC", normdat())` |
| `callModule(debrowserIQRplot, "IQR", df_select())` | `debrowserIQRplot("IQR", df_select())` |
| `callModule(debrowserIQRplot, "normIQR", normdat())` | `debrowserIQRplot("normIQR", normdat())` |
| `callModule(debrowserdensityplot, "density", df_select())` | `debrowserdensityplot("density", df_select())` |
| `callModule(debrowserdensityplot, "normdensity", normdat())` | `debrowserdensityplot("normdensity", normdat())` |
| `callModule(debrowsermainplot, "main", filt_data(), cond_names())` | `debrowsermainplot("main", filt_data(), cond_names())` |
| `callModule(debrowserheatmap, "heatmap", filt_data()[selectedMain()$selGenes(), cols()])` | `debrowserheatmap("heatmap", filt_data()[selectedMain()$selGenes(), cols()])` |

For lines 393 and 397 (multi-line `callModule(` calls — read the file to see the exact form), apply the same transformation: drop the `callModule(` and the function-name arg, keep the `"id"` and the rest.

- [ ] **Step 2: Verify no `callModule(` remains in the source**

```bash
grep -rn "callModule" /Users/alper/workdir/debrowser/R/ | grep -v "@importFrom\|callModule callModule"
```

Expected: empty output. The only remaining mentions of `callModule` should be in docstrings/comments referring to the old API.

- [ ] **Step 3: Drop `callModule` from the `@importFrom shiny` line in `R/server.R:27`**

The line currently lists `callModule` among many others. Remove just that token:

Find (around line 27 — exact text may vary slightly):
```
#'             updateQueryString callModule enableBookmarking htmlOutput
```

Replace with:
```
#'             updateQueryString enableBookmarking htmlOutput
```

- [ ] **Step 4: Re-run tests + load**

```bash
R -q -e 'pkgload::load_all("/Users/alper/workdir/debrowser"); devtools::test("/Users/alper/workdir/debrowser")' 2>&1 | tail -5
```

Expected: clean load + `PASS 88`.

- [ ] **Step 5: Regenerate Roxygen NAMESPACE so the @importFrom drop takes effect**

```bash
R -q -e 'roxygen2::roxygenise("/Users/alper/workdir/debrowser")' 2>&1 | tail -3
```

The diff to `NAMESPACE` should drop `importFrom(shiny,callModule)` (or similar).

- [ ] **Step 6: Commit**

```bash
git add R/server.R NAMESPACE
git commit -m "refactor: switch all server.R callModule sites to moduleServer

Drops callModule from the shiny @importFrom too — no longer used
anywhere in the package. Closes the Shiny 1.5+ migration."
```

---

## Task 5: Remove `library("debrowser")` from `R/ui.R`

**Files:**
- Modify: `R/ui.R`

- [ ] **Step 1: Find and delete the line**

In `R/ui.R`, find:
```r
  library("debrowser")
```
(currently at line 24, but may shift). Delete the entire line.

This is safe because: the package is *being loaded* when `deUI()` is called (it's a function inside the package). `library("debrowser")` inside its own function body is a no-op at best, and at worst attaches the package to the search path of whoever calls `deUI()` — which is unwanted side-effect behavior.

- [ ] **Step 2: Run tests**

```bash
R -q -e 'devtools::test("/Users/alper/workdir/debrowser")' 2>&1 | tail -5
```

Expected: `PASS 88` unchanged.

- [ ] **Step 3: Commit**

```bash
git add R/ui.R
git commit -m "refactor: drop library(\"debrowser\") self-import inside deUI()

The package is by definition loaded by the time deUI() runs (the
function lives inside it). The line was a no-op at best and a
side-effect (attaching to the caller's search path) at worst."
```

---

## Task 6: Replace `installpack()` with `requireNamespace()` in `R/GOterm.R`

**Files:**
- Modify: `R/GOterm.R`

`installpack(pkg)` does two things: side-effect-load the package via `library()`, and surface a `showNotification()` error if missing. We replace with `requireNamespace(pkg, quietly = TRUE)` which checks availability without attaching, and raise the user-facing error using `showNotification()` directly at the call site.

- [ ] **Step 1: Find every `installpack()` call**

```bash
grep -n "installpack" /Users/alper/workdir/debrowser/R/GOterm.R
```

Expected: 7 lines (25, 62, 102, 146, 342, 366, 447 in the pre-migration file).

- [ ] **Step 2: For each call, apply the replacement**

Each call currently looks like one of:

Pattern A (with notification handled inside `installpack`):
```r
if (!installpack(org)) {
  return(NULL)
}
```

Replace with:
```r
if (!requireNamespace(org, quietly = TRUE)) {
  showNotification(
    paste0("Please install ", org, " to use this function."),
    type = "error"
  )
  return(NULL)
}
```

Pattern B (line 366, 447 — passing literal `"DOSE"` or `"pathview"`):
```r
if (!installpack("DOSE")) {
```

Replace with:
```r
if (!requireNamespace("DOSE", quietly = TRUE)) {
```

(and add the matching `showNotification` + `return(NULL)` if the original branch did so — read the surrounding 5 lines of each site to see the full block).

For pattern B at line 447 (`if (installpack("pathview")) { … }` — note the inverted logic), simply replace `installpack("pathview")` with `requireNamespace("pathview", quietly = TRUE)`. No new error block needed — the original code had a "true branch" that required the package; now the same true branch runs only when the package is installed.

- [ ] **Step 3: Confirm no `installpack`/`loadpack` references remain in `R/GOterm.R`**

```bash
grep -n "installpack\|loadpack" /Users/alper/workdir/debrowser/R/GOterm.R
```

Expected: empty.

- [ ] **Step 4: Run tests**

```bash
R -q -e 'devtools::test("/Users/alper/workdir/debrowser")' 2>&1 | tail -5
```

Expected: `PASS 88`.

- [ ] **Step 5: Commit**

```bash
git add R/GOterm.R
git commit -m "refactor: replace installpack() with requireNamespace() in GOterm.R

Drops the side-effect package-loading hack. requireNamespace() checks
availability without attaching to the search path; the showNotification()
error message moves to each call site (5 sites use the same template
with the user-supplied 'org' variable; 2 sites use literal package
names DOSE and pathview)."
```

---

## Task 7: Delete `R/installpack.R` and its man pages

**Files:**
- Delete: `R/installpack.R`, `man/installpack.Rd`, `man/loadpack.Rd`
- Modify: `NAMESPACE` (regenerated)

- [ ] **Step 1: Confirm no remaining call sites**

```bash
grep -rn "installpack\|loadpack" /Users/alper/workdir/debrowser/R/ | grep -v "^/Users/alper/workdir/debrowser/R/installpack.R"
```

Expected: empty. If anything matches, **stop** and convert that site too before deleting.

- [ ] **Step 2: Delete the file and stale docs**

```bash
git rm R/installpack.R man/installpack.Rd man/loadpack.Rd
```

Also remove the `R/installpack.R` exclusion in `.lintr` (no longer needed):

In `/Users/alper/workdir/debrowser/.lintr`, the `exclusions` line currently reads:
```
exclusions: list("tests/testthat/_snaps", "man", "R/installpack.R")
```
Change to:
```
exclusions: list("tests/testthat/_snaps", "man")
```

- [ ] **Step 3: Regenerate Roxygen NAMESPACE**

```bash
R -q -e 'roxygen2::roxygenise("/Users/alper/workdir/debrowser")' 2>&1 | tail -3
```

Expect `export(installpack)` and `export(loadpack)` to disappear from `NAMESPACE`.

- [ ] **Step 4: Run tests + build**

```bash
R -q -e 'devtools::test("/Users/alper/workdir/debrowser")' 2>&1 | tail -5
cd /tmp && R CMD build /Users/alper/workdir/debrowser --no-build-vignettes --no-manual 2>&1 | tail -3
rm -f /tmp/debrowser_*.tar.gz
```

Expected: tests `PASS 88`; build clean.

- [ ] **Step 5: Commit**

```bash
git add R/installpack.R R/.lintr man/installpack.Rd man/loadpack.Rd NAMESPACE .lintr
git commit -m "refactor: remove installpack()/loadpack() — replaced by requireNamespace()

R/installpack.R and its two exported functions are gone; all call
sites in R/GOterm.R now use the standard requireNamespace() idiom.
Also drops the .lintr exclusion that was protecting installpack.R."
```

---

## Task 8: Drop the unused `aes_string` import from `R/server.R`

**Files:**
- Modify: `R/server.R`
- Modify: `NAMESPACE` (regenerated)

`aes_string` from ggplot2 is deprecated since ggplot2 3.0 (2018). A grep across all of `R/` confirms it's only listed in the `@importFrom ggplot2` line at `R/server.R:37` — never actually called. Drop it.

- [ ] **Step 1: Confirm no actual call sites**

```bash
grep -rn "aes_string" /Users/alper/workdir/debrowser/R/ | grep -v "@importFrom"
```

Expected: empty.

- [ ] **Step 2: Edit `R/server.R:37`**

Find the line that reads (approximately):
```
#' @importFrom ggplot2 aes aes_string geom_bar geom_point ggplot
```

Replace with:
```
#' @importFrom ggplot2 aes geom_bar geom_point ggplot
```

(Just delete the `aes_string ` token. Keep the rest.)

- [ ] **Step 3: Regenerate Roxygen NAMESPACE**

```bash
R -q -e 'roxygen2::roxygenise("/Users/alper/workdir/debrowser")' 2>&1 | tail -3
```

Expect `importFrom(ggplot2,aes_string)` to disappear from `NAMESPACE`.

- [ ] **Step 4: Run tests**

```bash
R -q -e 'devtools::test("/Users/alper/workdir/debrowser")' 2>&1 | tail -5
```

Expected: `PASS 88`.

- [ ] **Step 5: Commit**

```bash
git add R/server.R NAMESPACE
git commit -m "refactor: drop unused aes_string import (deprecated since ggplot2 3.0)"
```

---

## Task 9: Enable the shinytest2 smoke test

**Files:**
- Modify: `tests/shinytest2/test-smoke.R`

The A2 plan added a `shinytest2` smoke test scaffold marked `skip_on_ci()` because module IDs were unstable. After A4ac, the IDs are now namespaced consistently — try removing the skip.

- [ ] **Step 1: Read the current test**

```bash
cat /Users/alper/workdir/debrowser/tests/shinytest2/test-smoke.R
```

- [ ] **Step 2: Try running it locally first to see what happens**

```bash
R -q -e 'testthat::test_file("/Users/alper/workdir/debrowser/tests/shinytest2/test-smoke.R")' 2>&1 | tail -20
```

Expected behavior (one of):
- Test runs and passes — great, ready to enable in CI.
- Test fails because the legacy module IDs in the test (`"load-demo"`, `"load-Filter"`, `"#main-mainplot"`, etc.) don't match what the new module structure produces. **In that case, leave the skip in place** (the IDs are still legacy-shaped because the modules' UI builders haven't been refactored), update the test selectors to match the actual rendered IDs, and re-run.

- [ ] **Step 3: If the test passes locally, remove `skip_on_ci()`**

In `tests/shinytest2/test-smoke.R`, find:
```r
  skip_on_ci() # turn on once Phase A4 stabilises module IDs
```
Delete the entire line.

- [ ] **Step 4: If the test still doesn't pass locally, document the deferral**

Update the test's `skip_on_ci()` comment to point at the next deferral target (Phase B2 wizard), and update `tests/shinytest2/README.md` likewise:

```r
  skip_on_ci() # turn on after Phase B2's three-stage shell stabilises top-level IDs
```

In `tests/shinytest2/README.md`, replace `Phase A4` → `Phase B2`.

- [ ] **Step 5: Commit**

```bash
git add tests/shinytest2/
git commit -m "test: re-evaluate shinytest2 smoke after A4 module migration

[Either: 'Enable on CI now that module IDs are stable.'
 Or: 'Defer enablement to Phase B2 — top-level IDs still legacy-shaped
      because UI builders weren't refactored in A4.']"
```

(Pick whichever message matches what actually happened in Step 2.)

---

## Task 10: A4ac milestone — final verification + NEWS

**Files:**
- Modify: `NEWS.md`

- [ ] **Step 1: Final full-suite + build**

```bash
R -q -e 'devtools::test("/Users/alper/workdir/debrowser")' 2>&1 | tail -5
cd /tmp && R CMD build /Users/alper/workdir/debrowser --no-build-vignettes --no-manual 2>&1 | tail -5
rm -f /tmp/debrowser_*.tar.gz
```

Expected: `PASS 88` (or higher if shinytest2 was enabled in Task 9); build clean.

- [ ] **Step 2: Verify the inventory ended up at the right shape**

```bash
echo "callModule sites (expect 0):"
grep -rn "callModule" /Users/alper/workdir/debrowser/R/ | grep -v "@importFrom\|callModule callModule" | wc -l

echo "moduleServer sites (expect 13):"
grep -rn "moduleServer" /Users/alper/workdir/debrowser/R/ | wc -l

echo "installpack/loadpack sites (expect 0):"
grep -rn "installpack\|loadpack" /Users/alper/workdir/debrowser/R/

echo "aes_string in source (expect 0):"
grep -rn "aes_string" /Users/alper/workdir/debrowser/R/

echo "library(\"debrowser\") in source (expect 0):"
grep -rn 'library("debrowser")' /Users/alper/workdir/debrowser/R/
```

If any line shows a different count than expected, **investigate before committing**.

- [ ] **Step 3: Add A4ac entry to `NEWS.md`** (insert after the A3b section, before `### User-visible`)

```markdown
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
  in `R/GOterm.R`. Deleted `R/installpack.R` and its exported functions.
* Dropped the unused `aes_string` import (deprecated in ggplot2 3.0).
* `condSelect.R` is deliberately left untouched — full rewrite folded
  into Phase B2 alongside the three-stage-shell wizard redesign.
```

- [ ] **Step 4: Commit**

```bash
git add NEWS.md
git commit -m "docs: log Phase A4a + A4c in NEWS.md"
```

**Milestone reached: A4ac done. Phase A is essentially complete except for A4b (condSelect rewrite, deferred to B2) and A5 (slim `Imports` to `Suggests`, can land any time).**

---

## Self-Review

**Spec coverage check (A4 — items in scope for this plan):**
- [x] Modularize Shiny — all 13 existing modules migrated to `moduleServer` (Tasks 1, 2, 3); call sites updated (Tasks 2, 3, 4)
- [x] Remove `library("debrowser")` inside `deUI()` — Task 5
- [x] Replace `aes_string()` with `aes(.data[[...]])` — Task 8 (only @importFrom referenced it; no call sites needed updating)
- [x] Remove `installpack`/`loadpack` runtime install hacks — Tasks 6, 7
- [x] Re-evaluate `shinytest2` smoke (was skipped pending A4) — Task 9
- [x] `condSelect.R` rewrite — explicitly DEFERRED with rationale, not skipped accidentally

**Spec coverage gaps deliberately deferred:**
- A4b (condSelect.R rewrite) — folded into Phase B2
- A5 (slim Imports → Suggests) — can land any time after A4ac; will be its own short plan

**Placeholder scan:** every step has actual code or actual command. Task 9 is conditional (depends on whether the smoke test runs against the new module IDs); both branches are spelled out so the engineer doesn't guess.

**Type / name consistency:**
- All 13 module names spelled identically across the inventory (intro), per-task instructions, and the final verification grep.
- `moduleServer(id, function(input, output, session) { … })` form used identically in every conversion site.
- Field-name mapping `callModule(name, "id", …)` → `name("id", …)` applied uniformly.
- `requireNamespace(pkg, quietly = TRUE)` form used identically across all 7 GOterm.R sites.

**Risk callouts:**
- **The shinytest2 test in Task 9 may not run on first attempt** because the test's HTML selectors (`#main-mainplot`, `"load-demo"`, `"load-Filter"`) were written against the legacy app and may not match what Shiny renders after A4. Both branches of Task 9 are documented; the deferral path is the safe default.
- **No app-runtime testing is done in this plan.** `devtools::test()` exercises pure functions and panel-builder helpers only; it does not actually load the Shiny session and click through. The module conversion is byte-for-byte mechanical (every body is wrapped, no logic changes), so this is acceptable risk — but the user should manually verify `startDEBrowser()` opens and the demo loads before merging this plan to `devel`.
