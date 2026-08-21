# sosie

**A DOM equivalence checker for UI-conservative HTML/CSS refactoring.**

sosie answers a single question that existing tools do not answer reliably:
**"did this refactoring change the visual output?"**

It captures the resolved layout + style tree of a page from a real browser and
compares two captures structurally. Unlike pixel diffing, it is immune to
subpixel/GPU/font-rendering noise; unlike CSS diffing, it compares rendered
effect rather than source. The canonical snapshot extractor is a JavaScript
function built on standard Web APIs (`getBoundingClientRect`,
`getComputedStyle`); the Chrome DevTools Protocol is used only as an
optimization on Chromium.

> **Status:** `0.1.0` — first release, under active development. Being a `0.x`
> line, interfaces and the property whitelist may still change.

## Why

Refactoring HTML/CSS under UI preservation (extracting components, migrating
design systems, upgrading component libraries, removing dead CSS) changes the
source while intending to preserve what the user sees. Pixel diffing is flaky
and non-structural; CSS diffing flags the very changes refactoring is meant to
make; manual QA does not scale. sosie exists to give a trustworthy
"equivalent / not equivalent" verdict.

### Design principle: trustworthiness first

The value of sosie is the strength of its "equivalent" verdict. The design is
built around an asymmetry:

- **False negatives (missed visual regressions) are fatal.** A single one
  reaching production destroys trust.
- **False positives (spurious diffs) are tolerable.** The user inspects, sees
  it is harmless, and moves on.

The **property whitelist is the explicit trust boundary**: sosie's verdict is
exactly as strong as the whitelist is complete.

## Build

The project uses a local opam switch (`_opam/`, gitignored). Use
`opam exec --` to enter the environment:

```sh
opam exec -- dune build
opam exec -- dune runtest
opam exec -- dune exec sosie -- --version
```

## Usage

sosie is a CLI with several subcommands:

```sh
sosie capture           # Capture a DOM snapshot from a URL
sosie compare           # Compare two DOM snapshots
sosie capture-all       # Batch capture: routes x viewports x color schemes
sosie audit-whitelist   # Detect blind spots in the CSS property whitelist
sosie show-config       # Visualize normalization config overlays on a page
```

Run `sosie <command> --help` for the full options of each subcommand.

## Documentation

- Design: [`sosie-design.md`](sosie-design.md)
- Roadmap: [`sosie-roadmap.md`](sosie-roadmap.md)
- Formal methods survey: [`formal-methods-survey.md`](formal-methods-survey.md)
- Contributor conventions: [`CLAUDE.md`](CLAUDE.md)

## AI disclosure

In the interest of transparency, and in keeping with the transparency
principles of the EU Artificial Intelligence Act (Regulation (EU) 2024/1689):

- **This repository was developed with substantial assistance from a
  generative AI system** — Anthropic's Claude, used through the Claude Code
  agentic coding tool. AI assistance covered source code, tests,
  documentation, and design discussion. All AI-produced content was reviewed
  and is maintained under human direction; the maintainer is responsible for
  the contents of this repository.
- **sosie itself is not an AI system.** It contains no machine-learning
  models and performs no AI inference at runtime. Its output is a
  deterministic structural comparison of DOM snapshots. Consequently, sosie
  does not fall within the scope of the AI Act's obligations for AI systems,
  and it produces no "AI-generated content" within the meaning of Article 50.
- This notice is a **voluntary** provenance disclosure. It is not a claim of
  formal certification or conformity assessment under the AI Act, which
  governs AI *systems* placed on the EU market rather than the use of AI as a
  development aid.

## License

Released under the [MIT License](LICENSE). © 2026 Cuihtlauac Alvarado.
