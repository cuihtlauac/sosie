(** Snapshot round-trip generator.

    Converts a {!Snapshot_types.snapshot} into a minimal HTML document whose
    captured snapshot should reproduce the original. Every element node becomes
    an absolutely-positioned [<div>] with inline styles matching the snapshot's
    visual properties. Bounds are converted from page-absolute (as returned by
    [getBoundingClientRect]) to parent-relative CSS coordinates.

    This is the generator G in the round-trip property C ∘ G = id, which
    validates capture fidelity without human inspection. *)

type t = Sosie_shared.Snapshot_types.snapshot

val to_html : t -> string
(** Generate a self-contained HTML document that, when captured by the
    extractor, should produce the given snapshot.

    Every element node is emitted as a positioned [<div>] with all 29 CSS
    properties set as inline styles. Text nodes are skipped (they depend on
    font metrics and cannot round-trip reliably).

    The generated tree is wrapped in a [<div id="sosie-root">] inside
    [<body>], so round-trip tests can locate and compare the subtree
    independently of browser-added wrapper structure.

    @param t must have all CSS values in [Str] form (as produced by the
    extractor). *)
