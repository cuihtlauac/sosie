(** Longest common subsequence.

    Standard DP implementation for aligning children lists during tree
    matching. O(n*m) time and space where n and m are the input lengths. *)

type 'a edit =
  | Keep of 'a * 'a  (** Element present in both sequences. *)
  | Insert of 'a     (** Element in right only. *)
  | Delete of 'a     (** Element in left only. *)

val diff : eq:('a -> 'a -> bool) -> 'a list -> 'a list -> 'a edit list
(** [diff ~eq xs ys] computes the edit script transforming [xs] into [ys].

    @param eq equality predicate for elements
    @param xs the left (baseline) sequence
    @param ys the right (modified) sequence
    @return edit script in order *)
