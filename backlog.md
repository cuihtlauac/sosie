# Backlog

Pending work, current task first. See `plans/wpt-ingestion-campaign.md`
for the full campaign design and `sosie-roadmap.md` Step 10c for status.

## Whitelist extension guided by sensitivity measurement

Session B measured 99 false negatives on mismatch reftests; 80 are
recoverable by adding properties to the capture whitelist
(text-align-last, font-palette, writing-mode, direction, appearance,
outline*, accent-color, text-decoration-skip-ink,
text-underline-offset, text-shadow, text-combine-upright,
text-emphasis, -webkit-text-stroke, image-rendering). Add them,
re-run the negative controls (expect ≈254/274 = 92.7% sensitivity),
prune the recovered xfails, and re-triage match-test xfails the new
properties may cause (whitelist growth can add spurious diffs —
measure both directions). See TRIAGE.md sensitivity section.

## Extractor: null document.head crash on XML documents without <head>

`freeze_page` (`js_extractor/extractor.ml`) appends the
transition-freeze style to `document.head`, which is null in
XML-parsed documents lacking an explicit `<head>` — the XML parser
does not synthesize one (the HTML parser does). Crashes the capture
with `TypeError: Cannot read properties of null (reading
'appendChild')` on 8 WPT tests (css/CSS2/tables/table-*-group-001.xht
via their shared head-less reference; css-ruby root-ruby /
root-block-ruby; css-pseudo first-letter-of-html-root-refcrash;
css-cascade scope-implicit-004-print; css-images
svg-script-is-ignored). Fix: fall back to `documentElement` (or the
root element) when `head` is null; also audit `unfreeze_page` and any
other `document.head` uses. Re-run the affected tests, prune recovered
xfails. Diagnosed 2026-08-17 (TRIAGE.md session C section).

Session E added 7 more with the identical signature (TRIAGE.md session
E section): 3 mathml `.xhtml` (dynamic-rowspan-mozilla-370692,
mi-mathvariant-1/-2 — same XML no-`<head>` cause) and 4 svg `.html`
(painting/reftests/non-scaling-stroke-001/-003/-004, symbol-in-mask).
The svg `.html` cases are surprising — the HTML parser synthesizes a
`<head>`, so the null insertion point has a different cause than the
XML case; verify the `documentElement` fallback actually covers them
and diagnose why `head` is null there. Affected corpus-wide: 15 tests.

## Deferred (not scheduled)

- `.svg` reftest support in discovery. Now ~1,266 in-scope tests are
  skipped by the walker (`acc_if_reftest` accepts only .html/.xhtml/.xht):
  1,125 in `svg/` alone after session E ingested that tree, plus 113 in
  css-masking and a long tail. The snapshot schema currently assumes an
  HTML/BODY tree; SVG-rooted documents need schema work first.
- Paged-media modules via CDP `Emulation.setEmulatedMedia` (css-page,
  css/printing).
- Step 11: CI integration for ocaml.org (roadmap; the campaign
  interleaves before it).
