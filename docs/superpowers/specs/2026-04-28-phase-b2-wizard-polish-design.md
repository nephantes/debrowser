# Phase B2 — Wizard polish (post-B1 re-scope)

**Date:** 2026-04-28
**Branch:** `modernize`
**Predecessor:** B1 (bslib chrome + theme + dark mode), shipped at `36a6d4f`
**Successor:** B2.5 (condSelect rewrite), then B3 (sane defaults)

## Context

The original B2 spec (in `2026-04-27-debrowser-modernization-design.md`, lines 210–228) was written *before B1 landed*. It assumed a 2-tab `tabBox(Data Prep / Discover)` shell and proposed replacing it with a 3-stage `Data → Analyze → Explore` stepper plus a global Simple/Advanced view-mode toggle.

B1 has since shipped a `bslib::page_navbar` with five panels (Data Prep / Main Plots / QC Plots / GO Term / Tables), accordion-based menu items, and theme + dark mode. The structural problem the original B2 was solving — "the 2-tab shell is confusing for first-timers" — no longer exists.

This spec re-scopes B2 against post-B1 reality: drop the structural redesign, keep the *progress + first-run feel* the original stepper was meant to deliver, and apply it to B1's existing navbar.

## Goals

Deliver, on top of the post-B1 navbar:

1. **Progress visibility** — users can see where they are in the pipeline at a glance (which stages are done, which are unlocked, which are locked) without learning a new layout
2. **Cross-tab gating** — outer tabs that produce nothing useful before DE has run (Main Plots, GO Term, Tables) are not shown until DE has completed; QC Plots unlocks earlier (after counts load)
3. **First-run friendliness** — Stage 1 (data upload) reads as a wizard rather than a configuration form
4. **Cosmetic cleanup** — sibling-accordion consolidation and label cleanup carried over from B1
5. **CI safety net** — shinytest2 baselines locked in once the above stabilises, so B2.5 (condSelect rewrite) inherits regression coverage

## Re-scope summary (vs original B2)

| Original B2 item | Disposition | Rationale |
|---|---|---|
| 3-stage outer shell (`Data → Analyze → Explore`) | **Dropped** | B1's `page_navbar` already groups by purpose; no structural rebuild needed |
| Simple/Advanced global view-mode toggle | **Dropped** | Was load-bearing only when the 3-stage shell hid power-user views; nothing to hide post-B1 |
| Quick-Start wizard for Stage 1 (drop zone, separator auto-detect) | **Kept (B2b)** | First-run UX gain is independent of shell shape |
| Stage 2 "Treatment vs Control" language | **Moved to B2.5** | Bundled with full condSelect rewrite to avoid touching that module twice |
| Stage 3 land-on-volcano default | **Kept (B2a)** | Implementable as an auto-`nav_select` on DE completion |
| Cross-tab progress/gating | **Kept (B2a)** | The "wizard feel" without the structural rebuild |
| `condSelect.R` full rewrite | **Moved to B2.5** | Risk-isolated as its own phase |
| `bsModal → modalDialog` migrations | **Already done in B1.12** | Not part of B2 |
| shinytest2 on CI | **Kept (B2c)** | Lands last so baselines target stabilised UI |
| Cosmetic pass (sibling accordions, label cleanup) | **Kept (B2c)** | Bundled with shinytest2 |

## Decisions made during brainstorm (2026-04-28)

- **Q1 — Re-scope vs lock scope:** Re-scope against post-B1 reality first. Dropping the 3-stage shell replacement is justified; original spec's structural premise no longer holds.
- **Q2 — Progress visibility model:** In-place tab decoration (option (a)). Annotate existing `page_navbar` tabs with progress state; add per-step checkmarks to the Data Prep `navset_pill_list`. No separate progress strip above the navbar.
- **Q3 — condSelect rewrite placement:** Split into its own phase (B2.5). Risk-isolate the riskiest module change from the structural UX work.
- **Q4 — Decomposition slicing:** Approach 1 — three sub-plans (B2a state/decoration, B2b wizard, B2c shinytest2 + cosmetic). B2a and B2b parallel; B2c lands last.
- **Q5 — Simple/Advanced toggle:** Drop the global toggle entirely. Inside the upload card, keep a thin "Show all options" disclosure that pre-expands separator radio + sheet picker — local to upload, not global.
- **Q6 — Demo data buttons:** Keep both (Vernia smaller / Donnard larger), keep them as primary actions; they are alternative paths for trying the app, not redundant copies. Place below the drop zones under an "or try a demo:" caption.
- **Q7 — shinytest2 visual regression in v1:** Include screenshot-based assertions (3–5 frames). Baselines generated on Linux, with macOS dev workflow documented.

## Sub-plans

### B2a — State + decoration + gating + auto-nav

#### State model

Single source of truth at the top of `deServer`:

```r
rv$stages <- reactiveValues(
  upload = "pending",   # pending | done
  filter = "locked",    # locked | pending | done
  batch  = "skipped",   # locked | pending | done | skipped
  de     = "locked"     # locked | pending | done
)

rv$tabs <- reactiveValues(
  # Visibility only — bslib tracks the currently-selected tab via methodtabs id.
  # State enum: locked | unlocked. Data Prep is always shown; not tracked here.
  qc_plots   = "locked",   # unlocked when counts load (raw QC needs no DE)
  main_plots = "locked",   # unlocked after DE runs
  go_term    = "locked",   #
  tables     = "locked"    #
)
```

#### State transitions

Set by existing observers; B2a only adds status updates, no new business logic:

- `rv$counts` becomes non-null → `stages$upload = "done"`, `tabs$qc_plots = "unlocked"`, `stages$filter = "pending"`
- Filter button click + valid filter → `stages$filter = "done"`, `stages$batch = "pending"`
- Batch correction skipped or applied → `stages$batch = "skipped"|"done"`, `stages$de = "pending"`
- DE finishes → `stages$de = "done"`, `tabs$main_plots = tabs$go_term = tabs$tables = "unlocked"`

Reload behaviour: state resets to defaults. If counts happen to persist (e.g., via session storage), the upload-done observer re-fires on counts re-population; `de` stays locked until the user re-runs.

DE error: `stages$de` stays `"pending"`, downstream tabs stay locked. The existing DE error toast is unchanged; no new error UI.

Multi-comparison: `stages$de = "done"` once any one comparison succeeds. Subsequent comparisons do not re-lock.

#### Visual rendering

- *Outer navbar:* `nav_panel` titles wrap a small `de_progress_label(name, state)` helper that returns `<span>name <icon/></span>`. Icons via `bsicons::bs_icon("check-circle-fill")` (done), `bsicons::bs_icon("lock-fill")` (locked), no icon (active).
- *Locked outer tabs:* hidden via `bslib::nav_hide()`. Reasoning: bslib has no native disabled-tab state; CSS hacks fight bslib's own JS. Hiding is honest and matches the `nav_show`/`nav_hide` pattern already used in B1.
- *Data Prep pills:* `navset_pill_list` titles use the same `de_progress_label` helper. Locked pills stay visible but get `pointer-events: none` via a CSS class on the pill `<a>` (acceptable here because the pill list is our own, not a bslib internal).

#### Auto-nav after DE

A single observer on `stages$de == "done"` calls `bslib::nav_select(session, "methodtabs", "main_plots")`. Main Plots already lands on volcano via existing sub-nav default; verify during plan-writing.

#### Files touched

- `R/deServer.R` (or wherever `deServer` lives) — `rv$stages` / `rv$tabs` definitions + observers
- `R/ui.R` (`deUI`) — wrap `nav_panel` titles
- New: `R/de_progress.R` — `de_progress_label()` helper, `compute_progress_label()` pure function, ~40 lines
- `inst/extdata/www/debrowser.css` — `.de-pill-locked` class

#### Risk notes

- `bslib::nav_hide` re-show animation may flash on DE completion. Acceptable; if it bites, fall back to always-rendered titles + CSS-greyed locked tabs.
- `de_progress_label` must NOT introduce reactivity inside `renderUI` per nav title (cascading re-renders). Trick: render the navbar shell once with placeholder titles; use a targeted update API on transitions. Confirm the right bslib API during plan-writing — candidates: `bslib::nav_select` for active state, custom JS via `session$sendCustomMessage` for icon updates.

#### Tests

- Pure: `compute_progress_label(state, name)` → testthat unit tests
- Integration: deferred to B2c shinytest2

---

### B2b — Quick Start wizard for Stage 1

#### Scope

Replace the upload form in `R/dataLoad.R` with a wizard-style card:

- One prominent drop zone for counts (replacing two side-by-side `fileInput`s and the upfront separator radio)
- One smaller secondary drop zone for optional metadata, beneath the counts zone
- "or try a demo:" caption + both demo buttons (Vernia, Donnard) preserved as primary actions
- Inline 5-row × 6-column preview rendered immediately after upload completes
- "Show all options" disclosure that pre-expands separator radio + sheet picker (replaces the dropped global Simple/Advanced toggle)

#### Auto-detect logic

New pure helper `detect_separator(path, sample_lines = 50)`:

1. Strip BOM, decompress if `.gz`
2. Read first N lines
3. For each candidate in `c("\t", ",", ";")`:
   - Split lines, count fields
   - Parse columns 2..K as numeric
   - Score = number of columns with ≥80% numeric parse rate
4. Return highest-scoring delimiter with score ≥ 3, else `NA`

Tie-break: tab > comma > semicolon. `NA` triggers the "Show all options" expander auto-open + a "couldn't auto-detect — pick the separator" caption.

Excel files (`.xlsx`/`.xls`) skip auto-detect; existing sheet-picker path is preserved.

#### Default metadata fallback

New pure helper `make_default_metadata(counts)`: builds a single-condition single-batch data frame with all samples assigned to one group. If used, condSelect's existing "need ≥2 conditions" validation surfaces the requirement to the user — no new validation logic in B2b.

#### Files touched

- `R/dataLoad.R` — UI rework, auto-detect wiring, default-metadata path, "Show all options" expander
- New helpers (in `R/dataLoad.R` or new `R/fct_upload.R`): `detect_separator()`, `make_default_metadata()`
- `inst/extdata/www/debrowser.css` — drop-zone styling
- `tests/testthat/test-detect_separator.R` — fixtures: `.tsv`, `.csv`, `.csv` with quoted commas, ambiguous file, malformed file, `.csv.gz`, BOM-prefixed file, comma-decimal European CSV

#### Edge cases

- Tiny file (1–2 numeric columns): auto-detect returns `NA`; "Show all options" expander auto-opens
- Quoted commas inside a TSV: tab wins on numeric-column score
- `.csv.gz`, `.tsv.gz`: decompress then sniff
- Multi-byte BOM: stripped before counting
- Comma-decimal European CSV: numeric parse fails under `,` delimiter, so `;` wins

#### Risk notes

- Drop-zone visual change is the most user-visible part of B2; long-time users will notice. Mitigation: separator radio is one disclosure-click away; demo buttons preserved.
- Auto-detect mis-fire on legitimate files would block upload. Mitigation: aggressive fixture coverage + always-available "Show all options" fallback.

#### Tests

- `detect_separator()` and `make_default_metadata()` are pure → testthat fixtures
- UI flow → deferred to B2c shinytest2

---

### B2c — shinytest2 + cosmetic pass

Lands after B2a and B2b are merged so cosmetic edits and shinytest2 baselines target the stabilised UI.

#### shinytest2 enablement

Setup:

- Add `shinytest2` to `DESCRIPTION` Suggests
- New: `tests/testthat/test-app-shinytest2.R`
- Baselines stored under `tests/testthat/_snaps/`

Test scope:

1. **Smoke (state-based):** app starts, all 5 outer tabs render, dark-mode toggle present
2. **Golden path (state-based):** *Load Demo (Vernia)* → counts populate → `Upload ✓` decoration → Filter → `Filter ✓` → DE → outer tabs unlock → auto-nav to Main Plots → volcano renders with point count > 0
3. **Locked-tab DOM assertion (state-based):** before DE, Main Plots / GO / Tables not in DOM; after DE, present
4. **Visual regression (screenshot-based, 3–5 frames):**
   - Initial load (Stage 1 wizard with demo buttons visible)
   - Post-DE Main Plots (volcano with top 10 labelled)
   - Dark mode applied to Main Plots

Cross-OS handling:

- Baselines generated on Linux (CI runtime), committed from a Docker container or `act` locally — **not** from macOS dev workstation
- New: `tests/README-shinytest2.md` documenting the baseline-recording workflow
- `expect_screenshot()` calls use `threshold = 0.01` to absorb antialiasing diffs
- Screenshot tests `testthat::skip_on_os("mac")` so local dev runs don't generate spurious diffs

CI integration:

- New: `.github/workflows/shinytest2.yml` — Ubuntu, Chrome headless, runs on PR + push to `modernize`/`devel`
- Demo data load < 5s; DE on Vernia ~10–20s on CI runners; single-test budget

Risk notes:

- macOS-committed baselines fail Ubuntu CI — must be generated in Linux env
- Screenshot tests are inherently flakier than state assertions; expect early re-baseline rounds. Mitigation: keep frame count to 3–5; do not sprawl.

#### Cosmetic pass

1. **`R/heatmap.R::heatmapControlsUI`** — 8 sibling single-panel accordions consolidate into one `bslib::accordion(multiple = TRUE, open = FALSE, accordion_panel(...) × 8)`. Behaviour identical (independent collapsibility preserved by `multiple = TRUE`); structure cleaner.
2. **`R/uifuncs.R`** — same pattern; same fix.
3. **`R/heatmap.R::heatmapUI` roxygen `@example`** — currently `x <- heatmapUI()` but the function takes `(input, output, session)`. Replace with working example or wrap in `\dontrun{}`.
4. **Card titles using `session$ns(...)`** — replace `session$ns("Heatmap")` / `session$ns("plot")` / `session$ns("Size & Margins")` etc. with plain literals (`"Heatmap"`, `"Plot"`, `"Size & Margins"`).
5. **Sidebar accordion typography** — new CSS rule scoped to sidebar layouts:
    ```css
    .bslib-sidebar-layout .accordion-button {
      font-size: 0.875rem;
      padding: 0.5rem 0.75rem;
      line-height: 1.3;
    }
    .bslib-sidebar-layout .accordion-body {
      padding: 0.5rem 0.75rem;
    }
    ```
   Scoped via `.bslib-sidebar-layout` so main-content accordions keep default sizing.

#### Files touched

- `DESCRIPTION` — `shinytest2` to Suggests
- `tests/testthat/test-app-shinytest2.R` (new)
- `tests/testthat/_snaps/...` (new, generated on Linux)
- `tests/README-shinytest2.md` (new)
- `.github/workflows/shinytest2.yml` (new)
- `R/heatmap.R`, `R/uifuncs.R` — accordion consolidation, label cleanup, roxygen fix
- `inst/extdata/www/debrowser.css` — sidebar accordion typography rule

#### Sequencing within B2c

Cosmetic edits land first (no behavior change), then shinytest2 baselines are recorded against the cleaned UI. Single PR is fine — diff stays small.

---

## Sequencing & dependencies

```
B1 (shipped) ─┐
              ├─→ B2a ──┐
              ├─→ B2b ──┤
                        ├─→ B2c ──→ B2.5 (condSelect rewrite) ──→ B3
                        │
                        └─ B2a/B2b in either order or parallel — different files
```

**Inter-sub-plan contracts:**

- B2a publishes a stable `rv$stages` / `rv$tabs` shape; B2b's wizard sets `stages$upload = "done"` once counts load. That is the only interface they share.
- B2c assumes B2a's `nav_hide` / `nav_show` calls are stable (so locked-tab DOM assertions are deterministic).
- B2.5 inherits B2c's shinytest2 coverage as its safety net.

## Acceptance criteria

End-to-end, testable:

1. Fresh app load → only Data Prep visible in outer navbar; QC Plots / Main Plots / GO / Tables hidden
2. Click *Load Demo (Vernia)* → counts populate, inline preview renders, Stage 1 pill shows `Upload ✓`, QC Plots tab appears
3. Run filter + DE → Main Plots / GO / Tables tabs appear; app auto-navigates to Main Plots; volcano renders
4. Reload page → state resets; Main Plots / GO / Tables hidden again until DE re-runs
5. Heatmap sidebar shows 1 multi-panel accordion (not 8); panel titles read "Size & Margins" not "heatmapQC - Size & Margins"
6. shinytest2 CI run is green on Linux for 3–5 screenshot frames + state assertions
7. `R CMD check` passes with no new warnings beyond B1's pre-existing
8. `devtools::test()` passes ≥ 88 tests (B1 baseline) plus new tests for `detect_separator()`, `compute_progress_label()`, `make_default_metadata()`

## Out of scope (deliberate)

- 3-stage outer shell replacement
- Simple/Advanced global view-mode toggle
- "Treatment vs Control" condSelect language swap (→ B2.5)
- Full `condSelect.R` rewrite (→ B2.5)
- Plot UX (palettes, downloads, plotly dark mode) (→ B6)
- Sane defaults harmonization (padj 0.05, |log2FC| 1) (→ B3)
- Friendly error copy (→ B4)
- Onboarding (post-upload nudges, demo-data tour) (→ B5)
- Multi-factor / interaction designs (→ Phase F E5)

## Implementation plans (decomposition)

This spec decomposes into three implementation plans, written and executed in this order:

1. `2026-XX-XX-phase-b2a-progress-state.md` — written first
2. `2026-XX-XX-phase-b2b-quickstart-wizard.md` — written in parallel with B2a (or after, if context budget tight)
3. `2026-XX-XX-phase-b2c-shinytest2-cosmetic.md` — written after B2a + B2b merge

A separate spec covers B2.5 (condSelect rewrite) when it is its turn.
