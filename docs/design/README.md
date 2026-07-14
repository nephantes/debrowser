# DEBrowser UI Improvement Plan

> **For agentic workers:** each section below is an independently executable plan file. REQUIRED SUB-SKILL for implementation: `superpowers:subagent-driven-development` (fresh subagent per task, review between) or `superpowers:executing-plans`. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn DEBrowser's ambitious-but-accreted redesign layer into a coherent, documented, accessible design *system* — without regressing the look that already works.

**Architecture:** DEBrowser already ships a full redesign layer (`inst/extdata/www/debrowser.css`, ~4,900 lines) gated on `html[data-debrowser-redesign="1"]` (set in [ui.R:239](../../R/ui.R#L239), on by default, opt-out `?redesign=0`), with a `--de-*` design-token system, dark/light themes (`data-bs-theme`), and a cyan→violet gradient language. This plan does **not** restyle the app — it *consolidates* what exists: one grid, one palette (contrast-fixed), one icon set, real loading/hover conventions, and the docs/style-guide that make it maintainable.

**Tech stack:** R, Shiny, bslib (Bootstrap 5), htmltools, DT, plotly; CSS custom properties; Font Awesome (bundled); Inter + JetBrains Mono (Google Fonts).

---

## Global Constraints

Every task inherits these — copied verbatim into the section plans:

- **Additive & reversible.** The redesign is opt-in via `html[data-debrowser-redesign="1"]`. Keep that gate. Nothing may break the `?redesign=0` fallback.
- **Both themes always.** Every visual change must be checked in **light and dark** (`data-bs-theme` toggle, or the `T` keyboard shortcut). A fix that only works in dark is not done.
- **WCAG AA.** Small text ≥ 4.5:1, large/UI ≥ 3.0:1. New color pairs must be contrast-checked before commit.
- **Bioconductor package.** Changes go through `R CMD build`/`BiocCheck`; new dependencies land in `DESCRIPTION` Imports/Suggests with a NEWS entry. Keep `R/` roxygen + `man/` in sync.
- **House style.** Tokens are `--de-*`; redesign CSS is gated on the attribute selector; cards route through `de_card()` ([de_card.R:17](../../R/de_card.R#L17)); modules use `ns()`.
- **Verify before "done."** Run the app (or the style-guide harness from §6) and look, in both themes, before committing.

---

## Phase 0 — Canonical Token Foundation (do this first)

Several sections depend on these tokens existing. Add/change them in the token blocks at [debrowser.css:342–389](../../inst/extdata/www/debrowser.css#L342). **§2 owns** the full drop-in diff + contrast table for the palette/spacing/motion tokens; **§5 owns** the composite `--de-transition` (built from `--de-dur`/`--de-ease`); **§6 owns** `--de-ink-on-accent` and the migration of the ~28 hard-coded `#0B1020` sites. This is the authoritative summary — until Phase 0 lands, dependent rules reference these with fallbacks (e.g. `var(--de-dur, 140ms)`).

**Base block** `html[data-debrowser-redesign="1"]` — add:

```css
  /* Spacing scale (8px base) — replaces scattered inline margins / height:12px spacers */
  --de-space-1: 4px;  --de-space-2: 8px;  --de-space-3: 12px;
  --de-space-4: 16px; --de-space-5: 20px; --de-space-6: 24px;
  /* Motion — one duration + one curve for the whole app */
  --de-dur:  140ms;
  --de-ease: cubic-bezier(.2, .6, .2, 1);
  /* Ink that sits on top of an accent fill (was hard-coded #0B1020 in dozens of places) */
  --de-ink-on-accent: #0B1020;
```

**Light theme block** ([:361–373](../../inst/extdata/www/debrowser.css#L361)) — add + change:

```css
  --de-accent-ink: #0E7490;   /* accent-as-TEXT; 5.36:1 on #FFF, 4.87:1 on --de-bg-3 (PASS) */
  --de-text-3:     #556087;   /* was #6E7BA5 = 4.17:1 (FAIL); now 6.16:1 on white (PASS) */
```

**Dark theme block** ([:376–389](../../inst/extdata/www/debrowser.css#L376)) — add + change:

```css
  --de-accent-ink: #5EE6D6;   /* accent-as-text; 11.76:1 on --de-bg-1 (PASS) */
  --de-text-3:     #808CB8;   /* was #6E7BA5 = 4.31:1 (FAIL); now 5.44:1 on --de-bg-1 (PASS) */
```

**The role rule (the reason this fixes the "invisible eyebrow" bug):**

| Token | Role | Used for |
|---|---|---|
| `--de-accent-ink` | accent-as-**TEXT** | `.de-eyebrow`, inline `code`/`kbd`, active links, the `?` help icon, colored active-tab text |
| `--de-cyan` / `--de-grad` | **FILL** only | buttons, slider bars, wizard dots, gradient underline, badges |
| `--de-ink-on-accent` | text **on** a fill | button label over the gradient |

The bug today: raw `--de-cyan` (`#5EE6D6`) is used as *text*, which is a beautiful 11.8:1 on dark but an invisible **1.53:1 on white**. Splitting the "text" role into a theme-aware `--de-accent-ink` is the single change that fixes it. `de_theme()` keeps `primary = #0369A1` ([de_theme.R:157](../../R/de_theme.R#L157)) as the WCAG-safe (5.93:1) system fallback so un-overridden Bootstrap surfaces match the brand family instead of clashing with it.

---

## The six section plans

| # | Plan | Fixes | File |
|---|---|---|---|
| 1 | **Grid system** | 4 grid idioms → 1; ragged rows; floating buttons; 2 card systems; sidebar widths | [`01-grid-system-plan.md`](01-grid-system-plan.md) |
| 2 | **Color palette** | contrast fixes (text-3, accent-ink); two-palette conflict; role rule; full contrast table | [`02-color-palette-plan.md`](02-color-palette-plan.md) |
| 3 | **Iconography** | 5 icon families → Font Awesome; `fa-show` bug; favicon; orphan assets | [`03-iconography-plan.md`](03-iconography-plan.md) |
| 4 | **Loading states** | dead busy overlay; spinners on QC cards + tables; timing rule; 1.1 MB boot gif | [`04-loading-states-plan.md`](04-loading-states-plan.md) |
| 5 | **Hover & cursor** | one motion token; hover lift; global focus-visible; reduced-motion; perf | [`05-hover-cursor-plan.md`](05-hover-cursor-plan.md) |
| 6 | **Handoff & consolidation** | token source-of-truth; `!important` reduction; living style guide; `DESIGN.md` | [`06-handoff-plan.md`](06-handoff-plan.md) |

---

## Priority-wave roadmap (how to sequence all six together)

Rather than finishing one section before starting the next, run in **three waves** so the highest-value, lowest-risk work ships first.

### Wave 1 — Quick wins (accessibility + correctness; ~half a day, low risk)
Independent, mechanical, each self-contained:
- **Phase 0 tokens** + §2 contrast fixes (`--de-text-3`, `--de-accent-ink`) — fixes two verified WCAG failures.
- §5 `:focus-visible` global rule + `prefers-reduced-motion` block — keyboard/accessibility.
- §3 `fa-show` fix, favicon wiring, delete orphan assets.
- §4 delete orphan `loading2.gif`, wrap the 4 bare QC cards + tables with a spinner.
- §1 close the ragged rows (`3+3`→`c(6,6)`, `3+3+3`→`c(4,4,4)`, lone `col 6`) and wrap the floating buttons; unify sidebar width 280→300.

### Wave 2 — Consolidation (the "one of each" pass; ~1–2 days)
- §1 migrate the three 50/50 idioms + raw `bslib::card()` → `layout_columns` + `de_card()`.
- §2 migrate raw-cyan-as-text → `var(--de-accent-ink)`; adopt `--de-ink-on-accent`.
- §3 glyph-mapping migration (Unicode/SVG → FA), retire the hand-written `<i>` path.
- §5 replace `transition:all`, adopt the motion token, add the hover-lift + underline-wipe.
- §4 timing rule + stepwise DE progress + convert the boot gif to CSS/SVG.

### Wave 3 — System & docs (makes it *stay* consolidated; ~1–2 days)
- §6 build the **living style guide** (regression net) → then the **CSS consolidation** pass (collapse B3.1–B3.34, drive down the 1,201 `!important`) → write **`DESIGN.md`**.
- §1 spacing-token adoption + a grid lint/check.

Do Wave 1 in any order (tasks are independent). Wave 3's style guide should be built **before** the CSS consolidation so you have a screenshot-diff safety net.

---

## Execution

Each section file is a checkbox plan. To implement:

1. **Subagent-driven (recommended)** — one fresh subagent per task, review between tasks.
2. **Inline** — batch execution with checkpoints.

Verify every visual task against the running app (or the §6 style-guide page) in **both themes** before committing.
