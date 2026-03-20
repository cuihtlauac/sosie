(** GumTree-style three-phase tree matcher.

    Produces a mapping between nodes of two snapshot trees. The matching
    tolerates structural changes (wrapper insertion/removal, child reorder)
    while preserving identity of unchanged subtrees.

    Reference: Falleri et al., "Fine-grained and Accurate Source Code
    Differencing", ASE 2014. *)

type node_id = int
(** Unique node identifier (pre-order index in the tree). *)

type matching
(** A bidirectional mapping between nodes of two trees. *)

val match_trees :
  Sosie_shared.Snapshot_types.node ->
  Sosie_shared.Snapshot_types.node ->
  matching
(** [match_trees a b] computes a matching between the nodes of [a] and [b]
    using the three-phase GumTree algorithm:
    - Phase 1: bottom-up hash matching (identical subtrees)
    - Phase 2: container matching via dice coefficient
    - Phase 3: children alignment via LCS

    @param a the baseline tree root
    @param b the modified tree root
    @return the computed matching *)

val is_matched_a : matching -> node_id -> bool
(** [is_matched_a m id] is [true] if node [id] in tree A has a partner. *)

val is_matched_b : matching -> node_id -> bool
(** [is_matched_b m id] is [true] if node [id] in tree B has a partner. *)

val partner_of_a : matching -> node_id -> node_id option
(** [partner_of_a m id] returns the partner of node [id] in tree A. *)

val partner_of_b : matching -> node_id -> node_id option
(** [partner_of_b m id] returns the partner of node [id] in tree B. *)

val size_a : matching -> int
(** Number of nodes in tree A. *)

val size_b : matching -> int
(** Number of nodes in tree B. *)
