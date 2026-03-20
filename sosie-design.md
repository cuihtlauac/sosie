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

### Separation of concerns: extraction vs. automation

The design separates two things that CDP conflates:

1. **What data to capture** — DOM structure, bounding rects, computed styles.
   This is defined by standard Web APIs (`getBoundingClientRect()`,
   `getComputedStyle()`, DOM traversal) available in every browser.

2. **How to execute the capture** — launching a browser, navigating to a URL,
   running the extraction code. This is engine-specific.

The **snapshot extraction is a JavaScript function** — the reference
implementation of "what sosie captures." It runs in any browser:

```javascript
function sosieCapture(properties) {
  // Walk the DOM via TreeWalker
  // For each element: getBoundingClientRect(), getComputedStyle()
  // For pseudo-elements: getComputedStyle(el, '::before'), etc.
  // Return structured JSON matching sosie's snapshot schema
}
```

The **browser automation** is pluggable:

| Engine | Browsers | Automation | Extraction |
|--------|----------|-----------|------------|
| Blink | Chrome, Edge, Brave | CDP (WebSocket) | `DOMSnapshot.captureSnapshot` (fast) or JS extractor |
| Gecko | Firefox | WebDriver / BiDi | JS extractor via `executeScript` |
| WebKit | Safari | WebDriver | JS extractor via `executeScript` |

CDP's `DOMSnapshot.captureSnapshot` is an **optimization** for Chromium — one
atomic call that returns the full snapshot. The JS extractor is the
**canonical reference** that works everywhere. On Chromium, both paths must
produce identical snapshots (tested by the round-trip framework).

This means multi-engine support is a natural extension, not a rewrite. The
comparison logic is completely engine-agnostic — it operates on the snapshot
format, not on protocol-specific data.

### Same-engine equivalence, not cross-engine consistency

A refactoring is UI-conservative when, for every engine in the target set,
the before and after snapshots are equivalent:

```
for each engine E in target_engines:
  for each (route, viewport, scheme):
    capture(E, before) ≈ capture(E, after)
```

Each engine is compared **against itself**. Cross-engine differences (Chrome
renders `line-height: normal` differently from Safari) are expected and not
sosie's concern. That is a different problem (cross-browser consistency
testing) that could reuse sosie's infrastructure but has different
normalization needs.

### Chromium-first, multi-engine by design

For the initial implementation targeting ocaml.org, Chromium via CDP is
sufficient. The OCaml CDP client uses `httpun-ws` (actively maintained
WebSocket library with eio and lwt backends). No Node.js, no Playwright.

For multi-engine support, the OCaml side needs a WebDriver client (HTTP-based
protocol, simpler than CDP WebSocket) to launch Firefox/Safari, navigate, and
execute the JS extractor. WebDriver is a W3C standard supported by all
browsers.

### Pipeline

```
                    +-------------------+
   page URL ------->  Browser           |
   viewport size    |  (any engine)     |<---- CDP / WebDriver / BiDi
   color scheme     |                   |
                    +--------+----------+
                             |
              JS extractor   |   or CDP DOMSnapshot
              (any engine)   |   (Chromium optimization)
                             |
                    +--------v----------+
                    | JSON snapshot     |
                    | (engine-agnostic) |
                    +--------+----------+
                             |
                    +--------v----------+
                    |  Normalize        |  <- strip dynamic content,
                    |  & filter         |     mask dates, etc.
                    +--------+----------+
                             |
                    +--------v----------+
                    |  Canonical        |  <- clean typed AST
                    |  snapshot         |
                    +--------+----------+
                            |
             snapshot A ----+    +---- snapshot B
                        +--------+
                        | Compare |
                        +----+----+
                             |
                       equivalent / diff
```

### The CDP conversation (Chromium fast path)

On Chromium, the capture uses CDP's `DOMSnapshot.captureSnapshot` for
atomic, efficient extraction. The full sequence is five CDP calls:

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

sosie audit-whitelist \
  --url http://localhost:8080/learn \
  --viewport 1280x800 \
  --config sosie.yml \
  --output audit-learn.png

sosie show-config \
  --url http://localhost:8080/learn \
  --config sosie.yml

sosie self-test
```

`capture` launches Chromium headless, connects via CDP, captures, normalizes,
writes JSON. `compare` reads two sets of normalized snapshots and produces
diffs. They are separate commands — you can capture on different machines or at
different times.

When diffs are found, `compare` produces a spatial HTML report by default
(the `diff-view` format — side-by-side pages with highlighted elements and
click-to-inspect tooltips). XPaths are hard for humans to parse; a red box
around a button is actionable in seconds. Text output is available via
`--report report.txt` for CI pipelines and scripting.

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
- **Layering**: paint-order (the resolved stacking order from CDP). Note:
  `z-index` alone is insufficient — `opacity`, `transform`, and `will-change`
  create new stacking contexts that can change element layering without any
  `z-index` change. `paint-order` captures the actual resolved layering and
  should always be compared.
- **Interaction**: cursor

Everything else is either already captured in the bounding box geometry or
invisible.

**Tolerance note.** `line-height` deserves special attention: `line-height: 1.5`
resolves to pixels based on `font-size`, so a small font-size change cascades
to line-height. The `value_tolerance` config should apply to `line-height`
(and other font-dependent properties) just as `bounds_tolerance` applies to
bounding rectangles.

The whitelist is the **trust boundary**: sosie's "equivalent" verdict means
"equivalent with respect to these properties." It should be documented in
`sosie.yml` and reviewed alongside the code it validates. Extending the
whitelist is safe (more properties checked = stronger verdict); shrinking it
weakens the guarantee and should be justified.

## Visual tooling

Sosie's configuration involves visual choices: which CSS properties to compare,
which page regions to ignore, what tolerance to apply. These choices should not
be reviewed by reading CSS property names or YAML — they should be reviewed
visually. The same principle sosie applies to CSS refactoring (don't make humans
compare rendered pages) must apply to sosie's own configuration: **remove round
trips inside the human brain.**

### `sosie audit-whitelist` — show what sosie is blind to

The highest-value tool. For a given page and whitelist, show the user exactly
which visual effects fall outside sosie's coverage.

How it works:
1. Capture a screenshot of the page as-is via CDP
2. Generate a "reset" stylesheet from the whitelist complement: for every CSS
   property NOT on the whitelist, emit `* { <property>: initial !important }`
3. Inject the reset stylesheet via `CSS.addStyleSheet`, capture a second
   screenshot
4. Produce a pixel-diff overlay of the two screenshots

- If the two screenshots are identical → the whitelist covers everything
  visible on this page. No blind spots.
- If they differ → the highlighted regions show precisely which visual effects
  sosie cannot see (a `text-shadow` disappears, a `background-image` vanishes,
  a `letter-spacing` changes).

The user looks at an image, not a property list. They see "that shadow
disappeared — do I care about shadows?" and either add `text-shadow` to the
whitelist or consciously accept the blind spot.

The reset stylesheet is generated mechanically from the whitelist — it's the
set complement. ~100 lines of OCaml on top of the existing CDP connection.

```
sosie audit-whitelist \
  --url http://localhost:8080/learn \
  --viewport 1280x800 \
  --config sosie.yml \
  --output audit-learn.png
```

### `sosie show-config` — visualize normalization rules

Open a page in headed (non-headless) Chromium with visual overlays showing
what sosie will ignore:

- **Masked text**: highlighted in yellow with the replacement shown
  (e.g., `[DATE]` overlaid on the original text)
- **Dropped subtrees**: red semi-transparent overlay with "IGNORED" label
- **Dropped attributes**: blue border on elements that have dropped attributes
- **Rounding quantum**: subtle grid lines showing the `round_bounds` value

The overlays are injected via `Runtime.evaluate` — a few `querySelectorAll`
loops adding highlight elements. ~200 lines of JS, no build system.

```
sosie show-config \
  --url http://localhost:8080/learn \
  --config sosie.yml
```

This opens the page in a visible browser window. The user sees their actual
page with visual annotations. No YAML to mentally parse, no CSS selectors to
imagine — the masked regions and ignored subtrees are painted directly on the
page.

### `sosie diff-view` — spatial diff visualization

When sosie reports diffs, show them spatially on the actual pages instead of
as text paths. This is what `--report report.html` produces:

- Load both page screenshots side by side
- Highlight differing elements with colored outlines (red for style diffs,
  orange for bounds diffs, blue for structural diffs)
- Click an element to see the property-level diff in a tooltip
- Filter by diff type (style only, bounds only, structural only)

This replaces the text output:
```
/html/body/div[2]/section[1]/h2
  font-size: "30px" -> "28px"
```
with: the `<h2>` is highlighted on both pages, and hovering shows the
font-size change. The user sees the element in context, not an XPath they
have to mentally locate.

~500 lines of JS. The HTML report is self-contained (inline screenshots as
data URIs, inline JS, no external dependencies).

### Interactive whitelist editor (phase 2)

A locally-served web UI for tuning the whitelist:

1. Open the target page in a CDP-controlled tab
2. Click any element → a panel shows all its computed CSS properties, grouped
   into "checked by sosie" (green) and "not checked" (gray)
3. Toggle a property off → the page re-renders with that property reset to
   `initial` — the user sees the visual effect immediately
4. Toggle a property on → it's added to the whitelist
5. Export the final whitelist to `sosie.yml`

This turns whitelist review from "read a list of CSS property names and
imagine what they do" into "click things and see what happens." ~500 lines
of JS + small web UI. Deferred to phase 2.

### Design principle

Every human review step in the trust chain must be visual. If sosie is a
visual equivalence tool, its own configuration and validation UX must be
visual too. Text-based configuration is the authoring format; visual tooling
is the review format.

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

9. **HTML report format.** Resolved: the `diff-view` spatial visualization
   (see Visual Tooling section). Self-contained HTML with inline screenshots,
   element highlighting, and click-to-inspect tooltips. Now the default output.

## Design decisions

1. **Pseudo-element → real element replacement.** When a refactoring replaces
   a `::before` pseudo-element (e.g., a CSS icon) with an actual `<img>` or
   `<svg>` tag, sosie reports this as a structural diff (`Tag_mismatch` or
   `Extra_node`). This is a conscious choice: the tool should not silently
   treat structurally different DOM as equivalent. The user inspects the diff
   and decides if it's acceptable. Making sosie guess that `::before` and
   `<img>` are "the same thing" would violate the conservative principle
   (prefer false positives over false negatives).

## Testing and validation

Testing is not a secondary concern — it is the mechanism by which sosie earns
the trust described in the Key Requirement section. Sosie's correctness claim
is strong: "these two pages render identically with respect to the configured
properties." A bug that produces a false equivalence silently lets a visual
regression through.

The key insight is that **testing should not require human visual inspection of
hundreds of pages.** Category theory tells us where to start: just as
parser/pretty-printer round-trip tests should start from the AST (the canonical
side), not from the text (which has more degrees of freedom), sosie's tests
should start from snapshots, not from arbitrary HTML.

### The morphism structure

The system involves three spaces:

```
Source ──R──> Visual ──f──> Snapshot
  (HTML+CSS)    (what eyes see)    (what sosie captures)
```

- **R**: browser rendering. Source → Visual.
- **C = f ∘ R**: sosie capture. Source → Snapshot.
- **f**: extraction of whitelisted properties from visual output.

Sosie's soundness claim is: **C(a) = C(b) ⟹ R(a) = R(b)**. This holds iff f
is mono (injective) — distinct visual outputs always produce distinct snapshots.
The property whitelist determines whether f is mono.

The other direction, G ∘ C ≠ id in general — many HTML sources produce the
same snapshot. That's the whole point: the equivalence relation collapses
source differences that don't affect visual output.

Since capture has two paths (JS extractor and CDP fast path), the morphism
structure has an additional constraint:

```
C_js ∘ G = id              (JS extractor is faithful — tested on all engines)
C_cdp ∘ G = C_js ∘ G       (CDP path matches JS reference — tested on Chromium)
```

The JS extractor is the reference implementation. The CDP path is validated
against it.

### The snapshot generator G

Define a **generator** G : Snapshot → Source that produces minimal HTML+CSS
with known visual properties (absolute positioning, inline styles, known
fonts):

```
Snapshot ──G──> Source ──C──> Snapshot
         generate       capture
```

The round-trip property is: **C ∘ G = id_Snapshot**. Generate HTML from a
snapshot and recapture it → get back the same snapshot. This is a
retraction/section structure: C is a retraction (left inverse) of G.

The generator is simple — it doesn't need to produce realistic HTML, just HTML
where every visual property is controlled:

```html
<!-- G(snapshot) for a node with known bounds and styles -->
<div style="position:absolute; left:10px; top:20px; width:100px; height:50px;
            background-color:#ff0000; font-size:16px; font-family:monospace;
            opacity:0.8; z-index:5; border:2px solid #00ff00">
  Hello
</div>
```

You know *by construction* what the snapshot should contain. No human judgment
needed.

### Round-trip tests (the primary validation mechanism)

**Capture round-trips (needs browser, no human).** Generate snapshots
(programmatically or via QCheck/property-based testing), produce HTML via G,
capture via C, compare to the original snapshot. Each failure is a concrete
counterexample: "this snapshot with font-size=17px and opacity=0.3 doesn't
round-trip."

```ocaml
(* Property-based: generate random snapshots, round-trip through HTML *)
let prop_capture_round_trip =
  QCheck.Test.make arbitrary_snapshot (fun s ->
    let html = generate s in
    let s' = capture html in
    snapshot_equal s s')
```

This validates the entire capture pipeline (CDP decoding, string table, tree
reconstruction, CSS value parsing) across thousands of random property
combinations without ever looking at a browser window.

**Matcher round-trips (no browser).** Start from a tree A, apply known
transformations (wrap subtree, reorder children, change text), call the result
B. The ground-truth edit script is known by construction. Run `match(A, B)` and
verify it recovers the expected matching. Again: start from the canonical side
(the known transformation), not from arbitrary tree pairs.

**Normalization algebraic properties (no browser).** Normalization is a pure
function with checkable algebraic laws:
- **Idempotency**: `normalize(normalize(s)) = normalize(s)`
- **Monotonicity**: adding rules to the normalization config never produces
  *more* detail (normalization only removes information)
- **Independence**: order of independent rules doesn't affect the result (e.g.,
  `Round_bounds` and `Canonicalize_colors` commute)

These laws are not empirical observations — they follow from the structure of
the normalization rules as a confluent, terminating term rewrite system. The
rules act on disjoint parts of the node structure (attributes, bounds, colors,
fonts, text, subtrees). Non-overlapping TRSs are confluent (Baader & Nipkow,
1998). Termination is trivial: each rule is idempotent, reaching its normal
form in a single pass. The one potential overlap — two `Mask_text` rules
matching the same node — should be detected at config load time. See
`formal-methods-survey.md` for the full argument.

### Bounded exhaustive testing of the tree matcher

The GumTree-style matcher is the most complex and heuristic component. Hand-
crafted test cases (the table below) cover known scenarios, but cannot cover
all corner cases of the hash-matching, dice-coefficient, and LCS phases
interacting. Random testing (QCheck) samples the space but may miss rare
configurations.

**Bounded exhaustive testing** (the small scope hypothesis, Jackson 2006)
covers the *entire* space up to a small size. If a bug exists in the matcher,
it almost certainly manifests on trees with ≤5 nodes.

Enumerate all ordered labeled trees with k=3 labels (e.g., `div`, `span`,
`p`) up to size n. Test all pairs:

| Max nodes per tree | Trees | Pairs | Runtime |
|-------------------|-------|-------|---------|
| 3 | ~54 | ~2,900 | < 1s |
| 4 | ~378 | ~143K | seconds |
| 5 | ~3,402 | ~11.6M | minutes |

For every pair (A, B), verify:
- **Injectivity**: no node is matched twice
- **Label compatibility**: matched nodes have the same tag, or a `Tag_mismatch`
  diff is emitted
- **Completeness**: every unmatched node is reported as `Extra_node`
- **Symmetry**: `compare(A, B)` and `compare(B, A)` produce consistent diffs
- **Transitivity**: if `compare(A, B) = ∅` and `compare(B, C) = ∅`, then
  `compare(A, C) = ∅`
- **Ancestor preservation**: matched nodes preserve ancestor/descendant
  relationships (if x is an ancestor of y in tree A, and both are matched,
  then match(x) is an ancestor of match(y) in tree B)

This is strictly stronger than property-based random testing — it covers the
entire small space, not a sample. The small scope hypothesis (empirically
validated by Andoni et al., 2003) gives high confidence that exhaustive
testing at n=5 catches all matcher bugs that would manifest on larger trees.

Implementation: a tree enumerator using the Catalan number recurrence, with
k labels per node. ~100 lines of OCaml. The property checks are the same
metamorphic relations listed above, applied to every pair.

### Stratified random testing at scale

Bounded exhaustive testing covers all trees up to size ~5. For larger trees
(100-5000 nodes, representative of real DOM trees), random testing is needed.
But **naive uniform random generation is biased**: a uniform random ordered
tree of size n has depth O(√n) and geometric degree distribution (Flajolet &
Sedgewick, *Analytic Combinatorics*, 2009). Trees that stress the matcher —
deep caterpillars, stars, balanced trees, trees with many identical subtrees —
have exponentially small probability under uniform sampling.

Analytic combinatorics tells us what uniform sampling misses:

| Property | Uniform random tree (size n) | Matcher stress cases |
|----------|------------------------------|---------------------|
| Depth | O(√n) ≈ 22 for n=500 | O(n): paths, caterpillars |
| Max branching | geometric(½), rarely > 10 | O(n): star trees |
| Balance | random, moderately unbalanced | perfect: complete k-ary |
| Subtree repetition | rare | many identical subtrees |

The solution is **stratified generation**: sample from structurally diverse
shape classes, not from the uniform distribution. Each shape class targets a
different matcher behavior:

| Shape class | Generator | What it stresses |
|-------------|-----------|-----------------|
| Path (depth = n) | Direct construction | Deep recursion, LCS on singleton children |
| Star (depth = 1) | Direct construction | Wide children lists, many hash collisions |
| Caterpillar | Spine + random leaves | Mixed deep/wide, hash collision at leaves |
| Complete k-ary | Deterministic | Perfect symmetry, hash collision everywhere |
| Lopsided | One heavy child + leaf siblings | Dice coefficient edge cases |
| Uniform random | Boltzmann sampling | "Typical" trees |
| Random recursive | Sequential insertion | Logarithmic depth, different from uniform |

For each shape class, generate trees of size 100, 500, 1000, 5000. Test the
same structural properties as bounded exhaustive (injectivity, symmetry,
transitivity, ancestor preservation) plus performance: the matcher should
complete within the expected O(n log n) bound.

**Boltzmann sampling** (Duchon, Flajolet, Louchard, Schaeffer, 2004) is
the standard method for uniform generation of combinatorial structures from
a specification. For ordered labeled trees, the specification is
`T = Z × Seq(T)`, and the sampler produces trees of approximate target size
in O(n) expected time. The OCaml tool **Arbogen** (Bodini, Genitrini, Ponty)
implements this. However, Boltzmann sampling gives the uniform distribution
— it must be combined with the targeted generators above, not used alone.

**Pair generation** for matcher testing requires generating *(A, B)* where B
is derived from A by known transformations (wrap subtree, reorder children,
change labels, delete/insert nodes). This ensures the ground-truth diff is
known. The transformations are parameterized:

- `wrap(A, i)`: wrap the i-th subtree of A in a new node
- `reorder(A, i, perm)`: permute children of the i-th node
- `mutate(A, i, prop, val)`: change a style property of the i-th node
- `delete(A, i)`: remove the i-th subtree
- `insert(A, i, subtree)`: add a subtree at position i

Combining stratified base tree generation with parameterized transformations
gives thorough coverage of the matcher's behavior across structurally diverse
inputs. QCheck's `Gen.oneof` and `Gen.frequency` combinators support this
mixture directly.

Implementation: ~200 lines for the shape generators + ~100 lines for the
transformation operators. The Boltzmann sampler can use Arbogen or a direct
implementation of the Catalan Boltzmann sampler (~50 lines).

### CSS mutation testing

Round-trip tests validate the capture pipeline. Bounded exhaustive tests
validate the matcher. **Mutation testing validates sosie's sensitivity** — its
ability to detect actual visual changes.

The approach:
1. Start with two identical pages A and A' (A' is a copy of A)
2. Apply a CSS mutation operator to A', producing A_mutant
3. Verify via pixel diff that the mutation is actually visible (filter out
   equivalent mutants)
4. Run `sosie compare A A_mutant`
5. If sosie reports "equivalent," the mutant **survived** — this is a false
   negative, the fatal error mode

CSS mutation operators:

| Operator | Example | What it tests |
|----------|---------|---------------|
| Value perturbation | `font-size: 16px` → `17px` | Numeric comparison precision |
| Value replacement | `color: red` → `blue` | Color comparison |
| Property removal | delete `border-radius: 8px` | Detection of missing properties |
| Property swap | swap `color` between two elements | Per-element property tracking |
| Unit change | `width: 100px` → `100%` (where they differ) | Value resolution |
| Keyword change | `text-align: left` → `center` | Keyword comparison |

The **mutation score** (percentage of visible mutations detected) is a
quantitative measure of sosie's sensitivity. A score of 100% means sosie
detects every visible CSS change — the strongest possible statement about
false-negative rate.

Surviving mutants reveal exactly where sosie is blind: which property, which
element, which kind of change. This directly informs whitelist and tolerance
tuning.

Implementation: a mutation harness that takes an HTML file, applies each
operator to each eligible property, and runs the pipeline. The pixel-diff
filter (step 3) is essential — mutations that don't change the rendering
(equivalent mutants) must not count against the mutation score. ~200 lines of
OCaml + the existing CDP connection for pixel capture.

### Unit tests (Layer 1, no browser)

Standard OCaml tests (alcotest or inline expect tests).

**Tree reconstruction.** Given CDP-shaped JSON fixtures (column-oriented with
`parentIndex`, `nodeType`, `attributes`, etc.), assert the reconstructed tree
has the expected shape, parent-child relationships, and attribute values. Edge
cases:
- Root node (`parentIndex = -1`)
- Text nodes (no layout entry)
- Pseudo-elements (`::before` / `::after` ordering among siblings)
- Nodes with `display: none` (present in DOM, absent from layout)
- Empty string table references (`-1` sentinels)

**CSS value parsing.** Assert parse correctness:
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

**Tree matcher (GumTree phases).** Construct pairs of trees by hand and assert
the expected matching/diff:

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

### CDP integration tests (Layer 2, needs browser)

These validate that the capture pipeline produces correct snapshots from known
HTML. The round-trip tests (above) are the primary mechanism here.

**Additional fixture pages** for properties that are hard to generate
synthetically:

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
scheme. Assert the two snapshots are identical after normalization.

**Viewport/scheme test.** Capture a responsive page at two viewport sizes.
Assert bounds differ as expected. Capture in light and dark scheme. Assert
colors differ as expected.

### End-to-end tests (Layer 3)

These validate the full workflow: capture → normalize → compare.

**Identity test.** Capture a page, compare the snapshot to itself. Assert zero
diffs. The most basic soundness check.

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
permanent regression tests.

### CI integration

| Suite | Requires | Speed |
|-------|----------|-------|
| Unit tests + algebraic properties | Nothing | < 1s |
| Bounded exhaustive (matcher, n≤4) | Nothing | seconds |
| Bounded exhaustive (matcher, n≤5) | Nothing | minutes |
| Round-trip (property-based) | Chromium | ~10-30s |
| CDP integration fixtures | Chromium | ~5-10s |
| Mutation testing | Chromium | ~1-5 min |
| End-to-end | Chromium | ~10-30s |

Chromium is available in standard CI images (GitHub Actions `ubuntu-latest`,
Debian/Ubuntu `apt install chromium`). No Playwright, no npm.

### The trust argument

Sosie's correctness reduces to four independently verifiable claims:

1. **Capture fidelity**: the capture pipeline faithfully extracts the
   properties it claims to extract. **Verified by round-trip tests**
   (automated, no human needed). C ∘ G = id.

2. **Matcher correctness**: the tree matcher produces valid, complete
   matchings. **Verified by bounded exhaustive testing** on all tree pairs up
   to size 5 (automated, no human needed, covers the entire small space).

3. **Detection sensitivity**: sosie detects every visible CSS change within
   its whitelist. **Verified by mutation testing** (automated — mutate CSS
   properties, confirm detection via mutation score).

4. **Whitelist completeness**: the property whitelist covers all visually
   significant CSS properties. **Verified by `audit-whitelist`** (visual,
   one-time per project) and **human audit** (focused review of ~20 properties
   against the CSS spec).

Claims 1-3 are fully automated. Claim 4 requires one-time human review,
aided by the visual `audit-whitelist` tool. No other faith is required.

### Trust budget

Every false negative spends trust. The tool starts with zero trust and must
earn it through:

1. **Transparent scope.** The user can inspect the property whitelist and
   normalization config to understand exactly what is and isn't checked.
   No hidden assumptions.
2. **Self-tests.** `sosie self-test` runs the round-trip and fixture tests
   with the user's local Chromium, verifying the tool works in their
   environment before they rely on it.
3. **Diff auditability.** Every diff is traceable: which element, which
   property, what the old and new values are. A user can always verify a
   reported diff by inspecting the element in the browser.
4. **Regression accumulation.** Each real-world false positive or false
   negative found in use becomes a permanent test case. The test suite
   grows monotonically with usage, and the trust grows with it.

## Distribution

### For OCaml projects: opam

The native distribution channel. `opam install sosie` builds from source.
This is the right path for ocaml.org, Cascade, and other OCaml projects.

### For everyone else: npm (esbuild model)

To achieve adoption beyond the OCaml ecosystem, sosie must be installable
in seconds with `npm install -g sosie` or `npx sosie`. Web developers live
in npm. Meeting them there is a prerequisite for mass adoption.

The proven pattern (esbuild, Tailwind, Biome, oxlint):

1. **Platform-specific binary packages.** Publish pre-compiled binaries as
   scoped npm packages: `@sosie/cli-linux-x64`, `@sosie/cli-darwin-arm64`,
   `@sosie/cli-linux-arm64`, `@sosie/cli-win32-x64`, etc. Each package
   contains a single native binary built from the OCaml source.

2. **Thin loader package.** The main `sosie` npm package has an `install`
   script that detects OS and architecture, downloads the correct binary
   package via `optionalDependencies`, and places it on `PATH`. No OCaml
   runtime, no compilation, no opam.

3. **`npx sosie` just works.** The user never sees a `.ml` file.

This requires cross-compilation to each target (OCaml's cross-compilation
story via `dune` and `ocaml-cross` is adequate for Linux and macOS; Windows
may need `ocaml-cross` or a separate CI build).

### Bundled Chromium

The design currently lists Chromium as a system dependency. For zero-friction
onboarding, sosie should auto-download a revision-locked Chromium on first
run:

- Use the same Chrome for Testing download mechanism as Puppeteer
  (`@puppeteer/browsers` or a direct download from the Chrome for Testing
  API).
- Cache it in `~/.cache/sosie/chromium/` (XDG-compliant).
- Pin the exact Chromium revision in the sosie release. This eliminates
  "works on my Chrome but not yours" — every developer and CI run uses the
  same browser build.
- Allow override via `SOSIE_CHROMIUM_PATH` for environments that provide
  their own Chromium.

This means `npx sosie capture --url http://localhost:3000` works on a fresh
machine with only Node.js installed. No `apt install chromium`, no manual
setup.

### GitHub Action

A drop-in CI integration:

```yaml
- name: UI Equivalence Check
  uses: sosie-org/sosie-action@v1
  with:
    baseline: ./snapshots-main
    current: ./snapshots-pr
    config: sosie.yml
```

The action bundles the sosie binary and a pinned Chromium. Teams get the
full pipeline without knowing the tool is written in OCaml.

### Architecture constraint

The npm distribution imposes one constraint on the implementation: **sosie
must be a single statically-linked binary** (or at most binary + bundled
Chromium). No dynamic library dependencies beyond libc. OCaml's native
compiler produces static binaries by default, so this is not an obstacle.

### Adoption funnel

```
npx sosie capture --url ...        → zero-friction trial
npm install -g sosie               → local development
sosie.yml committed to repo        → team adoption
sosie-action in CI                 → enforced visual equivalence
```

The OCaml implementation is invisible to users. It surfaces only in
`sosie self-test` output ("Powered by OCaml for high-performance tree
matching") and in the contributor documentation. Developers who notice the
tool is faster and more precise than JS-based alternatives will find their
way to the source.

## Why OCaml

- Algebraic types for the AST and diff representation
- Pattern matching for the tree walker
- Normalization rules compose as `snapshot -> snapshot` functions
- Single static binary — no runtime, no GC pauses, ideal for npm-bin
  distribution
- Could share types/libraries with Cascade (color canonicalization, selector
  parsing for `drop_subtrees`)
- Could live in the Cascade project as `cascade.sosie` or stand alone

## Relationship to Cascade

[Cascade](https://github.com/samoht/cascade) defines styles in OCaml; sosie verifies the result matches. Together
they form a typed-and-verified CSS workflow:

- Cascade provides color parsing/canonicalization (reusable in normalization)
- Cascade provides selector parsing (reusable for `drop_subtrees` and
  `mask_text` rules)
- `cssdiff` compares CSS files; `sosie` compares their rendered effect
- A refactoring workflow: change styles with Cascade, prove equivalence with
  sosie
