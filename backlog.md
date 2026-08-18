# Backlog

Pending work, current task first. See `plans/wpt-ingestion-campaign.md`
for the full campaign design and `sosie-roadmap.md` Step 10c for status.

## 1. Round-trip (`C ∘ G`) breaks on `text-emphasis-position`

The `@integration` `test_round_trip` suite fails: the generator emits
`text-emphasis-position: over right` (the canonical two-value form) but
Chromium's getComputedStyle returns `over`, so `C ∘ G ≠ id` for the
hand-crafted (single div, nested divs) and qcheck ("C ∘ G preserves
structure") cases. Pre-existing, surfaced 2026-08-18 during the
null-`head` fix (unrelated to it). Likely fallout of the 29 → 49
whitelist extension that added `text-emphasis` longhands. Fix: align
the generator's serialization with the resolved-value form (or
normalize both sides) so the round-trip holds. A round-trip break is
close to the trust boundary — `C ∘ G = id` validates the capture
pipeline — so treat as higher priority than the deferred items.

## 2. Whitelist extension: SVG presentation properties

The 29 → 49 whitelist extension raised mismatch-control sensitivity to
82.4% (TRIAGE.md whitelist re-measurement section). Of the 67 residual
false negatives, 9 are recoverable: the `permission-element`
`icon-css-property-{fill,stroke,stroke-width,height}` reftests differ
only in SVG presentation properties not yet captured. Add `fill`,
`stroke`, `stroke-width` (and confirm `height` behaviour on replaced
SVG) to the whitelist, then re-measure sensitivity and re-triage
match-test xfails as before. The rest of the 67 are non-recoverable by
property capture (pseudo-element internals, glyph-level font selection,
MathML operator geometry, bitmap/highlight styling).

## 3. Deferred (not scheduled)

- `.svg` reftest support in discovery. Now ~1,266 in-scope tests are
  skipped by the walker (`acc_if_reftest` accepts only .html/.xhtml/.xht):
  1,125 in `svg/` alone after session E ingested that tree, plus 113 in
  css-masking and a long tail. The snapshot schema currently assumes an
  HTML/BODY tree; SVG-rooted documents need schema work first.
- Paged-media modules via CDP `Emulation.setEmulatedMedia` (css-page,
  css/printing).
- Step 11: CI integration for ocaml.org (roadmap; the campaign
  interleaves before it).
