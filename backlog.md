# Backlog

Pending work, current task first. See `plans/wpt-ingestion-campaign.md`
for the full campaign design and `sosie-roadmap.md` Step 10c for status.

## 1. `.svg` reftest support in discovery

Now ~1,266 in-scope tests are skipped by the walker (`acc_if_reftest`
accepts only .html/.xhtml/.xht): 1,125 in `svg/` alone after session E
ingested that tree, plus 113 in css-masking and a long tail. The
snapshot schema currently assumes an HTML/BODY tree; SVG-rooted
documents need schema work first.

## 2. Paged-media modules via CDP `Emulation.setEmulatedMedia`

Support the css-page and css/printing modules by emulating paged media
through CDP `Emulation.setEmulatedMedia`.

## 3. Step 11: CI integration for ocaml.org

Roadmap Step 11; the campaign interleaves before it.

## 4. Adopt cascade's colour/value/selector parsing

Replace the hand-rolled CSS primitives with `cascade` (published on opam,
extracted from `samoht/tw`). See the "Cascade integration addendum
(2026-08-18)" in `sosie-design.md`.

- Fold `Cascade.Values` (value/unit parsing) and `Cascade.Color_space`
  (CSS Color 4 colour spaces) into the `Color`/`Px`/`Num` cases of
  `css_value`. This fixes the lossy `Color of int` (no alpha, no
  wide-gamut) — a false-negative hazard, so a Claim-4 improvement, do it
  before relying on colour comparison in production.
- Fold `Cascade.Selector` (`of_string`, with CSS-escape handling) into
  `simple_selector` for `Drop_subtree` / `Mask_text` rules.
- Do **not** adopt `cascade.diff` — it diffs CSS source, a different
  problem from sosie's rendered-tree diff.
- First confirm the modules are re-exported under the top-level `Cascade`
  namespace (`opam install cascade` + merlin/odoc) before writing the
  `depends` stanza; the module names are taken from the README convention,
  not verified as public.
