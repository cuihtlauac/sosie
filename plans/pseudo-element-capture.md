# Plan: capture pseudo-elements beyond `::before`/`::after`

Backlog item #1. Goal: recover the ~25 sensitivity false negatives that
style UA shadow pseudo-elements (`::permission-icon`,
`::slider-{track,fill,thumb}`, `::placeholder`, `::file-selector-button`),
which the current extractor cannot see — it walks DOM elements plus only
`::before`/`::after`.

## Empirical findings (Chrome 151, headless, 2026-08-18)

Probe: `getComputedStyle(el, "::pseudo")` for 19 pseudo selectors ×
9 element types (range/file/text/textarea/div/progress/meter/details/li),
reading `display`, `width`, `height`, `background-color`, `appearance`,
`content`, `-webkit-appearance`, and the declaration `length`.

1. **`getComputedStyle` existence detection is unreliable.** Chrome
   returns a full 475-property declaration (`len=475`) for almost every
   (element × pseudo) pair, including pseudos that plainly do not apply
   (`div::placeholder`, `range::file-selector-button`,
   `li::-webkit-meter-bar`). So `len` does not discriminate real boxes
   from phantom resolutions.
   - `appearance:auto` distinguishes real from phantom on
     `<input type=file>` (`::file-selector-button` = auto vs slider
     pseudos = none) but NOT on `<input type=text>`, where every phantom
     webkit pseudo reports `appearance:auto` and inherits the input's own
     box (`width=150px height=15px`). No single discriminator works
     across pseudos.

2. **Modern `::slider-track` / `::slider-fill` / `::slider-thumb` are
   unsupported in Chrome 151** — `len=0`, all values empty, on every
   element. Chrome only exposes the legacy
   `::-webkit-slider-runnable-track` and `::-webkit-slider-thumb`.

3. **Confirmed-real pseudos and their tells (originating element →
   pseudo → real resolved values):**
   - `input[type=text]`/`textarea` → `::placeholder`:
     display=block, width/height = a real px box (phantom on div =
     display:inline, width=auto).
   - `input[type=file]` → `::file-selector-button`:
     display=inline-block, appearance=auto, bg=rgb(239,239,239),
     definite px width.
   - `input[type=range]` → `::-webkit-slider-runnable-track`,
     `::-webkit-slider-thumb`: display=inline-block, appearance=auto.
   - `progress` → `::-webkit-progress-bar`, `::-webkit-progress-value`;
     `meter` → `::-webkit-meter-bar`, `::-webkit-meter-inner-element`;
     `li` → `::marker` (display=inline-block, width=7px real vs auto);
     `details` → `::details-content` (display=block).

## Design decision: over-capture, element-type-gated (trust-safe)

Do NOT try to detect pseudo existence. sosie compares before-vs-after on
the SAME element; a phantom pseudo resolves IDENTICALLY on both sides (a
deterministic function of the element's own inherited style), so it adds
no NEW false-positive class. Over-capturing therefore risks only
tolerable false positives, never a fatal false negative — exactly the
trust asymmetry sosie is built on.

Approach: a fixed table `element predicate -> [applicable UA pseudo
selectors]`, captured UNCONDITIONALLY (no `content` gate — these are
structural, `content` is normal/none). Gating by element type exists only
to stop tree bloat (do not attach 15 phantom pseudos to every DOM node),
not for correctness. `::before`/`::after` stay content-gated as today,
applied to all elements.

Proposed table (Chrome-accurate names):
- text-like `<input>` (not in {checkbox,radio,range,file,color,...}) and
  `<textarea>` → `::placeholder`
- `<input type=file>` → `::file-selector-button`
- `<input type=range>` → `::-webkit-slider-runnable-track`,
  `::-webkit-slider-thumb`
- `<progress>` → `::-webkit-progress-bar`, `::-webkit-progress-value`
- `<meter>` → `::-webkit-meter-bar`, `::-webkit-meter-inner-element`
- `<permission>` → `::permission-icon` (needs flag to validate)

`::marker` and `::details-content` are structural/geometry, out of the
sensitivity-recovery scope; defer unless cheap.

## OPEN RISK (same shape as the refuted SVG-paint hypothesis)

Whether capturing `::permission-icon` actually recovers the 9
`permission-element icon-css-property-*` tests is UNVERIFIED. Those tests
mutate `fill`/`stroke`/`stroke-width`/`height` on the icon. Recovery
requires that `getComputedStyle(permissionEl, "::permission-icon")`
reflects the CSS-set value — needs a real `<permission>` element (behind
a flag) to confirm. If it does not, this is another refuted branch:
record it, keep the (trust-positive) capture anyway, do not fake a win.

## Implementation surface (both extractors + round-trip)

- `js/sosie-capture.js`: element-type→pseudo table; unconditional capture.
- `js_extractor/extractor.ml`: same table via JSOO DOM bindings.
- Schema needs NO type change: pseudo-elements are already `node`s with
  `tag = selector` (`snapshot_types.mli`).
- Round-trip `C ∘ G`: `snapshot_gen.ml` (generate source that reproduces
  the pseudo), native parse/serialize in `snapshot.ml`, `mutate.ml`
  Reset_to_default if it enumerates pseudo tags. Verify what currently
  special-cases `::before`/`::after`.
- Tests: unit (table gating, per element type), round-trip, then corpus
  re-measurement of sensitivity (monotonic recapture).
