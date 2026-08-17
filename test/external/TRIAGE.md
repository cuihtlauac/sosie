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
