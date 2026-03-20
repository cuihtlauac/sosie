(** Human-readable diff formatting.

    Formats {!Compare.diff} values as text suitable for terminal output.
    Path rendering uses XPath-like notation via {!Compare.path_to_string}. *)

val css_value_to_string : Sosie_shared.Snapshot_types.css_value -> string
(** Format a CSS value for display. *)

val format_diff :
  Sosie_shared.Snapshot_types.node -> Compare.diff -> string
(** [format_diff root diff] formats a single diff as a human-readable line,
    using the root node to resolve paths to XPath strings. *)

val format_diffs :
  Sosie_shared.Snapshot_types.node -> Compare.diff list -> string
(** Format a full diff list, one diff per line. *)

val summary : Compare.diff list -> string
(** One-line summary: "N diffs (M bounds, P style, ...)" or "no diffs". *)
