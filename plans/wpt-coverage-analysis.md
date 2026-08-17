# WPT corpus coverage analysis — is everything valuable included?

## Context

sosie ingests 12,909 WPT reftests (step 10b) from a sparse checkout of 37 css/
modules. The question: **have all WPT tests that bring value to sosie actually
been included?** The answer is measurably "no", but the gaps have never been
quantified. This session builds scaffolding to inventory the *entire* WPT tree
at the pinned commit and attribute every file to a category, producing a
committed coverage report. Scope: **analysis only** (user-confirmed) —
ingestion fixes and corpus expansion become follow-up items informed by the
numbers.

Key facts established during exploration:

- `fetch.sh` does `git fetch --depth 1` (no blob filter) — the local object
  store contains the **full WPT tree** at commit `55d076dca...` (102,838 files,
  77,609 .html/.xht/.xhtml). Verified via `git ls-tree -r HEAD`. So the
  analyzer reads everything with `git cat-file --batch`: zero network, zero
  checkout changes.
- Discovery (`test/external/ext_test_lib.ml:95-200`): .html/.xht/.xhtml only;
  excludes paths with `/reference/` or `/support/` components; excludes files
  matching `@keyframes|animation\s*:|transition\s*:|transition-`; requires a
  *quoted* `<link rel="match">`; takes the **first** match link only; silently
  skips tests whose ref file is absent from the sparse working tree.
- Measured gaps (sparse checkout): ~198 files with unquoted `rel=match`
  (regex bug), 313 `rel="mismatch"` reftests (excluded — but valuable as
  negative controls: sosie MUST diff on those; false negatives are fatal),
  561 fuzzy reftests, ~349 tests dropped for missing refs, WPT alternates
  (multiple match links) and chained refs unhandled, `.svg` reftests invisible.
- Out-of-scope modules (full tree, raw HTML counts): CSS2 (11,362!),
  css-break (1,331), css-view-transitions (703), selectors (656),
  filter-effects (529), css-counter-styles (481), css-page (471); outside
  css/: html/ (10,297 incl. html/rendering), mathml/ (807), svg/ (728).
  How many are *deterministic match-reftests with available refs* is unknown —
  that's what the analyzer computes.

## Step 0 — Commit pending triage work

Commit the uncommitted classification tooling first (clean baseline; its
`classification.json`, 12,909 keys, is the validation ground truth):
`test/external/wpt_classify.py`, `classification.json`, `.gitignore`,
`TRIAGE.md` (+38 lines documenting the classification DB).

## Step 1 — `test/external/wpt_coverage.py` (new, ~550 lines)

Separate script + separate `coverage.db` (NOT extending wpt_classify.py:
its `bootstrap`/`import` delete `classification.db` wholesale, and the corpus
differs — 78k files vs 12,909 tests). Follows wpt_classify.py conventions:
stdlib only, argparse subcommands (`scan`, `validate`, `report`, `summary`,
`query`), same dir. Reads groups from `manifest.json` at runtime (never
hardcoded).

**Scan (git plumbing).** `git -C wpt ls-tree -r -z HEAD` → full-tree path set
(ref-existence checks) + candidate list (.html/.xht/.xhtml/.svg blobs). Stream
contents through a single `git cat-file --batch` subprocess — writer thread
feeds SHAs, main thread reads `<sha> blob <size>\n` + body in request order
(writer thread mandatory to avoid pipe deadlock). Process and discard bodies;
flat memory. Estimated runtime 1.5–3 min for ~78k blobs / ~400 MB.

**Feature extraction — on raw bytes** (never decode bodies; sidesteps WPT's
mixed encodings). Two regex tiers:
- *OCaml-fidelity* (byte-exact ports of ext_test_lib.ml, case-sensitive,
  primary regex tried over whole doc before the alt-order one, nondeterminism
  checked before link parsing) — used for attribution.
- *Broad* (case-insensitive, quoted or unquoted, all hrefs captured in order,
  plus `rel=mismatch`, `<meta name=fuzzy>`, testharness.js, crashtest/manual/
  print heuristics) — used for gap measurement.
Ref resolution mirrors ext_test_lib.ml:171-176: leading `/` → wpt root, else
relative to test dirname; checked against both the sparse worktree
(`os.path.exists`, like `Sys.file_exists`) and the full-tree path set.

**Attribution** — one primary `category` per file, first rule wins:
1. `/reference/` or `/support/` path component → `excluded-support-reference-path`
2. module ∉ 37 groups → `out-of-scope-module` (+ `would_be` = category from
   continuing the chain, giving per-module "value available")
3. `.svg` extension → `not-scanned-svg-extension`
4. no match link: mismatch → `excluded-mismatch-only`; else `not-a-reftest`
   (testharness/crashtest/manual/other flags)
5. nondeterminism regex → `excluded-nondeterministic`
6. broad-but-not-OCaml-regex match → `missed-unquoted-rel`
7. first OCaml href absent from worktree → `missed-ref-missing-in-sparse`
   (ref in full tree) or `missed-ref-truly-absent`
8. → `included`

Orthogonal flags: `fuzzy`, `multiple_match_links` (alternates), `has_mismatch`,
`chained_ref` (post-pass over the in-memory path→hrefs map), `print_reftest`,
`nondet`, `testharness`.

**SQLite schema**: `scan_meta` (commit, timestamp, totals, groups JSON),
`files` (path PK, sha, size, ext, module, in_scope, category, would_be,
ocaml_href, counts + flags), `match_links` (path, ord, href, quoted, resolved,
in_fulltree) for alternates analysis. Single transaction, indexed on category
and (module, category).

## Step 2 — Validate (hard gate)

`validate`: scanner's `included` set must equal `classification.json` keys
(12,909) exactly; print diffs (capped), exit 1 on any. Any diff = scanner bug
(likely Re.Pcre vs Python `re` divergence or worktree drift — `scan` warns if
`wpt/.commit` ≠ manifest commit). Iterate until 0/0 before reporting.
Sanity bands (not exact targets): unquoted ≈198, mismatch-only in-scope ≈313,
fuzzy in-scope ≈561, missed-ref combined ≈349.

## Step 3 — Report

`report` generates two committed artifacts (compaction-resilience rule):
- **`test/external/COVERAGE.md`**: provenance (WPT commit, regen command);
  corpus totals; in-scope waterfall ending at included = 12,909; validation
  result (0/0); gap subsections (each `missed-*` + svg, count + 5 example
  paths + one-line fix sketch); **out-of-scope module table** sorted by
  would-be-included count (the "value available" answer for CSS2, css-break,
  html/rendering, mathml, svg, …); semantic opportunities with numbers
  (mismatch negative controls, fuzzy, alternates, chained refs, print).
- **`test/external/coverage-summary.json`**: same aggregates, machine-readable
  (no per-file rows).

Add `coverage.db` to `test/external/.gitignore`.

## Step 4 — Wrap up

- Commit: `wpt_coverage.py` + `COVERAGE.md` + `coverage-summary.json` +
  `.gitignore` change.
- Add a short addendum pointer in `sosie-roadmap.md` step 10b (coverage
  analysis exists; follow-up candidates: unquoted-rel fix, sparse-checkout ref
  fix, alternates semantics, mismatch negative controls, module expansion) —
  per the learning-from-mistakes convention.

## Files

| File | Action |
|---|---|
| `test/external/wpt_coverage.py` | new — analyzer |
| `test/external/COVERAGE.md` | new, generated, committed |
| `test/external/coverage-summary.json` | new, generated, committed |
| `test/external/.gitignore` | add `coverage.db` |
| `sosie-roadmap.md` | step 10b addendum pointer |
| `ext_test_lib.ml`, `wpt_classify.py`, `fetch.sh`, `manifest.json` | untouched (read-only inputs) |

## Verification

```
python3 test/external/wpt_coverage.py scan        # ~2-3 min
python3 test/external/wpt_coverage.py validate    # included=12909, diff 0/0, exit 0
python3 test/external/wpt_coverage.py report
python3 test/external/wpt_coverage.py query \
  "SELECT category, COUNT(*) FROM files GROUP BY category ORDER BY 2 DESC"
git -C test/external/wpt rev-parse HEAD           # equals report's commit line
opam exec -- dune build                           # untouched OCaml still builds
```

Risks: regex-engine divergence (mitigated by byte patterns + 12,909 hard
gate); cat-file deadlock (writer thread); encodings (bytes-only); CSS2
support/ skew (support exclusion applied before module counts).
