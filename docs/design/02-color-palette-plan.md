# 02 — Color Palette Refinement Plan (DEBrowser redesign layer)

**Scope:** the redesign CSS gated on `html[data-debrowser-redesign="1"]` in
`inst/extdata/www/debrowser.css`, plus the bslib theme in `R/de_theme.R`.

**Ownership:** this plan is the **canonical source of the design tokens**. Phase 0
below defines every `--de-*` token value. Sibling plans consume them:

- `../design/01-grid-system-plan.md` consumes the **spacing** tokens (`--de-space-1..6`).
- `../design/05-hover-cursor-plan.md` consumes the **motion** tokens (`--de-dur`, `--de-ease`).

Those plans MUST NOT redefine these tokens; they reference the values fixed here.

**Ground rules for every task below:**
- All CSS edits target `inst/extdata/www/debrowser.css` unless stated otherwise.
- Line numbers are **pre-edit anchors** (as of this plan). They shift once earlier
  tasks are applied, so each task also quotes the unambiguous **selector** to locate.
- Small text needs **>= 4.5:1**; large text (>= 24px, or >= 18.66px bold) and
  non-text UI boundaries need **>= 3.0:1** (WCAG 2.1 SC 1.4.3 / 1.4.11).
- Every ratio in this document was computed with the WCAG relative-luminance
  formula on the real hex values (see the verification script in §6).

---

## The one mistake (read this first)

**Cyan-as-TEXT in light mode is the core defect.** `--de-cyan #5EE6D6` is a
bright fill color engineered to sit *behind* dark ink (`#0B1020` reads **12.41:1**
on it — great for buttons and chips). The same cyan used as a **foreground text
color on a light surface** is nearly invisible:

| Cyan used as text (light mode) | Ratio | Verdict |
|---|---|---|
| `.de-eyebrow` cyan on white | **1.53:1** | FAIL — effectively invisible |
| inline `code`/`kbd` cyan on `--de-bg-3 #F1F4FB` | **1.39:1** | FAIL |
| `.de-drop-ic` cyan on white | **1.53:1** | FAIL |
| selectize ✓ checkmark cyan on selected tint | **1.43:1** | FAIL |

The fix is **not** to darken the cyan globally (that would ruin the buttons and
the gradient). The fix is a **role split**: introduce a second token,
`--de-accent-ink`, that is "the accent when it must be readable as text," and
resolve it per theme — a dark teal in light mode, the bright cyan in dark mode.
`--de-cyan`/`--de-grad` stay **fill-only**.

---

## Phase 0 — Canonical token block (OWNED HERE)

This is the authoritative token definition. Tasks 1–3 apply the three diffs that
turn the current block into this. Presented together first so downstream plans
have one place to cite.

### 0.1 Base block — `html[data-debrowser-redesign="1"]` (currently lines 342–358)

**BEFORE**
```css
html[data-debrowser-redesign="1"] {
  --de-cyan:    #5EE6D6;
  --de-violet:  #A78BFA;
  --de-blue:    #60A5FA;
  --de-mint:    #3CB6A0;
  --de-pink:    #FF7AA2;
  --de-grad:    linear-gradient(135deg, #5EE6D6 0%, #A78BFA 100%);
  --de-grad-soft: linear-gradient(135deg, rgba(94,230,214,.12), rgba(167,139,250,.12));

  --de-r-sm:   6px;
  --de-r-md:   10px;
  --de-r-lg:   14px;
  --de-r-pill: 999px;

  --de-shadow:    0 6px 24px rgba(0,0,0,.06);
  --de-shadow-lg: 0 12px 32px rgba(15,21,48,.10);
}
```

**AFTER**
```css
html[data-debrowser-redesign="1"] {
  /* --- Brand accents (FILL-only: buttons, chips, dots, slider bars,
     gradient underlines, borders). Never use --de-cyan as a text color;
     use --de-accent-ink (theme-resolved, see light/dark blocks) instead. --- */
  --de-cyan:    #5EE6D6;
  --de-violet:  #A78BFA;
  --de-blue:    #60A5FA;
  --de-mint:    #3CB6A0;
  --de-pink:    #FF7AA2;
  --de-grad:    linear-gradient(135deg, #5EE6D6 0%, #A78BFA 100%);
  --de-grad-soft: linear-gradient(135deg, rgba(94,230,214,.12), rgba(167,139,250,.12));

  /* Radii */
  --de-r-sm:   6px;
  --de-r-md:   10px;
  --de-r-lg:   14px;
  --de-r-pill: 999px;

  /* Spacing scale (4px base) — consumed by 01-grid-system-plan.md */
  --de-space-1: 4px;
  --de-space-2: 8px;
  --de-space-3: 12px;
  --de-space-4: 16px;
  --de-space-5: 24px;
  --de-space-6: 32px;

  /* Motion — consumed by 05-hover-cursor-plan.md */
  --de-dur:  140ms;
  --de-ease: cubic-bezier(.2,.6,.2,1);

  /* Shadows */
  --de-shadow:    0 6px 24px rgba(0,0,0,.06);
  --de-shadow-lg: 0 12px 32px rgba(15,21,48,.10);
}
```

### 0.2 Light block — `[data-bs-theme="light"], :not([data-bs-theme="dark"])` (currently lines 361–373)

**BEFORE**
```css
  --de-text-1:  #0F1530;
  --de-text-2:  #475270;
  --de-text-3:  #6E7BA5;
  --de-grid:    rgba(15,21,48,.04);
```
**AFTER**
```css
  --de-text-1:  #0F1530;
  --de-text-2:  #475270;
  --de-text-3:  #556087;   /* was #6E7BA5 (4.17:1 FAIL) -> 6.16:1 on white */
  --de-accent-ink: #0E7490; /* cyan-700: accent-as-TEXT. 5.36:1 on white */
  --de-grid:    rgba(15,21,48,.04);
```

### 0.3 Dark block — `[data-bs-theme="dark"]` (currently lines 376–389)

**BEFORE**
```css
  --de-text-1:  #E6ECFF;
  --de-text-2:  #A8B2D1;
  --de-text-3:  #6E7BA5;
  --de-grid:    rgba(255,255,255,.04);
```
**AFTER**
```css
  --de-text-1:  #E6ECFF;
  --de-text-2:  #A8B2D1;
  --de-text-3:  #808CB8;   /* was #6E7BA5 (4.31:1 FAIL) -> 5.44:1 on #0F1530 */
  --de-accent-ink: #5EE6D6; /* accent-as-TEXT in dark = the bright cyan. 11.76:1 */
  --de-grid:    rgba(255,255,255,.04);
```

**Dark `--de-text-3` decision.** Candidates on `--de-bg-1 #0F1530`:

| Candidate | Ratio | Note |
|---|---|---|
| `#6E7BA5` (current) | 4.31:1 | FAIL for small labels |
| **`#808CB8` (chosen)** | **5.44:1** | PASS — minimal bump, stays clearly dimmer than text-2 (8.51:1) so the tertiary tier still reads as tertiary |
| `#8B96BE` | 6.16:1 | PASS but nearly as bright as it can go; erodes the text-2/text-3 hierarchy step |

Chosen `#808CB8`: it is the smallest lightening that clears 4.5:1 with margin while
preserving the visual hierarchy `text-1 (15.22) > text-2 (8.51) > text-3 (5.44)`.

---

## THE ROLE RULE (canonical)

> **`--de-accent-ink`** = the accent **as TEXT / foreground**. Use it for any
> `color:` (or icon glyph `fill:` that reads as content) on a page surface:
> `.de-eyebrow`, inline `code`/`kbd`, active/hover **text** links, the `?` help
> icon, colored **active-tab text/number**, the selectize ✓ glyph.
>
> **`--de-cyan` / `--de-grad`** = the accent **as FILL**. Use for `background`,
> `border-color`, `box-shadow`, `outline`, gradient underlines, slider bars,
> dots, and chips — anything where the accent is a shape, not glyph text.
>
> **Exception — the navbar.** The navbar surface is always `#0B1020` (dark) in
> **both** themes. There, cyan-as-text is **12.41:1** and correct. Navbar glyphs
> (e.g. `.fa-user`) therefore **keep `--de-cyan`** and are NOT migrated — the
> light-mode `--de-accent-ink #0E7490` would be low-contrast on that dark bar.

---

## Phase 1 — Contrast bug fixes  `[Quick win]`

These two tasks fix real WCAG failures shipping today. Smallest possible diffs.

### Task 1 `[Quick win]` — Fix tertiary label contrast (`--de-text-3`)

`--de-text-3` labels the breadcrumb/caption tier (`.de-workbar .de-crumbs` line
1174, `details > summary::after` line 1395, etc.). Today it fails AA in both themes.

**Light block** (line 371):
```css
/* BEFORE */  --de-text-3:  #6E7BA5;
/* AFTER  */  --de-text-3:  #556087;   /* 4.17:1 -> 6.16:1 on white, 5.80:1 on canvas */
```
**Dark block** (line 385):
```css
/* BEFORE */  --de-text-3:  #6E7BA5;
/* AFTER  */  --de-text-3:  #808CB8;   /* 4.31:1 -> 5.44:1 on #0F1530 */
```
No selector edits needed — every `var(--de-text-3)` consumer inherits the fix.

**Commit:** `fix(a11y): raise --de-text-3 to AA (light #556087, dark #808CB8)`

### Task 2 `[Quick win]` — Introduce `--de-accent-ink` and migrate cyan-as-text

**Step 2a — add the token** (part of the light/dark blocks above):
```css
/* Light block, after --de-text-3 (~line 371) */
  --de-accent-ink: #0E7490;   /* cyan-700; 5.36:1 white / 4.87:1 bg-3 */
/* Dark block, after --de-text-3 (~line 385) */
  --de-accent-ink: #5EE6D6;   /* bright cyan; 11.76:1 on bg-1 */
```

**Step 2b — migrate every raw-cyan-as-TEXT usage.** Change `var(--de-cyan)` ->
`var(--de-accent-ink)` at exactly these seven `color:` sites (leave the fallback
form `var(--de-cyan, #5ee6d6)` structure, just swap the token name + fallback):

| # | Line | Selector | Change |
|---|---|---|---|
| 1 | 1141 | `.de-eyebrow` | `color: var(--de-cyan);` -> `color: var(--de-accent-ink);` |
| 2 | 1377 | `code, kbd` | `color: var(--de-cyan);` -> `color: var(--de-accent-ink);` |
| 3 | 1121 | `.fa-question-circle, a[href*="readthedocs"]` | `color: var(--de-cyan) !important;` -> `color: var(--de-accent-ink) !important;` |
| 4 | 1656 | `.de-help-btn .fa-info-circle` | `color: var(--de-cyan, #5ee6d6) !important;` -> `color: var(--de-accent-ink, #0E7490) !important;` |
| 5 | 2565 | `.de-drop-ic` | `color: var(--de-cyan);` -> `color: var(--de-accent-ink);` |
| 6 | 2987 | `.wiz-step.active .wiz-step-num` | `color: var(--de-cyan) !important;` -> `color: var(--de-accent-ink) !important;` |
| 7 | 730 | `.selectize-dropdown .option.selected::after` (✓) | `color: var(--de-cyan, #5ee6d6);` -> `color: var(--de-accent-ink, #0E7490);` |

Concrete example (site #1, lines 1138–1143):
```css
/* BEFORE */
html[data-debrowser-redesign="1"] .de-eyebrow {
  display: inline-flex; align-items: center; gap: 8px;
  font-size: 10.5px; font-weight: 600; letter-spacing: .14em;
  text-transform: uppercase; color: var(--de-cyan);
  margin-bottom: 6px;
}
/* AFTER */
html[data-debrowser-redesign="1"] .de-eyebrow {
  display: inline-flex; align-items: center; gap: 8px;
  font-size: 10.5px; font-weight: 600; letter-spacing: .14em;
  text-transform: uppercase; color: var(--de-accent-ink);
  margin-bottom: 6px;
}
```
Site #7 (the checkmark) also gets a fill upgrade for free: the ✓ glyph on the
14%-cyan selected tint goes from **1.43:1** (cyan) to **5.03:1** (accent-ink) in
light, and stays **8.65:1** in dark.

**DO NOT migrate** (verified fill/navbar — leave as `var(--de-cyan)`):
`.navbar ... .fa-user/.fa-circle-user` (line 1700, 12.41:1 on the dark navbar),
plus every `background/border-color/box-shadow/outline/fill/border-*` cyan site
(lines 490, 575, 624, 626, 659, 661, 723, 813–814, 829, 837, 872, 935, 1047, 1115,
1144, 1335, 1354, 1404, 1660–1661, 1977, 2555, 2756, 2838–2839, 2971, 2975–2976,
3136, 3618, 3744, 4001, 4499).

**Verify after edit** — no `color:` property should reference `--de-cyan` except
inside the navbar rule:
```bash
grep -nE 'color:\s*var\(--de-cyan' inst/extdata/www/debrowser.css
# expected: only line ~1700 (.navbar ... .fa-user) remains
```

**Commit:** `fix(a11y): add --de-accent-ink and migrate cyan-as-text to it`

---

## Phase 2 — Token consolidation & role hygiene

### Task 3 `[System]` — Add spacing + motion tokens (for plans 01 & 05)

Apply the base-block additions from §0.1: `--de-space-1..6`, `--de-dur`,
`--de-ease`. These are **purely additive** (no existing rule changes) and exist so
`01-grid-system-plan.md` and `05-hover-cursor-plan.md` can consume shared values
instead of hard-coding pixels/easings. Insert between the radii and the shadows in
`html[data-debrowser-redesign="1"]` (currently ~line 354).

```css
  /* Spacing scale (4px base) — consumed by 01-grid-system-plan.md */
  --de-space-1: 4px;
  --de-space-2: 8px;
  --de-space-3: 12px;
  --de-space-4: 16px;
  --de-space-5: 24px;
  --de-space-6: 32px;

  /* Motion — consumed by 05-hover-cursor-plan.md */
  --de-dur:  140ms;
  --de-ease: cubic-bezier(.2,.6,.2,1);
```
Scale rationale: 4px base matches the control paddings already in the file
(6/8/12/14/16px) so downstream migration to tokens is lossless. `140ms` +
`cubic-bezier(.2,.6,.2,1)` is a fast, slightly-eased curve suited to hover/focus
micro-interactions (Phase-05 territory).

**Commit:** `feat(tokens): add --de-space-1..6 and --de-dur/--de-ease scale`

### Task 4 `[Consolidation]` — Role-rule comment + fill audit

1. Add the FILL-only comment above `--de-cyan` in the base block (shown in §0.1 AFTER).
2. Re-run the guard grep from Task 2b to confirm the only surviving cyan `color:`
   is the navbar glyph. This is a no-code-change verification task that locks the
   invariant so future edits do not reintroduce cyan-as-text.

Known fill-side items left AS-IS (documented, not fixed here):
- **nav-tabs active underline** `border-bottom-color: var(--de-cyan)` (line 935) is
  **1.53:1** on white — below the 3.0:1 non-text threshold. **Accepted:** the active
  tab is redundantly coded (`color: var(--de-text-1)` **17.94:1** + `font-weight:600`,
  lines 934–936), so the underline is not the sole state cue. A later polish pass may
  switch it to `--de-grad` (the gradient's violet leg lifts perceived edge contrast).
- **plotly modebar hover/active fill** `fill: #5EE6D6` (line 1115) is **1.53:1** on a
  white plot in light mode. **Accepted:** transient hover state on a control that has a
  visible default (grey) glyph; belongs to a plotly-specific pass, out of palette scope.

**Commit:** `docs(css): document FILL-only cyan role rule + fill-contrast exceptions`

---

## Phase 3 — Resolve the two-palette conflict  `[System]`

### Task 5 `[System]` — Keep bslib `primary #0369A1`, document why

`R/de_theme.R:157` sets Bootstrap `primary = "#0369a1"`. The redesign layer paints
`.btn-primary` with `--de-grad` (cyan->violet, line 546). These look like two
different brand blues, but they are **complementary, not conflicting**, and both
must stay:

**Why keep `#0369A1`:** it is the **WCAG-safe, light-mode sibling of the gradient**.
Any Bootstrap surface the redesign CSS does *not* override — a stray link, a
third-party/bootswatch preset, a `.text-primary` utility, a focus ring Bootstrap
draws itself — falls back to `primary`. On white, `#0369A1` reads **5.93:1** (AA
pass for text), whereas the gradient's cyan leg `#5EE6D6` would be **1.53:1** and
the raw `--de-accent-ink #0E7490` is tuned for text, not for Bootstrap's tint/shade
machinery (buttons, alerts, `.bg-primary` all derive from `primary`). So:
`#0369A1` = safe system default; `--de-grad` = the branded, redesign-only skin on
top. Removing `#0369A1` would leave un-skinned surfaces with an inaccessible or
off-brand blue.

The value is **unchanged**; the deliverable is a documenting comment so the next
editor does not "unify" the two and break the fallback.

**BEFORE** (`R/de_theme.R`, lines 153–169):
```r
  bslib::bs_theme(
    version       = 5,
    bg            = "#ffffff",
    fg            = "#0f172a",
    primary       = "#0369a1",
    secondary     = "#64748b",
    ...
  )
```
**AFTER**:
```r
  bslib::bs_theme(
    version       = 5,
    bg            = "#ffffff",
    fg            = "#0f172a",
    # primary is the WCAG-safe (5.93:1 on white) light-mode sibling of the
    # redesign gradient (--de-grad, cyan->violet). It is the FALLBACK for any
    # Bootstrap surface the redesign CSS does not override (bootswatch presets,
    # .text-primary, native focus rings). The branded gradient skin lives only
    # in debrowser.css (.btn-primary { background: var(--de-grad) }). Keep both:
    # do NOT replace this with the gradient's cyan (#5EE6D6 = 1.53:1, fails AA).
    primary       = "#0369a1",
    secondary     = "#64748b",
    ...
  )
```

**Commit:** `docs(de_theme): explain why primary #0369A1 is the gradient's a11y fallback`

---

## §5 — Full contrast table (AFTER all fixes)

All values computed with the WCAG relative-luminance formula. `rgba()` navbar
colors are composited over `#0B1020` first. Threshold: small text 4.5:1, large/UI 3.0:1.

### Light theme (canvas `--de-bg-0 #F7F8FC`, surface `--de-bg-1 #FFFFFF`, `--de-bg-3 #F1F4FB`)

| Foreground | Role | Background | Ratio | AA |
|---|---|---|---|---|
| `--de-text-1 #0F1530` | body text | white | 17.94:1 | PASS |
| `--de-text-1 #0F1530` | body text | canvas | 16.91:1 | PASS |
| `--de-text-2 #475270` | secondary | white | 7.75:1 | PASS |
| `--de-text-2 #475270` | secondary | canvas | 7.30:1 | PASS |
| `--de-text-2 #475270` | secondary | bg-3 | 7.04:1 | PASS |
| `--de-text-3 #556087` **(fixed)** | caption/crumb | white | **6.16:1** | PASS |
| `--de-text-3 #556087` **(fixed)** | caption/crumb | canvas | **5.80:1** | PASS |
| `--de-text-3 #556087` **(fixed)** | caption/crumb | bg-3 | **5.59:1** | PASS |
| `--de-accent-ink #0E7490` **(new)** | eyebrow/link/icon text | white | **5.36:1** | PASS |
| `--de-accent-ink #0E7490` **(new)** | code/kbd/help-icon text | bg-3 | **4.87:1** | PASS |
| `--de-accent-ink #0E7490` **(new)** | wiz-num/eyebrow text | canvas | **5.05:1** | PASS |
| `--de-accent-ink #0E7490` **(new)** | selectize ✓ | selected tint `#E8FCF9` | **5.03:1** | PASS |
| btn-ink `#0B1020` | button label | cyan fill `#5EE6D6` | 12.41:1 | PASS |
| btn-ink `#0B1020` | button label | violet fill `#A78BFA` | 6.96:1 | PASS |
| btn-ink `#0B1020` | danger label | pink fill `#FF7AA2` | 7.72:1 | PASS |
| btn-ink `#0B1020` | badge/step | mint fill `#3CB6A0` | 7.56:1 | PASS |
| cyan `#5EE6D6` | nav-tabs active underline (UI) | white | 1.53:1 | **FAIL — accepted (redundant w/ bold text-1, §Task4)** |
| violet `#A78BFA` | accent border (UI) | white | 2.72:1 | **FAIL — decorative border only, not a state cue** |
| cyan `#5EE6D6` | plotly modebar hover fill | white plot | 1.53:1 | **FAIL — transient hover, out of scope (§Task4)** |

### Dark theme (canvas `--de-bg-0 #0B1020`, surface `--de-bg-1 #0F1530`, `--de-bg-2 #141B3A`, `--de-bg-3 #1A2147`)

| Foreground | Role | Background | Ratio | AA |
|---|---|---|---|---|
| `--de-text-1 #E6ECFF` | body text | bg-1 | 15.22:1 | PASS |
| `--de-text-2 #A8B2D1` | secondary | bg-1 | 8.51:1 | PASS |
| `--de-text-2 #A8B2D1` | secondary | bg-2 | 7.98:1 | PASS |
| `--de-text-3 #808CB8` **(fixed)** | caption/crumb | bg-1 | **5.44:1** | PASS |
| `--de-accent-ink #5EE6D6` **(new)** | eyebrow/code/link text | bg-1 | **11.76:1** | PASS |
| `--de-accent-ink #5EE6D6` **(new)** | help/drop icon text | bg-2 | 11.03:1 | PASS |
| `--de-accent-ink #5EE6D6` **(new)** | code/kbd text | bg-3 | 10.18:1 | PASS |
| `--de-accent-ink #5EE6D6` **(new)** | selectize ✓ | selected tint `#1A3247` | 8.65:1 | PASS |
| btn-ink `#0B1020` | button label | cyan / violet fills | 12.41 / 6.96:1 | PASS |

### Navbar (always `#0B1020`, both themes)

| Foreground | Role | Ratio | AA |
|---|---|---|---|
| `rgba(230,236,255,.72)` -> `#A9AEC1` | nav-link idle | 8.58:1 | PASS |
| `#FFFFFF` | nav-link active | 18.93:1 | PASS |
| `rgba(230,236,255,.85)` -> `#C5CBDE` | account dropdown toggle | 11.69:1 | PASS |
| `rgba(230,236,255,.55)` -> `#83899B` | UMMS Biocore link | 5.42:1 | PASS |
| cyan `#5EE6D6` | `.fa-user` glyph (KEEP cyan) | 12.41:1 | PASS |

**Everything used as text now passes AA in both themes.** The only remaining
sub-threshold ratios are three FILL/decorative cases (nav-tab underline, violet
border, plotly hover), all explicitly accepted with rationale in Task 4.

---

## §6 — Verification

### 6.1 Re-run the contrast checks

Save this as `scripts/contrast_check.py` (or run ad-hoc) and execute
`python3 scripts/contrast_check.py`. It hard-codes the AFTER token values and
prints PASS/FAIL for every pair in §5, including `rgba()` navbar compositing.

```python
def _lin(c):
    c /= 255.0
    return c/12.92 if c <= 0.03928 else ((c+0.055)/1.055)**2.4
def lum(h):
    h = h.lstrip('#'); r,g,b = (int(h[i:i+2],16) for i in (0,2,4))
    return 0.2126*_lin(r)+0.7152*_lin(g)+0.0722*_lin(b)
def ratio(fg,bg):
    a,b = lum(fg),lum(bg); hi,lo = max(a,b),min(a,b)
    return (hi+0.05)/(lo+0.05)
def over(fg,alpha,bg):            # composite rgba() fg over opaque bg
    f,b = fg.lstrip('#'), bg.lstrip('#')
    return '#'+''.join('%02X'%round(alpha*int(f[i:i+2],16)+(1-alpha)*int(b[i:i+2],16))
                       for i in (0,2,4))
def chk(fg,bg,label,t=4.5):
    r = ratio(fg,bg); print(f"{'PASS' if r>=t else 'FAIL'}  {r:5.2f}:1  {label}")

# --- Light (bg0 #F7F8FC / bg1 #FFFFFF / bg3 #F1F4FB) ---
chk("#556087","#FFFFFF","light text-3 on white")            # 6.16
chk("#556087","#F7F8FC","light text-3 on canvas")           # 5.80
chk("#0E7490","#FFFFFF","light accent-ink on white")        # 5.36
chk("#0E7490","#F1F4FB","light accent-ink on bg-3")         # 4.87
# --- Dark (bg1 #0F1530) ---
chk("#808CB8","#0F1530","dark text-3 on bg-1")              # 5.44
chk("#5EE6D6","#0F1530","dark accent-ink on bg-1")          # 11.76
# --- Fills (button ink) ---
chk("#0B1020","#5EE6D6","btn-ink on cyan")                  # 12.41
chk("#0B1020","#A78BFA","btn-ink on violet")                # 6.96
# --- Navbar (composited over #0B1020) ---
chk(over("#E6ECFF",.72,"#0B1020"),"#0B1020","navbar link .72")   # 8.58
chk(over("#E6ECFF",.55,"#0B1020"),"#0B1020","navbar UMMS .55")   # 5.42
```

### 6.2 Browser spot-check (both themes)

Toggle the theme with the navbar sun/moon control and eyeball these exact spots.
Use DevTools' element inspector -> Accessibility pane (Chrome/Edge report the
contrast ratio inline) or the axe DevTools extension on the running Shiny app.

| Where to look | Element | Expect |
|---|---|---|
| Upload / any panel header | `.de-eyebrow` uppercase label | teal in light, cyan in dark — **readable**, not washed out |
| Intro text with `code` names | inline `code`/`kbd` chip | teal-on-`bg3` in light, cyan in dark |
| Any `?`/help affordance | `.fa-question-circle`, `.de-help-btn .fa-info-circle` | visible teal/cyan; help-btn hover flips to cyan fill + dark glyph |
| Wizard rail active step | `.wiz-step.active .wiz-step-num` | number readable in light |
| Dropzone | `.de-drop-ic` glyph | readable in light (was invisible cyan) |
| Selectize open w/ selected items | `.option.selected` ✓ | checkmark readable |
| Breadcrumb / captions | `.de-workbar .de-crumbs`, `summary::after` | text-3 no longer faint (light AND dark) |
| Navbar (both themes) | `.fa-user`, nav links | unchanged — cyan glyph still fine on dark bar |

### 6.3 Guard grep (run after Task 2 and in review)
```bash
# Only the navbar glyph may use cyan as a text color:
grep -nE 'color:\s*var\(--de-cyan' inst/extdata/www/debrowser.css
# No token should be defined twice with different values:
grep -nE '--de-(accent-ink|text-3|space-[1-6]|dur|ease):' inst/extdata/www/debrowser.css
```

---

## Task / commit summary

| Task | Label | Files | Commit subject |
|---|---|---|---|
| 1 | Quick win | debrowser.css:371,385 | `fix(a11y): raise --de-text-3 to AA (light #556087, dark #808CB8)` |
| 2 | Quick win | debrowser.css:371,385 + 7 selectors | `fix(a11y): add --de-accent-ink and migrate cyan-as-text to it` |
| 3 | System | debrowser.css:~354 | `feat(tokens): add --de-space-1..6 and --de-dur/--de-ease scale` |
| 4 | Consolidation | debrowser.css:~343 | `docs(css): document FILL-only cyan role rule + fill-contrast exceptions` |
| 5 | System | R/de_theme.R:157 | `docs(de_theme): explain why primary #0369A1 is the gradient's a11y fallback` |
