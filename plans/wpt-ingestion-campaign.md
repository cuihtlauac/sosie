# WPT ingestion campaign — ingest everything useful

## Context

COVERAGE.md (commit 136df0c) quantified what sosie's WPT ingestion leaves out:
~185 in-scope tests lost to discovery bugs, 281 in-scope mismatch reftests
usable as negative controls, and 11,271 ready-to-run reftests in non-ingested
modules. The user wants to ingest **as much as is useful**, across several
sessions. Confirmed scope decision: exclude material invisible to
property-level comparison (image decoders, WOFF2, webvtt, html/canvas,
Houdini, animation modules, paged media until print-media emulation exists).
Net target: **≈ +10,300 tests** (corpus 12,909 → ~23k), total capture cost
≈ +1.5–2 h (measured: mean 0.48 s/test, current suite 1.7 h).

Verified mechanics that shape the design:
- The runner caches EVERY non-skip result (`test_wpt_reftests.ml:153`), FAILs
  included, and `--report` recomputes verdicts from cache against *current*
  expectations (`cached_to_outcome`, fail|xfail → Diff). So each expansion is:
  run once (exit 1, all results cached) → bulk-generate xfail expectations →
  `--report` is green. No recapture.
- The original bulk-xfail script (commit ebd1270) was never committed — it
  must be recreated as a durable `wpt_classify.py bulk-xfail` subcommand.
- `fetch.sh` skips everything when `wpt/.commit` matches — changing groups
  without changing the commit does nothing. Sparse re-sync needed.
- The 4 sparse-missing refs resolve to `css/filter-effects/reference/`,
  `css/CSS2/reference/`, `quirks/reference/` — dirs later sessions need anyway.
- `wpt_coverage.py` has an OCaml-fidelity regex tier that must evolve in
  lockstep with `ext_test_lib.ml`, and its validate gate re-checks every
  change against classification.json.

## Campaign structure (one session ≈ one series of commits)

This conversation executes **Session A**; B–E are queued in the committed
campaign plan (`plans/wpt-ingestion-campaign.md`, this file) and the roadmap
gets a **Step 10c: WPT corpus expansion** section describing the campaign.

### Session A — discovery fixes and shared tooling (+~250 tests)

1. **`fetch.sh` sparse re-sync.** Marker becomes `<commit> <sha1-of-sparse-
   patterns>`. On pattern change with same commit: rewrite
   `.git/info/sparse-checkout`, `git read-tree -mu HEAD` (objects are local —
   no network), refresh marker. Result cache NOT cleared on pattern-only
   change (results are keyed by test path; existing captures stay valid).
2. **Unquoted attribute support** in `ext_test_lib.ml` reftest link parsing
   (+181 tests). Replace the two quoted-only regexes with parsing that
   accepts `rel=match` / unquoted hrefs (values terminated by `\s>`).
3. **All match links, alternates semantics** (+68 tests currently compared
   against only their first ref). Discovery collects ALL `rel=match` hrefs
   in document order (`reftest.ref_hrefs : string list`, refs that exist);
   runner tries refs in order, Equivalent on ANY → pass; else cache the
   FIRST ref's diffs (WPT pass-if-any-matches semantics).
4. **Unit tests** (alcotest, per project standards): unquoted variants, both
   attribute orders, multiple links, mixed quoting, nondeterminism
   precedence — edge cases first.
5. **`wpt_classify.py bulk-xfail`**: scan `wpt-results/` for status
   fail/error not in expectations.json; derive reason from dominant
   diff type (reuse `classify_diff`, map via `TAG_TO_REASON`); merge into
   expectations.json. Also `--prune` removes stale xfails whose cached
   status is "pass" (unexpected-pass entries break the report).
6. **Support paths** for the 4 missing refs: add `css/filter-effects/reference/`,
   `css/CSS2/reference/`, `quirks/reference/` to `manifest.json`
   support_paths.
7. **Sync `wpt_coverage.py`** fidelity tier: unquoted parsing + all-links +
   ref-any-exists mirror the new OCaml semantics (former
   `missed-unquoted-rel` / `missed-ref-missing-in-sparse` become included).
8. **Run** the ~250 new tests (`dune exec` the runner; minutes), bulk-xfail,
   classify bootstrap+export, coverage scan+validate (new included count)+
   report, TRIAGE note, roadmap 10c section. Commit in logical units
   (fetch.sh + parsing + tests; tooling; results).

### Session B — mismatch reftests as negative controls (+281)

- Discovery: `rel=mismatch` links (mismatch-ONLY tests; mixed match+mismatch
  stay match-only for now, flagged). `reftest.kind = Match | Mismatch`.
- Runner inverts the verdict for Mismatch tests: Diff → pass ("sosie sees
  the difference WPT asserts"), Equivalent → FAIL — a measured **false
  negative**, sosie's blind spot. Expected blind spots (e.g. property not
  in whitelist) become xfail entries whose reasons enumerate sensitivity
  gaps; that list goes into TRIAGE.md as the sensitivity section (ties to
  roadmap step 9's trustworthiness goal).
- Unit tests for inverted semantics; coverage scanner learns the category.

### Session C — CSS2 (+~6,270, ~1 h capture)

- Add `css/CSS2` to groups; fetch re-sync; run; bulk-xfail; classify;
  category summary appended to TRIAGE.md; regenerate COVERAGE.md.

### Session D — remaining css/* layout & style modules (+~2,600)

- Groups: css-break (1,003), filter-effects (263), css-counter-styles (234),
  selectors (218), css-conditional (160), motion (93), css-highlight-api
  (92), mediaqueries (58), compositing (56), css-scrollbars (31), quirks
  (25), css-scroll-snap (23), compat (23), density-size-correction (20),
  css-rhythm (18), css-nesting (17), css-color-adjust (16), css-style-attr
  (15). Same run/triage/commit cycle.

### Session E — non-CSS trees (+~750)

- Groups: `html/rendering` (170), `html/semantics` (227), `html/dom` (127),
  `mathml` (234), `svg` (168); NOT html/canvas (bitmap assertions).
  Watch for cross-tree ref/support needs (`images/`, already-present
  `common/`, `fonts/`); add support_paths as the missing-ref check dictates.

### Explicitly excluded (record in roadmap 10c + COVERAGE.md context)

Image decoders (png/jpegxl/apng/avif/gif), WOFF2, webvtt, html/canvas,
css-layout-api/css-paint-api (Houdini), css-view-transitions /
web-animations / scroll-animations / animation-worklet (nondeterministic),
css-page + css/printing (paged media — revisit with CDP
`Emulation.setEmulatedMedia`), long tail of modules with <15 recoverable
tests. Rationale: the asserted behavior is invisible to whitelist-property
comparison; ingestion would produce trivial passes or pure xfail noise.

## Files touched (Session A)

| File | Change |
|---|---|
| `test/external/fetch.sh` | sparse-pattern hash in marker, re-sync path |
| `test/external/manifest.json` | +3 support_paths (later sessions: groups) |
| `test/external/ext_test_lib.ml/.mli` | link parsing rewrite, `ref_hrefs` list, alternates |
| `test/external/test_wpt_reftests.ml` | try-each-ref loop |
| `test/external/test/` or dune test stanza | new alcotest unit tests for parsing (pure, no browser) |
| `test/external/wpt_classify.py` | `bulk-xfail` subcommand |
| `test/external/wpt_coverage.py` | fidelity tier sync |
| `test/external/TRIAGE.md`, `COVERAGE.md`, `expectations.json`, `classification.json` | regenerated/updated |
| `sosie-roadmap.md` | Step 10c campaign section |
| `plans/wpt-ingestion-campaign.md` | this plan, committed before work starts |

Note: unit tests for `ext_test_lib` parsing may need the parsing functions
exposed in the .mli (currently internal) — expose `parse_reftest_links` (new
plural) with doc comments rather than testing through discovery.

## Verification (per session)

```
opam exec -- dune build && opam exec -- dune runtest        # unit tests pass
opam exec -- dune exec test/external/test_wpt_reftests.exe  # capture run
python3 test/external/wpt_classify.py bulk-xfail            # expectations
opam exec -- dune exec test/external/test_wpt_reftests.exe -- --report  # green, exit 0
python3 test/external/wpt_classify.py bootstrap && ... export
python3 test/external/wpt_coverage.py scan && validate && report  # 0/0 gate at new count
```

Session A acceptance: discovered count rises 12,909 → ≈13,160; validate gate
0/0 against regenerated classification.json; `--report` exits 0; unit tests
green.
