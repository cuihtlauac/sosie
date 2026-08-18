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

## `::permission-icon` risk — RESOLVED, recovery viable (2026-08-18)

The prior SVG-paint refutation concluded these tests were unreachable.
That is now overturned for `fill`/`stroke`/`stroke-width`:

- The element is `<geolocation>` (a PEPC permission-element subtype), NOT
  `<permission>`. The 80 corpus occurrences all use `<geolocation>`; the
  rule is a bare `::permission-icon { fill: red }`. My first probe used
  `<permission type=camera>`, which does not render on `file://` (0x0
  box), giving the false "refuted" reading.
- `<geolocation>` RENDERS with no flag (147x38px box in headless Chrome
  151) and `getComputedStyle(el, "::permission-icon")` DOES cascade the
  author value: test icon `fill = rgb(255,0,0)` vs ref `rgb(0,0,255)`
  (currentColor from `color:blue`). The values differ, so capturing the
  icon makes sosie detect the mismatch.
- Verified end-to-end through the COMPILED JSOO extractor: it emits a
  `::permission-icon` node carrying `fill: rgb(255,0,0)` on the real test
  HTML. Table updated to gate on GEOLOCATION/CAMERA/MICROPHONE/PERMISSION.

Recoverable: `icon-css-property-{fill,stroke,stroke-width}` (whitelisted).
NOT recoverable: `icon-css-property-{height,min-height,margin-inline-end}`
(`height` deliberately unwhitelisted; pseudo geometry not exposed by
standard APIs — bounds are the parent's rect). `icon-hidden`,
`icon-restricted-css-no-effect`, `icon-different-for-precise-location`
depend on non-whitelisted mechanisms; authoritative counts come from the
corpus sensitivity re-measurement.

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

## Results (2026-08-18)

Implemented in both extractors; integration test
`capture_includes_ua_shadow_pseudo_elements` added; round-trip and
mutation integration suites still green.

Corpus re-measurement. Adding pseudo nodes is monotonic (can only add
diffs) AND a no-op for any test whose test and refs contain no gated
control (identical captures -> identical verdict). So the recapture set
was `(pass ∪ sensitivity-FN) ∩ (test-or-ref has a gated control)` = 356
of 3,487, computed with a permissive (over-approximating, hence safe)
reftest-link parser. Recaptured those 356; the other 3,131 are provably
unchanged.

- **5 sensitivity false-negatives recovered:**
  `css/css-pseudo/file-selector-button-001` (::file-selector-button),
  `css/css-pseudo/placeholder-input-number` (::placeholder), and the
  geolocation `icon-css-property-{fill,stroke,stroke-width}` reftests
  (::permission-icon — the branch the SVG-paint effort thought refuted).
- **1 tolerable false positive:**
  `html/rendering/.../number-placeholder-right-aligned` — the
  ::placeholder box's overflow/display differ between interchangeable
  test/ref markup. Bulk-xfailed by type.
- Sensitivity 316/381 (82.9%) -> **321/381 (84.3%)**; residual FN 65->60
  (60 remaining need pseudo geometry / non-whitelisted props like the
  icon height/min-height tests — unreachable by design).
- Suite: 3,422->3,426 pass, 19,829->19,825 xfail, 0 fail, 0 errors;
  coverage gate 23,251/23,251 (no tests added).
