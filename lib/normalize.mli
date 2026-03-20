(** Snapshot normalization rules.

    Pure [snapshot -> snapshot] transforms that remove dynamic content,
    layout noise, and style variant differences before comparison.
    Each rule is a recursive tree transform applied to every node in
    the snapshot.

    Rules are constructed programmatically in code and tests. Config
    file parsing is a CLI concern, not part of this module. *)

type simple_selector =
  | Tag of string  (** Match on tag name (case-insensitive). *)
  | Id of string  (** Match on the [id] attribute value. *)
  | Class of string
      (** Match on membership in the space-separated [class] attribute. *)
  | Universal  (** Match any node. *)
(** A simple selector for matching nodes. *)

type attr_pattern =
  | Exact of string  (** Exact attribute name match. *)
  | Prefix of string  (** Attribute name prefix match. *)
(** Pattern for matching attribute names. [Exact "class"] matches the
    attribute named ["class"]. [Prefix "data-"] matches any attribute
    whose name starts with ["data-"]. *)

type rule =
  | Drop_attributes of attr_pattern list
      (** Remove attributes matching any of the given patterns. *)
  | Mask_text of { selector : simple_selector; replacement : string }
      (** Replace [text] of nodes matching [selector] (and [#text] children
          whose parent matches) with [replacement]. *)
  | Mask_text_matching of { pattern : Re.re; replacement : string }
      (** Apply regex replacement to [text] fields across all nodes. *)
  | Drop_subtree of simple_selector
      (** Remove children matching [selector] from their parent's child list. *)
  | Round_bounds of float
      (** Round [x], [y], [w], [h] to the nearest multiple of the given step. *)
  | Canonicalize_colors
      (** Normalize color strings: strip whitespace, convert
          [rgba(r,g,b,1)] to [rgb(r,g,b)]. *)
  | Canonicalize_fonts
      (** Keep first named font + first generic family from [font-family]. *)
  | Sort_attributes  (** Sort [node.attributes] lexicographically. *)
(** A normalization rule. Rules are applied in order by {!apply}. *)

val apply : rule list -> Sosie_shared.Snapshot_types.snapshot ->
  Sosie_shared.Snapshot_types.snapshot
(** [apply rules snapshot] applies each rule sequentially to [snapshot],
    returning the normalized snapshot. An empty rule list is the identity
    function.

    @param rules the normalization rules to apply in order
    @return the snapshot with all rules applied *)
