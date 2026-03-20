# sosie — implementation plan

## Principle

Each step produces something runnable and testable. Real ocaml.org pages are
touched as early as possible — the biggest risk is that CDP doesn't give us
what we think it gives us, and no amount of design can substitute for looking
at real data.

Steps are ordered by dependency and information value. Steps that reduce
uncertainty come first. Steps that add polish come last.

## Starting point

- The design document (`sosie-design.md`) describes the target.
- No code exists.
- ocaml.org can be built and served locally (`make build && make start`).
- Chromium is available on the development machine.

---

## Step 0: Project scaffold

Set up the OCaml project structure: dune-project, opam file, library
structure. Minimal dependencies to start: `yojson` (JSON parsing),
`eio` (async runtime). No WebSocket library yet — that's step 1.

**Output:** An OCaml project that builds and runs `sosie --version`.

**Test:** `dune build` succeeds.

---

## Step 1: JS extractor + CDP bridge

Two things in parallel, because they serve different roles:

### Step 1a: The JS extractor (reference implementation)

Write the JavaScript function that walks the DOM and collects snapshot data
using standard Web APIs. This is the **canonical definition** of "what sosie
captures" and runs in any browser.

```javascript
function sosieCapture(properties) {
  // TreeWalker over document.documentElement
  // For each element: getBoundingClientRect(), getComputedStyle()
  // For pseudo-elements: getComputedStyle(el, '::before'), etc.
  // Return structured JSON matching sosie's snapshot schema
}
```

**Test:** Open the browser console on `http://localhost:8080/`, paste the
function, run it, inspect the JSON output. Do this on **Chromium and
Firefox** (and Safari if available). Verify the output schema is identical
across engines. This is the first cross-engine validation — before writing
any OCaml.

### Step 1a addendum (2026-03-20): js_of_ocaml extractor

The raw JS extractor duplicates the OCaml snapshot types and property
whitelist in an untyped language. This is a type-safety gap that undermines
the design's trust model. The corrected approach: compile the extractor from
OCaml via js_of_ocaml, sharing the snapshot types with the native code.

The raw JS extractor (`js/sosie-capture.js`) is retained as a test oracle.
A new Step 1c (below) introduces the JSOO extractor. Once validated, the
raw JS is retired and the JSOO output becomes the canonical extractor.

### Step 1b: CDP bridge (Chromium automation)

Launch Chromium headless, connect via WebSocket, send CDP commands.
Start with `Browser.getVersion`. Then use `Runtime.evaluate` to execute
the JS extractor from Step 1a.

**Dependencies:** WebSocket library (originally `httpun-ws-eio`, replaced
in Step 1d with a hand-rolled blocking client over Unix sockets).

**Output:** A module `Cdp` with:
- `connect : unit -> connection`
- `send : connection -> string -> Yojson.Safe.t -> Yojson.Safe.t`
- `close : connection -> unit`
- `evaluate_js : connection -> string -> Yojson.Safe.t`

**Risk reduction:** This is where we learn if the WebSocket library works,
if Chromium's CDP port is reliable, if the JSON encoding/decoding is correct.

---

## Step 1c: js_of_ocaml extractor (replaces raw JS)

Replace the hand-written `js/sosie-capture.js` with an OCaml
implementation compiled to JavaScript via js_of_ocaml. This eliminates
the type-safety gap between the extractor and the snapshot schema.

### Shared types library (lib_shared/)

Extract `snapshot`, `node`, `rect`, `visual_properties`, `css_value`, and
the property whitelist into a pure OCaml library with no platform
dependencies. This library is compiled to both native (for the CLI/parser)
and JavaScript (for the extractor).

### JSOO extractor (js_extractor/)

A `js_of_ocaml` executable (`(modes js)`) that uses `js_of_ocaml`'s DOM
bindings to walk the DOM and build typed `snapshot` values. Same logic as
the raw JS extractor, but type-checked against the shared types. Compiles
to a single `.js` file exposing `sosieCapture()`.

### Validation

Both extractors (raw JS and JSOO) are run on the same pages. Their
outputs must be structurally equal after parsing. Once validated, the raw
JS is retired and the JSOO extractor becomes canonical.

**Dependencies:** `js_of_ocaml`, `js_of_ocaml-compiler`, `js_of_ocaml-ppx`.

**Output:** `js_extractor/extractor.bc.js` — drop-in replacement for
`js/sosie-capture.js`.

**Test:** Integration test comparing raw JS vs JSOO output on identical
pages. Structural equality after parsing into `Snapshot_types.snapshot`.

See `plans/jsoo-extractor-refactor.md` for the detailed implementation
plan.

---

## Step 1d: Replace Eio + httpun-ws with blocking Unix WebSocket

**Motivation:** The CDP bridge pulled in Eio, httpun-ws-eio, httpun-ws,
httpun, gluten-eio, gluten, faraday, angstrom, bigstringaf — 76+
transitive packages. sosie's usage is strictly sequential: one CDP
command at a time, blocking until the response arrives. The entire async
machinery existed only because `httpun-ws-eio` required it.

**What was done:**
- New `lib/ws.ml` (~170 lines): RFC 6455 blocking WebSocket client over
  `Unix.file_descr`. Handshake via `Digestif.SHA1` + `Base64`. Frame
  read/write with masking. Continuation frame reassembly. Ping/Pong.
- Rewrote `lib/cdp.ml`: connection is `{ ws: Ws.t; next_id; events }`.
  No promises, no mutex, no fibers. Blocking `Ws.recv` loop.
- Rewrote `lib/cdp_launcher.ml`: `Unix.create_process` + `Unix.pipe`
  for Chromium launch, `Unix.open_connection` for HTTP, `Unix.sleepf`
  for retries. New `with_chromium` bracket API.
- Removed all Eio boilerplate from `bin/main.ml` and integration tests.

**Dropped direct deps:** `eio`, `eio_main`, `eio.unix`, `httpun-ws-eio`,
`httpun-ws`, `httpun`, `bigstringaf`.

**Kept:** `digestif` (SHA-1 for handshake), `base64` (nonce encoding).

**Test:** 10 new frame round-trip tests in `test/test_ws.ml`. All 43
unit tests pass. Integration tests updated (Eio boilerplate removed).

---

## Step 2: Raw capture — get a snapshot from ocaml.org [done]

Run the JS extractor on a real page via CDP's `Runtime.evaluate`.
Capture module (`lib/capture.ml`) wraps the full sequence: launch Chromium,
navigate, wait for fonts, evaluate the JSOO extractor, return parsed JSON.

**Output:** `Capture.capture` function returning `Yojson.Safe.t`.
Integration tests validate the schema on `about:blank`.

**Test:** Integration tests verify: version=1, root tag=HTML, correct
viewport and color scheme. Manual inspection on real pages confirmed
the extractor captures all whitelisted properties correctly.

---

## Step 3: Snapshot parsing and serialization [done]

Parse the JS extractor's JSON output into the typed AST: `node`, `rect`,
`css_value`, `visual_properties`, `snapshot`. Serialize back to JSON.
Pretty-print for debugging.

**Output:** Module `Snapshot` (`lib/snapshot.ml`) with:
- `type t = Snapshot_types.snapshot`
- `of_json : Yojson.Safe.t -> t` (parse JS extractor output)
- `to_json : t -> Yojson.Safe.t` (serialize, round-trip faithful)
- `pp : Format.formatter -> t -> unit` (human-readable debug output)

All CSS values stored as `Str` at parse time — typed parsing (Px, Num,
Color) deferred to the normalization step (Step 5).

**Unit tests** (20 tests in `test/test_snapshot.ml`):
- Round-trip: `of_json (to_json s) = s` at JSON string level
- Parsing edge cases: null text, empty children, `#text` tag, attributes
- Error cases: missing version, wrong version, malformed viewport/bounds
- Format fidelity: serialized JSON matches known-good fixtures
- Integration: capture → `of_json` → typed snapshot verified

---

## Step 4: Snapshot round-trip generator (trust bootstrap)

Before building comparison, build the trust mechanism.

Implement the generator `G : Snapshot → HTML` that produces minimal HTML
with absolute positioning and inline styles from a snapshot. Then implement
the round-trip test: generate HTML from a snapshot, capture it via CDP,
parse, compare to the original.

Start with a single hand-crafted snapshot (one div with known bounds, color,
font-size). Verify C ∘ G = id for that one case. Then generalize to
QCheck-generated snapshots.

**Output:** Module `Gen` with:
- `snapshot_to_html : Snapshot.t -> string`
- A QCheck test: `prop_round_trip`

**Test:** The round-trip property holds for random snapshots. Each failure
is a concrete counterexample showing which property doesn't survive the
round-trip.

**Why now, not later:** This validates the capture pipeline (steps 1-3)
before we build on top of it. If round-trips fail, we fix the capture code.
If they pass, we have high confidence in the foundation.

---

## Step 5: Normalization

Implement the normalization rules: `Drop_attributes`, `Mask_text`,
`Round_bounds`, `Canonicalize_colors`, `Canonicalize_fonts`,
`Sort_attributes`, `Drop_subtree`, `Mask_text_matching`.

Each rule is a `snapshot -> snapshot` function. The full normalizer applies
all rules from a config.

**Output:** Module `Normalize` with:
- `type rule` (the normalize_rule type from the design)
- `apply : rule list -> Snapshot.t -> Snapshot.t`
- Config file parsing moved to Step 7 (`Config` module, JSON format).

**Write a first `sosie.json` for ocaml.org:** mask dates, drop class
attributes, drop dynamic feed, round bounds to 0.5px. This config will be
refined throughout the project as we learn what varies between captures.

**Test:**
- Unit tests for each rule (construct snapshot, apply, check result).
- Idempotency: `apply rules (apply rules s) = apply rules s` (QCheck).
- Commutativity of independent rules (QCheck).
- **On ocaml.org:** Capture the same page twice with normalization. If the
  normalized snapshots are identical, determinism holds. If not, the diff
  tells us what normalization rule we're missing.

---

## Step 6: Basic comparison (lockstep)

Before GumTree, implement a simple lockstep tree comparison. Walk both
trees in parallel, report diffs when nodes differ. This is wrong for
structural changes (it will report false diffs on wrapper insertions), but
it's correct for the first use case: **same HTML structure, different CSS**.

This is enough to start refactoring ocaml.org CSS classes.

**Output:** Module `Compare` with:
- `type diff` (the diff type from the design, minus `Wrapper_inserted` etc.)
- `compare : config -> Snapshot.t -> Snapshot.t -> diff list`

**Test:**
- Unit tests from the test matrix (identical, text change, style change,
  bounds tolerance).
- **On ocaml.org:** Capture main branch, capture a branch where one CSS
  class is renamed (a trivial refactoring). With `drop_attributes: [class]`,
  expect zero diffs. This is the first end-to-end validation of the full
  pipeline on real data.

---

## Step 7: CLI and first real refactoring [done]

Wire everything into a CLI: `sosie capture`, `sosie compare`,
`sosie capture-all`.

Use it on an actual ocaml.org refactoring: extract a CSS component class
(e.g., the "Learn" page hero section). Capture baseline, refactor, capture
modified, compare.

**Output:** A working CLI that can capture and compare ocaml.org pages.

**Validation:** The first real refactoring proves the tool is useful (or
reveals what's missing). This is where we learn:
- Is the normalization config complete? (If not, we see noise diffs.)
- Is the property whitelist complete? (Run `audit-whitelist` mentally — we
  haven't built the visual tool yet, but we can inspect the diff output.)
- Are the tolerance values right?
- How long does capture take? Is it fast enough for CI?

This step produces the first "user story": a developer refactors CSS, runs
sosie, sees zero diffs (or sees exactly the diffs they introduced).

### Step 7 addendum (2026-03-20): JSON config instead of YAML

The design doc originally specified YAML for `sosie.yml`. The project has
no YAML dependency, and the config schema maps directly to JSON. Since
`yojson` is already a dependency, we use JSON (`sosie.json`) to avoid
adding a YAML library. The schema is identical — only the serialization
format changed.

Implemented modules:
- `Config` (`lib/config.ml`): JSON config parser → normalize rules + compare config.
  Supports selector parsing (`#id`, `.class`, `tag`, `*`), attribute patterns
  (`exact`, `prefix*`), all normalize rule types, and compare config fields
  with defaults for missing fields.
- `Diff_fmt` (`lib/diff_fmt.ml`): Human-readable diff formatter with
  XPath path rendering and summary with counts by diff type.
- `sosie compare --baseline FILE --modified FILE [--config FILE]`: reads two
  snapshots, normalizes, compares, prints diffs. Exit 0 if equivalent, 1 if
  diffs found (for CI use).
- `sosie capture-all`: batch capture across routes × viewports × schemes,
  reusing a single Chromium instance.

Tests: 16 config tests, 15 diff formatter tests. All 176 tests pass.

---

## Step 8: GumTree matcher [done]

Replace the lockstep comparison with the three-phase GumTree matcher.

- Phase 1: bottom-up structural hashing, greedy matching by hash.
- Phase 2: container matching via dice coefficient on matched descendants.
- Phase 3: children alignment via LCS (using `patience_diff` or a custom
  implementation).

**Test:**
- The unit test matrix from the design (wrapper inserted, removed, child
  reorder, etc.).
- **Bounded exhaustive testing:** Enumerate all tree pairs up to size 4
  (runs in seconds). Check injectivity, symmetry, transitivity, ancestor
  preservation on every pair.
- Extend to size 5 (~11.6M pairs, runs in minutes) for a thorough run.
- **Stratified random testing:** Generate trees from each shape class (path,
  star, caterpillar, balanced, lopsided, uniform, random recursive) at sizes
  100-1000. Check the same properties.

**On ocaml.org:** Re-run the refactoring from Step 7 (if it involved
structural changes) and verify the matcher tolerates wrapper insertions
while still catching visual changes.

### Step 8 addendum (2026-03-20): implementation notes

Implemented without new dependencies — LCS is ~40 lines of standard DP,
structural hashing uses `Hashtbl.hash`.

New modules:
- `Lcs` (`lib/lcs.ml`): generic LCS diff with `Keep`/`Insert`/`Delete` edits.
- `Gumtree` (`lib/gumtree.ml`): three-phase matcher. Phase 1 matches by
  structural hash (unique hashes matched directly, ambiguous hashes
  disambiguated by parent match and sibling index). Phase 2 matches
  remaining nodes by dice coefficient (threshold 0.5). Phase 3 aligns
  children of matched pairs via LCS.

Design decision: roots are always matched (anchored) if they share the same
tag. Without this, the dice threshold can fail on small trees where one extra
child pushes the coefficient below 0.5.

New diff variants: `Moved_node`, `Wrapper_inserted`, `Wrapper_removed`.
The lockstep `Compare.compare` is preserved. `Compare.compare_matched` is
the new default used by the CLI. `Diff_fmt` accepts optional `~root_b` for
formatting diffs that reference positions in both trees.

The original plan called for `patience_diff` for LCS — replaced with a
hand-rolled DP implementation to avoid pulling in `base` + `core` + `ppx_jane`.

Tests: 12 LCS unit tests, 12 GumTree unit tests (identical trees, text/style
changes, wrapper inserted/removed, extra child, deep identical subtrees, hash
collision siblings, tag change, child reorder, bounds tolerance), 5 QCheck
property tests (self-comparison empty, injectivity, tolerance monotonicity,
matching count symmetry, ancestor preservation). 3 new diff_fmt tests for
the new diff types.

Bounded exhaustive testing and stratified random testing completed.
`test/test_exhaustive.ml` runs via `dune build @exhaustive`. Enumerates all
ordered labeled trees up to size 5 with 3 tags (3402 trees at size 5,
~15M pairs total). Checks injectivity, symmetry, ancestor preservation, and
self-match completeness on all pairs — all pass at 0% violation rate.
Stratified random tests cover 5 shape classes (path, star, caterpillar,
balanced binary, left comb) at sizes 50/100/200 with 3 perturbations (swap,
wrap, remove leaf). Exhaustive test dumps OCaml source for failing witnesses
when properties are violated (up to 3 per property).

Additional unit tests: child reorder matching, bounds tolerance suppression.
Additional QCheck tests: matching count symmetry, ancestor preservation.

### Step 8 addendum (2026-03-20): symmetrization and ancestor repair

Exhaustive testing at size 5 revealed that the raw GumTree matcher violated
symmetry on 0.11% of pairs and ancestor preservation on a larger fraction.
Both are inherent to the greedy, directional algorithm (Phase 1 iterates
only hashes from tree A; Phase 2 iterates only unmatched A nodes).

Fix: post-processing pipeline in `match_trees`:
1. **Intersection**: run `match_directed(A→B)` and `match_directed(B→A)`,
   keep only pairs agreed upon by both. Guarantees symmetry.
2. **Bidirectional ancestor repair**: for each matched pair, walk ancestors
   in A and verify partners are ancestors in B; then walk ancestors in B
   and verify partners are ancestors in A. Remove violating pairs (leaves
   first). Uses pre/post-order numbering for O(1) ancestry queries.

Both steps only remove matches, never add — unmatched nodes surface as
`Extra_node` diffs (false positives, not false negatives), consistent with
the design's trust model. Cost: 2× matching time + O(n × depth) repair.

After the fix, all four invariants (injectivity, symmetry, ancestor
preservation, self-match completeness) hold on all 15M exhaustive pairs
and all stratified random tests.

---

## Step 9: Mutation testing and sensitivity measurement

Build the CSS mutation harness. For a set of ocaml.org pages:
1. Capture baseline.
2. For each page, for each element, for each whitelisted property: apply a
   mutation (change the value), capture, compare.
3. Filter equivalent mutants (pixel diff unchanged).
4. Compute the mutation score.

**Output:** `sosie mutate` command and a mutation score report.

**Validation:** The mutation score tells us how sensitive sosie actually is
on real ocaml.org pages. If it's below 100%, the surviving mutants tell us
exactly what's wrong (tolerance too high? property not being compared?
matcher losing the element?).

This is the step where the tool earns quantitative trust.

---

## Step 10: Visual tooling

Build the visual tools in order of value:

1. **`audit-whitelist`** — the blind-spot detector. Inject a reset
   stylesheet for non-whitelisted properties, screenshot, pixel-diff.
   Run on a few ocaml.org pages and verify the whitelist covers
   everything visible.

2. **`diff-view`** (HTML report) — spatial diff visualization. Side-by-side
   pages with highlighted elements, click-to-inspect tooltips. Make this the
   default output for `sosie compare`.

3. **`show-config`** — normalization overlay. Open a page in headed Chromium
   with visual annotations of masked text, dropped subtrees, etc.

**On ocaml.org:** Use `audit-whitelist` on the homepage, /learn, /install,
/packages. If the blind-spot pixel diff is empty, the whitelist is complete
for ocaml.org. If not, add the missing properties.

---

## Step 11: CI integration for ocaml.org

Write a CI job (GitHub Actions) that:
1. Checks out main, builds, serves, captures baseline.
2. Checks out the PR branch, builds, serves, captures modified.
3. Runs `sosie compare`, posts the HTML report as a PR comment (or as a
   CI artifact).
4. Fails the job if diffs are found (configurable: fail on any diff, or
   only on style/bounds diffs, ignoring structural-only diffs).

**Validation:** The CI job runs on a real ocaml.org PR. If the refactoring
is UI-conservative, the job passes. If not, the HTML report shows exactly
what changed.

This is the deliverable: a PR check that blocks visual regressions.

---

## Step 12: Harden

With ocaml.org working as the testbed, address remaining items:

- **Error handling:** Chromium crash recovery, page 404s, WebSocket
  timeouts. These surface during CI runs on real PRs.
- **Snapshot versioning:** Add version field, refuse to compare across
  versions.
- **`sosie self-test`:** Package the round-trip tests, fixture pages, and
  bounded exhaustive tests into a self-test command that users can run to
  verify their environment.
- **Performance:** Profile capture-all on the full ocaml.org route list
  (~50 routes × 3 viewports × 2 schemes = 300 captures). Optimize if
  needed (parallel tabs, incremental capture).

---

## Step 13: npm distribution (esbuild model)

Once sosie works and is validated on ocaml.org, distribute it to the
wider web ecosystem. The goal: `npx sosie capture --url http://localhost:3000`
works on a fresh machine with only Node.js installed.

### Cross-compilation

Set up CI builds for all target platforms:
- `linux-x64` (GitHub Actions, most CI)
- `linux-arm64` (ARM servers, Graviton)
- `darwin-x64` (Intel Mac)
- `darwin-arm64` (Apple Silicon)
- `win32-x64` (Windows, if feasible)

OCaml's native compiler produces static binaries. Cross-compilation via
`dune` + `ocaml-cross` or separate CI runners per platform.

### npm package structure

```
sosie/                         # main package (thin loader)
  package.json
  bin/sosie                    # JS script: detect platform, exec binary
@sosie/cli-linux-x64/         # platform packages (optionalDependencies)
  package.json
  bin/sosie                    # native OCaml binary
@sosie/cli-darwin-arm64/
  ...
```

The main `sosie` package declares platform packages as
`optionalDependencies`. npm installs only the one matching the user's
platform. The `bin/sosie` script finds and execs the native binary.

### Bundled Chromium

On first run or during `npm install`, auto-download a revision-locked
Chromium:
- Use the Chrome for Testing download API (same mechanism as Puppeteer).
- Cache in `~/.cache/sosie/chromium/` (XDG-compliant).
- Pin the exact Chromium revision in the sosie release — every developer
  and CI run uses the same browser build.
- Override via `SOSIE_CHROMIUM_PATH` for managed environments.

### GitHub Action

```yaml
- name: UI Equivalence Check
  uses: sosie-org/sosie-action@v1
  with:
    baseline: ./snapshots-main
    current: ./snapshots-pr
    config: sosie.json
```

The action bundles the sosie binary and pinned Chromium. Zero setup for
the user.

### Documentation for adopters

- Quick start: `npx sosie capture --url ...` in 30 seconds.
- `sosie.json` reference with examples for common frameworks (Next.js,
  Rails, Django, static sites).
- Normalization presets for common framework noise.
- Migration guide from BackstopJS / Percy / Chromatic.

### Contributor on-ramp

The OCaml implementation is invisible to users. It surfaces in:
- `sosie self-test` output: "Powered by OCaml"
- Error messages that are precise enough to be notable
- `CONTRIBUTING.md` with opam/dune setup instructions for contributors

---

## Step 14: Multi-engine support (Firefox, Safari)

With the JS extractor already working (written in Step 1a, tested across
engines from day 1), adding Firefox and Safari requires only a new
automation backend.

### WebDriver client

Implement a minimal WebDriver client in OCaml (HTTP-based, simpler than
CDP's WebSocket):
- `POST /session` — create a session with the target browser
- `POST /session/{id}/url` — navigate
- `POST /session/{id}/execute/sync` — run the JS extractor
- `DELETE /session/{id}` — close

WebDriver is a W3C standard. Firefox (geckodriver), Safari (safaridriver),
and Chromium (chromedriver) all support it.

### CLI integration

```
sosie capture \
  --url http://localhost:8080/learn \
  --engine firefox \
  --config sosie.json \
  --output snapshots/learn-firefox.json

sosie capture-all \
  --engines chromium,firefox,webkit \
  --base-url http://localhost:8080 \
  --routes routes.txt \
  --config sosie.json \
  --output snapshots/
```

The comparison is always same-engine before vs. after:
```
sosie compare \
  --baseline snapshots-main/ \
  --modified snapshots-pr/ \
  --config sosie.json
```

This compares `learn-chromium-before` vs. `learn-chromium-after`, then
`learn-firefox-before` vs. `learn-firefox-after`, etc. Cross-engine
comparison is not performed.

### Validation

Run the same ocaml.org refactoring from Step 7 on all three engines.
If the refactoring is truly UI-conservative, it should produce zero diffs
on every engine. If it produces diffs on Firefox but not Chromium, that's
a real cross-engine regression that sosie caught — and that Chromium-only
testing would have missed.

---

## Milestone map

| | Step | Milestone | Depends on | Key risk addressed |
|---|------|-----------|------------|-------------------|
| [x] | 0 | Project builds | — | — |
| [x] | 1a | Raw JS extractor works in browser console | 0 | Snapshot schema correct across engines |
| [x] | 1b | CDP bridge works | 0 | WebSocket + CDP protocol |
| [x] | 1c | JSOO extractor replaces raw JS | 1a | Type safety, schema consistency |
| [x] | 1d | Blocking Unix WebSocket (drop Eio) | 1b | Dependency minimization |
| [x] | 2 | Raw snapshot via capture pipeline | 1b, 1c | JS extractor works end-to-end |
| [x] | 3 | Typed AST with round-trip parsing | 2 | Snapshot parsing correctness |
| [x] | 4 | Round-trip tests pass | 3 | Capture pipeline fidelity |
| [x] | 5 | Normalization on real pages | 3 | Deterministic snapshots |
| [x] | 6 | First comparison works | 3, 5 | Diff detection on real pages |
| [x] | 7 | First real refactoring validated | 6 | **Tool is useful** |
| [x] | 8 | GumTree matcher works | 6 | Structural changes tolerated |
| [ ] | 9 | Mutation score measured | 7 | **Tool is trustworthy** |
| [ ] | 10 | Visual tooling | 7 | Human review is visual |
| [ ] | 11 | CI integration for ocaml.org | 7 | **Tool is deployed** |
| [ ] | 12 | Hardening | 11 | Production readiness |
| [ ] | 13 | npm distribution + GitHub Action | 12 | **Mass adoption** |
| [ ] | 14 | Multi-engine (Firefox, Safari) | 12 | **Browser diversity** |

Steps 1-7 form the critical path to a working tool on ocaml.org.
Steps 8-12 improve it and make it production-ready.
Steps 13-14 take it to the wider ecosystem.

The JSOO extractor (Step 1c) is the canonical and only capture primitive.
CDP is used solely as an automation transport (navigate + `Runtime.evaluate`).
Multi-engine support (Step 14) adds a WebDriver automation backend — no
changes to extraction, normalization, or comparison.

### Parking lot

- **CDP DOMSnapshot fast path.** `DOMSnapshot.captureSnapshot` could provide
  an alternative, more efficient capture path on Chromium (single atomic call,
  column-oriented format with string deduplication). Requires a dedicated
  parser. Deferred until capture latency becomes a bottleneck.

Key moments:
- **Step 1c** — JSOO extractor replaces raw JS. Type safety achieved.
- **Step 7** — first real refactoring validated. The tool is useful.
- **Step 9** — mutation score measured. The tool is trustworthy.
- **Step 11** — CI integration. The tool is deployed on ocaml.org.
- **Step 14** — multi-engine. Refactorings validated on all target browsers.
