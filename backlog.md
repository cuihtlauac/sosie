# Backlog

Pending work, current task first. See `plans/wpt-ingestion-campaign.md`
for the full campaign design and `sosie-roadmap.md` Step 10c for status.

## 1. Capture pseudo-elements beyond `::before`/`::after`

The SVG-paint extension proved that the `::permission-icon`,
`::slider-{track,fill,thumb}`, `::placeholder`, and
`::file-selector-button` false negatives (~25 sensitivity controls) are
unreachable because the extractor walks DOM elements plus only those two
pseudos. Recovering them needs the extractor to enumerate and capture
additional (and UA shadow) pseudo-elements — schema and both-extractor
work.

## 2. `.svg` reftest support in discovery

Now ~1,266 in-scope tests are skipped by the walker (`acc_if_reftest`
accepts only .html/.xhtml/.xht): 1,125 in `svg/` alone after session E
ingested that tree, plus 113 in css-masking and a long tail. The
snapshot schema currently assumes an HTML/BODY tree; SVG-rooted
documents need schema work first.

## 3. Paged-media modules via CDP `Emulation.setEmulatedMedia`

Support the css-page and css/printing modules by emulating paged media
through CDP `Emulation.setEmulatedMedia`.

## 4. Step 11: CI integration for ocaml.org

Roadmap Step 11; the campaign interleaves before it.
