(** Self-contained HTML diff report with side-by-side screenshots.

    Generates a single HTML file containing base64-encoded screenshots,
    colored diff overlays (SVG), click-to-inspect tooltips, and diff-type
    filter checkboxes. No external dependencies — the report is fully
    self-contained and can be opened in any browser.

    Overlay colors follow the diff type:
    - Red: style diffs
    - Orange: bounds diffs
    - Blue: structural diffs (tag mismatch, extra/missing nodes)
    - Purple: moved nodes *)

val diff_to_json :
  root_a:Sosie_shared.Snapshot_types.node ->
  root_b:Sosie_shared.Snapshot_types.node ->
  Compare.diff ->
  Yojson.Safe.t
(** Serialize a single diff to a JSON object with type, paths, bounds,
    and property details. Used to embed diff data in the report.
    @param root_a the baseline snapshot root (for path resolution).
    @param root_b the modified snapshot root (for path resolution). *)

val diffs_to_json :
  root_a:Sosie_shared.Snapshot_types.node ->
  root_b:Sosie_shared.Snapshot_types.node ->
  Compare.diff list ->
  string
(** Serialize the full diff list to a JSON array string. *)

val generate :
  root_a:Sosie_shared.Snapshot_types.node ->
  root_b:Sosie_shared.Snapshot_types.node ->
  diffs:Compare.diff list ->
  screenshot_a:string ->
  screenshot_b:string ->
  string
(** [generate ~root_a ~root_b ~diffs ~screenshot_a ~screenshot_b] produces
    a self-contained HTML report string.

    @param root_a baseline snapshot root.
    @param root_b modified snapshot root.
    @param diffs the list of diffs from {!Compare.compare_matched}.
    @param screenshot_a raw PNG bytes of the baseline page.
    @param screenshot_b raw PNG bytes of the modified page.
    @return complete HTML document as a string. *)
