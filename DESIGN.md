# DEBrowser Design System

DEBrowser ships a self-contained visual redesign layer. This document is the
contract: read it before editing `inst/extdata/www/debrowser.css`. The full
rationale lives in `docs/design/01`–`06`; this is the quick reference. To *see*
the system, open the style guide: `debrowser::de_style_guide()` (or
`inst/extdata/www/style-guide.html` in any browser).

## 1. How the redesign is wired

- **The gate.** Every redesign rule is scoped under
  `html[data-debrowser-redesign="1"]`. The attribute is set by an inline script
  in `R/ui.R`, **on by default**. Opt out with `?redesign=0` in the URL — those
  users get stock bslib. *Never write a redesign rule without this prefix*; that
  is what keeps opt-out clean and the layer reversible.
- **Themes.** Light/dark is `data-bs-theme` on `<html>`. Token values switch in
  the light/dark blocks at `debrowser.css:421-452`. Toggle via the theme button
  or the `T` key.
- **Keyboard shortcuts** (ignored while typing in a field): `1`–`6` switch the
  top-level tab; `T` toggles light/dark.
- **Fonts.** Inter (UI, via bslib) + JetBrains Mono (numeric / table headers).

## 2. Token vocabulary — the single source of truth

All values live once, in the token block at `debrowser.css:370-452` (shared
`370-419`, light `421-435`, dark `437-452`). Consume via `var(--de-*)`; never
paste a literal into a component block.

| Token | Light | Dark | Use |
|-------|-------|------|-----|
| `--de-cyan` | `#6366F1` | `#6366F1` | primary accent (fill) — **indigo** (Clinical Indigo direction) |
| `--de-violet` | `#A78BFA` | `#A78BFA` | secondary/categorical accent (fill) |
| `--de-blue` / `--de-mint` / `--de-pink` | `#60A5FA` / `#3CB6A0` / `#FF7AA2` | (same) | categorical palette (fill) |
| `--de-grad` | indigo `#4F46E5 → #6366F1`, 135° | `#6366F1 → #818CF8` | primary button / chip / progress fill (monochromatic — reads solid) |
| `--de-accent-ink` | `#4338CA` | `#A5B4FC` | **accent as TEXT** (WCAG-safe; never use `--de-cyan` for text) |
| `--de-ink-on-accent` | `#FFFFFF` | `#FFFFFF` | text/icon placed **on** an accent fill (white — the indigo accent is dark) |
| `--de-bg-0` | `#F7F8FC` | `#0B1020` | page canvas |
| `--de-bg-1` | `#FFFFFF` | `#0F1530` | card / raised surface |
| `--de-bg-2` / `--de-bg-3` | `#FFFFFF` / `#F1F4FB` | `#141B3A` / `#1A2147` | nested / hover surfaces |
| `--de-border` / `--de-border-strong` | ink @10% / @18% | white @8% / @14% | hairlines |
| `--de-text-1` | `#0F1530` | `#E6ECFF` | primary text |
| `--de-text-2` | `#475270` | `#A8B2D1` | secondary text |
| `--de-text-3` | `#556087` | `#808CB8` | muted text (raised from `#6E7BA5` for WCAG AA — see §2 plan) |
| `--de-grid` | ink @4% | white @4% | canvas grid |
| `--de-r-sm/-md/-lg/-pill` | 6 / 10 / 14 / 999px | (same) | radii |
| `--de-space-1…6` | 4 / 8 / 12 / 16 / 24 / 32px | (same) | spacing scale (see §1 plan) |
| `--de-dur` / `--de-ease` | `140ms` / `cubic-bezier(.2,.6,.2,1)` | (same) | motion primitives (see §5 plan) |
| `--de-transition` | named-property composite of the two above | (same) | the one transition for interactive bases |
| `--de-shadow` / `--de-shadow-lg` | soft | deeper | elevation |

> **Plot heights** are the one dimension that can't be a CSS token: shiny/bslib
> run `plotOutput(height=)` and `layout_columns(gap=)` through
> `validateCssUnit()`, which rejects `var()`. Their single source of truth is
> the R helper `de_plot_h("sm"|"md"|"lg")` = `360|420|500px` (`R/de_card.R`).
>
> **Legal pages** (`inst/extdata/www/legal/`) are standalone HTML served outside
> the redesign gate, so they inline their own dark-set `:root`. De-duplicating
> those into a shared `legal.css` is tracked in §1b of the handoff plan (not yet
> done); if you change a brand token, update the three legal pages too.

## 3. Grid & spacing

One grid primitive (`bslib::layout_columns(col_widths=)`), one card wrapper
(`de_card()`), one spacing scale (`--de-space-*`) — never magic px. The full
rules and the `tools/check-grid.sh` lint that enforces them are in
`docs/design/01-grid-system-plan.md`.

## 4. One icon set

DEBrowser uses **Font Awesome 6 only**. Do not mix in Bootstrap Icons or inline
SVGs. Icon names must be valid FA identifiers, passed via `shiny::icon()`. The
redesign re-asserts the FA `font-family` with `!important` so the Inter UI font
can't clobber glyphs — do not remove that rule. Full policy + favicon wiring:
`docs/design/03-iconography-plan.md`.

Documented exceptions (intentional, not icons): the standalone legal pages use
typographic glyphs (`§`, `←`) rather than FA, and a few purely decorative CSS
arrows (`▾ ▴ →`) appear in pseudo-elements. These are deliberate and out of the
FA-only rule.

## 5. Loading, hover & motion

- **Loading/busy.** The page-load overlay is the CSS conic ring `#loading-debrowser`
  (`R/ui.R`); long operations use `shiny::withProgress` (the DE run reports
  Normalizing → Fitting → Contrasts). DEBrowser deliberately uses `withProgress`
  rather than a spinner library. Details: `docs/design/04-loading-states-plan.md`.
- **Hover / focus / motion.** Transitions use `--de-transition` (never a
  hard-coded timing or `transition: all`). Keyboard focus is a `:focus-visible`
  accent-ink outline; disabled controls and locked wizard steps get
  `cursor: not-allowed`; `prefers-reduced-motion` is honored globally.
  Details: `docs/design/05-hover-cursor-plan.md`.

## 6. Editing rules (the short version)

1. New value that repeats? Add a token at `debrowser.css:370-452`, don't paste a
   literal.
2. Scope every rule under `html[data-debrowser-redesign="1"]`.
3. One component = one block. Don't append a "fix" block; edit the component's
   section.
4. Reach for `!important` only to beat Bootstrap/bslib/third-party *inline*
   styles or font-family cascade, and comment what it overrides.
5. Changed anything visual? Re-open `de_style_guide()` in **both** themes (and
   `?theme=light|dark` for a shot) and confirm nothing else moved.
6. Run `bash tools/check-grid.sh` before committing layout changes.
