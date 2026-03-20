# sosie — Claude Code project conventions

## What this project is

sosie is a DOM equivalence checker for UI-conservative HTML/CSS refactoring.
It captures resolved layout+style trees from a browser via CDP and compares
them structurally. The design document is `sosie-design.md`.

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

- `main` — current validated design
- `explored/<topic>` — explored but discarded directions
- `wip/<topic>` — work in progress, not yet validated

## Key design principles (from the design document)

- **Trustworthiness is the key requirement.** False negatives (missed visual
  regressions) are fatal. False positives (spurious diffs) are tolerable.
  Every design decision serves this asymmetry.
- **Round-trip testing over visual inspection.** The snapshot generator
  G : Snapshot -> Source enables C . G = id round-trip tests that validate the
  capture pipeline without human visual comparison.
- **Explicit trust boundary.** The property whitelist is the trust boundary.
  Sosie's verdict is exactly as strong as the whitelist is complete.
