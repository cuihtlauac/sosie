# Changelog

Completed work, most recent first.

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
