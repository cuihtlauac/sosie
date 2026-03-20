(** Lockstep snapshot comparison.

    Walks two snapshot trees in parallel, reporting diffs when nodes differ.
    Correct for same-structure comparisons (CSS-only changes); structural
    changes like wrapper insertions require the GumTree matcher (step 8).

    Normalization is the caller's responsibility: [compare] operates on
    already-normalized snapshots. *)

type path = int list
(** Path from root to a node as a list of child indices.
    E.g., [\[0; 2; 1\]] means root's child 0, then child 2, then child 1. *)

val path_to_string : Sosie_shared.Snapshot_types.node -> path -> string
(** [path_to_string root path] renders [path] as an XPath-like string
    (e.g., ["/HTML/BODY/DIV\[2\]/P"]) by walking the tree. Sibling indices
    are 0-based internally but rendered 1-based with tag disambiguation:
    the index is omitted when a tag is unique among its siblings.

    @param root the root node of the snapshot tree
    @param path the path to render
    @return the XPath-like string representation *)

type diff =
  | Bounds_diff of {
      path : path;
      property : string;
      a : float;
      b : float;
    }
  | Style_diff of {
      path : path;
      property : string;
      a : Sosie_shared.Snapshot_types.css_value;
      b : Sosie_shared.Snapshot_types.css_value;
    }
  | Text_diff of {
      path : path;
      a : string option;
      b : string option;
    }
  | Paint_order_diff of { path : path; a : int; b : int }
  | Tag_mismatch of { path : path; a : string; b : string }
  | Extra_node of {
      path : path;
      side : [ `Left | `Right ];
      tag : string;
    }
  | Moved_node of {
      old_path : path;
      new_path : path;
    }
  | Wrapper_inserted of {
      path : path;
      wrapper_tag : string;
    }
  | Wrapper_removed of {
      path : path;
      wrapper_tag : string;
    }
(** A single difference between two snapshot trees. *)

type config = {
  check_bounds : bool;
  check_visual : bool;
  check_text : bool;
  check_paint_order : bool;
  bounds_tolerance : float;
  value_tolerance : float;
}
(** Comparison configuration controlling which checks are enabled and
    what numerical tolerances to apply. *)

val default_config : config
(** All checks enabled, tolerances at [0.0]. *)

val compare :
  config ->
  Sosie_shared.Snapshot_types.snapshot ->
  Sosie_shared.Snapshot_types.snapshot ->
  diff list
(** [compare config a b] walks the two snapshot trees in lockstep and
    returns all differences found. The returned list is in tree-traversal
    order (pre-order, depth-first).

    When a [Tag_mismatch] is found, recursion into that subtree stops.
    Extra children on either side produce [Extra_node] diffs.

    @param config comparison configuration
    @param a the "before" snapshot
    @param b the "after" snapshot
    @return list of diffs, empty if the snapshots are equivalent *)

val compare_matched :
  config ->
  Sosie_shared.Snapshot_types.snapshot ->
  Sosie_shared.Snapshot_types.snapshot ->
  diff list
(** [compare_matched config a b] uses GumTree matching to tolerate structural
    changes (wrapper insertion/removal, child reorder) while detecting visual
    regressions. Produces [Moved_node], [Wrapper_inserted], and
    [Wrapper_removed] diffs in addition to the standard property diffs.

    @param config comparison configuration
    @param a the "before" snapshot
    @param b the "after" snapshot
    @return list of diffs, empty if the snapshots are equivalent *)
