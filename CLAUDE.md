# sosie — Claude Code project conventions

## What this project is

sosie is a DOM equivalence checker for UI-conservative HTML/CSS refactoring.
It captures resolved layout+style trees from a browser and compares them
structurally. The canonical snapshot extraction is a JavaScript function
using standard Web APIs; CDP is a Chromium optimization.

Design: `sosie-design.md`. Roadmap: `sosie-roadmap.md`.
Formal methods survey: `formal-methods-survey.md`.

## Code standards

### Documentation

- Every `.mli` file has a module-level doc comment explaining purpose and
  invariants.
- Every public function has an `(** ... *)` ocamldoc comment. Include
  `@param`, `@return`, `@raise` where non-obvious.
- Non-trivial algorithms (GumTree phases, tree reconstruction, normalization)
  have inline comments explaining the logic, referencing the design document
  section or academic paper where applicable.
- Do not add comments that merely restate the code. Comment the *why*, not
  the *what*.

### Commits

- Each commit is atomic: one logical change, buildable, tests pass.
- Commit message format: imperative mood, first line ≤72 chars, blank line,
  then body explaining *why* (not *what* — the diff shows what).
- No `--no-verify`. If a hook fails, fix the issue.
- Do not amend published commits.

### Testing

- **Exhaustive unit test coverage.** Every public function has tests. Every
  branch in pattern matches is covered. Every error path is tested.
- **Edge cases first.** Write tests for boundary conditions, empty inputs,
  malformed data, and degenerate cases before the happy path.
- **Test names describe the property being tested**, not the function name.
  E.g., `normalization_is_idempotent`, not `test_normalize`.
- **Algebraic property tests** (QCheck): idempotency, commutativity,
  round-trip (C . G = id), symmetry, transitivity.
- **Bounded exhaustive tests** for the tree matcher: all tree pairs up to
  size 5. Not optional — this is a required test suite.
- **No test should depend on external state** (network, filesystem, running
  browser) unless it is explicitly in the CDP/integration test suite.
  Unit tests are pure.
- Use `alcotest` for unit tests. Use `qcheck` + `alcotest` for property
  tests. Use inline expect tests where output comparison is clearer than
  assertions.

### Code style

- Follow the OCaml standard: `snake_case` for values, `CamelCase` for
  modules, `t` for the primary type of a module.
- Prefer `.mli` files for all library modules. The `.mli` is the contract.
- No dead code. No commented-out code. No `TODO` without a tracking issue.
- Keep functions short. If a function needs a comment explaining its
  structure, it should probably be split.
- Error handling: use `Result.t` or exceptions with documented `@raise`.
  No silent failures. No swallowed exceptions.

## Conversation-as-commits workflow

This project tracks design discussions as git history. The convention:

- **Validated reasoning gets committed.** When a discussion step produces
  validated output (analysis, design decisions, code), commit it immediately.
  The commit message should summarize what was decided and why.
- **Prompts are part of the record.** The commit captures the outcome of a
  prompt, not the prompt itself (prompts are ephemeral; the artifact is what
  matters).
- **Dead ends become branches.** When a line of reasoning is explored but
  discarded, commit it on a branch, name the branch descriptively
  (e.g., `explored/lockstep-comparison`), and switch back to the point where
  the better path was identified. Do not delete these branches — they document
  what was tried and why it was rejected.
- **Backtracking is explicit.** To revisit a decision, create a branch from
  the relevant commit, not from HEAD. This preserves the original line of
  reasoning while exploring the alternative.

### Why

Context compaction in Claude Code is all-or-nothing: when the context window
fills, older messages are summarized non-selectively. Committing validated
reasoning to files means it survives compaction. The git history becomes the
durable record of the design process, not the conversation transcript.

### Branch naming

- `main` — current validated design and code
- `explored/<topic>` — explored but discarded directions
- `wip/<topic>` — work in progress, not yet validated

## Key design principles

- **Trustworthiness is the key requirement.** False negatives (missed visual
  regressions) are fatal. False positives (spurious diffs) are tolerable.
  Every design decision serves this asymmetry.
- **JS extractor is the canonical primitive.** Standard Web APIs
  (getBoundingClientRect, getComputedStyle), not CDP. Works in any browser.
- **Round-trip testing over visual inspection.** The snapshot generator
  G : Snapshot -> Source enables C . G = id round-trip tests that validate the
  capture pipeline without human visual comparison.
- **Explicit trust boundary.** The property whitelist is the trust boundary.
  Sosie's verdict is exactly as strong as the whitelist is complete.
- **Same-engine equivalence.** Before vs. after on each target engine.
  Cross-engine consistency is a different problem.
