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

## Step 1: CDP bridge — talk to Chromium

The foundation. Everything depends on this.

Launch Chromium headless, fetch the WebSocket URL from
`http://localhost:9222/json`, connect via WebSocket, send a CDP command,
receive a response.

Start with the simplest possible CDP call: `Browser.getVersion`. If we get
a JSON response back, the bridge works.

**Dependencies:** WebSocket library (`httpun-ws-eio` or hand-rolled).

**Output:** A module `Cdp` with:
- `connect : unit -> connection`
- `send : connection -> string -> Yojson.Safe.t -> Yojson.Safe.t`
- `close : connection -> unit`

**Test:** `sosie cdp-ping` connects to a running Chromium and prints the
browser version. Manual verification.

**Risk reduction:** This is where we learn if the WebSocket library works,
if Chromium's CDP port is reliable, if the JSON encoding/decoding is correct.
Better to learn this in 100 lines than after building the whole pipeline.

---

## Step 2: Raw capture — get a DOMSnapshot from ocaml.org

Use the CDP bridge to run the full capture sequence on a real ocaml.org page:
`Emulation.setDeviceMetricsOverride`, `Page.navigate`, wait for
`Page.loadEventFired`, `DOMSnapshot.captureSnapshot`.

Don't parse the response into a typed AST yet. Just save the raw JSON to a
file and inspect it manually.

**Output:** A raw JSON snapshot of `http://localhost:8080/` saved to disk.

**Test:** Manual inspection of the JSON. Questions to answer:
- How big is it? (bytes, number of string table entries, number of nodes)
- Does the `parentIndex` array look right? (node 0 is the document root)
- Are pseudo-elements present? With what `nodeName`?
- What does `layout.styles` look like for a known element?
- Are `layout.bounds` in the expected coordinate space?
- Does `layout.nodeIndex` have gaps (elements with no layout)?

**This is the most important step.** It tells us whether the CDP response
matches the design document's description. If it doesn't, we adjust before
building on wrong assumptions.

---

## Step 3: Tree reconstruction

Parse the raw CDP JSON into the typed AST defined in the design:
`node`, `rect`, `css_value`, `visual_properties`, `snapshot`.

This is the column-oriented-to-tree conversion: iterate `parentIndex` in
order, build children lists, look up layout entries via `nodeIndex`, parse
attribute pairs, map `layout.styles` to the `visual_properties` record.

**Output:** Module `Snapshot` with:
- `type t` (the snapshot type from the design)
- `of_cdp_json : Yojson.Safe.t -> t`
- `to_json : t -> Yojson.Safe.t` (serialize for saving to disk)
- `of_json : Yojson.Safe.t -> t` (deserialize)
- `pp : Format.formatter -> t -> unit` (pretty-print for debugging)

**Test on ocaml.org:** Parse the raw JSON from Step 2, pretty-print the
tree, manually verify it matches what the browser shows for a few elements
(check tag names, text content, bounds, a few style values).

**Unit tests:**
- Construct a minimal CDP-shaped JSON by hand, parse it, check the tree.
- Edge cases: `parentIndex = -1`, text nodes, `display:none` elements.
- CSS value parsing: `"16px"` → `Px 16.0`, `"rgb(59,130,246)"` → `Color`.

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
- `of_yaml : string -> rule list` (parse sosie.yml)

**Write a first `sosie.yml` for ocaml.org:** mask dates, drop class
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

## Step 7: CLI and first real refactoring

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

---

## Step 8: GumTree matcher

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

## Step 12: Harden and generalize

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
- **Documentation:** Usage guide, sosie.yml reference, whitelist reference.

---

## Milestone map

| Step | Milestone | Depends on | Key risk addressed |
|------|-----------|------------|-------------------|
| 0 | Project builds | — | — |
| 1 | CDP bridge works | 0 | WebSocket + CDP protocol |
| 2 | Raw JSON from ocaml.org | 1 | CDP response matches expectations |
| 3 | Typed AST from real data | 2 | Tree reconstruction correctness |
| 4 | Round-trip tests pass | 3 | Capture pipeline fidelity |
| 5 | Normalization on real pages | 3 | Deterministic snapshots |
| 6 | First comparison works | 3, 5 | Diff detection on real pages |
| 7 | First real refactoring validated | 6 | **Tool is useful** |
| 8 | GumTree matcher works | 6 | Structural changes tolerated |
| 9 | Mutation score measured | 7 | **Tool is trustworthy** |
| 10 | Visual tooling | 7 | Human review is visual |
| 11 | CI integration | 7 | **Tool is deployed** |
| 12 | Hardening | 11 | Production readiness |

Steps 1-7 form the critical path to a working tool. Steps 8-12 improve it.
The first "real value" moment is Step 7 (a developer uses sosie on an actual
refactoring). The first "trust" moment is Step 9 (quantitative mutation
score). The first "deployment" moment is Step 11 (CI blocks visual
regressions).
