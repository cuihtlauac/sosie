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
