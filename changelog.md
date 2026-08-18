# Changelog

Completed work, most recent first.

## 2026-08-18 — Fix `test_audit_integration`: enumerate CSS props via JS

`Audit_whitelist.all_css_properties` called CDP
`CSS.getSupportedCSSProperties`, which Chrome 151 has removed entirely
(the command no longer exists — verified against the live
`/json/protocol`; an interim `DOM.enable` fix cleared the "DOM agent
needs to be enabled first" error only to surface `'…' wasn't found`).
Replaced it with a `Runtime.evaluate` that reads property names off a
`getComputedStyle(document.documentElement)` object — the array-like set
of every longhand the engine exposes. That is in fact the precise,
non-redundant set the blind-spot reset needs: resetting each
non-whitelisted longhand to `initial` covers everything that can affect
rendering, without the old command's shorthand/longhand duplication. No
CSS/DOM CDP domain enable is required anymore. `@integration`
`test_audit_integration` passes; `audit-whitelist` smoke-tested
end-to-end (a page using non-whitelisted `margin`/`letter-spacing`/
`transform` correctly reports blind spots).

## 2026-08-18 — Fix `C ∘ G` round-trip on `text-emphasis-position`

The `@integration` `test_round_trip` suite failed: fixtures and the
generator used `over right` as the canonical resolved value of
`text-emphasis-position`, but Chromium's getComputedStyle normalizes it
to `over` (verified: `over right` → `over`, `right over` → `over`,
`over` → `over`; only the non-default `left` component survives, e.g.
`under left` → `under left`). So `C ∘ G ≠ id` for the hand-crafted and
qcheck round-trip cases. Fixed by using the true canonical resolved
value `over` everywhere the initial value is hardcoded: `mutate.ml`'s
`Reset_to_default` table (where `over right` also produced a spurious
no-op reset mutation, since resetting `over` → `over right` captures
back as `over`), and the test fixtures across the suite. The
trust-critical path (`compare.ml` over two real captures) was never
affected — both sides come from getComputedStyle and are already
canonical; `over right` only ever appeared as a hand-authored literal.
`@integration` `test_round_trip` (4 cases) now passes;
`test_mutation_integration` passes; unit suite green.

Surfaced (pre-existing, unrelated) while running `@integration`:
`test_audit_integration` fails with CDP `DOM agent needs to be enabled
first` — `Audit_whitelist.all_css_properties` calls
`CSS.getSupportedCSSProperties` without a prior `DOM.enable` (a
Chromium behavior change). Confirmed failing on the clean tree; queued
in the backlog.

## 2026-08-18 — Fix null `document.head` crash on head-less documents

`freeze_page`/`unfreeze_page` fall back to `documentElement` when
`document.head` is null, and unfreeze removes the freeze `<style>` from
its actual parent (`parentNode` / `.remove()`) rather than re-deriving
the insertion point. Applied identically to both extractors — the
canonical `js/sosie-capture.js` and the JSOO `js_extractor/extractor.ml`
(where `document##.head` is typed non-optional, so it is read via
`Js.Unsafe.get` to null-check it). Regression test
`capture_headless_document_does_not_crash` (an `application/xhtml+xml`
data-URL with no `<head>`) added under `@integration`.

Re-ran the 12 xfails carrying the `appendChild`/null-`head` signature —
the only `extractor exception` class in the corpus. All 12 now capture
without crashing: 3 mathml tests recovered to pass (pruned from
`expectations.json`), 9 remain xfail for genuine structural/layout
reasons (crash reasons refreshed via `diffs_to_reason`). Corpus xfails
19,829 → 19,826.

Resolved session E's "surprising" svg `.html` crashes: the crash was in
their SVG *reference* documents (`rel="match"` → `green-100x100.svg`,
`svg-script-is-ignored-ref.svg`), which are SVG-rooted with no head —
not the HTML test files (which parse normally). Same null-`head`
mechanism, on the reference; the `documentElement` fallback covers both.
Details in TRIAGE.md.

## 2026-08-17 — Whitelist extension guided by sensitivity measurement

Extended the capture whitelist 29 → 49 properties to recover the false
negatives measured in session B: `text-align-last`, `font-palette`,
`writing-mode`, `direction`, `appearance`, `accent-color`,
`image-rendering`, `text-decoration-skip-ink`, `text-underline-offset`,
`text-shadow`, `text-combine-upright`, and the `outline` /
`text-emphasis` / `-webkit-text-stroke` shorthands expanded to
longhands (getComputedStyle does not reliably serialize a shorthand;
an empty computed value would be a silent false negative). Threaded
through every construction site (shared record + Property_whitelist,
JSOO + raw JS extractor, native parse/serialize, generator, mutator,
comparator, color canonicalizer) with tests and QCheck generators;
whitelist-count assertions 29 → 49. Commit `ffd9e99`.

Re-measured the 384 discovered Mismatch controls in both directions.
Exploited monotonicity (widening only adds diffs) to recapture just the
4,022 passes + 142 false-negatives; the other 19,087 are provably
verdict-stable. Added a `--kinds` runner mode for the authoritative
Mismatch denominator. **Sensitivity 239/381 (62.7%) → 314/381
(82.4%)** — 75 of 142 false negatives recovered, led by the
`appearance`/`writing-mode`/`direction` form-control suites (~40),
`text-align-last` (16), `font-palette` (9). Cost: 675 previously
passing Match reftests now report a (tolerable) spurious diff, 588 of
them `appearance` on interchangeable form controls; bulk-xfailed by
dominant type. 2 `css-anchor-position` tests flipped on bounds (capture
non-determinism, not the whitelist). 67 residual false negatives are
non-recoverable (pseudo-element internals, glyph-level font selection,
MathML operator geometry, bitmap/highlight) except 9
`permission-element` icon tests recoverable by adding SVG `fill`/
`stroke`/`stroke-width`/`height` — queued in the backlog. TRIAGE.md
whitelist re-measurement section.
Suite: 23,251 tests, 4,022 → 3,422 pass, 19,229 → 19,829 xfail, 0 fail;
coverage gate 23,251/23,251 unchanged (no tests added).

## 2026-08-17 — WPT campaign session E: non-CSS trees

Five non-CSS trees added to the manifest in one cycle: `html/rendering`,
`html/semantics`, `html/dom`, `mathml`, `svg` (NOT `html/canvas` —
bitmap assertions invisible to property comparison). No new
`support_paths` needed: the coverage scanner confirmed 1,222 refs
resolve within the ingested subtrees, 21 against existing support, 1
into `compat/`. Sparse re-sync, one capture run, `bulk-xfail`, classify
bootstrap+export, coverage scan/validate/report — session A tooling
unchanged. 1,207 reftests ingested (plan estimated ~750–926; the
coverage scan projected the true 1,207 up front); 444 pass (36.8% —
more than double session D, these trees carry self-contained reftests);
763 xfail (bounds 32.1%, tag-agnostic 29.6%, style 12.8%, error 12.1%,
sensitivity 4.6%, content-text 4.1%; TRIAGE.md session E section). No
new extractor crash class: of 92 errors, 85 are `reftest-wait` timeouts
(mostly `the-select-element` interactive popovers) and 7 are the
session-C null-`document.head` crash extended to 3 mathml `.xhtml` +
4 svg `.html` (the latter surprising — HTML parser synthesizes a head;
noted in the backlog fix item). Fixed a stale hardcoded "37 groups"
string in `wpt_coverage.py`'s report generator (now derives from
scan_meta). Also recorded: the now-ingested `svg/` tree exposes ~1,125
in-scope `.svg`-extension reftests the walker skips (deferred item
count updated 132 → ~1,266).
Suite: 22,044 → 23,251 (+1,207), 4,022 pass, 19,229 xfail, 0 fail;
coverage gate 23,251/23,251 exact.

## 2026-08-17 — WPT campaign session D: remaining css/* + top-level modules

18 groups added to the manifest in one cycle — the css/* layout and
style modules left after A–C (css-break, filter-effects,
css-counter-styles, selectors, css-conditional, motion,
css-highlight-api, mediaqueries, compositing, css-scrollbars,
css-scroll-snap, css-rhythm, css-nesting, css-color-adjust,
css-style-attr) plus three top-level trees (quirks, compat,
density-size-correction). Sparse re-sync from local objects, one
capture run, `bulk-xfail`, classify bootstrap+export, coverage
scan/validate/report — session A tooling unchanged. 2,387 reftests
ingested (planned ~2,600; the rest skipped for refs absent from the
sparse checkout); 389 pass (16.3%), 1,998 xfail. `css/css-break` is
42% of the session (1,004 tests, 1.9% pass, all 987 tag-agnostic
xfails) — a fragmentation suite where equal visuals come from unequal
box trees. No new extractor crash class; the 5 errors are
`reftest-wait` timeouts on events that never fire headless. Category
and per-module tables in TRIAGE.md session D section.
Suite: 19,657 → 22,044 (+2,387), 3,578 pass, 18,466 xfail, 0 fail;
coverage gate 22,044/22,044 exact.

## 2026-08-17 — WPT campaign session C: css/CSS2 module

`css/CSS2` added to manifest groups; sparse re-sync from local
objects, one ~50 min capture run, `bulk-xfail`, classify
bootstrap+export, coverage scan/validate/report — session A tooling
handled the module-sized expansion unchanged. 6,287 reftests ingested;
408 pass (6.5% — CSS2 predates the reftest style guide, test/ref
differ in prose and markup), 5,879 xfail (bounds 43%, tag-agnostic
17%, content-text 13%, style 14%; TRIAGE.md session C section).
Diagnosed an extractor crash class (8 tests corpus-wide): null
`document.head` in XML documents without an explicit `<head>`; fix
queued in backlog.
Suite: 13,370 → 19,657 (+6,287), 3,189 pass, 16,468 xfail, 0 fail;
coverage gate 19,657/19,657 exact.

## 2026-08-17 — WPT campaign session B: mismatch reftests as negative controls

274 mismatch-only reftests ingested with inverted verdicts (Diff →
pass, Equivalent → measured false negative); `reftest_kind` in
discovery, pure `cache_status` mapping in verdict space (report mode
kind-agnostic), 86 mixed tests flagged match-only, tooling synced.
**Measured sensitivity: 174/274 (63.5%)**; the 99 false negatives are
classified into 17 `sensitivity:` xfail categories (TRIAGE.md), 80
recoverable by whitelist extension (queued in backlog). The controls'
first run caught a harness bug: `.xht` served as text/html drops
CDATA-wrapped styles on BOTH sides — match tests passed trivially,
only t31-color-text-a (mismatch) could notice. Fixed
(application/xhtml+xml), 2,723 results recaptured, 10 stale xfails
pruned, 49 trivial passes became honest xfails.
Suite: 13,096 → 13,370 (+274), 2,781 pass, 10,589 xfail, 0 fail;
coverage gate 13,370/13,370 exact. Commits `af61812`, `dee5903`,
`b8a6100`, `153a895`, `fec26f4`.

## 2026-08-17 — WPT campaign session A: discovery fixes and shared tooling

Reftest link parsing rewritten (unquoted attributes, either attribute
order, rel token lists, case-insensitive names, malformed-tag recovery);
discovery collects ALL match references and the runner implements WPT
alternates semantics (pass if any reference matches). fetch.sh re-syncs
the sparse checkout from local git objects when groups change, without
refetching or clearing the result cache. `wpt_classify.py bulk-xfail`
durably recreates the bulk triage step. Two parser bugs found and
regression-tested: greedy `[^>]*` swallowing a match link after a
malformed tag, and bare attribute values truncated at `/`.
Suite: 12,909 → 13,096 tests (+187), 2,646 pass, 10,450 xfail, 0 fail;
coverage gate 13,096/13,096 exact. Commits `a022282`, `6aabf18`.

## 2026-08-17 — WPT corpus coverage analyzer

`wpt_coverage.py` scans the entire WPT tree at the pinned commit via
git plumbing (79,222 candidates in ~3 s), replicates discovery
semantics exactly (validated path-for-path against classification.json),
and attributes every file to an inclusion/exclusion category.
COVERAGE.md quantifies the gaps; the ingestion campaign
(`plans/wpt-ingestion-campaign.md`) was scoped from it. Commit `136df0c`.
