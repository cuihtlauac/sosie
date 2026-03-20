# Plan: Replace raw JS extractor with js_of_ocaml extractor

## Motivation

The current `js/sosie-capture.js` is hand-written JavaScript. This creates
a maintenance burden and type-safety gap:

| Feature                | Raw JS extractor    | JSOO extractor            |
|------------------------|---------------------|---------------------------|
| Type safety            | None (easy to miss) | Total (compiler enforces) |
| AST consistency        | Manual JSON sync    | Automatic via shared types|
| Maintenance            | Two languages       | Single language (OCaml)   |
| Performance            | Native JS           | Highly optimized JS       |

The property whitelist, snapshot schema, and CSS value types are all defined
in OCaml (design doc §Typed AST). The JS extractor duplicates these
definitions in an untyped language. A js_of_ocaml extractor shares the
OCaml types directly — the compiler ensures the extractor and the parser
agree on the schema. A property added to the whitelist in OCaml is
automatically captured by the extractor; with raw JS, it's a manual sync
that can silently drift.

## Approach

### Phase 1: Shared types library (lib_shared/)

Extract the snapshot types into a pure library with no platform dependencies.
This library is compiled to both native (for the CLI) and JavaScript (for
the extractor).

**Modules:**

- `Snapshot_types` — `rect`, `css_value`, `visual_properties`, `node`,
  `snapshot` (the types from the design doc §Typed AST)
- `Property_whitelist` — the canonical list of CSS property names, as an
  OCaml value. No more duplicated JS array.
- `Snapshot_json` — `to_json : snapshot -> Yojson.Safe.t` and
  `of_json : Yojson.Safe.t -> snapshot`. Pure serialization, no browser
  APIs.

This library depends only on OCaml stdlib. No yojson in the shared lib —
JSON serialization uses a minimal signature so the JSOO side can use
`Js_of_ocaml.Json` or a lightweight encoder.

### Phase 2: JSOO extractor (js_extractor/)

A js_of_ocaml program that compiles to a single `.js` file. It uses the
browser DOM API bindings from `js_of_ocaml` to implement the same logic
as `sosie-capture.js`:

1. Freeze the page (inject `<style>` disabling transitions/animations)
2. Walk the DOM (`document.documentElement`, recursive child traversal)
3. For each element: `getBoundingClientRect()`, `getComputedStyle()`
4. For pseudo-elements: `getComputedStyle(el, "::before"/"::after")`
5. For text nodes: inherit bounds/styles from parent
6. Build the `Snapshot_types.snapshot` value
7. Serialize to JSON and return

The output is a self-contained JS file that exposes `sosieCapture()` —
same interface as the current raw JS.

**Key dune setup:**

```
(executable
 (name extractor)
 (modes js)
 (libraries js_of_ocaml sosie_shared)
 (js_of_ocaml
  (flags (:standard --opt 3))
  (javascript_files)))
```

### Phase 3: Validation against raw JS

The existing `js/sosie-capture.js` becomes the test oracle. For a set of
test pages, both extractors must produce identical snapshots (modulo
serialization order). This validates the JSOO extractor before the raw JS
is retired.

**Test strategy:**

1. Load the same page in Chromium via CDP
2. Run raw JS extractor → snapshot A
3. Run JSOO extractor → snapshot B
4. Parse both with `Snapshot_json.of_json`
5. Assert structural equality: `A = B`

This is an integration test (requires browser), gated like existing
CDP integration tests.

### Phase 4: Retire raw JS

Once the JSOO extractor is validated:

1. Delete `js/sosie-capture.js`
2. Update CDP pipeline to inject the JSOO-compiled JS
3. Update design doc and roadmap

## Dependencies to install

```
opam install js_of_ocaml js_of_ocaml-compiler js_of_ocaml-ppx
```

## Impact on roadmap steps

- **Step 2 (raw capture):** Uses JSOO extractor instead of raw JS
- **Step 3 (tree reconstruction):** `of_js_json` parser trivially correct
  because the JSOO extractor produces data from the same OCaml types
- **Step 4 (round-trip):** Round-trip G ∘ C = id becomes even more
  meaningful since C is type-checked OCaml
- **Step 14 (multi-engine):** JSOO extractor works in Firefox/Safari via
  WebDriver `executeScript` — same as raw JS, but type-safe

## Implementation order

1. Create `lib_shared/` with `Snapshot_types`, `Property_whitelist`
2. Add `js_of_ocaml` dependencies to dune-project
3. Create `js_extractor/` with JSOO DOM walking code
4. Build JSOO extractor: `dune build js_extractor/extractor.bc.js`
5. Write comparison integration test (raw JS vs JSOO on same page)
6. Validate on a real page (e.g., about:blank, then a local HTML fixture)
7. Once validated, update CDP's `evaluate_js` to use JSOO output
8. Delete `js/sosie-capture.js`

## Risks

1. **js_of_ocaml output size.** The compiled JS may be larger than the
   hand-written version. Mitigation: `--opt 3` and dead code elimination.
   For CDP injection, size is not critical (it's a local WebSocket, not
   a network transfer). For console paste, we can provide a minified
   build.

2. **DOM API bindings.** `js_of_ocaml`'s DOM bindings cover standard
   APIs (`getBoundingClientRect`, `getComputedStyle`, `childNodes`).
   If any API is missing, we write a thin FFI binding (a few lines).

3. **JSON interop.** The JSOO extractor runs in the browser and needs
   to return JSON that the OCaml native side can parse. Two options:
   (a) Use `Js_of_ocaml.Json.output` to produce a JS object, then
   `JSON.stringify` on the browser side. (b) Build a JSON string
   directly in OCaml using a lightweight encoder. Option (a) is simpler.

## Non-goals for this refactor

- No changes to the CDP bridge, launcher, or CLI.
- No changes to the snapshot comparison logic.
- No new snapshot schema — the types are extracted as-is from the design
  doc.
- The raw JS extractor stays as a test oracle until the JSOO extractor
  is fully validated. No premature deletion.
