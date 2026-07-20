# 05 — Hover / Cursor / Motion Polish

**Scope:** DEBrowser R‑Shiny redesign theme. All CSS lives in
`inst/extdata/www/debrowser.css` (~4903 lines). Every redesign rule is gated on
`html[data-debrowser-redesign="1"]`; the plain legacy theme is untouched except
where a rule is intentionally global (the `prefers-reduced-motion` reset, T2).

**Depends on Phase 0** (`02-color-palette-plan.md`), which defines the tokens
used throughout: `--de-dur: 140ms`, `--de-ease: cubic-bezier(.2,.6,.2,1)`,
`--de-accent-ink`, `--de-shadow`, `--de-shadow-lg`, `--de-cyan`, `--de-grad`,
`--de-bg-2` / `--de-bg-3`, `--de-r-*`. This phase adds one new token,
`--de-transition` (T4), alongside them.

> **Line refs** are against the current HEAD of `debrowser.css`. They shift as
> tasks land — always re-anchor by the quoted selector, not the number. Tasks
> are ordered so the three accessibility/perf quick wins go first and touch the
> fewest lines.

---

## Current state (verified)

Only **eight** live `transition:` declarations exist in the redesign scope, with
mixed durations and easings. Most hover targets have **no** transition at all,
so their color/background changes snap instantly.

| Line | Selector | Current declaration | Problem |
|------|----------|---------------------|---------|
| 89   | `.de-dropzone .card` | `border-color 0.15s ease, background-color 0.15s ease` | off-token duration/easing |
| 538  | `.btn` | `all .12s ease` | **`all` perf trap**; off-token |
| 616  | `.form-control` | `border-color .12s ease, outline-color .12s ease` | off-token |
| 1089 | `.js-plotly-plot .plotly .modebar` | `opacity .12s ease-in-out` | off-token (leave; Plotly-owned) |
| 1459 | `.de-nav-chip-num` | `all .12s ease` | **`all` perf trap**; off-token |
| 2551 | `.de-drop` | `border-color .15s ease, background .15s ease` | off-token |
| 2734 | `.wiz-step-dot` | `all .15s ease` | **`all`**; **competes with 3110** |
| 3110 | `.wiz-step-dot` | `background .15s ease, box-shadow .2s ease, opacity .15s ease` | **duplicate base; wins over 2734** |

Other verified facts that shape the plan:

- **No** hover state uses `transform`/`scale`/`translate` — there is zero "lift"
  anywhere. Box‑shadow depth exists only on base/active/focus states (e.g.
  `.btn-primary` base shadow :549; focus halos `0 0 0 3px` at :487, :2745, :2757,
  :3117, :3138, :3615, :3741) — **never on hover**.
- **`focus-visible` exists on only two elements**: `.btn` (:573–578) and
  `.de-help-btn` (:1627, :1659). Nav‑links, `.wiz-step`, `.de-side-list-item`,
  table rows, `.de-drop`/dropzone, and the modebar have **no focus style at
  all** → keyboard focus is invisible there.
- **`cursor:`** is used only for `pointer` and a single `not-allowed` (:2368, on
  disabled DT pagination). Locked wizard steps rely on
  `pointer-events:none` + `opacity` (:2761–2763, :3024, :3634–3636) with **no**
  `not-allowed` cursor. No custom/decorative cursors, no `grab` anywhere.
- **`@keyframes de-pulse`** (:2992–3001) is declared on the active dot at
  :2979 (`animation: de-pulse 1.8s ease-in-out infinite`), but a **later rule at
  :3068 neutralizes it** with `animation: none !important`. So it does not
  currently run — yet the declaration and keyframes remain in the file as a
  latent motion source. **No `prefers-reduced-motion` block exists anywhere.**

---

## Task list

| # | Label | Task | Touches |
|---|-------|------|---------|
| T1 | **[Quick win]** | Global `:focus-visible` outline for the un-styled interactive elements | new block |
| T2 | **[Quick win]** | `prefers-reduced-motion` reset + retire the latent `de-pulse` | new block; :2979, :2992 |
| T3 | **[Quick win]** | Replace the two `transition: all` with explicit property lists | :538, :1459 |
| T4 | **[Consolidation]** | Add the `--de-transition` token; apply one transition to all interactive bases; collapse the duplicate `.wiz-step-dot` transitions | token block; :538, :1459, :2734, :3110, + bases |
| T5 | **[System]** | Subtle 1px hover **lift** on CTAs + upload/demo cards | :551, new blocks |
| T6 | **[System]** | Gradient underline **wipe** on the navbar tabs | :437, :1255 |
| T7 | **[System]** | Restrained **slide** on dropdown + selectize options | :673, :1032 |
| T8 | **[Quick win]** | `cursor: not-allowed` on disabled buttons + locked steps; cursor policy | :2761/:3634, new block |

> **Quick wins** = T1, T2, T3, T8. They are pure accessibility/perf, isolated,
> and safe to ship on their own. **Consolidation** (T4) is a mechanical refactor
> that everything after it leans on. **System** tasks (T5–T7) are the visible
> polish and should land after T4 so they inherit `--de-transition`.

---

## T1 — Global `:focus-visible` outline  **[Quick win]**

**Why:** Keyboard users currently get no visible focus on nav‑links, wizard
steps, side‑list rows, table rows, dropzones, or the modebar. This is a WCAG
2.4.7 gap. One rule fixes all of them with the Phase‑0 accent ink. `.btn`
(:573–578) and `.de-help-btn` (:1627/:1659) already have bespoke treatments —
leave those; this rule covers only the elements that have none.

**After** (new block, place near the other focus rules ~:578):

```css
/* Keyboard focus for interactive elements that lacked any focus style.
   :focus-visible so mouse clicks don't paint a ring. */
html[data-debrowser-redesign="1"] .navbar .nav-link:focus-visible,
html[data-debrowser-redesign="1"] .nav-tabs .nav-link:focus-visible,
html[data-debrowser-redesign="1"] .wiz-step:focus-visible,
html[data-debrowser-redesign="1"] .de-side-list-item:focus-visible,
html[data-debrowser-redesign="1"] table.dataTable tbody tr:focus-visible,
html[data-debrowser-redesign="1"] .table tbody tr:focus-visible,
html[data-debrowser-redesign="1"] .de-drop:focus-visible,
html[data-debrowser-redesign="1"] .de-dropzone .card:focus-visible,
html[data-debrowser-redesign="1"] .modebar-btn:focus-visible,
html[data-debrowser-redesign="1"] .dropdown-item:focus-visible,
html[data-debrowser-redesign="1"] .selectize-dropdown .option:focus-visible {
  outline: 2px solid var(--de-accent-ink);
  outline-offset: 2px;
}
```

**Notes**
- Table rows are only reachable by keyboard if DT/JS gives them `tabindex`; the
  rule is harmless when they aren't, and correct the moment they are — keep it as
  forward-looking coverage.
- `outline` (not `box-shadow`) is deliberate: it never triggers layout, is not
  clipped by `overflow:hidden` ancestors, and respects Windows High Contrast.

**Commit:** `feat(a11y): global :focus-visible outline for nav, wizard, side-list, table, dropzone, modebar`

---

## T2 — `prefers-reduced-motion` + retire `de-pulse`  **[Quick win]**

**Why:** There is no reduced-motion handling at all, and the file still carries
the infinite `de-pulse` glow declaration (:2979) even though it is currently
overridden at :3068. A global reset honors the OS setting for the whole app;
retiring the latent keyframe removes the only *continuous* animation so it can't
resurface if the :3068 override is ever refactored away.

**After — part A** (global reset; place once, near the top of the file so it can
win by source order, or at the very end — either works with `!important`):

```css
/* Respect users who ask for less motion. Global on purpose: accessibility is
   not gated on the redesign theme. Near-zero (not 0) so transitionend/
   animationend handlers still fire. */
@media (prefers-reduced-motion: reduce) {
  * {
    transition-duration: .01ms !important;
    animation-duration: .01ms !important;
    animation-iteration-count: 1 !important;
    scroll-behavior: auto !important;
  }
}
```

**After — part B** (retire the latent pulse). Two edits:

At **:2979**, drop the animation from the active dot (the `box-shadow` on the
same rule already provides a static glow):

```css
/* Before (:2974–2980) */
html[data-debrowser-redesign="1"] .wiz-step.active .wiz-step-dot {
  background: var(--de-cyan) !important;
  border-color: var(--de-cyan) !important;
  box-shadow: 0 0 0 5px rgba(94,230,214,.28),
              0 0 14px rgba(94,230,214,.40) !important;
  animation: de-pulse 1.8s ease-in-out infinite;   /* ← remove this line */
}

/* After */
html[data-debrowser-redesign="1"] .wiz-step.active .wiz-step-dot {
  background: var(--de-cyan) !important;
  border-color: var(--de-cyan) !important;
  box-shadow: 0 0 0 5px rgba(94,230,214,.28),
              0 0 14px rgba(94,230,214,.40) !important;
}
```

Then delete the now-unused `@keyframes de-pulse { … }` (:2992–3001) and the dead
`animation: none !important;` override at :3068 (it exists only to cancel the
line you just removed). Net effect: one fewer keyframe, one fewer override, no
visual change in the default theme.

**Notes**
- Part A alone would tame `de-pulse` (iteration-count → 1) for reduced-motion
  users, but Part B removes it for everyone, which is the cleaner end state given
  it was already disabled in the cascade.
- The reset caps *durations*, not *properties*, so hover color/background still
  changes — it just changes instantly. That is the intended reduced-motion
  behavior (no easing, not "no feedback").

**Commit:** `feat(a11y): honor prefers-reduced-motion; retire latent de-pulse keyframe`

---

## T3 — Replace `transition: all` with explicit lists  **[Quick win]**

**Why:** `transition: all` (:538, :1459) is a performance trap: it observes
*every* animatable property, including layout ones (`width`, `height`, `margin`,
`top`/`left`), so any unrelated style change forces the browser to schedule a
reflow, and it silently starts animating future properties you never intended.
Naming the properties fixes both. Uses the Phase‑0 duration/easing tokens so it
needs nothing from T4.

**`.btn` base — :538**

```css
/* Before (:538) */
  transition: all .12s ease;

/* After */
  transition: color var(--de-dur) var(--de-ease),
              background-color var(--de-dur) var(--de-ease),
              border-color var(--de-dur) var(--de-ease),
              transform var(--de-dur) var(--de-ease),
              box-shadow var(--de-dur) var(--de-ease);
```

**`.de-nav-chip-num` — :1459**

```css
/* Before (:1459) */
  transition: all .12s ease;

/* After — the chip only ever changes color/background/shadow */
  transition: color var(--de-dur) var(--de-ease),
              background-color var(--de-dur) var(--de-ease),
              box-shadow var(--de-dur) var(--de-ease);
```

> T4 folds these two into `transition: var(--de-transition)`. Doing the explicit
> list first means the perf trap is gone even if T4 slips.

**Commit:** `perf(css): replace transition:all with explicit property lists (:538,:1459)`

---

## T4 — One reusable transition on interactive bases  **[Consolidation]**

**Why:** Nine hand-written transitions with three durations (.12s/.15s/.2s) and
two easings (`ease`, `ease-in-out`) make motion feel inconsistent, and half the
interactive surfaces have none. Define the timing **once** as a token and point
every interactive base at it. This also resolves the duplicate `.wiz-step-dot`
transitions (:2734 vs :3110).

**Step 1 — add the token** to the Phase‑0 token block (wherever `--de-dur` /
`--de-ease` are declared):

```css
:root {
  /* … existing Phase-0 tokens … */
  --de-transition:
    color            var(--de-dur) var(--de-ease),
    background-color var(--de-dur) var(--de-ease),
    border-color     var(--de-dur) var(--de-ease),
    transform        var(--de-dur) var(--de-ease),
    box-shadow       var(--de-dur) var(--de-ease);
}
```

**Step 2 — apply it to the interactive bases** (new grouped block). This gives
every hover/focus target a smooth, uniform ramp and the `transform`/`box-shadow`
channels that T5–T7 animate:

```css
html[data-debrowser-redesign="1"] .btn,
html[data-debrowser-redesign="1"] .card,
html[data-debrowser-redesign="1"] .bslib-card,
html[data-debrowser-redesign="1"] .de-dropzone .card,
html[data-debrowser-redesign="1"] .navbar .nav-link,
html[data-debrowser-redesign="1"] .nav-tabs .nav-link,
html[data-debrowser-redesign="1"] .wiz-step,
html[data-debrowser-redesign="1"] .de-side-list-item,
html[data-debrowser-redesign="1"] table.dataTable tbody tr,
html[data-debrowser-redesign="1"] .table tbody tr,
html[data-debrowser-redesign="1"] .dropdown-item,
html[data-debrowser-redesign="1"] .selectize-dropdown .option {
  transition: var(--de-transition);
}
```

**Step 3 — re-point the two T3 lines** at the token (removes the duplication T3
left behind):

```css
/* .btn  :538  → */   transition: var(--de-transition);
/* .de-nav-chip-num :1459 → */
   transition: color var(--de-dur) var(--de-ease),
               background-color var(--de-dur) var(--de-ease),
               box-shadow var(--de-dur) var(--de-ease);
```

(The chip keeps its narrower list because it must not pick up `transform`.)

**Step 4 — collapse the competing `.wiz-step-dot` transitions.** Both :2734 and
:3110 target the same selector at the same specificity, so :3110 already wins and
:2734 is dead. Remove :2734's line and normalize :3110 onto the tokens:

```css
/* Before — :2734 (.wiz-step-dot base #1) */
  transition: all .15s ease;              /* ← delete this line */

/* Before — :3110 (.wiz-step-dot base #2, currently the winner) */
  transition: background .15s ease, box-shadow .2s ease, opacity .15s ease;

/* After — :3110 only; the dot animates color/shadow/opacity, never transform */
  transition: background-color var(--de-dur) var(--de-ease),
              box-shadow var(--de-dur) var(--de-ease),
              opacity var(--de-dur) var(--de-ease);
```

**Notes**
- Leave `.form-control` (:616), `.de-drop` (:2551), and the Plotly modebar
  (:1089) as they are for this phase — they already list explicit properties and
  the modebar timing is Plotly-adjacent. They can migrate to `--de-transition` in
  a later sweep; not worth the churn now.
- Optional: normalize :616 and :2551 durations to `var(--de-dur)/var(--de-ease)`
  in the same commit for consistency if reviewing time allows.

**Commit:** `refactor(css): add --de-transition token; unify interactive-base + wiz-step-dot transitions`

---

## T5 — 1px hover lift on CTAs + upload/demo cards  **[System]**

**Why:** Nothing lifts on hover today, so primary actions feel flat. A 1px
`translateY` plus a deeper shadow is the lightest possible "this is clickable"
cue. `translateY` runs on the compositor (no reflow), and `:active` snaps it back
to 0 for a tactile press. Requires T4 (the `transform`/`box-shadow` channels).

**Scope, deliberately restrained:** apply the lift to **CTA buttons and the small
upload/demo cards only** — *not* every `.card`. The large plot/table panels are
cards too, and lifting a full data panel on mouse-over reads as noise. This keeps
the effect where "click me" is the point.

**CTA buttons** — replace the existing hover rule at :551–555 (keep its
brightness, add lift + shadow) and add an `:active` reset:

```css
/* Before (:551–555) */
html[data-debrowser-redesign="1"] .btn-primary:hover,
html[data-debrowser-redesign="1"] .btn-success:hover {
  filter: brightness(1.05);
  color: #0B1020 !important;
}

/* After */
html[data-debrowser-redesign="1"] .btn-primary:hover,
html[data-debrowser-redesign="1"] .btn-success:hover {
  filter: brightness(1.05);
  color: #0B1020 !important;
  transform: translateY(-1px);
  box-shadow: 0 6px 18px rgba(94,230,214,.24);   /* deeper than base :549 */
}
html[data-debrowser-redesign="1"] .btn-primary:active,
html[data-debrowser-redesign="1"] .btn-success:active {
  transform: translateY(0);
}
```

**Upload / demo cards** — new block (these cards are genuinely clickable drop /
launch targets):

```css
html[data-debrowser-redesign="1"] .de-dropzone .card:hover {
  transform: translateY(-1px);
  box-shadow: var(--de-shadow-lg) !important;   /* base is var(--de-shadow) :506 */
}
html[data-debrowser-redesign="1"] .de-dropzone .card:active {
  transform: translateY(0);
}
```

**Notes**
- If you later want the lift on the demo/settings launch rows, add
  `.de-side-list-item:hover { transform: translateY(-1px); }` — it already has
  `var(--de-transition)` from T4. Left out here to keep the first pass minimal.
- Do **not** put `transform` on `.card` globally: it would lift plot and table
  panels and can also create a new stacking context that reorders overlapping
  tooltips/modebars.

**Commit:** `feat(motion): 1px hover lift on CTAs + upload/demo cards`

---

## T6 — Gradient underline wipe on navbar tabs  **[System]**

**Why:** The active tab already draws a gradient underline via `::after`, but it
only appears on `.active` and pops in with no motion. Reusing that same
pseudo-element as a `scaleX` wipe gives hovered tabs a directional "growing
underline" and makes tab changes feel animated — for free, on the compositor.

There are **two** copies of the active underline: an earlier one at :437–440
(`left/right:10px; bottom:-4px`) and a later, winning one at :1255–1263
(`left/right:14px; bottom:0`). Consolidate to a single base‑level pseudo that
wipes on hover and locks open on active. **Delete the :437–440 block** (it is a
superseded duplicate) and replace the :1255 block:

```css
/* Before (:1255–1263) — active only, no motion */
html[data-debrowser-redesign="1"] .navbar .nav-link.active::after,
html[data-debrowser-redesign="1"] .navbar .nav-link[aria-selected="true"]::after {
  content: "";
  position: absolute;
  left: 14px; right: 14px; bottom: 0;
  height: 2px;
  background: var(--de-grad);
  border-radius: 2px;
}

/* After — underline lives on the base, collapsed; wipes in from the left */
html[data-debrowser-redesign="1"] .navbar .nav-link::after {
  content: "";
  position: absolute;
  left: 14px; right: 14px; bottom: 0;
  height: 2px;
  border-radius: 2px;
  background: var(--de-grad);
  transform: scaleX(0);
  transform-origin: left;
  transition: transform var(--de-dur) var(--de-ease);
}
html[data-debrowser-redesign="1"] .navbar .nav-link:hover::after,
html[data-debrowser-redesign="1"] .navbar .nav-link.active::after,
html[data-debrowser-redesign="1"] .navbar .nav-link[aria-selected="true"]::after {
  transform: scaleX(1);
}
```

**Notes**
- The base `.nav-link` is already `position: relative` (:429), so the absolutely
  positioned `::after` anchors correctly.
- `scaleX` on a 2px bar is a pure compositor animation — no paint of the tab box.
- The reduced-motion reset (T2) collapses the wipe to an instant show, which is
  the correct fallback (underline still present, just no sweep).
- `.nav-tabs .nav-link.active` (:932) uses `border-bottom-color` rather than an
  `::after`, so it is intentionally **out of scope** here — this task is the
  navbar underline only, matching the two `::after` sources.

**Commit:** `feat(motion): gradient underline wipe on navbar tabs`

---

## T7 — Restrained slide on dropdown + selectize options  **[System]**

**Why:** The third, quietest treatment. Menu and multi-select options currently
just swap background on hover. A 2px `translateX` gives the hovered row a subtle
"steps forward" feel that reinforces which item is under the cursor — the kind of
micro-motion that reads as polish without demanding attention. `transform` (not
`padding-left`) keeps it on the compositor per the perf rules below. Both
selectors already carry `var(--de-transition)` from T4.

**Dropdown items** — extend the hover rule at :1032–1036:

```css
/* Before (:1032–1036) */
html[data-debrowser-redesign="1"] .dropdown-item:hover,
html[data-debrowser-redesign="1"] .dropdown-item:focus {
  background: var(--de-bg-3);
  color: var(--de-text-1);
}

/* After */
html[data-debrowser-redesign="1"] .dropdown-item:hover,
html[data-debrowser-redesign="1"] .dropdown-item:focus {
  background: var(--de-bg-3);
  color: var(--de-text-1);
  transform: translateX(2px);
}
```

**Selectize options** — extend the hover rule at :673–677:

```css
/* Before (:673–677) */
html[data-debrowser-redesign="1"] .selectize-dropdown .option.active,
html[data-debrowser-redesign="1"] .selectize-dropdown .option:hover {
  background: var(--de-bg-3) !important;
  color: var(--de-text-1) !important;
}

/* After — nudge only the hovered row, not the keyboard-active one */
html[data-debrowser-redesign="1"] .selectize-dropdown .option:hover {
  transform: translateX(2px);
}
```

**Notes**
- Keep the nudge to `:hover` only. The `.option.active` (keyboard highlight)
  should stay put so arrow-key navigation doesn't jitter the list.
- 2px is deliberate — enough to perceive, small enough not to reveal a gap at the
  row's left edge. Do not exceed the option's left padding (10px, :671).

**Commit:** `feat(motion): subtle translateX slide on dropdown + selectize options`

---

## T8 — Cursor semantics  **[Quick win]**

**Why:** Disabled buttons and locked wizard steps give no cursor signal that they
can't be used. `cursor: not-allowed` is the standard affordance. (DT pagination
already does this at :2368.)

**Disabled buttons** — new block:

```css
html[data-debrowser-redesign="1"] .btn:disabled,
html[data-debrowser-redesign="1"] .btn.disabled,
html[data-debrowser-redesign="1"] .btn[disabled] {
  cursor: not-allowed;
}
```

**Locked wizard steps** — the important nuance:
`.wiz-step.de-pill-locked` sets `pointer-events: none !important` (:2762, :3024,
:3636). With `pointer-events: none`, the element receives **no** pointer events,
so a `cursor: not-allowed` on it would *never* show — the cursor falls through to
whatever is behind. To actually surface the `not-allowed` affordance, put the
cursor on the **container** so it shows in the locked row's hit area while the
step itself still ignores clicks:

```css
/* Container shows not-allowed; the step keeps pointer-events:none so it
   can't be activated. The row visually reads as locked. */
html[data-debrowser-redesign="1"] .wizard-step-list:has(> .wiz-step.de-pill-locked) {
  /* scoped so only lists that contain a locked step pay for :has() */
}
html[data-debrowser-redesign="1"] .wiz-step.de-pill-locked {
  cursor: not-allowed;   /* takes effect only if pointer-events is restored */
}
```

**Recommended:** the cleanest fix is to stop suppressing pointer events on locked
steps and instead block activation in the click handler (or via
`aria-disabled="true"`), then the `cursor: not-allowed` on
`.wiz-step.de-pill-locked` works directly and the step is announced as disabled
to assistive tech. That is a small JS/handler change beyond this CSS file — flag
it for the wizard step owner. If we keep `pointer-events:none`, apply
`cursor: not-allowed` to the wrapping list item / row container instead, since
the step itself will never report a cursor.

**Plot drag / `grab`:** searched — there is **no** app-owned draggable surface in
the CSS (`grep grab` → none) and Plotly renders its own contextual cursors on its
drag layer (crosshair for zoom, `ew-/ns-resize` on axes, `move` on pan). We do
**not** add `cursor: grab` anywhere: doing so would fight Plotly's own cursors and
mislead. Add `cursor: grab` / `grabbing` **only if** a custom draggable is ever
introduced (e.g. a resizable panel splitter or a hand-rolled region selector),
and scope it to that element.

**Against decorative custom cursors:** do **not** ship a custom/branded cursor
image for this tool.
1. DEBrowser is a precision data app — users hover dense DT tables cell-by-cell
   and read tiny monospace values; a fat decorative cursor obscures exactly the
   pixels they're targeting and slows hit accuracy.
2. Plotly already swaps the cursor contextually inside plots (crosshair,
   resize, pan). A global custom cursor either overrides those useful signals or
   flickers as the pointer crosses plot boundaries.
3. Custom cursors add a rendering cost and an accessibility/consistency hazard
   for no analytical benefit. Native semantic cursors (`pointer`, `text`,
   `not-allowed`, `grab`) communicate everything this UI needs.

**Commit:** `fix(a11y): cursor:not-allowed on disabled buttons + locked wizard steps`

---

## Performance guardrails (applies to T4–T7)

- **Animate only `transform` and `opacity`.** They are handled by the compositor
  and skip layout + paint, so they hold 60fps even on large panels. Every motion
  in this plan is a `translate`/`scaleX` or an outline/color change — no layout
  property is animated.
- **`transition: all` is a trap** (why T3 exists): it watches every animatable
  property, so any style mutation — including layout ones — can trigger a reflow,
  and it will animate future properties you never meant to. Always name the
  properties.
- **Never transition `width` / `height` / `top` / `left` / `margin` / `padding`.**
  These are layout properties; animating them forces a reflow **every frame**.
  This is exactly why T7 uses `transform: translateX(2px)` instead of
  `padding-left`, and T5/T6 use `translate`/`scaleX` instead of moving box edges.
- **`box-shadow` transitions paint** (not composited), but at the sizes and
  counts here (a handful of buttons/cards on hover) the cost is negligible. If a
  shadow ever needs to animate on many elements at once, cross-fade a
  pseudo-element's `opacity` instead — not needed in this phase.
- **`will-change`:** skip it. It is only worth adding to an element that animates
  *continuously*; on discrete hover transitions it wastes memory by keeping
  layers alive. (We removed the one continuous animation in T2.)

---

## Suggested landing order & verification

1. **T1, T2, T3, T8** (quick wins) — ship together or individually; each is
   self-contained and reversible.
2. **T4** (consolidation) — mechanical; verify no visual regression by toggling
   through nav tabs, wizard steps, buttons, and a DT table.
3. **T5, T6, T7** (system polish) — land after T4 so they inherit
   `--de-transition`.

**Manual verification checklist**
- Tab through the navbar, sidebar wizard, demo/settings list, a dropdown, and a
  selectize input — every stop shows the 2px accent-ink ring (T1).
- Enable the OS "Reduce motion" setting → hovers change color instantly, the tab
  underline appears without sweeping, no pulsing dot (T2).
- Hover a primary/success button and an upload card → 1px lift + deeper shadow;
  mouse-down snaps flat (T5).
- Hover navbar tabs → underline wipes in from the left; active tab stays
  underlined (T6).
- Open a dropdown / selectize menu → hovered option slides 2px right; arrow-key
  navigation does not jitter (T7).
- Hover a disabled button and a locked wizard step → `not-allowed` cursor
  (T8; locked step requires the pointer-events note to be addressed).
- DevTools Performance: hover interactions show compositor-only work, no
  layout/reflow entries.
