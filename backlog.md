# Backlog

Pending work, current task first. See `plans/wpt-ingestion-campaign.md`
for the full campaign design and `sosie-roadmap.md` Step 10c for status.

## WPT campaign session D — remaining css/* layout modules (+~2,600)

Groups: css-break (1,003), filter-effects (263), css-counter-styles
(234), selectors (218), css-conditional (160), motion (93),
css-highlight-api (92), mediaqueries (58), compositing (56),
css-scrollbars (31), quirks (25), css-scroll-snap (23), compat (23),
density-size-correction (20), css-rhythm (18), css-nesting (17),
css-color-adjust (16), css-style-attr (15). Same cycle as session C.

## WPT campaign session E — non-CSS trees (+~750)

Groups: html/rendering (170), html/semantics (227), html/dom (127),
mathml (234), svg (168). NOT html/canvas (bitmap assertions invisible
to property comparison). Watch for cross-tree ref/support needs; add
support_paths as the missing-ref check dictates.

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
other `document.head` uses. Re-run the 8 tests, prune recovered
xfails. Diagnosed 2026-08-17 (TRIAGE.md session C section).

## Deferred (not scheduled)

- `.svg` reftest support in discovery (132 in-scope tests; snapshot
  schema currently assumes an HTML/BODY tree).
- Paged-media modules via CDP `Emulation.setEmulatedMedia` (css-page,
  css/printing).
- Step 11: CI integration for ocaml.org (roadmap; the campaign
  interleaves before it).
