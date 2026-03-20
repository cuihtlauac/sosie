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

### Step 1b: CDP bridge (Chromium automation)

Launch Chromium headless, connect via WebSocket, send CDP commands.
Start with `Browser.getVersion`. Then use `Runtime.evaluate` to execute
the JS extractor from Step 1a.

**Dependencies:** WebSocket library (`httpun-ws-eio` or hand-rolled).

**Output:** A module `Cdp` with:
- `connect : unit -> connection`
- `send : connection -> string -> Yojson.Safe.t -> Yojson.Safe.t`
- `close : connection -> unit`
- `evaluate_js : connection -> string -> Yojson.Safe.t`

**Risk reduction:** This is where we learn if the WebSocket library works,
if Chromium's CDP port is reliable, if the JSON encoding/decoding is correct.

---

## Step 2: Raw capture — get a snapshot from ocaml.org

Run the JS extractor on a real ocaml.org page via CDP's `Runtime.evaluate`.
Save the raw JSON to a file and inspect it manually.

Also run the CDP-native `DOMSnapshot.captureSnapshot` and save that JSON
separately. Compare the two outputs for the same page — they should contain
the same data in different formats. This validates the JS extractor against
CDP's native snapshot.

**Output:** Two raw JSON snapshots of `http://localhost:8080/`:
- `snapshot-js.json` (from JS extractor)
- `snapshot-cdp.json` (from DOMSnapshot.captureSnapshot)

**Test:** Manual inspection. Questions to answer:
- Do both contain the same elements with the same bounds?
- Do computed style values match between the two?
- How big is each? (the JS output is likely larger — no string table
  deduplication — but that's fine for correctness)
- Are pseudo-elements captured by the JS extractor?

**This is the most important step.** It tells us whether the JS extractor
works correctly and whether it agrees with CDP's native snapshot.

---

## Step 3: Tree reconstruction

Parse the snapshot JSON into the typed AST: `node`, `rect`, `css_value`,
`visual_properties`, `snapshot`.

Two parsers:
- `of_js_json` — parses the JS extractor's output format (primary, used
  for all engines)
- `of_cdp_json` — parses CDP's column-oriented format (Chromium optimization)

Both produce the same `Snapshot.t`. The test is that they produce identical
results for the same page.

**Output:** Module `Snapshot` with:
- `type t` (the snapshot type from the design)
- `of_js_json : Yojson.Safe.t -> t`
- `of_cdp_json : Yojson.Safe.t -> t`
- `to_json : t -> Yojson.Safe.t` (serialize for saving to disk)
- `of_json : Yojson.Safe.t -> t` (deserialize)
- `pp : Format.formatter -> t -> unit` (pretty-print for debugging)

**Test on ocaml.org:** Parse both raw JSONs from Step 2 into `Snapshot.t`.
Assert they are equal. Pretty-print and verify against what the browser
shows.

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
    config: sosie.yml
```

The action bundles the sosie binary and pinned Chromium. Zero setup for
the user.

### Documentation for adopters

- Quick start: `npx sosie capture --url ...` in 30 seconds.
- `sosie.yml` reference with examples for common frameworks (Next.js,
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
  --config sosie.yml \
  --output snapshots/learn-firefox.json

sosie capture-all \
  --engines chromium,firefox,webkit \
  --base-url http://localhost:8080 \
  --routes routes.txt \
  --config sosie.yml \
  --output snapshots/
```

The comparison is always same-engine before vs. after:
```
sosie compare \
  --baseline snapshots-main/ \
  --modified snapshots-pr/ \
  --config sosie.yml
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

| Step | Milestone | Depends on | Key risk addressed |
|------|-----------|------------|-------------------|
| 0 | Project builds | — | — |
| 1a | JS extractor works in browser console | 0 | Snapshot schema correct across engines |
| 1b | CDP bridge works | 0 | WebSocket + CDP protocol |
| 2 | Raw snapshot from ocaml.org | 1a, 1b | JS and CDP outputs agree |
| 3 | Typed AST from real data | 2 | Tree reconstruction correctness |
| 4 | Round-trip tests pass | 3 | Capture pipeline fidelity |
| 5 | Normalization on real pages | 3 | Deterministic snapshots |
| 6 | First comparison works | 3, 5 | Diff detection on real pages |
| 7 | First real refactoring validated | 6 | **Tool is useful** |
| 8 | GumTree matcher works | 6 | Structural changes tolerated |
| 9 | Mutation score measured | 7 | **Tool is trustworthy** |
| 10 | Visual tooling | 7 | Human review is visual |
| 11 | CI integration for ocaml.org | 7 | **Tool is deployed** |
| 12 | Hardening | 11 | Production readiness |
| 13 | npm distribution + GitHub Action | 12 | **Mass adoption** |
| 14 | Multi-engine (Firefox, Safari) | 12 | **Browser diversity** |

Steps 1-7 form the critical path to a working tool on ocaml.org.
Steps 8-12 improve it and make it production-ready.
Steps 13-14 take it to the wider ecosystem.

The JS extractor (Step 1a) is written and tested across engines from day 1.
Multi-engine support (Step 14) is a natural extension that adds a WebDriver
automation backend — no changes to extraction, normalization, or comparison.

Key moments:
- **Step 1a** — JS extractor tested on Chromium + Firefox. Cross-engine
  correctness validated before any OCaml code.
- **Step 7** — first real refactoring validated. The tool is useful.
- **Step 9** — mutation score measured. The tool is trustworthy.
- **Step 11** — CI integration. The tool is deployed on ocaml.org.
- **Step 14** — multi-engine. Refactorings validated on all target browsers.
