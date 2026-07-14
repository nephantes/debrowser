# 06 — Client Handoff & Design-System Consolidation

**Status:** Plan (implementation not yet started)
**Scope:** `inst/extdata/www/debrowser.css`, `inst/extdata/www/legal/*`, a new `DESIGN.md`, a new style-guide page, and four housekeeping fixes in `R/`.
**Package:** debrowser 1.31.2 (Bioconductor, branch `modernize`)
**Author context:** nephantes@gmail.com · 2026-07-13
**Non-goals:** No visual redesign here. This plan does not change how anything *looks*; it changes how the design layer is *organised, documented, and shipped* so it survives a client handoff and a Bioconductor review.

This is the umbrella/backbone document for the design series. It assumes and cross-references its siblings:

| Ref | File | Owns |
|-----|------|------|
| 01 | [`./01-grid-system-plan.md`](./01-grid-system-plan.md) | grid, spacing scale, layout rules |
| 02 | [`./02-color-palette-plan.md`](./02-color-palette-plan.md) | color tokens, Phase-0 token additions |
| 03 | [`./03-iconography-plan.md`](./03-iconography-plan.md) | one-icon-set rule, favicon, `fa-*` names |
| 04 | [`./04-loading-states-plan.md`](./04-loading-states-plan.md) | spinners, skeletons, busy states |
| 05 | [`./05-hover-cursor-plan.md`](./05-hover-cursor-plan.md) | hover / focus / transition (motion) conventions |
| 06 | `./06-handoff-plan.md` | **this doc** — consolidation, docs, packaging |

> The Phase-0 motion tokens (`--de-dur`, `--de-ease`, and the composite `--de-transition`) are owned by [`./05-hover-cursor-plan.md`](./05-hover-cursor-plan.md); do not hard-code transition timings.

---

## 0. Why this document exists (the evidence)

The redesign CSS was built by **live-audit patching**, not from a system: someone launched the app, screenshotted a tab, and appended a corrective block. Thirty times. The file works, but every new rule is another override on top of the last, and there is no map. A client (or a Bioconductor reviewer) opening `debrowser.css` today has no way to find "the button styles" — they are smeared across ~17 blocks and stabilised with `!important`.

**Verified metrics** (reproduce each with the command shown — run from repo root):

| Symptom | Value | Reproduce |
|---|---|---|
| `!important` declarations | **1,201** | `grep -c '!important' inst/extdata/www/debrowser.css` |
| Total CSS lines | **4,903** | `wc -l inst/extdata/www/debrowser.css` |
| Distinct patch sections | **30** (`B3.1`…`B3.34`, with gaps at 19/21/27/30) | `grep -nE 'B3\.[0-9]+ (—\|--)' inst/extdata/www/debrowser.css` |
| Patch banners | e.g. *"Punch list fixes after first launch (live audit on 3839)"*, *"Match mockup specs EXACTLY"*, *"DONE ALWAYS WINS."*, *"Final override."* | `grep -nE 'B3\.[0-9]' inst/extdata/www/debrowser.css` |
| `.navbar` re-declarations | ~72 rule blocks (102 raw occurrences) | `grep -c '\.navbar' inst/extdata/www/debrowser.css` |
| `.nav-link` | ~50 | `grep -c '\.nav-link' inst/extdata/www/debrowser.css` |
| `.btn` family | ~17 blocks (75 raw) | `grep -c '\.btn' inst/extdata/www/debrowser.css` |
| `.card` | ~15 blocks (52 raw) | `grep -c '\.card' inst/extdata/www/debrowser.css` |
| `.accordion-button` | ~15 (17 raw) | `grep -c '\.accordion-button' inst/extdata/www/debrowser.css` |
| `.selectize-input` | ~9 (12 raw) | `grep -c '\.selectize-input' inst/extdata/www/debrowser.css` |
| Hard-coded `#0B1020` literal | **29** occurrences (should be a token) | `grep -ciE '#0b1020' inst/extdata/www/debrowser.css` |
| Token duplication | `--de-*` re-declared in **3** legal HTML files | `grep -rc -- '--de-' inst/extdata/www/legal/` |
| Design docs for contributors | **0** (no `DESIGN.md`) | `ls DESIGN.md 2>/dev/null` |

**How the redesign is wired** (so any consolidation stays inside the gate):

- The whole redesign is gated on `html[data-debrowser-redesign="1"]`, set by an inline script in `R/ui.R:239`. It is **on by default**; opt out with `?redesign=0`.
- Dark/light is `data-bs-theme` on `<html>`, toggled by `#dark_mode_toggle` and the `T` key in `R/ui.R:250`.
- Keyboard shortcuts `1`–`6` switch the six top-level tabs (`R/ui.R:268-277`).
- Tokens are the single set at `debrowser.css:342-389`. Inter is loaded by bslib; JetBrains Mono via `<link>` in `R/ui.R:245`.

### Task labels
Every task below is tagged:
- **[Quick win]** — small, safe, no regression surface. Do these first / anytime.
- **[Consolidation]** — refactors CSS or assets; needs the regression net (Task 3) in place.
- **[System]** — creates lasting structure (docs, harness, packaging).

### Recommended order (dependency graph)
```
Task 3  (style guide / regression net)  ──┐
                                          ├─► Task 2 (CSS consolidation)
Task 1  (token source of truth)  ─────────┘
Task 5  (housekeeping) ─── independent, do anytime (quick wins)
Task 4  (DESIGN.md)    ─── after Task 1 (needs final token table)
Task 6  (packaging)    ─── last (bundles the outputs of 1–5)
```
> All commits follow the repo convention `type(scope): message` and carry the standard `Co-Authored-By` trailer per repo policy.

---

## 1. Token source of truth  **[Consolidation]**

**Goal:** `debrowser.css:342-389` is the *only* place a color/radius/shadow/spacing value is defined. Everything else consumes `var(--de-*)`. No component block invents a literal.

### 1a. Introduce `--de-ink-on-accent` and migrate the 29 `#0B1020` literals

`#0B1020` is the near-black "ink" that sits on top of the cyan/violet/pink accents (primary buttons, the eyebrow chip, slider handles/labels). It is **constant across light and dark** (the accent gradient is the same in both themes), so it belongs in the theme-independent base block, not in the light/dark blocks. It is currently pasted as a raw literal 29 times.

Breakdown of the 29 occurrences (`grep -inE '#0b1020' inst/extdata/www/debrowser.css`):
- **25** are `color: #0B1020` — text on an accent surface → migrate to `var(--de-ink-on-accent)`.
- **3** are borders/insets on accent surfaces (lines 423, 830, 1277) → also `var(--de-ink-on-accent)`.
- **1** is the token *definition* itself (`--de-bg-0: #0B1020` at line 377, dark theme) → **leave as a literal** (it defines a token; the dark page background happens to equal the ink color, but they are different concepts).

**Add the definition** to the base block (`debrowser.css:342-358`):

```css
html[data-debrowser-redesign="1"] {
  --de-cyan:    #5EE6D6;
  --de-violet:  #A78BFA;
  /* ... existing palette ... */
  --de-r-pill: 999px;
  --de-shadow:    0 6px 24px rgba(0,0,0,.06);
  --de-shadow-lg: 0 12px 32px rgba(15,21,48,.10);

  /* Ink that sits on cyan/violet/pink accents. Constant across themes. */
  --de-ink-on-accent: #0B1020;
}
```

**Before / After — 3 representative sites:**

*Site A — primary/success buttons (`debrowser.css:545-556`):*
```css
/* Before */
html[data-debrowser-redesign="1"] .btn-primary,
html[data-debrowser-redesign="1"] .btn-success {
  background: var(--de-grad) !important;
  color: #0B1020 !important;
  border: 0 !important;
  box-shadow: 0 4px 14px rgba(94,230,214,.18);
}
/* After */
html[data-debrowser-redesign="1"] .btn-primary,
html[data-debrowser-redesign="1"] .btn-success {
  background: var(--de-grad) !important;
  color: var(--de-ink-on-accent) !important;
  border: 0 !important;
  box-shadow: 0 4px 14px rgba(94,230,214,.18);
}
```

*Site B — eyebrow chip (`debrowser.css:1144-1148`):*
```css
/* Before */
html[data-debrowser-redesign="1"] .de-eyebrow .de-eyebrow-chip {
  background: var(--de-grad); color: #0B1020; font-size: 10px;
}
/* After */
html[data-debrowser-redesign="1"] .de-eyebrow .de-eyebrow-chip {
  background: var(--de-grad); color: var(--de-ink-on-accent); font-size: 10px;
}
```

*Site C — slider handle border (`debrowser.css:827-833`):*
```css
/* Before */
html[data-debrowser-redesign="1"] .irs-handle {
  background: var(--de-cyan) !important;
  border: 2px solid #0B1020 !important;
}
/* After */
html[data-debrowser-redesign="1"] .irs-handle {
  background: var(--de-cyan) !important;
  border: 2px solid var(--de-ink-on-accent) !important;
}
```

**Find the rest (and verify migration is complete):**
```bash
# All literal uses — after migration only line 377 (the --de-bg-0 definition) should remain:
grep -niE '#0b1020' inst/extdata/www/debrowser.css

# The 25 `color:` consumers (the bulk migration):
grep -niE 'color:[[:space:]]*#0b1020' inst/extdata/www/debrowser.css

# Mechanical migration of the color: consumers (macOS/BSD sed; note the empty '' arg):
sed -i '' -E 's/(color:[[:space:]]*)#0[Bb]1020/\1var(--de-ink-on-accent)/g' \
  inst/extdata/www/debrowser.css
# Then migrate the 3 border/inset sites (lines 423, 830, 1277) by hand.
```
Verify: `grep -ciE '#0b1020' inst/extdata/www/debrowser.css` should return **1** (the definition).

**Generalise:** after `--de-ink-on-accent`, sweep for any other stray literal that should be a token:
```bash
# Any hex literal in the file (audit which belong in the token block):
grep -noE '#[0-9A-Fa-f]{3,8}' inst/extdata/www/debrowser.css | sort | uniq -c | sort -rn
```
Anything appearing more than once — and any raw `rgba(94,230,214,...)` (cyan) or `rgba(167,139,250,...)` (violet) — is a token candidate. Fold recurring ones into `debrowser.css:342-389` and reference via `var()`. Defer the palette decisions to [`./02-color-palette-plan.md`](./02-color-palette-plan.md); this task just enforces "define once, consume via `var()`."

**Commit:**
```
refactor(css): add --de-ink-on-accent token; migrate 28 #0B1020 literals
```

### 1b. De-duplicate the legal-page tokens

`inst/extdata/www/legal/{privacy,cookies,terms}.html` each open with a full `:root { --de-cyan … --de-bg-0:#0B1020 … }` block plus a hard-coded `color:#0B1020` in `.eyebrow .chip`. That is the same token vocabulary copied three times, drifting from the canonical set. These pages are served as **plain standalone HTML** (outside the Shiny redesign gate), so they cannot `var()` off `debrowser.css`'s `html[data-debrowser-redesign="1"]` scope — they need their own `:root`.

**Recommended (primary): a shared partial.** Extract the common block into one file and link it from all three pages.

Create `inst/extdata/www/legal/legal.css`:
```css
/* Canonical legal-page tokens. MIRROR of debrowser.css:342-389 (dark set).
   Keep in sync — see docs/design/06-handoff-plan.md §1b. */
:root {
  --de-cyan:#5EE6D6; --de-violet:#A78BFA;
  --de-grad:linear-gradient(135deg,#5EE6D6 0%,#A78BFA 100%);
  --de-bg-0:#0B1020; --de-bg-1:#0F1530; --de-bg-3:#1A2147;
  --de-border:rgba(255,255,255,.08); --de-border-strong:rgba(255,255,255,.14);
  --de-text-1:#E6ECFF; --de-text-2:#A8B2D1; --de-text-3:#6E7BA5;
  --de-ink-on-accent:#0B1020;
}
/* shared component rules (.eyebrow, .chip, .back, headings) move here too */
```
Then each of the three HTML files replaces its inline `<style>:root{…}` with:
```html
<link rel="stylesheet" href="legal.css">
```
(and `.eyebrow .chip { … color: var(--de-ink-on-accent); }`).

**Fallback (if single-file portability is required):** keep the copy but make the drift auditable — add the header comment shown above to each block and add a guard so the mirror can't silently rot:
```bash
# tests/check-legal-tokens.sh — fails if a legal file omits the MIRROR marker
grep -L 'MIRROR of debrowser.css' inst/extdata/www/legal/*.html && \
  { echo 'legal token block missing MIRROR marker'; exit 1; } || true
```

**Commit:**
```
refactor(legal): extract shared legal.css; stop triplicating --de-* tokens
```

---

## 2. CSS consolidation pass  **[Consolidation]**

**Goal:** collapse the `B3.1`…`B3.34` patch history into a small set of clean, *one-component-one-block* sections — **with zero visual regression**. We do not rewrite the CSS by hand from scratch; we merge and de-`!important` in small, screenshot-verified steps.

### Method (do these in order)

**(a) Build the regression net FIRST.** Ship the style guide (Task 3) and capture a baseline screenshot of every surface in both themes *before touching a single CSS rule*. Nothing in this task starts until baselines exist. The surfaces are:
- `style-guide.html` (light) + `style-guide.html` (dark) — the component matrix.
- The 6 app tabs × 2 themes = 12 shots, driven by the `1`–`6` and `T` shortcuts.

Baseline + diff harness (uses `webshot2` already available to R packages; `pixelmatch`/ImageMagick for the diff):
```r
# scripts/shots.R — capture baselines for the style guide
webshot2::webshot("inst/extdata/www/style-guide.html?theme=light",
                  "docs/design/baseline/guide-light.png", vwidth = 1440)
webshot2::webshot("inst/extdata/www/style-guide.html?theme=dark",
                  "docs/design/baseline/guide-dark.png",  vwidth = 1440)
```
```bash
# after each consolidation step, re-shoot to docs/design/after/ then diff:
compare -metric AE docs/design/baseline/guide-light.png \
                    docs/design/after/guide-light.png diff-light.png; echo
# AE (absolute pixel diff) must be 0 for a clean merge. Non-zero => investigate.
```
For the live app tabs, drive a headless session (Playwright or `shinytest2`) that presses `1`–`6` and `T`, screenshotting each state. Any consolidation commit that produces a non-zero diff is rejected or explained.

**(b) Merge duplicate selector blocks, one component per commit.** Work component-by-component, not line-by-line. For each component, gather its scattered blocks, order them by cascade, fold into a single labelled section, delete the `B3.x` copies, re-shoot, diff. Suggested component order (least-entangled first):
```
1. .btn family        (~17 blocks -> 1 section)   e.g. lines 528-600, 2103-2436, 3914-3960 …
2. .card / de_card     (~15 -> 1)                  497-, 1138-, …
3. .accordion-button   (~15 -> 1)
4. .selectize-input    (~9  -> 1)
5. .nav-link / tabs    (~50 -> 1)
6. .navbar / header    (~72 -> 1)  ← do last; most patched, most entangled
```
Find every block for a component before merging:
```bash
grep -nE '^\s*html\[data-debrowser-redesign="1"\][^,{]*\.btn' inst/extdata/www/debrowser.css
```
Replace the scattered `/* B3.x — … */ … /* End B3.x */` fragments with a single header:
```css
/* ========================================================================
   BUTTONS  (.btn, .btn-primary/-success/-secondary/-danger, .btn-sm, icons)
   Consolidated from former B3.5, B3.18, B3.22-24. One block, no dupes.
   ======================================================================== */
```

**(c) Drive down `!important` by leaning on the gate, not by stacking.** The redesign already wins the cascade for free: every rule is scoped under `html[data-debrowser-redesign="1"]`, an attribute selector on the root. That selector has *higher specificity than most Bootstrap defaults* (which are class- or element-scoped). So most `!important`s exist only because a *later B3.x block* had to beat an *earlier B3.x block* — once the duplicates are merged (step b), the internal fights disappear and the `!important` can come off.

Rule of thumb applied per merged block:
1. Merge duplicates first (step b) so there is one rule per selector.
2. Remove `!important` from that rule.
3. Re-shoot + diff. If it still matches baseline, the `!important` was self-inflicted — keep it off.
4. If it regresses, the override target is genuinely Bootstrap/bslib inline style or a third-party (selectize/DT/ion-rangeslider) inline rule — keep `!important` and add a one-line comment saying *what* it overrides.

**Measurable targets:**
| Metric | Before | Target |
|---|---|---|
| `!important` declarations | 1,201 | **< 350** (only genuine third-party/inline overrides remain, each commented) |
| `B3.x` patch sections | 30 | **0** (folded into ~12 component sections) |
| Blocks per component | up to ~72 | **1** ("one component = one block") |
| Baseline screenshot diff (per commit) | — | **AE = 0** for style guide; visually clean for app tabs |

**Guardrails:**
- One component per commit — never batch two. A regression is then trivially bisectable.
- Never delete a rule you cannot account for in the merged block; if unsure what a B3.x rule fixed, keep it and note it.
- Keep the `html[data-debrowser-redesign="1"]` prefix on every rule — that gate is what keeps opt-out (`?redesign=0`) users unaffected.
- Do not touch `debrowser.css:342-389` here (that is Task 1's territory).

**Commit (one per component):**
```
refactor(css): consolidate .btn styles into one block; drop 140 self-inflicted !important
```

---

## 3. Living style guide + regression harness  **[System]**

**Goal:** one page that renders **every component in both themes**, so (a) a client/reviewer sees the whole system at a glance and (b) Task 2 has a pixel baseline.

### Recommendation

Ship **both**, primary = the standalone HTML:

1. **Primary — `inst/extdata/www/style-guide.html`** (standalone). Loads `debrowser.css`, sets `data-debrowser-redesign="1"`, has a light/dark toggle wired to `data-bs-theme`. Zero R needed — opens in any browser, ships in the handoff bundle, is the exact file `webshot2` shoots. It is both the client artifact and the regression target.
2. **Secondary — `de_style_guide()`** (thin R wrapper, ~15 lines). Opens the same page from within the installed package so QA can view it in the *exact* bslib/Bootstrap context the app compiles, and so it is reachable without knowing the file path.

Why the HTML is primary: it is self-contained, versioned with the package under `inst/`, and needs no running Shiny server to screenshot — ideal for CI diffing. The R wrapper exists for convenience and for verifying against the live bslib build.

### Component inventory the page must cover
buttons (primary/success/secondary/outline/danger/sm/with-icon) · form controls (text, select, checkbox, radio, switch, textarea) · selectize · sliders (ion-rangeslider `.irs-*`) · cards / `de_card` (with & without download header, full-screen) · accordion · nav-tabs & pills · DT table · alerts · badges · `.de-eyebrow` / `.de-stat-strip` / `.de-workbar` helpers · wizard pills (`.wiz-step`, `.de-pill-done/-locked`) · modals · tooltips/popovers · progress bar.

### File: `inst/extdata/www/style-guide.html` (starter skeleton — real, runnable)

Covers buttons + cards + form controls + eyebrow + stat-strip, with the theme toggle wired. Remaining components follow the same pattern (add one `<section>` each).

```html
<!doctype html>
<html lang="en" data-debrowser-redesign="1" data-bs-theme="light">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>DEBrowser — Design System Style Guide</title>
  <!-- Same CSS environment as the app: Bootstrap 5.3 + FA + Inter + JetBrains Mono + debrowser.css.
       For an offline/Bioconductor build, vendor these into inst/extdata/www/vendor/ and repoint. -->
  <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/css/bootstrap.min.css">
  <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.1/css/all.min.css">
  <link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700;800&family=JetBrains+Mono:wght@400;500&display=swap">
  <link rel="stylesheet" href="debrowser.css">
  <style>
    /* guide-only chrome, not part of the system */
    .sg-wrap   { max-width: 1100px; margin: 0 auto; padding: 32px; }
    .sg-toolbar{ position: sticky; top: 0; z-index: 10; display: flex; gap: 12px;
                 align-items: center; padding: 12px 0; margin-bottom: 24px;
                 border-bottom: 1px solid var(--de-border);
                 background: var(--de-bg-0); }
    .sg-section{ margin: 40px 0; }
    .sg-section > h2 { font: 700 14px/1 'JetBrains Mono', monospace;
                       letter-spacing: .12em; text-transform: uppercase;
                       color: var(--de-text-3); margin-bottom: 16px; }
    .sg-row    { display: flex; flex-wrap: wrap; gap: 12px; align-items: center; }
  </style>
</head>
<body>
  <div class="sg-wrap">

    <div class="sg-toolbar">
      <strong>DEBrowser Style Guide</strong>
      <span class="spacer" style="flex:1"></span>
      <button id="themeBtn" class="btn btn-secondary btn-sm" type="button">
        <i class="fa fa-circle-half-stroke"></i> Toggle theme
      </button>
    </div>

    <!-- EYEBROW + STAT STRIP -->
    <section class="sg-section">
      <h2>Eyebrow &amp; stat strip</h2>
      <div class="de-eyebrow"><span class="de-eyebrow-chip">01</span> Upload &amp; configure</div>
      <h3 class="de-headline">Section headline</h3>
      <div class="de-stat-strip">
        <span><span class="de-stat-dot" style="background:var(--de-cyan)"></span><b>12,481</b> genes</span>
        <span><span class="de-stat-dot" style="background:var(--de-violet)"></span><b>24</b> samples</span>
        <span><span class="de-stat-dot" style="background:var(--de-blue)"></span><b>2</b> conditions</span>
      </div>
    </section>

    <!-- BUTTONS -->
    <section class="sg-section">
      <h2>Buttons</h2>
      <div class="sg-row">
        <button class="btn btn-primary">Primary</button>
        <button class="btn btn-success">Success</button>
        <button class="btn btn-secondary">Secondary</button>
        <button class="btn btn-outline-secondary">Outline</button>
        <button class="btn btn-danger">Danger</button>
        <button class="btn btn-primary btn-sm"><i class="fa fa-download"></i> With icon</button>
        <button class="btn btn-primary" disabled>Disabled</button>
      </div>
    </section>

    <!-- CARDS / de_card -->
    <section class="sg-section">
      <h2>Cards (de_card)</h2>
      <div class="sg-row" style="align-items:stretch">
        <div class="card" style="min-width:280px">
          <div class="card-header">Plain card</div>
          <div class="card-body">Body content sits on <code>var(--de-bg-1)</code>.</div>
        </div>
        <div class="card" style="min-width:280px">
          <div class="card-header d-flex align-items-center">
            Card with download
            <div class="ms-auto">
              <button class="btn btn-primary btn-sm"><i class="fa fa-download"></i></button>
            </div>
          </div>
          <div class="card-body">Mirrors <code>de_card(download_id=…)</code>.</div>
        </div>
      </div>
    </section>

    <!-- FORM CONTROLS -->
    <section class="sg-section">
      <h2>Form controls</h2>
      <div class="sg-row" style="align-items:flex-start">
        <div style="min-width:220px">
          <label class="form-label">Text input</label>
          <input class="form-control" placeholder="e.g. TP53">
        </div>
        <div style="min-width:220px">
          <label class="form-label">Select</label>
          <select class="form-select"><option>DESeq2</option><option>EdgeR</option><option>Limma</option></select>
        </div>
        <div class="form-check mt-4">
          <input class="form-check-input" type="checkbox" id="c1" checked>
          <label class="form-check-label" for="c1">Checkbox</label>
        </div>
        <div class="form-check form-switch mt-4">
          <input class="form-check-input" type="checkbox" id="s1" checked>
          <label class="form-check-label" for="s1">Switch</label>
        </div>
      </div>
    </section>

    <!-- Remaining sections follow the same pattern, one <section> each:
         selectize · sliders (.irs-*) · accordion · nav-tabs/pills ·
         DT table · alerts · badges · workbar · wizard pills
         (.wiz-step/.de-pill-done/.de-pill-locked) · modal · tooltip · progress -->

  </div>

  <script>
    // Light/dark toggle -> data-bs-theme on <html> (matches R/ui.R:250 behaviour).
    // Also honours ?theme=dark|light so webshot2 can request either directly.
    (function () {
      var html = document.documentElement;
      var q = new URL(location.href).searchParams.get('theme');
      if (q === 'dark' || q === 'light') html.setAttribute('data-bs-theme', q);
      document.getElementById('themeBtn').addEventListener('click', function () {
        var cur = html.getAttribute('data-bs-theme');
        html.setAttribute('data-bs-theme', cur === 'dark' ? 'light' : 'dark');
      });
    })();
  </script>
</body>
</html>
```

### Secondary: `R/de_style_guide.R`
```r
#' Open the DEBrowser design-system style guide
#'
#' Opens the standalone component gallery shipped at
#' `inst/extdata/www/style-guide.html`. Doubles as the visual-regression
#' baseline for the CSS consolidation (see docs/design/06-handoff-plan.md).
#'
#' @param theme one of "light" or "dark" (sets the initial `data-bs-theme`).
#' @return (invisibly) the path opened.
#' @examples
#' \dontrun{ de_style_guide("dark") }
#' @export
de_style_guide <- function(theme = c("light", "dark")) {
  theme <- match.arg(theme)
  path <- system.file("extdata", "www", "style-guide.html", package = "debrowser")
  if (!nzchar(path)) stop("style-guide.html not found in installed package")
  utils::browseURL(sprintf("%s?theme=%s", path, theme))
  invisible(path)
}
```

**Why it doubles as a regression harness:** the same file that shows a client the system is the file `webshot2` shoots in Task 2, before and after each merge. If a consolidation step changes a pixel, the guide diff catches it immediately — no need to click through the live app.

**Commit:**
```
feat(design): add self-contained style-guide.html + de_style_guide() harness
```

---

## 4. `DESIGN.md` — the contributor design doc  **[System]**

**Goal:** the file a new contributor / client / Bioconductor reviewer reads before touching the CSS. It is not a placeholder — the outline below is the content. Create it at `/Users/alper/ws/Projects/debrowser/DESIGN.md` after Task 1 finalises the token table.

### Content to write:

````markdown
# DEBrowser Design System

DEBrowser ships a self-contained visual redesign layer. This document is the
contract: read it before editing `inst/extdata/www/debrowser.css`. The full
rationale lives in `docs/design/01`–`06`; this is the quick reference.

## 1. How the redesign is wired

- **The gate.** Every redesign rule is scoped under
  `html[data-debrowser-redesign="1"]`. The attribute is set by an inline
  script in `R/ui.R:239`, **on by default**. Opt out with `?redesign=0` in the
  URL — those users get stock bslib. *Never write a redesign rule without this
  prefix*; that is what keeps opt-out clean.
- **Themes.** Light/dark is `data-bs-theme` on `<html>`. Token values switch in
  the two theme blocks at `debrowser.css:360-389`. Toggle via the
  `#dark_mode_toggle` button or the `T` key (`R/ui.R:250`).
- **Keyboard shortcuts** (`R/ui.R:250-283`, ignored while typing in a field):
  | Key | Action |
  |-----|--------|
  | `1`–`6` | switch top-level tab (`panel0,panel1,panel_cc,panel3,panel4`) |
  | `T` | toggle light/dark |
- **Fonts.** Inter (UI, via bslib) + JetBrains Mono (numeric/table, `<link>` in
  `R/ui.R:245`).

## 2. Token vocabulary — the single source of truth

All values live once, at `debrowser.css:342-389`. Consume via `var(--de-*)`;
never paste a literal into a component block.

| Token | Light | Dark | Use |
|-------|-------|------|-----|
| `--de-cyan` / `--de-violet` / `--de-blue` / `--de-mint` / `--de-pink` | (same) | (same) | accent palette |
| `--de-grad` | cyan→violet 135° | (same) | primary button / chip fill |
| `--de-ink-on-accent` | `#0B1020` | `#0B1020` | text/border **on** an accent surface |
| `--de-bg-0` | `#F7F8FC` | `#0B1020` | page canvas |
| `--de-bg-1` | `#FFFFFF` | `#0F1530` | card / raised surface |
| `--de-bg-2` / `--de-bg-3` | white / `#F1F4FB` | `#141B3A` / `#1A2147` | nested / hover surfaces |
| `--de-border` / `--de-border-strong` | ink @10% / @18% | white @8% / @14% | hairlines |
| `--de-text-1/2/3` | `#0F1530` / `#475270` / `#6E7BA5` | `#E6ECFF` / `#A8B2D1` / `#6E7BA5` | primary / secondary / muted text |
| `--de-grid` | ink @4% | white @4% | canvas grid |
| `--de-r-sm/-md/-lg/-pill` | 6 / 10 / 14 / 999px | (same) | radii |
| `--de-shadow` / `--de-shadow-lg` | soft | deeper | elevation |
| `--de-space-1…6` | 4/8/12/16/24/32px | (same) | spacing scale — see 01 |
| `--de-dur` / `--de-ease` | motion duration / easing | (same) | transitions — see 05 |
| `--de-accent-ink` | (Phase-0) | (Phase-0) | see 02 |

> Legal pages (`inst/extdata/www/legal/`) are standalone HTML and keep a
> **mirror** of the dark token set in `legal/legal.css`. If you change a token,
> update that mirror (§1b of the handoff plan).

## 3. Grid & spacing
Use the `--de-space-*` scale, never magic px. Layout, column rules, and the
56px canvas grid are specified in `docs/design/01-grid-system-plan.md`.

## 4. One icon set
DEBrowser uses **Font Awesome only**. Do not mix in Bootstrap Icons or inline
SVGs. Icon names must be valid FA identifiers. Full rule + the favicon wiring:
`docs/design/03-iconography-plan.md`.

## 5. Loading, hover & motion
- Loading/busy states (spinners, skeletons, the page-load overlay):
  `docs/design/04-loading-states-plan.md`.
- Hover / focus / transition conventions use `--de-dur` + `--de-ease`:
  `docs/design/05-hover-cursor-plan.md`. Do not hard-code transition timings.

## 6. Editing rules (the short version)
1. New value that repeats? Add a token at `debrowser.css:342-389`, don't paste.
2. Scope every rule under `html[data-debrowser-redesign="1"]`.
3. One component = one block. Don't append a "fix" block; edit the component's
   section.
4. Reach for `!important` only to beat Bootstrap/bslib/third-party *inline*
   styles, and comment what it overrides.
5. Changed anything visual? Re-shoot `inst/extdata/www/style-guide.html` in both
   themes and diff (see `de_style_guide()`).
````

**Commit:**
```
docs(design): add DESIGN.md contributor design contract
```

---

## 5. Housekeeping checklist  **[Quick win]** (each independent)

Four small, verified fixes surfaced by the audit. Each is command → verify → commit.

### 5a. Wire the favicon
`inst/extdata/www/favicon.ico` exists but is never referenced (`grep -rn favicon R/ inst/` → nothing). Add a `<link rel="icon">` in the `<head>` assembled in `R/ui.R`. Exact placement and any icon-set-consistent replacement are owned by [`./03-iconography-plan.md`](./03-iconography-plan.md); the task here is just to wire what exists.

- **Edit:** in `R/ui.R` `<head>`, add
  `tags$link(rel = "icon", href = "www/favicon.ico")` (the `www` resource path is already registered via `addResourcePath`).
- **Verify:** load the app; DevTools → Network shows `favicon.ico` 200, and the browser tab shows the icon.
- **Commit:** `fix(ui): wire favicon.ico into <head>`

### 5b. Delete orphan assets
`images/delete_button.png` and `images/loading2.gif` have zero references (`grep -rl delete_button.png R/ inst/` and same for `loading2.gif` → empty).

- **Command:**
  ```bash
  git rm inst/extdata/www/images/delete_button.png \
         inst/extdata/www/images/loading2.gif
  ```
- **Verify:** `grep -rn 'delete_button\|loading2' R/ inst/` → no hits; app still builds.
- **Commit:** `chore(assets): remove orphan delete_button.png + loading2.gif`

### 5c. Resolve the dead loading overlay
`getLoadingMsg()` (`R/uifuncs.R:482`) is rendered by `output$loading` (`R/server.R:1150`) but **no `uiOutput("loading")` placeholder exists** in the UI, so it never reaches the DOM — dead code. (The *live* page-load spinner is the separate `#loading-debrowser` div in `R/ui.R:97-98`, using `initial_loading.gif` — leave that alone.) Decide with [`./04-loading-states-plan.md`](./04-loading-states-plan.md): either remove the dead path or place the missing `uiOutput`.

- **If removing** (recommended if 04 confirms the `#loading-debrowser` overlay is the keeper): delete the `output$loading <- renderUI({ getLoadingMsg() })` block in `R/server.R:1149-1151` and the now-unused `getLoadingMsg()`; then its assets `loading.gif` / `loading_start.gif` become orphans and can be removed too.
- **Verify:** `grep -rn 'output\$loading\|getLoadingMsg' R/` → no dangling references; app loads with the intended spinner only.
- **Commit:** `refactor(server): remove dead loading overlay (no uiOutput placeholder)`

### 5d. Fix the invalid Font Awesome name `fa-show`
`R/funcs.R:294` calls `actionButtonDE(..., icon = "show")`. `actionButtonDE` builds `<i class='fa fa-show'>` (`R/funcs.R:407`), but **`fa-show` is not a Font Awesome icon** — nothing renders. The intended "Show Data" glyph is `fa-eye`. Icon-name policy is owned by [`./03-iconography-plan.md`](./03-iconography-plan.md).

- **Edit:** `R/funcs.R:294`, change `icon = "show"` → `icon = "eye"`.
- **Verify:** the "Show Data" button renders an eye glyph; `grep -rn 'fa-show\|icon = "show"' R/` → no hits.
- **Commit:** `fix(funcs): use valid FA icon fa-eye instead of nonexistent fa-show`

---

## 6. Packaging the handoff bundle  **[System]**

**Goal:** ship the design system as one coherent, versioned bundle so a client (or the next maintainer) receives the *system*, not just the CSS.

### What ships, and where
| Artifact | Location | Role |
|---|---|---|
| Design plans 01–06 | `docs/design/*.md` | rationale + this backbone |
| Contributor contract | `DESIGN.md` (repo root) | the one file everyone reads first |
| Token source of truth | `debrowser.css:342-389` | single definition point |
| Style guide | `inst/extdata/www/style-guide.html` | client-facing gallery + regression baseline |
| Style-guide opener | `R/de_style_guide.R` (exported) | in-package access |
| Screenshot baselines | `docs/design/baseline/*.png` | regression reference |

### Versioning
- The style guide lives under `inst/`, so it is **installed with the package** and pinned to the exact `debrowser.css` of that version — client and code never drift.
- Bump `DESCRIPTION` `Version:` (currently `1.31.2`) and add an `NEWS.md` entry under the in-development header, e.g.:
  ```markdown
  ## debrowser 1.31.3 (in development)
  - Design-system consolidation: single token source of truth
    (`--de-ink-on-accent`), style-guide harness, `DESIGN.md`, and CSS
    de-duplication (B3.x patch history folded into component sections).
  ```
- Export `de_style_guide()` in `NAMESPACE` (roxygen `@export` handles this on `devtools::document()`).
- Add a `.Rd` for `de_style_guide` (generated) and reference `DESIGN.md` from the package `README`/vignette so it is discoverable.

### Bioconductor-review benefits (call these out in the submission notes)
- **Reviewability:** a reviewer can open `style-guide.html` and `DESIGN.md` and understand the entire visual layer in minutes, instead of scrolling 4,903 lines of patched CSS.
- **`BiocCheck` hygiene:** removing orphan assets (5b) and dead code (5c) trims the tarball and clears "unused file"/"undocumented object" style flags; fixing `fa-show` (5d) removes a broken UI element.
- **Maintainability signal:** a documented token vocabulary + a regression harness demonstrates the package is maintainable, which Bioconductor weighs for long-term packages.
- **No new runtime deps:** the style guide is static HTML and `de_style_guide()` uses only `utils`/`system.file` — nothing added to `Imports`. (The CDN links in the guide are dev-time; vendor them into `inst/extdata/www/vendor/` if a fully offline build is required.)

**Commit:**
```
chore(handoff): bundle design docs + style guide, bump NEWS for 1.31.3
```

---

## Task summary

| # | Task | Label | Depends on | Commit scope |
|---|------|-------|------------|--------------|
| 1a | `--de-ink-on-accent` + migrate 28 `#0B1020` | [Consolidation] | — | `refactor(css)` |
| 1b | De-dupe legal-page tokens | [Consolidation] | — | `refactor(legal)` |
| 2 | Fold B3.x into component blocks, drop `!important` | [Consolidation] | 3 | `refactor(css)` ×~6 |
| 3 | `style-guide.html` + `de_style_guide()` | [System] | — | `feat(design)` |
| 4 | `DESIGN.md` | [System] | 1 | `docs(design)` |
| 5a | Wire favicon | [Quick win] | — (detail: 03) | `fix(ui)` |
| 5b | Delete orphan assets | [Quick win] | — | `chore(assets)` |
| 5c | Resolve dead loading overlay | [Quick win] | — (detail: 04) | `refactor(server)` |
| 5d | Fix `fa-show` → `fa-eye` | [Quick win] | — (detail: 03) | `fix(funcs)` |
| 6 | Bundle + version the handoff | [System] | 1–5 | `chore(handoff)` |

**Definition of done:** `grep -ciE '#0b1020' debrowser.css` = 1 · `grep -c '!important' debrowser.css` < 350 · zero `B3.x` banners · `style-guide.html` renders every component in both themes with AE=0 baselines · `DESIGN.md` present · four housekeeping fixes verified · `NEWS.md` bumped.
