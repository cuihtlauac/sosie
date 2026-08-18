# WPT reftest triage — 2026-03-24

## Summary

12,909 WPT reftests discovered. After five targeted fixes (see roadmap
Step 10b addendum), 2,623 pass (20.3%). The remaining 10,286 xfails are
classified by root cause in `expectations.json`.

**2026-08-17 update (ingestion campaign session A):** discovery now
accepts unquoted attributes, alternate references, and malformed link
tags (roadmap Step 10c). 13,096 reftests discovered (+187); 2,646 pass,
10,450 xfail, 0 fail. The 164 new xfails were bulk-classified with
`wpt_classify.py bulk-xfail`. The percentages below describe the
original 12,909-test corpus.

**2026-08-17 update (session B, mismatch negative controls):** 274
`rel="mismatch"` reftests ingested with inverted verdicts; 13,370
reftests discovered, 2,781 pass, 10,589 xfail, 0 fail. Their first run
exposed an XHTML MIME bug in the test file server (see the sensitivity
section) whose fix invalidated 2,723 cached results: on recapture, 10
stale xfails became passes and 49 trivial passes became genuine
xfails. Measured sensitivity: 174/274 asserted differences detected
(63.5%); the 99 misses are classified below.

**2026-08-17 update (session C, css/CSS2 module):** the `css/CSS2`
group added 6,287 reftests; 19,657 discovered, 3,189 pass, 16,468
xfail, 0 fail. See the session C section below for the category
breakdown and the extractor crash it uncovered.

**2026-08-17 update (session D, remaining css/* + top-level modules):**
18 groups added (css-break, filter-effects, css-counter-styles,
selectors, css-conditional, motion, css-highlight-api, mediaqueries,
compositing, css-scrollbars, css-scroll-snap, css-rhythm, css-nesting,
css-color-adjust, css-style-attr, quirks, compat,
density-size-correction); 22,044 discovered (+2,387), 3,578 pass,
18,466 xfail, 0 fail. See the session D section below.

## Classification

| Category | Count | % total | Description |
|----------|------:|--------:|-------------|
| **PASS** | **2,623** | **20.3%** | |
| requires tag-agnostic matching | 3,883 | 30.1% | Test and ref use different element types (IMG vs DIV, etc.) to achieve the same visual. GumTree matcher requires tag match. |
| bounds differ between test/ref | 2,501 | 19.4% | Different CSS layout strategies producing the same pixels but different box geometry. |
| display property differs | 1,459 | 11.3% | Test uses flex/grid/inline-block, ref uses block/different display. Inherent to cross-page comparison. |
| border property differs | 823 | 6.4% | Test and ref use different border styles. |
| body height collapse | 296 | 2.3% | BODY element has different height in test vs ref. |
| requires background-image comparison | 270 | 2.1% | Test paints with background-image (gradient/SVG/PNG), ref uses background-color. Sosie doesn't compare background-image. |
| HTML element height discrepancy | 251 | 1.9% | HTML root element has different height. |
| overflow computed value differs | 175 | 1.4% | `overflow:clip` vs `overflow:hidden` and similar. |
| z-index differs | 151 | 1.2% | Different stacking contexts, same visual. |
| font / font-family / line-height | 265 | 2.1% | Different font stacks or line-height producing same visual. |
| text-align / text-decoration | 93 | 0.7% | Logical vs physical values, or different decoration achieving same visual. |
| cursor / visibility / opacity / box-shadow / color | 53 | 0.4% | Minor style differences. |
| requires bg-color body propagation normalization | 15 | 0.1% | CSS body-to-root background-color propagation: test sets bg on BODY, ref on HTML. |
| unformattable diff (formatter bug) | 19 | 0.1% | Bug in Diff_fmt — should be fixed. |
| errors / timeouts / edge cases | 32 | 0.2% | CDP connection lost, extractor exceptions, capture timeouts. |

## Analysis by category

### Tag-agnostic matching (3,883 tests)

The largest class. WPT reftests achieve the same visual using completely
different DOM elements. For example, a test might use `<img>` elements
while the ref uses `<div>` with background-color. The GumTree matcher
requires tag name agreement to match nodes; unmatched nodes surface as
`Extra_node` diffs.

**Pattern:** All diffs are structural (extra baseline/modified node,
wrapper inserted/removed, moved). Zero style or bounds diffs.

**Fix options:**
- Tag-agnostic matching mode (match by bounds/position instead of tag name)
- Weakens sosie's structural guarantees for its primary use case
- Would need to be WPT-specific, not default behavior

### Bounds differ (2,501 tests)

WPT reftests achieve the same pixels via different CSS layout strategies.
The test might use `align-content: start` while the ref uses default flow;
or the test uses anchor positioning while the ref uses absolute
coordinates. The rendered output is identical but `getBoundingClientRect`
returns different values.

**Breakdown by location:**
- HTML/BODY only: 1,162 (container-level noise, ignorable)
- Content elements: 1,277 (genuinely different layout)
- Uniform position shift (scroll state): 62

**Breakdown by magnitude:**
- ≤ 5px: 100 (tolerance would fix)
- 6–20px: 257 (moderate)
- > 20px: 2,144 (fundamentally different layout strategies)

2,276 of these tests are pure CSS (no JavaScript) — the bounds diffs are
real, not capture artifacts. This is a fundamental limit of property-level
comparison: two different layouts that paint the same pixels cannot be
distinguished without pixel comparison.

**Fix options:**
- Ignore HTML/BODY bounds (fixes 1,162 container-only cases)
- Disable bounds check entirely for WPT (`check_bounds = false`)
- Accept as xfail (these are correctly identified as beyond sosie's model)

### Display property differs (1,459 tests)

Test uses `display: flex`, ref uses `display: block` (or grid vs
inline-block, etc.). These are genuinely different computed styles — the
test is proving that a CSS feature produces the same visual as a simpler
layout mode.

**No fix possible** without ignoring the display property, which would be
a significant weakening.

### Background-image comparison (270 tests)

Test uses `background-image` (gradient, SVG, PNG) to paint a colored area.
Ref uses `background-color`. Both look identical, but sosie only compares
`background-color` (the ref has `green`, the test has `transparent`).

**Fix:** Add `background-image` to the property whitelist. Hard because
it's a URL/gradient string, not a simple comparable value. Would need
gradient normalization or image comparison.

### Body propagation (15 tests)

CSS spec propagates `background-color` from `<body>` to `<html>` when
`<html>` has no background. Test sets bg on BODY, ref sets it on HTML.
Visually identical, but computed values are on different elements.

**Fix:** Normalization rule that canonicalizes body-to-root bg-color
propagation. Small targeted fix, 15 tests.

## Sensitivity: mismatch reftests as negative controls (2026-08-17)

`rel="mismatch"` reftests assert two pages render DIFFERENTLY, so the
runner inverts the verdict: a Diff is a pass, an Equivalent is a
measured **false negative** — the failure mode sosie's design declares
fatal. Unlike the match-test xfails above (spurious diffs, tolerable),
every entry here is a real blind spot quantified by WPT itself.

Of the 281 in-scope mismatch-only tests: 274 ingested, 5 excluded as
nondeterministic (css-ui caret tests use animation), 2 have no
reference anywhere in the tree (css-transforms text-perspective-001,
transform-flattening-001).

**Result: 174/274 asserted differences detected (63.5%).** One test
errors (css-overflow/overflow-video-hidden: reftest-wait never clears
without video playback). The 99 false negatives, by cause
(`expectations.json` reasons prefixed `sensitivity:`):

| Gap | Count | Recoverable? |
|-----|------:|--------------|
| writing-mode/direction/appearance not in whitelist (form controls) | 26 | whitelist add |
| font-palette not in whitelist (glyph palette colors) | 18 | whitelist add (partially — `@font-palette-values` changes may not surface in the computed value) |
| text-align-last not in whitelist | 16 | whitelist add |
| form control pseudo-element internals (::slider-*, ::placeholder, ::file-selector-button) | 9 | no — extractor walks DOM elements, not pseudo-elements |
| text-decoration-skip-ink not in whitelist | 7 | whitelist add |
| glyph-level font selection/synthesis (lang attr, system-ui per locale, emoji, synthetic italic) | 6 | no — computed font properties identical, glyphs differ |
| text-underline-offset, text-shadow, text-combine-upright/text-emphasis, -webkit-text-stroke | 5 | whitelist add |
| outline, accent-color, appearance, image-rendering | 8 | whitelist add |
| gradient image pixels (background-image not compared) | 2 | background-image string comparison would catch these two |
| highlight pseudo-element styling | 1 | no |
| line-breaking geometry (text-wrap: balance) | 1 | no — element bounds identical, line boxes differ |

**80 of 99 misses are recoverable by extending the property
whitelist** — extending it and re-running the negative controls would
raise measured sensitivity to a potential 254/274 (92.7%). This is the
trust boundary made concrete: sosie's verdict is exactly as strong as
the whitelist is complete, and these 274 tests now measure that
strength on every run.

### Harness bug found by the negative controls

On their first run, `css/css-color/t31-color-text-a.xht` (green text
vs. black text, `color` IS whitelisted) reported Equivalent. Root
cause: the test file server served `.xht`/`.xhtml` as `text/html`,
where the HTML parser hands the XHTML `<![CDATA[...]]>` style wrapper
to the CSS parser as garbage — dropping ALL style rules on BOTH sides.
Test and reference genuinely rendered identical (unstyled). Every
match reftest in that state passed trivially; only a negative control
could notice. Fix: serve XHTML as `application/xhtml+xml`
(`lib/file_server.ml`), recapture the 2,723 affected results.

## Session C: css/CSS2 module (2026-08-17)

6,287 reftests from `css/CSS2` (the CSS 2.1 test suite port: normal
flow, margins/padding/clear, positioning, selectors, borders, tables,
backgrounds, generated content, floats). 408 pass (6.5%), 5,879 xfail.
The pass rate is far below the corpus average (20.3%) because CSS2
tests predate the reftest style guide: test and reference routinely
differ in prose ("Test passes if..." vs. a bare box) and in markup
strategy, not just in the property under test.

Xfail reasons (`wpt_classify.py bulk-xfail`):

| Reason | Count | % of CSS2 |
|--------|------:|----------:|
| layout: bounds differ between test/ref | 2,727 | 43.4% |
| requires tag-agnostic matching | 1,076 | 17.1% |
| content: text differs | 842 | 13.4% |
| style: property differs (display 174, background-color 158, color 140, line-height 105, border-* ~200, other ~100) | 881 | 14.0% |
| unclassified failure | 349 | 5.6% |
| errors (see below) | 4 | 0.1% |

`content: text differs` is essentially a CSS2 phenomenon: 842 of the
corpus-wide 862 come from this module (test page says "Test passes
if...", reference page shows different or no prose — real DOM text
difference, correctly reported, inherent to cross-page comparison).

### Extractor crash diagnosed by session C

Three new tests crash the snapshot extractor —
`css/CSS2/tables/table-{header,footer,row}-group-001.xht`:

```
TypeError: Cannot read properties of null (reading 'appendChild')
    at appendChild (<anonymous>:22192:36)  [js_of_ocaml frames follow]
```

Root cause (diagnosed here, affects 8 tests corpus-wide): `freeze_page`
in `js_extractor/extractor.ml` appends the transition-freeze `<style>`
to `document.head`, which is **null** in an XML-parsed document with no
explicit `<head>` element — the HTML parser synthesizes a missing head,
the XML parser does not. The three CSS2 tests share the reference
`table-row-group-001-ref.xht`, whose markup goes straight from `<html>`
to `<body>`. The five pre-existing xfails with the same signature fit
the same pattern (css-ruby `root-ruby`/`root-block-ruby`, css-pseudo
`first-letter-of-html-root-refcrash`, css-cascade
`scope-implicit-004-print`, css-images `svg-script-is-ignored`): headless
documents parsed as XML or with non-HTML roots. Fix is small — fall
back to `documentElement` when `head` is null — queued in the backlog.

The fourth error is a `reftest-wait` timeout
(`stacking-context/composite-change-after-scroll-preserves-stacking-order.html`,
needs compositing activity that never settles headless).

## Session D: remaining css/* + top-level modules (2026-08-17)

18 groups ingested in one capture run (+2,387 discovered, 389 pass =
16.3%, 1,998 xfail): the css/* layout and style modules left after
sessions A–C, plus three top-level trees (`quirks`, `compat`,
`density-size-correction`). The session A tooling absorbed the
expansion unchanged.

Per-module pass rate spans the full range, tracking how closely each
module's tests follow the reftest style guide:

| Module | Pass/Total | % |
|--------|-----------:|--:|
| css/css-break | 19/1004 | 1.9% |
| css/filter-effects | 35/266 | 13.2% |
| css/css-counter-styles | 13/235 | 5.5% |
| css/selectors | 94/226 | 41.6% |
| css/css-conditional | 107/160 | 66.9% |
| css/css-highlight-api | 10/94 | 10.6% |
| css/motion | 49/93 | 52.7% |
| css/compositing | 1/59 | 1.7% |
| css/mediaqueries | 7/58 | 12.1% |
| css/css-scrollbars | 23/31 | 74.2% |
| quirks | 0/28 | 0.0% |
| compat | 4/23 | 17.4% |
| css/css-scroll-snap | 0/23 | 0.0% |
| density-size-correction | 10/20 | 50.0% |
| css/css-rhythm | 0/18 | 0.0% |
| css/css-nesting | 6/17 | 35.3% |
| css/css-color-adjust | 5/17 | 29.4% |
| css/css-style-attr | 6/15 | 40.0% |

`css/css-break` dominates the module (1,004 tests, 42% of the session)
and pulls the aggregate rate down: it is a fragmentation suite (page
and multicolumn breaks) where test and reference build the same visual
from structurally different box trees, so 987 of the session's 987
`requires tag-agnostic matching` xfails and most of its layout diffs
originate here. The three 0%-pass modules (css-scroll-snap, css-rhythm,
quirks) are small and similarly cross-page by construction.

Xfail reasons (`wpt_classify.py bulk-xfail`):

| Reason | Count | % of session |
|--------|------:|-------------:|
| requires tag-agnostic matching | 987 | 41.4% |
| layout: bounds differ between test/ref | 414 | 17.3% |
| content: text differs | 209 | 8.8% |
| unclassified failure | 117 | 4.9% |
| style: property differs (background-color 82, display 67, color 48, text-decoration 24, opacity 15, overflow-y 11, other ~14) | 261 | 10.9% |
| sensitivity: mismatch false negative | 8 | 0.3% |
| error: reftest-wait timeout | 5 | 0.2% |

The category mix mirrors the corpus: tag-agnostic matching and bounds
diffs are the structural cross-page limitations described above, not
extractor defects. Eight `sensitivity:` entries are mismatch reftests
in these modules whose two pages render equivalent under the
comparison whitelist — genuine blind spots, folded into the same
whitelist-extension work queued from session B.

The five errors are all `reftest-wait` timeouts (tests that gate on an
event that never fires headless: dynamic filter changes, `:has()`
recomputation on DOM mutation, `@media`/container-query re-evaluation,
`::cue`). No new extractor crash class appeared — the session C
null-`document.head` diagnosis stands as the only open extractor bug.

## Session E: non-CSS trees (2026-08-17)

Five non-CSS trees ingested in one capture run (+1,207 discovered, 444
pass = 36.8%, 763 xfail): `html/rendering`, `html/semantics`,
`html/dom`, `mathml`, `svg`. `html/canvas` was deliberately excluded —
its assertions are bitmap comparisons invisible to property-level
capture. No new `support_paths` were needed: the coverage scanner
confirmed 1,222 of the trees' references resolve within the ingested
subtrees themselves, 21 against existing support paths, and 1 into
`compat/` (already a group).

The 36.8% aggregate pass rate is more than double session D's — these
trees carry many self-contained reftests that render identically
across test and reference, rather than the cross-page fragmentation
suites that dominate `css/css-break`.

| Group | Pass/Total | % |
|-------|-----------:|--:|
| html/rendering | 134/277 | 48.4% |
| html/semantics | 115/359 | 32.0% |
| html/dom | 69/127 | 54.3% |
| mathml | 90/272 | 33.1% |
| svg | 36/172 | 20.9% |
| **total** | **444/1,207** | **36.8%** |

`svg` is the weakest tree (20.9%): its `.html`-wrapped reftests draw the
same picture from structurally different SVG DOMs (different `use`
expansions, `defs`/`symbol` instancing), which surface as bounds and
tag-agnostic diffs. `html/dom` and `html/rendering` lead — they assert
concrete box geometry that the property capture reproduces well.

Xfail reasons (`wpt_classify.py bulk-xfail`):

| Reason | Count | % of session |
|--------|------:|-------------:|
| layout: bounds differ between test/ref | 245 | 32.1% |
| requires tag-agnostic matching | 226 | 29.6% |
| style: property differs (various) | 98 | 12.8% |
| error (85 timeout, 7 null-`head` crash) | 92 | 12.1% |
| unclassified failure | 36 | 4.7% |
| sensitivity: mismatch false negative | 35 | 4.6% |
| content: text differs | 31 | 4.1% |

The 35 `sensitivity:` entries are mismatch reftests in these trees whose
two pages render equivalent under the comparison whitelist — genuine
blind spots, folded into the whitelist-extension work queued from
session B.

### No new extractor crash class; null-`head` crash extends to session E

Of the 92 errors, 85 are `reftest-wait` timeouts (the bulk from
`html/semantics/forms/the-select-element/` — `appearance: base-select`
and `filterable-select` popovers that gate on user interaction never
delivered headless). The remaining 7 are the **session-C
null-`document.head` crash**, same signature verbatim (`TypeError:
Cannot read properties of null (reading 'appendChild')` in
`freeze_page`):

- 3 mathml `.xhtml` (`dynamic-rowspan-mozilla-370692`,
  `mi-mathvariant-1`/`-2`) — XML-parsed, no synthesized `<head>`, as
  diagnosed in session C.
- 4 svg `.html` (`painting/reftests/non-scaling-stroke-001`/`-003`/
  `-004`, `symbol-in-mask`) — *surprising*, since the HTML parser
  synthesizes a `<head>`. Worth checking against the queued fix: the
  `documentElement` fallback covers them regardless, but the mechanism
  (head present yet insertion point null?) differs from the XML case.

These 7 do not change the fix already queued in the backlog; they
expand its affected-test list and its test evidence.

## Null-`head` crash fixed (2026-08-18)

`freeze_page`/`unfreeze_page` now fall back to `documentElement` when
`document.head` is null, and `unfreeze` removes the freeze `<style>`
from its actual parent (`parentNode` / `.remove()`) rather than
re-deriving the insertion point. Applied identically to both extractors
(`js_extractor/extractor.ml` and the canonical `js/sosie-capture.js`).
A regression test (`capture_headless_document_does_not_crash`, an
`application/xhtml+xml` data-URL with no `<head>`) guards it under
`@integration`.

Re-ran the **12** xfails carrying the `appendChild`/null-`head`
signature — the only `extractor exception` class in the corpus. All 12
now capture without crashing:

- **3 recovered → pass**, pruned from `expectations.json`: mathml
  `dynamic-rowspan-mozilla-370692`, `mi-mathvariant-1`, `mi-mathvariant-2`.
- **9 still xfail for genuine reasons** (crash reasons refreshed via
  `diffs_to_reason`): the three css/CSS2 `table-*-group-001` and
  css-pseudo `first-letter-of-html-root-refcrash` →
  *requires tag-agnostic matching* (BODY wrapper / baseline-node
  insertion); svg `non-scaling-stroke-001`/`-003`/`-004` →
  *layout: bounds differ*; css-images `svg-script-is-ignored` and svg
  `symbol-in-mask` → structural.

Corpus xfails 19,829 → 19,826.

### Root cause of the "surprising" svg `.html` cases (resolved)

Session E flagged the 4 svg `.html` crashes as surprising because the
HTML parser synthesizes a `<head>`. Resolved: the crash was never in the
`.html` test capture — those parse as HTML with `documentElement = HTML`
(post-fix captures root at `/HTML/BODY/svg/...`). It was the **reference**
capture. Each uses `rel="match"` to an SVG reference
(`non-scaling-stroke`/`symbol-in-mask` → `green-100x100.svg`;
`svg-script-is-ignored` → `svg-script-is-ignored-ref.svg`), and those
`.svg` documents are SVG-rooted (`documentElement = <svg>`, no head).
Same null-`head` mechanism, on the reference rather than the test. The
`documentElement` fallback covers both. Their residual xfails are now
SVG-rooted-tree comparison artifacts (SVG reference vs HTML-rooted test),
i.e. the SVG-schema work tracked in backlog item 3, not a crash.

## Whitelist extension: sensitivity re-measurement (2026-08-17)

The property whitelist grew from 29 to 49 (commit extending the
capture with `text-align-last`, `font-palette`, `writing-mode`,
`direction`, `appearance`, `accent-color`, `image-rendering`,
`text-decoration-skip-ink`, `text-underline-offset`, `text-shadow`,
`text-combine-upright`, and the `outline`/`text-emphasis`/
`-webkit-text-stroke` shorthands expanded to longhands). This section
measures the effect on the negative controls in both directions.

**Re-run scope.** Widening the whitelist is *monotonic*: comparing more
properties can only add diffs, never remove them. So the only possible
verdict flips are a passing Match test → spurious fail, or a
false-negative Mismatch control → recovered pass; every Match xfail and
error is provably verdict-stable. Only the 4,022 passes and the 142
false-negative controls were recaptured (4,164 tests); the other 19,087
cached results are unaffected by construction.

**Sensitivity (384 discovered Mismatch controls, 3 errored).**

| | detected | false-neg | sensitivity |
|--|--------:|----------:|------------:|
| before | 239 | 142 | 239/381 = 62.7% |
| after  | 314 |  67 | 314/381 = **82.4%** |

75 of the 142 false negatives are now detected. The recovered controls
are exactly the whitelist additions earning their place: the
`appearance`/`writing-mode`/`direction` form-control suites
(`css-writing-modes/forms/*`, `the-meter-element/*`, ~40),
`text-align-last` (`css-text/text-align/*-last-*`, 16), `font-palette`
(9), `text-decoration-skip-ink` (7), plus `accent-color`, `outline`,
`image-rendering`, `text-underline-offset`, `text-shadow`,
`text-combine-upright`, `-webkit-text-stroke` (1–2 each).

**Cost — spurious Match diffs (the other direction).** 675 previously
passing Match reftests now report a diff. WPT asserts these render
identically, so every one is a false positive (tolerable by design;
false negatives are the fatal class). They are bulk-xfailed by dominant
diff type:

| Reason | Count |
|--------|------:|
| style: appearance differs | 588 |
| style: writing-mode differs | 23 |
| style: direction differs | 17 |
| style: text-align-last differs | 8 |
| style: outline-width differs | 8 |
| style: font-palette differs | 8 |
| style: text-shadow differs | 5 |
| style: text-underline-offset differs | 4 |
| style: display / accent-color / other | ~12 |
| layout: bounds differ | 2 |

`appearance` dominates because match reftests freely interchange
`appearance` values on form controls that render the same. The 2
`layout: bounds` flips are `css-anchor-position` tests
(`anchor-center-002`, `position-area-overflow-icb-001`) with large
(tens-of-px) bounds differences between runs — capture
non-determinism in anchor positioning, unrelated to the whitelist;
xfailed as `layout: bounds`. The 3,347 stable passes confirm capture
determinism holds everywhere else.

Suite: 4,022 → 3,422 pass, 19,229 → 19,829 xfail, 0 fail (net −600 =
−675 spurious xfails + 75 recovered passes).

**67 residual false negatives** — the non-recoverable classes, plus one
new opportunity:

- Form-control pseudo-element internals (`::slider-*`, `::placeholder`,
  `::file-selector-button`, ~15 in `css-pseudo`, `html/rendering
  widgets`): the extractor walks DOM elements, not pseudo-elements.
- Glyph-level font selection/synthesis (`css-fonts` `lang-attribute`,
  `system-ui-*`, `font-variant-emoji`, `test-synthetic-italic`) and
  `@font-palette-values` add/remove/delete that do not surface in the
  computed value (~12): computed properties identical, glyphs differ.
- MathML operator geometry (`presentation-markup/operators/
  embellished-op-*`, `op-dict`, `stretchy-*`, `frac-linethickness`,
  16): operator spacing/stretch is glyph/geometry, not a whitelisted
  property.
- Pixel/bitmap (`mix-blend-mode` image/video, gradient interpolation,
  `highlight-api`/`selection-image` highlight styling, ~10):
  `background-image` and raster content are not compared.
- **Conjectured recoverable — tested and refuted (see the SVG paint
  section below):** the `permission-element`
  `icon-css-property-{fill,stroke,stroke-width,height}` reftests were
  thought recoverable by whitelisting the SVG presentation properties
  they toggle. The 2026-08-18 extension added `fill`/`stroke`/
  `stroke-width` and recaptured them: **none recovered**. The
  declarations target the `::permission-icon` pseudo-element, which the
  extractor does not capture (only `::before`/`::after`); no captured
  element carries the changed value. These belong with the
  pseudo-element-internals class above.

## SVG paint whitelist extension (2026-08-18)

The whitelist grew from 49 to 52 with the SVG paint presentation
properties `fill`, `stroke`, `stroke-width`. The goal was to recover the
9 `permission-element` icon false negatives the previous section flagged
as a "recoverable opportunity". `height` was deliberately **not** added:
computed height is per-element and highly variable, so whitelisting it
would inject thousands of corpus-wide spurious Match diffs to recover at
most two pseudo-element tests — and those are pseudo-element geometry,
non-recoverable by a general element-level property regardless.

**Re-run scope.** Same monotonicity argument as the 49-property section:
widening only adds diffs. Only the 3,425 passes and the 67 sensitivity
false-negatives were recaptured (3,492 tests); the other 19,759 xfails
are verdict-stable by construction.

**The hypothesis was refuted: 0 controls recovered.** All eight
`icon-css-property-{fill,stroke,stroke-width,height}` reftests still
render equivalent under the whitelist. Root cause: every one styles the
`::permission-icon` pseudo-element (e.g. `::permission-icon { fill: red }`),
and the extractor captures only `::before`/`::after` pseudos and does not
descend into shadow DOM (`js/sosie-capture.js:73`,
`js_extractor/extractor.ml:122`). No captured element carries the changed
`fill`/`stroke`/`stroke-width`, so both sides compare identical. The
prior "recoverable" note was inferred from the test *source* (the CSS
declarations), not verified against capture behaviour. These join the
pseudo-element-internals non-recoverable class.

**Cost — 5 spurious Match diffs.** Five previously-passing Match reftests
now report a paint diff, bulk-xfailed by dominant type:

| Reason | Test |
|--------|------|
| style: fill differs | `css-text-decor/text-shadow/svg-fill-opacity` |
| style: fill differs | `css-pseudo/svg-text-selection-002` |
| style: stroke-width differs | `css-pseudo/textpath-selection-011` |
| style: stroke-width differs | `css-viewport/zoom/stroke` |
| style: stroke-width differs | `css-viewport/zoom/svg-path` |

Each is a genuine `fill`/`stroke`/`stroke-width` difference on inline SVG
that the reftest neutralises visually (`fill-opacity` vs opaque `rgb`;
`stroke-width` doubling under `zoom`). They are the tolerable
false-positive class, not false negatives. Near-zero blast radius vs the
675 from the 49-property extension — the props are inherited with
constant defaults (`fill: rgb(0, 0, 0)`, `stroke: none`,
`stroke-width: 1px`) on all non-SVG content.

**Kept anyway.** The properties earn their place for sosie's actual use
case — UI-conservative refactoring of inline SVG, where a changed
`fill`/`stroke`/`stroke-width` is exactly the kind of visual regression
the whitelist must catch — even though they recovered no negative
controls here.

**Incidental, unrelated to the new props.** The recapture surfaced two
sensitivity controls, `css-fonts/font-palette-add` and
`font-palette-remove`, now stably detected (3/3 runs) via the
already-whitelisted `font-palette`; their stale "non-recoverable
glyph-palette" xfails were pruned to honest passes. Sensitivity thus
moved 314/381 (82.4%) → **316/381 (82.9%)** — but the +2 is
`font-palette`, not SVG paint; SVG paint contributed 0. Residual false
negatives 67 → 65.

**Observed flake (pre-existing, unrelated).**
`css-anchor-position/position-try-switch-from-fixed-anchor` reported a
structural diff (`extra baseline node`) once under batch load but passes
on isolated rerun (2/2) — anchor-position layout non-determinism, the
same class as the two anchor flips in the 49-property section. Left as
pass.

Suite: 3,422 pass, 19,829 xfail, 0 fail; coverage gate 23,251/23,251
exact (no tests added or removed — discovery unchanged).

## Possible improvement phases (by ROI)

**Phase B — Body/HTML container normalization (~1,200 tests):**
Ignore HTML/BODY bounds. Targets body-height-collapse (296),
HTML-height (251), and container-only bounds diffs (1,162, overlapping).

**Phase C — Disable bounds check for WPT (~2,500 tests, aggressive):**
Set `check_bounds = false`. Defensible for cross-page reftests where
different layout is expected. Weakens the test.

**Phase D — Style ignore list for WPT (~2,400 tests, aggressive):**
Ignore display, z-index, border-* in WPT comparison. These properties
intentionally differ between test and ref. Significantly weakens the check.

**Phase E — Accept the plateau (~3,900 tests):**
Tag-agnostic matching (3,883) represents a fundamental matcher limitation.
Would require a new matching mode. Correctly classified as xfail until
then.

## Relationship to sosie's primary use case

WPT reftests are a *cross-page* equivalence problem: different HTML/CSS
producing the same visual. Sosie's primary use case is *same-page*
refactoring: same HTML/CSS reorganized without changing the visual.

In same-page refactoring:
- Tags don't change → tag-agnostic matching not needed
- Layout doesn't change → bounds always match
- Display property doesn't change → no false positives
- Background strategy doesn't change → no background-image gap

The xfails are real limitations of property-level comparison for cross-page
equivalence, but they don't affect sosie's primary use case. The WPT suite
serves as a stress test for the extractor, parser, and normalization — the
20.3% that pass validate robustness across 2,623 diverse real-world CSS
patterns.

## Classification database

The multi-dimensional classification lives in two artifacts:

- **`classification.json`** (committed) — durable export, source of truth
  for tags and notes. One object per test, all dimensions.
- **`classification.db`** (gitignored) — SQLite working database for
  queries and annotation.

Use `wpt_classify.py` to manage the database:

```bash
# Build DB from test HTML + cached results + expectations
python3 test/external/wpt_classify.py bootstrap

# Print summary table
python3 test/external/wpt_classify.py summary

# Run arbitrary SQL
python3 test/external/wpt_classify.py query "SELECT css_spec, COUNT(*) FROM tests GROUP BY css_spec ORDER BY 2 DESC LIMIT 10"

# Tag / annotate a test
python3 test/external/wpt_classify.py tag css/css-flexbox/some-test.html my-tag
python3 test/external/wpt_classify.py note css/css-flexbox/some-test.html "Investigated: layout is correct"

# Export DB to JSON (commit this)
python3 test/external/wpt_classify.py export

# Import JSON into DB (fresh clone)
python3 test/external/wpt_classify.py import

# Sync reason strings back to expectations.json
python3 test/external/wpt_classify.py sync-expectations
```

Dimensions per test: status, WPT metadata (title, assertion, spec section),
diff analysis (types, counts, bounds delta), tags (many-to-many), and notes.
