# Theme Preset URL Param Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let developers swap the bslib preset at runtime via `?preset=NAME` URL query param, while keeping the default URL byte-identical to today.

**Architecture:** Two-file change. `de_theme()` gains an optional `preset` arg — when set, it returns a preset-only theme (custom colors dropped, Inter font kept) so the preset's palette is visible; when unset, today's custom Slate + OK-blue theme is unchanged. `deUI` is converted to a request-aware function `deUI(req)` that reads the query string via `shiny::parseQueryString(req$QUERY_STRING)` and forwards a validated preset name to `de_theme()`. Unknown presets fall back to default with a console `message()`.

**Tech Stack:** R, Shiny, bslib (Bootstrap 5), testthat.

**Spec:** [docs/superpowers/specs/2026-04-30-theme-preset-url-param-design.md](../specs/2026-04-30-theme-preset-url-param-design.md)

---

## File Structure

- **Modify:** [R/de_theme.R](../../../R/de_theme.R) — add `preset` arg + whitelist + validator
- **Modify:** [R/ui.R](../../../R/ui.R) — convert `deUI` to `deUI(req)`, parse query string, forward to `de_theme()`
- **Create:** `tests/testthat/test-de_theme.R` — unit tests for `de_theme()` (default, valid preset, invalid preset)

Each file has a single responsibility: theme construction, page assembly, theme tests.

---

## Task 1: Whitelist of valid presets in `R/de_theme.R`

**Files:**
- Modify: `R/de_theme.R` — add a top-level constant near the top of the file

- [ ] **Step 1: Add the whitelist constant**

Add this directly above the existing `de_theme` definition (above the roxygen block on line 1):

```r
# Valid bslib preset names (Bootstrap 5 + Bootswatch + shiny default).
# Used by `de_theme()` to validate the `preset` argument and by the URL-
# param playground in `deUI()`. See `?bslib::bs_theme` for the source list.
.de_theme_presets <- c(
  "bootstrap", "shiny",
  "cerulean", "cosmo", "cyborg", "darkly", "flatly", "journal", "litera",
  "lumen", "lux", "materia", "minty", "morph", "pulse", "quartz",
  "sandstone", "simplex", "sketchy", "slate", "solar", "spacelab",
  "superhero", "united", "vapor", "yeti", "zephyr"
)

```

- [ ] **Step 2: Verify the file still loads**

Run: `Rscript -e 'devtools::load_all(".", quiet = TRUE); message("loaded")'`
Expected: prints `loaded` with no errors.

- [ ] **Step 3: Commit**

```bash
git add R/de_theme.R
git commit -m "feat(theme): add bslib preset whitelist constant"
```

---

## Task 2: Test — `de_theme()` default behavior unchanged

**Files:**
- Create: `tests/testthat/test-de_theme.R`

- [ ] **Step 1: Write the failing test**

Create `tests/testthat/test-de_theme.R` with:

```r
test_that("de_theme() with no args returns a bs_theme object", {
  t <- de_theme()
  expect_s3_class(t, "bs_theme")
})
```

- [ ] **Step 2: Run the test to verify it passes (no behavior change yet)**

Run: `Rscript -e 'devtools::test(filter = "de_theme")'`
Expected: 1 PASS — current `de_theme()` already returns a `bs_theme`. This locks the contract before we touch it.

- [ ] **Step 3: Commit**

```bash
git add tests/testthat/test-de_theme.R
git commit -m "test(theme): lock current de_theme() return contract"
```

---

## Task 3: Test — `de_theme(preset = "zephyr")` returns a `bs_theme`

**Files:**
- Modify: `tests/testthat/test-de_theme.R`

- [ ] **Step 1: Add the failing test**

Append to `tests/testthat/test-de_theme.R`:

```r
test_that("de_theme(preset) returns a bs_theme using the named preset", {
  t <- de_theme(preset = "zephyr")
  expect_s3_class(t, "bs_theme")
})
```

- [ ] **Step 2: Run it to verify it fails**

Run: `Rscript -e 'devtools::test(filter = "de_theme")'`
Expected: FAIL with "unused argument (preset = ...)" — `de_theme()` does not yet accept a `preset` parameter.

- [ ] **Step 3: Implement `preset` arg in `de_theme()`**

Replace the entire body of `R/de_theme.R` (keep the whitelist constant from Task 1 above the roxygen block):

```r
#' de_theme
#'
#' DEBrowser bslib theme. Default behavior: hand-rolled Slate + OK-blue
#' palette with Inter typography on Bootstrap 5. When `preset` is supplied
#' (e.g. `"zephyr"`, `"lumen"`, `"cosmo"`), returns a preset-only theme so
#' the chosen preset's palette is visible — custom color overrides are
#' dropped; Inter font is kept so typography stays constant across
#' comparisons. Used as the `theme` argument to `bslib::page_navbar()` in
#' [deUI()]. The URL-param playground (`?preset=NAME`) wires this up.
#'
#' @param preset Optional bslib preset name. One of `.de_theme_presets`.
#'   `NULL` (default) returns the standard custom theme.
#' @return a `bs_theme` object
#' @examples
#' x <- de_theme()
#' y <- de_theme(preset = "zephyr")
#' @export
de_theme <- function(preset = NULL) {
  if (!is.null(preset)) {
    return(bslib::bs_theme(
      version      = 5,
      preset       = preset,
      base_font    = bslib::font_google("Inter", local = FALSE),
      heading_font = bslib::font_google("Inter", local = FALSE)
    ))
  }
  bslib::bs_theme(
    version       = 5,
    bg            = "#ffffff",
    fg            = "#0f172a",
    primary       = "#0369a1",
    secondary     = "#64748b",
    success       = "#16a34a",
    danger        = "#dc2626",
    warning       = "#d97706",
    info          = "#0891b2",
    "navbar-bg"                 = "#0f172a",
    "navbar-dark-color"         = "#cbd5e1",
    "navbar-dark-hover-color"   = "#7dd3fc",
    "navbar-dark-active-color"  = "#7dd3fc",
    base_font     = bslib::font_google("Inter", local = FALSE),
    heading_font  = bslib::font_google("Inter", local = FALSE)
  )
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `Rscript -e 'devtools::test(filter = "de_theme")'`
Expected: 2 PASS — the new preset case plus the default case still green.

- [ ] **Step 5: Regenerate roxygen docs**

Run: `Rscript -e 'devtools::document()'`
Expected: updates `man/de_theme.Rd` with the new `preset` parameter. No errors.

- [ ] **Step 6: Commit**

```bash
git add R/de_theme.R man/de_theme.Rd tests/testthat/test-de_theme.R
git commit -m "feat(theme): de_theme() accepts bslib preset name"
```

---

## Task 4: Test — invalid preset falls back to default with a console message

**Files:**
- Modify: `tests/testthat/test-de_theme.R`
- Modify: `R/de_theme.R`

- [ ] **Step 1: Add the failing test**

Append to `tests/testthat/test-de_theme.R`:

```r
test_that("de_theme(preset = '<unknown>') falls back to default with a message", {
  expect_message(
    t <- de_theme(preset = "not-a-real-preset"),
    regexp = "not-a-real-preset"
  )
  expect_s3_class(t, "bs_theme")
})
```

- [ ] **Step 2: Run it to verify it fails**

Run: `Rscript -e 'devtools::test(filter = "de_theme")'`
Expected: FAIL — current `de_theme(preset = "not-a-real-preset")` will either raise an `bslib::bs_theme()` error or pass without emitting a `message()`. The test demands a graceful fallback.

- [ ] **Step 3: Add validation at the top of `de_theme()`**

In `R/de_theme.R`, replace the line `if (!is.null(preset)) {` and the block that follows it with:

```r
  if (!is.null(preset)) {
    if (!preset %in% .de_theme_presets) {
      message(sprintf(
        "de_theme(): unknown preset '%s'. Valid presets: %s. Falling back to default theme.",
        preset, paste(.de_theme_presets, collapse = ", ")
      ))
      preset <- NULL
    }
  }
  if (!is.null(preset)) {
    return(bslib::bs_theme(
      version      = 5,
      preset       = preset,
      base_font    = bslib::font_google("Inter", local = FALSE),
      heading_font = bslib::font_google("Inter", local = FALSE)
    ))
  }
```

The double `if (!is.null(preset))` looks redundant but is intentional: the first block may set `preset <- NULL` after warning; the second decides whether to use the preset path or fall through to the default theme.

- [ ] **Step 4: Run the tests to verify all pass**

Run: `Rscript -e 'devtools::test(filter = "de_theme")'`
Expected: 3 PASS — default, valid preset, invalid preset all green.

- [ ] **Step 5: Commit**

```bash
git add R/de_theme.R tests/testthat/test-de_theme.R
git commit -m "feat(theme): validate preset name with graceful fallback"
```

---

## Task 5: Wire `?preset=` into `deUI`

**Files:**
- Modify: `R/ui.R` — convert `deUI` to take a `req` argument

- [ ] **Step 1: Update `deUI` to accept the request**

In [R/ui.R:14](../../../R/ui.R#L14), change the function signature line and add the query parsing right after the `addResourcePath` call.

Before:
```r
deUI <- function() {
  addResourcePath(
    prefix = "www",
    directoryPath = system.file("extdata", "www", package = "debrowser")
  )

  version_label <- getNamespaceVersion("debrowser")
```

After:
```r
deUI <- function(req) {
  addResourcePath(
    prefix = "www",
    directoryPath = system.file("extdata", "www", package = "debrowser")
  )

  version_label <- getNamespaceVersion("debrowser")

  # Theme playground: ?preset=NAME swaps the bslib preset at runtime.
  # Unknown / missing preset → default Slate theme. See `de_theme()`.
  preset <- shiny::parseQueryString(req$QUERY_STRING)[["preset"]]
```

- [ ] **Step 2: Pass `preset` to `de_theme()`**

In the same file, find [R/ui.R:29](../../../R/ui.R#L29) (currently `theme   = de_theme(),`) and change it to:

```r
    theme   = de_theme(preset = preset),
```

- [ ] **Step 3: Update the `deUI` roxygen block**

Replace the existing roxygen for `deUI` (lines 1–13 of `R/ui.R`) with:

```r
#' deUI
#'
#' Creates a shinyUI to be able to run DEBrowser interactively.
#' B1 shell: bslib::page_navbar with 5 nav panels (Data Prep / Main Plots /
#' QC Plots / GO Term / Tables), Slate + OK-blue theme, light/dark toggle.
#'
#' Accepts a Shiny `request` argument so that the theme can be swapped at
#' runtime via the `?preset=NAME` query parameter (e.g. `?preset=zephyr`).
#' Unknown or missing `preset` keeps the default theme.
#'
#' @param req Shiny request object (auto-supplied by Shiny when `deUI` is
#'   used as the `ui` argument to `shinyApp()`).
#' @note \code{deUI}
#' @return the page tagList for DEBrowser
#'
#' @examples
#' \dontrun{
#'   shiny::shinyApp(ui = deUI, server = deServer)
#' }
#'
#' @export
```

- [ ] **Step 4: Regenerate docs**

Run: `Rscript -e 'devtools::document()'`
Expected: updates `man/deUI.Rd` with the `req` parameter. No errors.

- [ ] **Step 5: Sanity-check that the package still loads**

Run: `Rscript -e 'devtools::load_all(".", quiet = TRUE); message("loaded")'`
Expected: prints `loaded` with no errors. (We do not unit-test `deUI(req)` directly because constructing a fake Rook request is more boilerplate than the change is worth, and `R CMD check` exercises the function via examples.)

- [ ] **Step 6: Run the full test suite**

Run: `Rscript -e 'devtools::test()'`
Expected: all tests pass — the `deUI` change is upstream of every test, so a regression here would surface immediately.

- [ ] **Step 7: Commit**

```bash
git add R/ui.R man/deUI.Rd
git commit -m "feat(ui): deUI honors ?preset= query param for theme playground"
```

---

## Task 6: Manual smoke test

**Files:** none — runtime check only.

- [ ] **Step 1: Launch the app**

Run: `Rscript -e 'devtools::load_all("."); debrowser::startDEBrowser()'`
Expected: Shiny app starts and prints a `Listening on http://127.0.0.1:NNNN` URL.

- [ ] **Step 2: Open default URL — confirm unchanged**

In a browser, open the printed URL (no query string). Confirm:
- Navbar is dark Slate (`#0f172a`).
- Primary buttons are OK-blue (`#0369a1`).
- Inter font is rendered.

- [ ] **Step 3: Try four representative presets**

Open each in a separate tab and visually confirm a noticeable change:
- `?preset=zephyr` — light, neutral, modern feel (closest to "smaller elements" goal).
- `?preset=lumen` — soft, blue-tinted.
- `?preset=cosmo` — flat, blue.
- `?preset=slate` — dark grey, matches current navbar mood.

- [ ] **Step 4: Try an invalid preset**

Open `?preset=nonsense` and confirm:
- Default Slate theme renders.
- The R console shows the `message()`: `de_theme(): unknown preset 'nonsense'. ...`.

- [ ] **Step 5: Stop the app**

Press `Ctrl+C` in the R session.

- [ ] **Step 6: No commit** — this task is pure verification.

---

## Task 7: Final check — `R CMD check`

**Files:** none.

- [ ] **Step 1: Run `R CMD check` (or `devtools::check()`)**

Run: `Rscript -e 'devtools::check(args = c("--no-manual"), quiet = FALSE)'`
Expected: 0 errors, 0 warnings, 0 new notes (notes that existed before this change are acceptable; compare against `git stash` baseline if unsure).

- [ ] **Step 2: If clean, no extra commit**

Acceptance criteria from the spec are now met:
- `de_theme()` and `de_theme(preset = "<valid>")` both return `bs_theme`.
- Invalid preset → default + console message.
- `?preset=` URL param works end-to-end.
- Default URL is byte-identical to pre-change.
- Test suite green; `R CMD check` clean.
