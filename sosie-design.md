# sosie — DOM equivalence checker for UI-conservative refactoring

## Motivation

Refactoring EML templates in ocaml.org (extracting CSS component classes,
decomposing large pages into components) is blocked by the absence of a way to
prove the refactoring is UI conservative. Screenshot-based tools (Playwright,
BackstopJS) compare pixels, which is both too strict (subpixel rendering noise)
and not structural (can't tell you *what* changed).

Rendering engines are pure systems: given a fixed `(DOM, Stylesheet,
ViewportSize)`, they compute a deterministic layout tree — a tree of boxes with
absolute positions, dimensions, and resolved style values. This is a fixpoint of
the CSS constraint system. We can capture this fixpoint via the Chrome DevTools
Protocol and compare it structurally.

The idea is to build an OCaml tool that:

1. Captures the resolved DOM + layout + computed styles from a browser via CDP
2. Normalizes the snapshot (strips dynamic content, canonicalizes values)
3. Compares two normalized snapshots under a configurable equivalence relation
4. Reports structured diffs or declares equivalence

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

This is doable in OCaml with `cohttp` + a WebSocket library. No Node.js, no
Playwright, no npm. The system dependency is just Chromium, which CI
environments already have.

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

The full capture sequence is four CDP calls:

```
->  Emulation.setDeviceMetricsOverride   { width: 375, height: 667 }
->  Emulation.setEmulatedMedia           { features: [{name: "prefers-color-scheme", value: "dark"}] }
->  Page.navigate                        { url: "http://localhost:8080/learn" }
<-  Page.loadEventFired                  (wait for this event)
->  DOMSnapshot.captureSnapshot          { computedStyles: [...], includeDOMRects: true }
<-  { strings: [...], documents: [...] }
```

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
- **Shared string table**: all strings deduplicated
- **Sparse data**: rare properties stored as index/value pairs
- **Layout separate from DOM**: `display:none` elements have no layout entry
- **Styles are whitelist-filtered**: you choose which properties to capture

## Normalization

Between capture and comparison, a **normalize** pass transforms the raw snapshot
into a canonical form. This scopes out everything that shouldn't affect
equivalence.

```ocaml
type normalize_rule =
  | Drop_attributes of string list
      (* remove class, style, data-* -- these are expected to change *)
  | Mask_text of { selector: string; replacement: string }
      (* e.g., mask dates: any <time> element -> "[DATE]" *)
  | Mask_text_matching of { pattern: Re.t; replacement: string }
      (* regex-based: "March 20, 2026" -> "[DATE]" *)
  | Drop_subtree of string
      (* remove entire subtrees by selector, e.g., "#dynamic-feed" *)
  | Round_bounds of float
      (* round all coordinates to nearest N px, e.g., 0.5 *)
  | Canonicalize_colors
      (* "rgb(59, 130, 246)" and "#3b82f6" -> same canonical form *)
  | Canonicalize_fonts
      (* collapse font-family fallback lists:
         "Inter, ui-sans-serif, system-ui, sans-serif" -> "Inter, sans-serif" *)
  | Sort_attributes
      (* alphabetize attributes so order doesn't matter *)

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

type visual_properties = {
  display: string;
  visibility: string;
  opacity: string;
  color: string;
  background_color: string;
  font_family: string;
  font_size: string;
  font_weight: string;
  line_height: string;
  text_align: string;
  text_decoration: string;
  border_top: border;
  border_right: border;
  border_bottom: border;
  border_left: border;
  border_radius: string;
  box_shadow: string;
  overflow_x: string;
  overflow_y: string;
  z_index: string;
  cursor: string;
}
and border = { width: string; style: string; color: string }

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
  url: string;
  viewport: int * int;
  color_scheme: [ `Light | `Dark ];
  root: node;
}
```

## Equivalence checker

```ocaml
type path = string  (* e.g., "/html/body/div[2]/section[1]/h2" *)

type diff =
  | Bounds_diff of { path: path; property: string; a: float; b: float }
  | Style_diff of { path: path; property: string; a: string; b: string }
  | Text_diff of { path: path; a: string; b: string }
  | Children_count of { path: path; a: int; b: int }
  | Tag_mismatch of { path: path; a: string; b: string }
  | Extra_node of { path: path; side: [`Left | `Right]; node: node }

type config = {
  check_bounds: bool;
  check_visual: bool;
  check_text: bool;
  bounds_tolerance: float;
}

val compare : config -> snapshot -> snapshot -> diff list
```

The comparison walks both trees in lockstep. Since this is for refactoring (same
HTML structure, different CSS), the trees should match 1:1 in most cases. When
they don't -- because you decomposed a `<div>` into a component that wraps it
differently -- the checker reports structural diffs.

The output is a list of diffs, not a boolean. This is important: you can inspect
*what* changed and decide if it's acceptable.

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
diffs. They are separate commands -- you can capture on different machines or at
different times.

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

## Open questions

1. **Pseudo-elements** (`::before`, `::after`). `captureSnapshot` includes them
   in the layout tree. They need to be matched by position within their parent,
   not by tag name.

2. **Hover/focus states.** The default capture is at rest. States could be
   injected via `CSS.forcePseudoState` before capturing — but this multiplies
   the snapshot count. Probably a phase 2 feature.

3. **Scroll-dependent layout.** `position: sticky` elements change with scroll
   offset. Capturing at scroll-top is the default; capturing at specific scroll
   positions could be an option.

4. **Iframes.** `captureSnapshot` doesn't cross cross-origin iframe boundaries.
   Same-origin iframes are included. Not a concern for ocaml.org.

5. **Canvas/SVG.** SVG elements are in the DOM and captured. Canvas content is
   a bitmap and not captured. ocaml.org uses inline SVG for icons, so they're
   covered.

6. **CSS transitions/animations.** A snapshot captures a single frame. Elements
   with `transition` or `animation` should be captured after animations
   complete — a configurable settle delay after `Page.loadEventFired` handles
   this.

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
