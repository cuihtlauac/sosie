# Formal methods survey for sosie validation

## Context

This survey was conducted to identify verification and testing approaches
beyond unit tests, QuickCheck, and property-based testing that could
strengthen sosie's trustworthiness guarantees. The CT-inspired round-trip
framework (C . G = id) already provides automated validation of capture
fidelity. The question is: what else can formal methods bring?

## Tier 1: High value, moderate effort

### 1. Bounded exhaustive testing of the tree matcher (small scope hypothesis)

The GumTree-style matcher is the most complex and heuristic component.
Exhaustive testing of all tree pairs up to a small size is tractable.

With k=3 labels (e.g., `div`, `span`, `p`), all tree pairs where each tree
has <=4 nodes: ~152K pairs (runs in seconds). With <=5 nodes per tree: ~18M
pairs (runs in minutes). Jackson's small scope hypothesis (empirically
validated by Andoni et al., 2003): if a bug exists, it almost certainly
manifests at size <=5.

Properties to check exhaustively:
- Matching is injective (no node matched twice)
- Matched nodes have compatible labels (or a Tag_mismatch diff is emitted)
- Every unmatched node is reported
- Symmetry: diffs(A, B) and diffs(B, A) are consistent
- Transitivity: if compare(A,B) = {} and compare(B,C) = {}, then compare(A,C) = {}
- The matching preserves ancestor/descendant relations

This is strictly stronger than property-based random testing -- it covers
the entire small space, not a sample. Analogous to Korat (Boyapati et al.,
ISSTA 2002).

**Key references:**
- Jackson, D. *Software Abstractions.* MIT Press, 2006/2012.
- Boyapati, C., Khurshid, S., Marinov, D. "Korat: Automated Testing Based
  on Java Predicates." ISSTA 2002.
- Andoni, A. et al. "Evaluating the Small Scope Hypothesis." MIT TR, 2003.

**Combinatorics (ordered labeled trees):**
- Unlabeled ordered trees with n nodes: Catalan number C(n-1).
  C(4)=14, C(5)=42, C(6)=132, C(7)=429.
- With k labels: k^n * C(n-1) trees of size n.
- For k=3, n=5: 3^5 * C(4) = 243 * 14 = 3,402 trees.
- Pairs: 3,402^2 ~ 11.6M. Tractable.
- Reference: Stanley, R. *Enumerative Combinatorics, Vol. 2.* Cambridge, 1999.

### 2. CSS mutation testing

The "dual" of round-trip testing. Mutate known-good pages and verify
detection:

1. Start with identical pages A and A'
2. Apply a mutation operator to A' (change font-size by 1px, swap a color,
   remove a border)
3. Verify via pixel diff that the mutation is actually visible
4. Run sosie compare -- sosie must report a diff
5. Surviving mutants (sosie says "equivalent") are false negatives

CSS mutation operators:
- Value perturbation: font-size: 16px -> 17px
- Value replacement: color: red -> blue
- Property removal: delete border-radius
- Property swap: swap color values between elements
- Unit change: width: 100px -> 100% (where they differ)
- Keyword change: text-align: left -> center
- Shorthand expansion: border: 1px solid red -> individual properties

The mutation score (percentage of visible mutations detected) is a
quantitative measure of sosie's sensitivity.

**Key references:**
- DeMillo, R., Lipton, R., Sayward, F. "Hints on Test Data Selection."
  IEEE Computer 11(4), 1978.
- Yang, X. et al. "Finding and Understanding Bugs in C Compilers."
  PLDI 2011 (Csmith).
- Jia, Y. & Harman, M. "An Analysis and Survey of the Development of
  Mutation Testing." IEEE TSE 37(5), 2011.

### 3. Normalization as a provably confluent, terminating rewrite system

Sosie's normalization rules are term rewrite rules on a tree algebra.

**Termination:** Each rule is idempotent (reaches normal form in one pass).
The measure (|attrs|, inversions, |non_canonical_colors|, |unmasked_text|,
|matchable_subtrees|) ordered lexicographically strictly decreases. Trivially
terminating.

**Confluence:** Rules act on disjoint parts of the node structure. Non-
overlapping TRSs are confluent (Baader & Nipkow, Ch. 6). The one potential
overlap -- two Mask_text rules matching the same node -- should be detected
at config load time.

**Consequence:** Normal forms are unique. Normalization order doesn't matter.
This is a provable property, not an empirical one.

**Key references:**
- Baader, F. & Nipkow, T. *Term Rewriting and All That.* Cambridge, 1998.
- Knuth, D. E. & Bendix, P. B. "Simple Word Problems in Universal Algebras."
  1970.
- Dershowitz, N. "Orderings for Term-Rewriting Systems." TCS 17(3), 1982.

## Tier 2: Moderate value, moderate effort

### 4. Differential testing against pixel differ

Run sosie and a pixel differ on the same inputs. The interesting
disagreement: sosie says "equivalent" but pixels visibly changed. This is a
potential sosie bug (whitelist gap or matcher error).

| Sosie     | Pixel differ | Meaning                           |
|-----------|-------------|-----------------------------------|
| Equiv     | Same        | Agreement                         |
| Different | Different   | Agreement                         |
| Equiv     | Different   | **Potential sosie bug**           |
| Different | Same        | Expected (structural change only) |

Inspired by McKeeman's differential testing (Digital Technical Journal, 1998)
and Csmith (Yang et al., PLDI 2011).

### 5. The whitelist as a Galois connection

The property whitelist is an abstraction function alpha in the Cousot &
Cousot framework:

- alpha: FullVisualState -> WhitelistedState (projection)
- gamma: WhitelistedState -> P(FullVisualState) (concretization)

Sosie's soundness requires **completeness** of this abstraction:
ker(alpha) is a subset of ~visual (the whitelist kernel is contained in the
visual equivalence relation).

The lattice structure: whitelists ordered by inclusion. Adding a property
refines the abstraction (stronger verdict). The optimal whitelist is the
coarsest one where completeness holds.

The `audit-whitelist` command is the empirical completeness check.

**Key references:**
- Cousot, P. & Cousot, R. "Abstract Interpretation: A Unified Lattice Model."
  POPL, 1977.
- Giacobazzi, R. et al. "Making Abstract Interpretations Complete."
  JACM 47(2), 2000.

### 6. Metamorphic relations

Sosie's comparison should satisfy oracle-free structural properties:

- Reflexivity: compare(A, A) = {}
- Symmetry: diffs(A, B) and diffs(B, A) are consistent
- Transitivity: compare(A,B) = {} and compare(B,C) = {} => compare(A,C) = {}
- Monotonicity under irrelevant changes: if compare(A, B) = {}, adding the
  same irrelevant mutation to both preserves equivalence

**Key reference:**
- Chen, T.Y. et al. "Metamorphic Testing: A Review of Challenges and
  Opportunities." ACM Computing Surveys 51(1), 2018.

### 7. Round-trip / lens laws (the CT pattern formalized)

The C . G = id round-trip is an instance of the GetPut lens law (Foster
et al., POPL 2005). The bidirectional programming literature has studied
this pattern extensively.

Related framing: Blum & Kannan's self-testing programs (STOC 1989) --
use algebraic properties of a function to check it without an independent
oracle.

**Key references:**
- Foster, J.N. et al. "Combinators for Bidirectional Tree Transformations."
  POPL 2005.
- Blum, M. & Kannan, S. "Designing Programs That Check Their Work."
  STOC 1989.
- Claessen, K. & Hughes, J. "QuickCheck." ICFP 2000.

## Tier 3: Interesting but lower priority

### 8. Congruence closure / e-graphs

GumTree Phase 1 is equivalent to computing term equality (the finest
congruence). Wrapper transparency could be formalized as an equational
theory: wrap(tag, t) ~ t. Congruence closure modulo that theory would
capture wrapper insertion/removal algebraically.

E-graphs (Willsey et al., POPL 2021) could represent equivalence classes
under normalization. Theoretically clean, practically equivalent to the
current design.

**Key references:**
- Nelson, G. & Oppen, D. C. "Fast Decision Procedures Based on Congruence
  Closure." JACM 27(2), 1980.
- Willsey, M. et al. "egg: Fast and Extensible Equality Saturation."
  POPL 2021.
- Bachmair, L. et al. "Abstract Congruence Closure." JAR 31(2), 2003.

### 9. Model checking the CDP conversation

The CDP conversation is a small state machine (~6 states). TLA+ or SPIN
could verify temporal ordering. Alternatively, encode valid transitions as
an OCaml variant type making invalid states unrepresentable.

**Key references:**
- Lamport, *Specifying Systems.* Addison-Wesley, 2002.
- Newcombe et al. "How Amazon Web Services Uses Formal Methods." CACM, 2015.

### 10. Formal verification in a proof assistant

Verifying the GumTree matcher in Coq/Isabelle would be a research project.
The most tractable piece: verify diff generation (matching -> diff list)
satisfies its spec. Brucker & Herzberg's DOM formalization could be a
foundation.

Not recommended as engineering. Bounded exhaustive testing gives similar
confidence for much less effort.
