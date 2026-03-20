# sosie — DOM equivalence checker for UI-conservative refactoring

## The problem

Refactoring HTML and CSS under UI preservation is an industry-wide open
problem. Teams routinely need to:

- Extract CSS component classes from monolithic stylesheets
- Migrate design systems (Bootstrap → custom, CSS-in-JS → vanilla CSS)
- Upgrade component libraries across major versions
- Restructure templates into reusable components
- Remove dead CSS rules

All of these change the HTML structure, the CSS rules, or both — while
intending to preserve what the user sees. Yet there is no widely adopted tool
that answers: **"did this refactoring change the visual output?"**

### Why existing tools fail

**Pixel diffing** (BackstopJS, Percy, Chromatic, Playwright screenshots)
compares bitmaps. It is both too strict (subpixel rendering differences across
OS/GPU/font configurations produce false positives) and not structural (a 1px
shift and a color change look the same). Teams learn to ignore the output or
maintain large "acceptable diff" baselines. Flakiness destroys trust.

**CSS diffing** compares stylesheets, not their rendered effect. A refactoring
that produces identical rendering but different source — the whole point of
refactoring — always shows diffs.

**Manual QA** is the most common approach: refactor, eyeball it, hope for the
best. This is why large CSS refactorings are rare, risky, and often abandoned.

## Key requirement: trustworthiness

The value of sosie is the strength of its "equivalent" verdict. If the tool
says two pages render the same, they must render the same. A single false
negative (missed visual regression) that reaches production destroys trust and
makes the tool worthless. Conversely, a small rate of false positives (spurious
diffs) is tolerable — the user inspects the diff, sees it's harmless, moves on.
Noise is annoying; silent breakage is fatal.

This asymmetry drives every design decision:

- **Explicit equivalence scope.** Sosie declares exactly which CSS properties
  it compares (the whitelist) and which it ignores. There is no hidden
  coverage gap — the user knows what is checked and what is not. This is
  unlike pixel diffing where coverage is implicit and opaque.
- **Configurable normalization.** Anything the tool ignores (dynamic content,
  attribute changes, float rounding) is stated in the config file, not buried
  in the implementation. The config is auditable and version-controlled.
- **No approximations in comparison.** Once two nodes are matched, their
  properties are compared exactly (modulo configured tolerance). There is no
  fuzzy matching, no "close enough" heuristic.
- **Conservative tree matching.** The GumTree-style matcher is designed to
  err on the side of reporting diffs. Unmatched nodes are reported, not
  silently dropped. Ambiguous hash collisions are resolved by position, not
  guessed.
- **Deterministic output.** Same inputs → same diffs. No randomness, no
  timing dependence, no environment sensitivity. The normalize step absorbs
  everything that could vary between runs.
- **Testable at every layer.** Pure functions (normalization, matching,
  comparison) are unit-testable without a browser. CDP integration is
  testable with fixture pages. End-to-end is testable with known-equivalent
  and known-different HTML pairs. See the Testing section.

The trust model is: **sosie's "equivalent" verdict is as strong as the
property whitelist is complete.** If the whitelist covers the visual properties
that matter for your project, the verdict is reliable. If it doesn't, sosie
tells you exactly what it checked — you know where the blind spots are.

## Approach

Rendering engines are pure systems: given a fixed `(DOM, Stylesheet,
ViewportSize)`, they compute a deterministic layout tree — a tree of boxes with
absolute positions, dimensions, and resolved style values. This is a fixpoint of
the CSS constraint system. We can capture this fixpoint via the Chrome DevTools
Protocol and compare it structurally.

Sosie:

1. Captures the resolved DOM + layout + computed styles from a browser via CDP
2. Normalizes the snapshot (strips dynamic content, canonicalizes values)
3. Compares two normalized snapshots under a configurable equivalence relation
4. Reports structured diffs or declares equivalence

The tool is framework-agnostic — it captures from URLs. It doesn't care if the
page is React, Next.js, Rails, Django, OCaml/Dream, or static HTML.

### Origin: ocaml.org

The immediate motivation is refactoring EML templates in
[ocaml.org](https://github.com/ocaml/ocaml.org) (extracting CSS component
classes, decomposing large pages into reusable components). But the problem
and the approach are general.

## Formal background

### The CSS rendering pipeline

The W3C spec defines a six-stage value pipeline for every CSS property on every
element:

```
Declared -> Cascaded -> Specified -> Computed -> Used -> Actual
```

- **Computed values**: relative values partly resolved (em to px, currentColor
  to absolute), but percentages may remain. This is what's inherited.
- **Used values**: fully absolute, after layout. `width: 50%` becomes `400px`.
- **Resolved values**: what `getComputedStyle()` returns — a pragmatic hybrid
  (used values for layout properties, computed values for others).

The layout tree is the output of this pipeline: a tree of boxes with concrete
positions and sizes in pixels.

### Academic precedent

**Cassius** (OOPSLA 2016, UW PLSE — Panchekha, Torlak et al.) formalized a
substantial fragment of CSS 2.1 as declarative constraints (quantifier-free
linear real arithmetic). Given a DOM + stylesheet, it generates an SMT formula
whose satisfying assignment gives box positions and dimensions. This enables
verification, debugging, and synthesis of CSS properties.

**VizAssert** (PLDI 2018, UW PLSE) built on Cassius to verify visual properties
("no text is clipped", "all elements fit within the viewport") across all
viewport widths.

**Brucker & Herzberg** formalized the Core DOM and Shadow DOM in Isabelle/HOL,
verifying functional correctness of DOM operations.

### Levels of equivalence

From weakest to strongest:

1. **Semantic equivalence**: same accessibility tree (roles, names, structure).
   Captures meaning, not visual layout.
2. **Layout equivalence**: same box tree with same bounding rectangles. Every
   element occupies the same position and size.
3. **Layout + visual property equivalence**: same bounding boxes *and* same
   visual properties (colors, fonts, borders, shadows, opacity). This catches
   "same layout but the button is now blue."
4. **Pixel equivalence**: same rendered bitmap. Too strict and not structural.

For EML refactoring, **Level 3** is the right target.

## Architecture

### No Playwright dependency

CDP is a WebSocket protocol. Chrome/Chromium ships with it. The only thing
needed is:

1. Launch `chromium --headless --remote-debugging-port=9222`
2. Fetch `http://localhost:9222/json` to get the WebSocket URL
3. Open a WebSocket, send CDP commands as JSON, receive responses

This is doable in OCaml with `httpun-ws` (actively maintained WebSocket
library with eio and lwt backends, by Antonio Nuno Monteiro). No Node.js, no
Playwright, no npm. The system dependency is just Chromium, which CI
environments already have.

Alternative: a hand-rolled WebSocket client (~300 LOC). CDP only needs text
frames over localhost (no TLS, no compression), so the full RFC 6455 is not
needed. This avoids the `httpun` dependency tree but means owning the code.

### Pipeline

```
                    +---------------+
   page URL ------->  Chromium      |
   viewport size    |  --headless   |<---- CDP over WebSocket
   color scheme     |  (system dep) |
                    +-------+-------+
                            |
                    DOMSnapshot.captureSnapshot
                            |
                    +-------v-------+
                    | JSON snapshot |
                    +-------+-------+
                            |
                    +-------v-------+
                    |  Normalize    |  <- strip dynamic content,
                    |  & filter     |     mask dates, etc.
                    +-------+-------+
                            |
                    +-------v-------+
                    |  Canonical    |  <- clean typed AST
                    |  snapshot     |
                    +-------+-------+
                            |
             snapshot A ----+    +---- snapshot B
                        +--------+
                        | Compare |
                        +----+----+
                             |
                       equivalent / diff
```

### The CDP conversation

The full capture sequence is five CDP calls:

```
->  Emulation.setDeviceMetricsOverride   { width: 375, height: 667 }
->  Emulation.setEmulatedMedia           { features: [{name: "prefers-color-scheme", value: "dark"}] }
->  Page.navigate                        { url: "http://localhost:8080/learn" }
<-  Page.loadEventFired                  (wait for this event)
->  Runtime.evaluate                     { expression: "document.fonts.ready",
                                           awaitPromise: true }
<-  result                               (fonts are loaded)
->  DOMSnapshot.captureSnapshot          { computedStyles: [...], includeDOMRects: true }
<-  { strings: [...], documents: [...] }
```

The `document.fonts.ready` wait is essential: web fonts loaded via `@font-face`
may not be ready at `loadEventFired`, causing incorrect font metrics in the
snapshot. This is the same mechanism Puppeteer and Playwright use internally.

The response is a single JSON blob with the full DOM, layout, and styles.
Approximately 50-200ms for a 500-element page.

### DOMSnapshot.captureSnapshot response structure

Column-oriented storage with a shared string table:

```json
{
  "strings": ["div", "class", "container", "Hello", ...],
  "documents": [{
    "documentURL": 0,
    "nodes": {
      "parentIndex": [0, 0, 1, 1, ...],
      "nodeType": [9, 1, 1, 3, ...],
      "nodeName": [5, 12, 18, ...],
      "nodeValue": [-1, -1, -1, 42, ...],
      "attributes": [[], [0,1,2,3], ...]
    },
    "layout": {
      "nodeIndex": [0, 1, 3, ...],
      "styles": [[0,1], [0,2], ...],
      "bounds": [[0,0,1920,50], [8,60,400,200], ...],
      "text": [5, -1, 42, ...],
      "paintOrders": [1, 2, 3, ...],
      "offsetRects": [...],
      "scrollRects": [...],
      "clientRects": [...]
    },
    "textBoxes": {
      "layoutIndex": [2, 2, 5, ...],
      "bounds": [[10,62,100,16], ...],
      "start": [0, 5, 0, ...],
      "length": [5, 8, 12, ...]
    }
  }]
}
```

Key design points:
- **Column-oriented**: parallel arrays, not array of objects
- **Shared string table**: all strings deduplicated; `-1` is the sentinel for
  "no value"
- **Sparse data**: rare properties stored as `RareStringData` /
  `RareBooleanData` (index/value pair arrays, not one entry per node)
- **Layout separate from DOM**: `display:none` elements have no layout entry;
  `layout.nodeIndex[j]` maps layout entry `j` back to DOM node index (sorted,
  binary-searchable)
- **Styles are whitelist-filtered**: `layout.styles[j]` is a parallel array to
  the `computedStyles` request parameter, same order, values as string indices
- **Attributes encoding**: flat alternating `[nameIdx, valueIdx, nameIdx,
  valueIdx, ...]` per node
- **Pseudo-elements**: appear as nodes named `"::before"` / `"::after"`,
  parented to their host element, in document order
- **Shadow DOM**: flattened into the composed (rendered) tree
- **Transforms**: `layout.bounds` reports the post-transform axis-aligned
  bounding box (like `getBoundingClientRect()`); `layout.offsetRects` (when
  present) gives untransformed layout values

### Tree reconstruction from column format

The `parentIndex` array is in document order (depth-first pre-order). The
reconstruction algorithm is:

1. Create a node object for each index `i` from 0 to `len(parentIndex) - 1`
2. `parentIndex[i] = -1` marks root nodes (typically the document node at
   index 0)
3. Iterate indices in ascending order; append node `i` to
   `children[parentIndex[i]]` — the resulting child order is correct because
   nodes appear in document order
4. For each node `i`, look up `layout.nodeIndex` (binary search) to find the
   matching layout entry `j`, if any; attach bounds and styles from `layout`
5. Pseudo-elements `::before` / `::after` appear as regular children in
   document order (before first real child / after last real child)

## Normalization

Between capture and comparison, a **normalize** pass transforms the raw snapshot
into a canonical form. This scopes out everything that shouldn't affect
equivalence.

```ocaml
type normalize_rule =
  | Drop_attributes of attr_pattern list
      (* remove class, style, data-* -- these are expected to change.
         Patterns support prefix matching: "data-*" drops all data- attributes *)
  | Mask_text of { selector: simple_selector; replacement: string }
      (* e.g., mask dates: any <time> element -> "[DATE]" *)
  | Mask_text_matching of { pattern: Re.t; replacement: string }
      (* regex-based: "March 20, 2026" -> "[DATE]" *)
  | Drop_subtree of simple_selector
      (* remove entire subtrees by selector, e.g., "#dynamic-feed" *)
  | Round_bounds of float
      (* round all coordinates to nearest N px, e.g., 0.5 *)
  | Canonicalize_colors
      (* "rgb(59, 130, 246)" and "#3b82f6" -> same canonical form *)
  | Canonicalize_fonts
      (* collapse font-family fallback lists: keep first named font + first
         generic family. "Inter, ui-sans-serif, system-ui, sans-serif" ->
         "Inter, sans-serif". Pure-generic stacks like "system-ui,
         -apple-system, BlinkMacSystemFont" -> "system-ui" *)
  | Sort_attributes
      (* alphabetize attributes so order doesn't matter *)

(* Minimal selector language: tag, #id, .class, * — no combinators.
   Sufficient for normalization rules. Could be replaced with Cascade's
   selector parser later if full CSS selectors are needed. *)
and simple_selector =
  | Tag of string        (* "time", "div" *)
  | Id of string         (* "#planet-feed" *)
  | Class of string      (* ".swiper-wrapper" *)
  | Universal            (* "*" *)

(* Attribute name pattern: exact match or prefix glob ("data-*") *)
and attr_pattern =
  | Exact of string
  | Prefix of string     (* "data-" when written as "data-*" *)

val normalize : normalize_rule list -> snapshot -> snapshot
```

A project-specific config file declares the rules:

```yaml
# sosie.yml for ocaml.org
normalize:
  drop_attributes: [class, style, data-x-*]
  sort_attributes: true
  round_bounds: 0.5
  canonicalize_colors: true
  canonicalize_fonts: true
  mask_text:
    - selector: "time"
      replacement: "[DATE]"
    - selector: ".changelog-body"
      replacement: "[CONTENT]"
  mask_text_matching:
    - pattern: "\\d{4}-\\d{2}-\\d{2}"
      replacement: "[DATE]"
    - pattern: "OCaml \\d+\\.\\d+\\.\\d+"
      replacement: "OCaml [VERSION]"
  drop_subtrees:
    - "#planet-feed"
    - ".swiper-wrapper"
```

Normalization is a pure function: `snapshot -> snapshot`. It runs independently
on both snapshots before comparison. This means:

- Dynamic content never reaches the comparator
- Class attribute changes (the whole point of the refactoring) are invisible
- Floating-point layout noise is absorbed
- Color representation differences are normalized

## Typed AST

```ocaml
type rect = { x: float; y: float; w: float; h: float }

(* CSS values are parsed into typed representations at decode time to avoid
   false diffs from formatting differences ("16px" vs "16.0px", "400" vs
   "400.0") and to enable numeric tolerance in comparison. *)
type css_value =
  | Px of float          (* "16px" -> Px 16.0 *)
  | Num of float         (* "400" -> Num 400.0, for font-weight, opacity, z-index *)
  | Color of int         (* "#3b82f6" / "rgb(59,130,246)" -> Color 0x3b82f6 *)
  | Str of string        (* fallback for anything else *)

type visual_properties = {
  display: css_value;
  visibility: css_value;
  opacity: css_value;
  color: css_value;
  background_color: css_value;
  font_family: css_value;
  font_size: css_value;
  font_weight: css_value;
  line_height: css_value;
  text_align: css_value;
  text_decoration: css_value;
  border_top: border;
  border_right: border;
  border_bottom: border;
  border_left: border;
  border_radius: css_value;
  box_shadow: css_value;
  overflow_x: css_value;
  overflow_y: css_value;
  z_index: css_value;
  cursor: css_value;
}
and border = { width: css_value; style: css_value; color: css_value }

type node = {
  tag: string;
  attributes: (string * string) list;
  bounds: rect;
  styles: visual_properties;
  text: string option;
  paint_order: int;
  children: node list;
}

type snapshot = {
  version: int;          (* snapshot format version; bump on AST changes *)
  url: string;
  viewport: int * int;
  color_scheme: [ `Light | `Dark ];
  root: node;
}
```

## Tree matching and equivalence checker

### Why not lockstep comparison

A naive lockstep walk assumes both trees have identical structure. This breaks
the moment someone wraps an element in a `<div>` — which is the most common
operation in component extraction. We need a matcher that tolerates structural
wrapper changes while detecting true content/visual differences.

### GumTree-style three-phase matching

The comparison uses a simplified GumTree algorithm (Falleri et al., ASE 2014),
adapted for DOM trees. It runs in three phases:

**Phase 1 — Hash matching (O(n)).** Compute a bottom-up structural hash for
every subtree: `hash(node) = H(tag + hash(child_1) + ... + hash(child_k))`.
Build a map from hash to node(s) for both trees. Match identical subtrees
greedily, largest first. This handles 80-95% of nodes in a typical refactoring.
When you wrap `A B C` in a new `<div>`, the subtrees for A, B, C hash
identically and match instantly.

**Phase 2 — Container matching (O(n²) worst, fast in practice).** For each
unmatched node in tree A, compute the fraction of its descendants that are
already matched to descendants of some unmatched node in tree B (dice
coefficient). If the overlap exceeds a threshold (e.g., 0.5), match the two
nodes. This catches wrapper insertion/removal: the new `<div class="wrapper">`
gets matched to the old parent because their descendant sets overlap.

**Phase 3 — Children alignment (O(n·b)).** For matched nodes whose children
aren't fully aligned, use LCS (longest common subsequence) on the children
lists to detect insertions, deletions, and reorderings. The `patience_diff`
library (Jane Street, production-quality) provides a generic LCS implementation.

Performance: 5-50ms at 500 nodes, 50-500ms at 5000 nodes. Orders of magnitude
faster than exact tree edit distance (Zhang-Shasha is O(n⁴) worst case; RTED
is O(n³) — both too slow above ~1000 nodes).

### Why not exact tree edit distance

Zhang-Shasha (1989) and RTED (Pawlik & Augsten, 2011) compute the optimal
edit script but are prohibitively expensive for DOM-sized trees. At 5000 nodes,
RTED takes 30-120s vs. <500ms for the GumTree approach. The optimality
guarantee doesn't add value here — we need a *correct and informative* diff,
not the *minimal* one.

### Diff types

```ocaml
type path = string  (* e.g., "/html/body/div[2]/section[1]/h2" *)

type diff =
  | Bounds_diff of { path: path; property: string; a: float; b: float }
  | Style_diff of { path: path; property: string; a: css_value; b: css_value }
  | Text_diff of { path: path; a: string; b: string }
  | Paint_order_diff of { path: path; a: int; b: int }
  | Tag_mismatch of { path: path; a: string; b: string }
  | Extra_node of { path: path; side: [`Left | `Right]; tag: string }
  | Moved_node of { old_path: path; new_path: path }
  | Wrapper_inserted of { path: path; wrapper_tag: string }
  | Wrapper_removed of { path: path; wrapper_tag: string }

type config = {
  check_bounds: bool;
  check_visual: bool;
  check_text: bool;
  check_paint_order: bool;
  bounds_tolerance: float;
  value_tolerance: float;   (* numeric tolerance for Px/Num css_values *)
}

val compare : config -> snapshot -> snapshot -> diff list
```

The output is a list of diffs, not a boolean. This is important: you can inspect
*what* changed and decide if it's acceptable. `Wrapper_inserted` /
`Wrapper_removed` diffs are informational — they describe structural changes
that may or may not affect visual output.

### Hash collision disambiguation

Small common subtrees (`<div></div>`, `<span>text</span>`) produce identical
hashes, creating ambiguous matches. Disambiguation strategy:
1. Prefer the candidate whose parent is already matched.
2. Among remaining candidates, prefer the one at the closest position
   (sibling index).
3. If still ambiguous, defer to Phase 2 container matching.

## CLI

```
sosie capture \
  --url http://localhost:8080/learn \
  --viewport 375x667 \
  --scheme dark \
  --config sosie.yml \
  --output snapshots/learn-375x667-dark.json

sosie capture-all \
  --base-url http://localhost:8080 \
  --routes /,/learn,/install,/packages,/community \
  --viewports 375x667,768x1024,1280x800 \
  --schemes light,dark \
  --config sosie.yml \
  --output snapshots/

sosie compare \
  --baseline snapshots-main/ \
  --modified snapshots-pr/ \
  --config sosie.yml \
  --report report.txt

sosie compare \
  --baseline snapshots-main/ \
  --modified snapshots-pr/ \
  --config sosie.yml \
  --report report.html
```

`capture` launches Chromium headless, connects via CDP, captures, normalizes,
writes JSON. `compare` reads two sets of normalized snapshots and produces
diffs. They are separate commands — you can capture on different machines or at
different times.

### Error handling

- **Chromium crash**: detect WebSocket close, report with the URL that was being
  captured and any partial state.
- **Page errors (404, 500)**: check the HTTP status in the `Page.navigate`
  response before attempting capture; report the status and skip the page.
- **Malformed CDP JSON**: use `Yojson` with proper error paths; report the raw
  response on decode failure.
- **Missing routes**: when one snapshot set has a route the other doesn't,
  report it as "route only in baseline" or "route only in modified" rather than
  failing.
- **Snapshot version mismatch**: refuse to compare snapshots with different
  `version` fields; print both versions and advise re-capture.

### Parallelism in `capture-all`

Sequential by default: reuse a single browser tab, navigate between pages.
At 200ms capture + 500ms settle per page, 300 captures ≈ 3.5 minutes —
acceptable for CI. If needed, open N tabs in the same Chromium instance and
capture in parallel (Chromium handles this natively via CDP targets).

## Workflow for ocaml.org refactoring

```bash
# 1. Capture baseline from main branch
git checkout main
make build && make start &
sosie capture-all \
  --base-url http://localhost:8080 \
  --routes routes.txt \
  --viewports 375x667,768x1024,1280x800 \
  --schemes light,dark \
  --config sosie.yml \
  --output baseline/
kill %1

# 2. Refactor EML files on branch
git checkout refactor-extract-components
# ... edit EML files, extract CSS classes ...
make build && make start &
sosie capture-all \
  --base-url http://localhost:8080 \
  --routes routes.txt \
  --viewports 375x667,768x1024,1280x800 \
  --schemes light,dark \
  --config sosie.yml \
  --output modified/
kill %1

# 3. Prove equivalence
sosie compare \
  --baseline baseline/ \
  --modified modified/ \
  --config sosie.yml \
  --report report.txt
```

If the output is empty: the refactoring is UI conservative. If not: you see
exactly which elements on which pages at which viewports differ, and how.

Example diff output:

```
/learn @ 768x1024 dark:
  /html/body/div[2]/section[1]/h2
    font-size: "30px" -> "28px"

/install @ 375x667 light:
  /html/body/div[3]/div[1]/a
    bounds.width: 343.0 -> 341.5 (delta: 1.5px, tolerance: 0.5px)
```

## Property whitelist

You don't need 350 CSS properties. ~20 visual properties cover what the eye
sees:

- **Layout** (captured in bounds): position, size, margins, padding, flex
  distribution, grid tracks — all resolved into the bounding rectangle
- **Display/visibility**: display, visibility, opacity, overflow-x, overflow-y
- **Color**: color, background-color
- **Typography**: font-family, font-size, font-weight, line-height, text-align,
  text-decoration
- **Borders**: border-{top,right,bottom,left}-{width,style,color}, border-radius
- **Effects**: box-shadow, z-index
- **Interaction**: cursor

Everything else is either already captured in the bounding box geometry or
invisible.

The whitelist is the **trust boundary**: sosie's "equivalent" verdict means
"equivalent with respect to these properties." It should be documented in
`sosie.yml` and reviewed alongside the code it validates. Extending the
whitelist is safe (more properties checked = stronger verdict); shrinking it
weakens the guarantee and should be justified.

## Resolved questions

1. **Pseudo-elements** (`::before`, `::after`). `captureSnapshot` includes them
   as nodes named `"::before"` / `"::after"`, parented to their host element in
   document order. They participate in tree matching like any other node.

2. **Font loading.** Resolved by awaiting `document.fonts.ready` via
   `Runtime.evaluate` before capturing (see CDP conversation above).

3. **CSS transforms.** `layout.bounds` reports the post-transform axis-aligned
   bounding box. No special handling needed — transforms are already reflected
   in the captured bounds.

## Open questions

1. **Hover/focus states.** The default capture is at rest. States could be
   injected via `CSS.forcePseudoState` before capturing — but this multiplies
   the snapshot count. Probably a phase 2 feature.

2. **Scroll-dependent layout.** `position: sticky` elements change with scroll
   offset. Capturing at scroll-top is the default; capturing at specific scroll
   positions could be an option.

3. **Iframes.** `captureSnapshot` doesn't cross cross-origin iframe boundaries.
   Same-origin iframes are included via `contentDocumentIndex`. Not a concern
   for ocaml.org.

4. **Canvas/SVG.** SVG elements are in the DOM and captured. Canvas content is
   a bitmap and not captured. ocaml.org uses inline SVG for icons, so they're
   covered.

5. **CSS transitions/animations.** A snapshot captures a single frame. Elements
   with `transition` or `animation` should be captured after animations
   complete — a configurable settle delay after font loading handles this.

6. **Responsive images and `srcset`.** Different viewport sizes may load
   different images, affecting layout. Not currently handled.

7. **`clip-path`.** Affects visual appearance but is not reflected in bounding
   boxes and is not in the property whitelist. Add if needed for the target
   project.

8. **Snapshot size.** A 500-element page with 20 properties each is ~10K
   values. For 300 captures (50 routes × 3 viewports × 2 schemes), snapshots
   are manageable. Complex pages (5000+ elements) could produce multi-MB
   snapshots — worth monitoring.

9. **HTML report format.** `--report report.html` is advertised in the CLI but
   unspecified. Needs design (inline screenshots? side-by-side element
   highlighting?).

## Testing and validation

Testing is not a secondary concern — it is the mechanism by which sosie earns
the trust described in the Key Requirement section. Sosie's correctness claim
is strong: "these two pages render identically with respect to the configured
properties." A bug that produces a false equivalence silently lets a visual
regression through. Testing must cover every layer independently and then
end-to-end, with a bias toward catching false negatives (missed differences)
over false positives (spurious diffs).

### Layer 1: Pure functions (unit tests)

These are standard OCaml tests (alcotest or inline expect tests). No browser
needed.

**Tree reconstruction.** Given a CDP-shaped JSON fixture (column-oriented with
`parentIndex`, `nodeType`, `attributes`, etc.), assert the reconstructed tree
has the expected shape, parent-child relationships, and attribute values. Test
edge cases:
- Root node (`parentIndex = -1`)
- Text nodes (no layout entry)
- Pseudo-elements (`::before` / `::after` ordering among siblings)
- Nodes with `display: none` (present in DOM, absent from layout)
- Empty string table references (`-1` sentinels)

**CSS value parsing.** Assert round-trip correctness:
- `"16px"` → `Px 16.0`, `"400"` → `Num 400.0`
- `"rgb(59, 130, 246)"` and `"#3b82f6"` → same `Color` value
- Malformed values → `Str` fallback (not an exception)

**Normalization rules.** For each rule type, construct a snapshot, apply the
rule, assert the expected transformation:
- `Drop_attributes [Exact "class"]` removes class but preserves id
- `Prefix "data-"` removes `data-x-foo` but not `datafoo`
- `Mask_text` on a `<time>` element replaces text; non-matching elements
  are untouched
- `Round_bounds 0.5` rounds `16.3` to `16.5`, `16.7` to `16.5`
- `Canonicalize_colors` normalizes `rgb()`, `#hex`, named colors to same form
- `Canonicalize_fonts` keeps first named + first generic; pure-generic stacks
  collapse correctly
- Normalization is idempotent: `normalize rules (normalize rules s) = normalize rules s`

**Tree matcher (GumTree phases).** This is the most critical unit to test.
Construct pairs of trees by hand and assert the expected matching/diff:

| Test case | Tree A | Tree B | Expected |
|-----------|--------|--------|----------|
| Identical | `<div><p>hello</p></div>` | same | no diffs |
| Text change | `<p>hello</p>` | `<p>world</p>` | `Text_diff` |
| Style change | `font-size: 16px` | `font-size: 18px` | `Style_diff` |
| Wrapper inserted | `<div>A B C</div>` | `<div><section>A B C</section></div>` | `Wrapper_inserted`, no content diffs |
| Wrapper removed | inverse of above | | `Wrapper_removed` |
| Child reorder | `<div>A B C</div>` | `<div>A C B</div>` | `Extra_node` or `Moved_node` diffs |
| Extra child | `<div>A B</div>` | `<div>A B C</div>` | `Extra_node` on right |
| Sibling type change | `<div><p>x</p></div>` | `<div><span>x</span></div>` | `Tag_mismatch` |
| Deep identical subtrees | large shared subtree | same with new wrapper at root | wrapper diff only, subtree matched by hash |
| Hash collision | two `<div></div>` siblings | same | matched by position, no false diffs |
| Bounds tolerance | `width: 100.0` | `width: 100.3` (tolerance 0.5) | no diff |
| Bounds tolerance exceeded | `width: 100.0` | `width: 101.0` (tolerance 0.5) | `Bounds_diff` |

**Snapshot comparison.** Assert that `compare` refuses mismatched `version`
fields and reports missing routes correctly.

### Layer 2: CDP integration tests

These require a running Chromium instance. They validate that the capture
pipeline produces correct snapshots from known HTML.

**Test fixture pages.** A set of minimal HTML files served by a local HTTP
server (OCaml `cohttp` or just `python3 -m http.server`), each designed to
test one thing:

- `fixed-layout.html`: a page with hardcoded `width`, `height`, `color`,
  `font-size` on every element. Assert the captured snapshot has exactly the
  expected bounds and style values.
- `font-loading.html`: a page that loads a web font via `@font-face`. Assert
  the captured `font-family` reflects the loaded font, not the fallback. (This
  validates the `document.fonts.ready` wait.)
- `display-none.html`: elements with `display: none`. Assert they appear in
  the DOM tree but have no layout entry.
- `pseudo-elements.html`: elements with `::before` / `::after` content. Assert
  pseudo-elements appear in the tree with correct text and bounds.
- `transform.html`: an element with `transform: translateX(50px)`. Assert
  bounds reflect the transformed position.

**Determinism test.** Capture the same page twice with the same viewport and
scheme. Assert the two snapshots are identical after normalization. This
validates that no non-determinism leaks through (timestamps, random IDs, etc.).

**Viewport/scheme test.** Capture a responsive page at two viewport sizes.
Assert bounds differ as expected. Capture in light and dark scheme. Assert
colors differ as expected.

### Layer 3: End-to-end (the "sosie tests sosie" level)

These validate the full workflow: capture → normalize → compare.

**Identity test.** Capture a page, compare the snapshot to itself. Assert zero
diffs. This is the most basic soundness check — if sosie reports diffs between
a page and itself, something is fundamentally broken.

**Known-equivalent refactoring.** Two HTML files that are structurally different
but visually identical:
- `v1.html`: `<div class="old-class" style="color: red">text</div>`
- `v2.html`: `<div class="new-class" style="color: red">text</div>`
With `drop_attributes: [class]` in config, assert zero diffs.

**Known-different refactoring.** Two HTML files that differ visually:
- `v1.html`: `<p style="font-size: 16px">text</p>`
- `v2.html`: `<p style="font-size: 18px">text</p>`
Assert exactly one `Style_diff` on `font-size`.

**Wrapper-transparent test.** The critical test for the GumTree matcher:
- `v1.html`: `<main><h1>Title</h1><p>Body</p></main>`
- `v2.html`: `<main><div class="wrapper"><h1>Title</h1><p>Body</p></div></main>`
Same styles on all elements. Assert: `Wrapper_inserted` diff reported, but no
`Style_diff` or `Bounds_diff` (the wrapper doesn't change visual output because
`<div>` is transparent by default).

**Regression suite.** As sosie is used on real projects, collect pairs of
snapshots where a bug was found (false positive or false negative). Add them as
regression tests. This is the long-term quality mechanism.

### CI integration

Tests are split by what they require:

| Suite | Requires | Runs in CI? | Speed |
|-------|----------|-------------|-------|
| Unit tests (Layer 1) | Nothing | Yes, always | < 1s |
| CDP integration (Layer 2) | Chromium | Yes, with `chromium` in CI image | ~5-10s |
| End-to-end (Layer 3) | Chromium + HTTP server | Yes, with `chromium` | ~10-30s |

Chromium is available in standard CI images (GitHub Actions `ubuntu-latest`
includes it; Debian/Ubuntu CI can `apt install chromium`). No Playwright, no
npm.

### What "correct" means

Sosie's correctness has two sides:
- **Soundness**: if sosie says "equivalent," the pages really do look the same
  with respect to the configured properties. Tested by the known-different
  tests (Layer 3) — sosie must report the diff.
- **Completeness**: if sosie says "different," there really is a visual
  difference. Tested by the known-equivalent and identity tests — sosie must
  report zero diffs.

False negatives (missed differences) are worse than false positives (spurious
diffs), because the tool's purpose is to prove equivalence. The testing
strategy is biased accordingly: more known-different test cases than
known-equivalent ones.

### Trust budget

Every false negative spends trust. The tool starts with zero trust and must
earn it through:

1. **Transparent scope.** The user can inspect the property whitelist and
   normalization config to understand exactly what is and isn't checked.
   No hidden assumptions.
2. **Self-tests.** Sosie ships with its own test suite of known-equivalent
   and known-different page pairs. A user can run `sosie self-test` with
   their Chromium to verify the tool works correctly in their environment
   before relying on it.
3. **Diff auditability.** Every diff is traceable: which element, which
   property, what the old and new values are. A user can always verify a
   reported diff by inspecting the element in the browser.
4. **Regression accumulation.** Each real-world false positive or false
   negative found in use becomes a permanent test case. The test suite
   grows monotonically with usage, and the trust grows with it.

## Why OCaml

- Algebraic types for the AST and diff representation
- Pattern matching for the tree walker
- Normalization rules compose as `snapshot -> snapshot` functions
- Could share types/libraries with Cascade (color canonicalization, selector
  parsing for `drop_subtrees`)
- Could live in the Cascade project as `cascade.sosie` or stand alone
- The only non-OCaml part is launching Chromium — a system dependency, not a
  library dependency

## Relationship to Cascade

[Cascade](https://github.com/samoht/cascade) defines styles in OCaml; sosie verifies the result matches. Together
they form a typed-and-verified CSS workflow:

- Cascade provides color parsing/canonicalization (reusable in normalization)
- Cascade provides selector parsing (reusable for `drop_subtrees` and
  `mask_text` rules)
- `cssdiff` compares CSS files; `sosie` compares their rendered effect
- A refactoring workflow: change styles with Cascade, prove equivalence with
  sosie
