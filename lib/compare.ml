(** Lockstep snapshot comparison. *)

open Sosie_shared.Snapshot_types

type path = int list

let child_segment siblings i =
  let child = List.nth siblings i in
  let same_tag_count =
    List.length (List.filter (fun c -> c.tag = child.tag) siblings)
  in
  if same_tag_count <= 1 then child.tag
  else
    (* Count how many earlier siblings share this tag *)
    let pos =
      let rec go j acc = function
        | [] -> acc
        | c :: cs ->
          if j = i then acc
          else go (j + 1) (if c.tag = child.tag then acc + 1 else acc) cs
      in
      go 0 0 siblings
    in
    Printf.sprintf "%s[%d]" child.tag (pos + 1)

let path_to_string root path =
  let buf = Buffer.create 64 in
  Buffer.add_char buf '/';
  Buffer.add_string buf root.tag;
  let rec walk node = function
    | [] -> ()
    | i :: rest ->
      Buffer.add_char buf '/';
      Buffer.add_string buf (child_segment node.children i);
      walk (List.nth node.children i) rest
  in
  walk root path;
  Buffer.contents buf

type diff =
  | Bounds_diff of { path : path; property : string; a : float; b : float }
  | Style_diff of {
      path : path;
      property : string;
      a : css_value;
      b : css_value;
    }
  | Text_diff of { path : path; a : string option; b : string option }
  | Paint_order_diff of { path : path; a : int; b : int }
  | Tag_mismatch of { path : path; a : string; b : string }
  | Extra_node of {
      path : path;
      side : [ `Left | `Right ];
      tag : string;
    }
  | Moved_node of { old_path : path; new_path : path }
  | Wrapper_inserted of { path : path; wrapper_tag : string }
  | Wrapper_removed of { path : path; wrapper_tag : string }

type config = {
  check_bounds : bool;
  check_visual : bool;
  check_text : bool;
  check_paint_order : bool;
  bounds_tolerance : float;
  value_tolerance : float;
}

let default_config =
  {
    check_bounds = true;
    check_visual = true;
    check_text = true;
    check_paint_order = true;
    bounds_tolerance = 0.0;
    value_tolerance = 0.0;
  }

(* --- Internal helpers --- *)

let float_diff tol a b = Float.abs (a -. b) > tol

let compare_css_value tol va vb =
  match (va, vb) with
  | Px a, Px b -> not (float_diff tol a b)
  | Num a, Num b -> not (float_diff tol a b)
  | Color a, Color b -> a = b
  | Str a, Str b -> String.equal a b
  | _ -> false

let compare_bounds config path (a : rect) (b : rect) =
  let tol = config.bounds_tolerance in
  let check name va vb acc =
    if float_diff tol va vb then
      Bounds_diff { path; property = name; a = va; b = vb } :: acc
    else acc
  in
  [] |> check "x" a.x b.x |> check "y" a.y b.y |> check "w" a.w b.w
  |> check "h" a.h b.h
  |> List.rev

let compare_border config path prefix (a : border) (b : border) =
  let tol = config.value_tolerance in
  let check name va vb acc =
    if not (compare_css_value tol va vb) then
      Style_diff { path; property = prefix ^ "-" ^ name; a = va; b = vb }
      :: acc
    else acc
  in
  [] |> check "width" a.width b.width |> check "style" a.style b.style
  |> check "color" a.color b.color
  |> List.rev

let compare_styles config path (a : visual_properties) (b : visual_properties) =
  let tol = config.value_tolerance in
  let check name va vb acc =
    if not (compare_css_value tol va vb) then
      Style_diff { path; property = name; a = va; b = vb } :: acc
    else acc
  in
  let diffs =
    []
    |> check "display" a.display b.display
    |> check "visibility" a.visibility b.visibility
    |> check "opacity" a.opacity b.opacity
    |> check "color" a.color b.color
    |> check "background-color" a.background_color b.background_color
    |> check "font-family" a.font_family b.font_family
    |> check "font-size" a.font_size b.font_size
    |> check "font-weight" a.font_weight b.font_weight
    |> check "line-height" a.line_height b.line_height
    |> check "text-align" a.text_align b.text_align
    |> check "text-decoration" a.text_decoration b.text_decoration
    |> check "border-radius" a.border_radius b.border_radius
    |> check "box-shadow" a.box_shadow b.box_shadow
    |> check "overflow-x" a.overflow_x b.overflow_x
    |> check "overflow-y" a.overflow_y b.overflow_y
    |> check "z-index" a.z_index b.z_index
    |> check "cursor" a.cursor b.cursor
    |> check "text-align-last" a.text_align_last b.text_align_last
    |> check "text-decoration-skip-ink" a.text_decoration_skip_ink b.text_decoration_skip_ink
    |> check "text-underline-offset" a.text_underline_offset b.text_underline_offset
    |> check "text-shadow" a.text_shadow b.text_shadow
    |> check "text-combine-upright" a.text_combine_upright b.text_combine_upright
    |> check "text-emphasis-style" a.text_emphasis_style b.text_emphasis_style
    |> check "text-emphasis-color" a.text_emphasis_color b.text_emphasis_color
    |> check "text-emphasis-position" a.text_emphasis_position b.text_emphasis_position
    |> check "-webkit-text-stroke-width" a.webkit_text_stroke_width b.webkit_text_stroke_width
    |> check "-webkit-text-stroke-color" a.webkit_text_stroke_color b.webkit_text_stroke_color
    |> check "font-palette" a.font_palette b.font_palette
    |> check "writing-mode" a.writing_mode b.writing_mode
    |> check "direction" a.direction b.direction
    |> check "appearance" a.appearance b.appearance
    |> check "accent-color" a.accent_color b.accent_color
    |> check "image-rendering" a.image_rendering b.image_rendering
    |> check "outline-width" a.outline_width b.outline_width
    |> check "outline-style" a.outline_style b.outline_style
    |> check "outline-color" a.outline_color b.outline_color
    |> check "outline-offset" a.outline_offset b.outline_offset
  in
  let diffs = List.rev diffs in
  diffs
  @ compare_border config path "border-top" a.border_top b.border_top
  @ compare_border config path "border-right" a.border_right b.border_right
  @ compare_border config path "border-bottom" a.border_bottom b.border_bottom
  @ compare_border config path "border-left" a.border_left b.border_left

let rec compare_nodes config path (a : node) (b : node) =
  if not (String.equal a.tag b.tag) then
    [ Tag_mismatch { path; a = a.tag; b = b.tag } ]
  else
    let diffs = ref [] in
    let add ds = diffs := !diffs @ ds in
    if config.check_bounds then add (compare_bounds config path a.bounds b.bounds);
    if config.check_visual then add (compare_styles config path a.styles b.styles);
    if config.check_text && a.text <> b.text then
      add [ Text_diff { path; a = a.text; b = b.text } ];
    if config.check_paint_order && a.paint_order <> b.paint_order then
      add [ Paint_order_diff { path; a = a.paint_order; b = b.paint_order } ];
    (* Recurse into paired children *)
    let na = List.length a.children in
    let nb = List.length b.children in
    let min_n = min na nb in
    for i = 0 to min_n - 1 do
      let ca = List.nth a.children i in
      let cb = List.nth b.children i in
      add (compare_nodes config (path @ [ i ]) ca cb)
    done;
    (* Extra children *)
    for i = min_n to na - 1 do
      let c = List.nth a.children i in
      add [ Extra_node { path = path @ [ i ]; side = `Left; tag = c.tag } ]
    done;
    for i = min_n to nb - 1 do
      let c = List.nth b.children i in
      add [ Extra_node { path = path @ [ i ]; side = `Right; tag = c.tag } ]
    done;
    !diffs

let compare config (a : snapshot) (b : snapshot) =
  compare_nodes config [] a.root b.root

(* --- GumTree-matched comparison --- *)

(* Build id -> (node, path) index by pre-order walk.
   IDs are assigned in pre-order to match Gumtree.annotate's numbering. *)
let index_tree root =
  let tbl = Hashtbl.create 64 in
  let rec count n = 1 + List.fold_left (fun acc c -> acc + count c) 0 n.children in
  let rec go path id (n : node) =
    Hashtbl.replace tbl id (n, List.rev path);
    let next = ref (id + 1) in
    List.iteri (fun i child ->
      let child_id = !next in
      go (i :: path) child_id child;
      next := child_id + count child
    ) n.children
  in
  go [] 0 root;
  tbl

(* Detect wrapper insertion: a node in B is a "wrapper" if it has exactly one
   child, that child is matched, and the matched partner in A was a child of
   the B-node's matched parent's partner. *)
let detect_wrappers matching tbl_a tbl_b =
  let wrappers_inserted = ref [] in
  let wrappers_removed = ref [] in
  let n_b = Gumtree.size_b matching in
  let n_a = Gumtree.size_a matching in
  (* Wrapper inserted: unmatched node in B with single child that's matched *)
  for b_id = 0 to n_b - 1 do
    if not (Gumtree.is_matched_b matching b_id) then begin
      let (b_node, b_path) = Hashtbl.find tbl_b b_id in
      (* Check if all children of this unmatched B node are matched *)
      let b_child_count = List.length b_node.children in
      if b_child_count > 0 then begin
        (* Check if this looks like a wrapper: it wraps children that existed
           before. A simple heuristic: unmatched node whose children are all
           matched. *)
        let all_children_ids =
          (* Get the child ids: they follow b_id in pre-order *)
          let collect_child_ids parent_id n =
            let next = ref (parent_id + 1) in
            List.map (fun child ->
              let cid = !next in
              let rec count nd = 1 + List.fold_left (fun acc c -> acc + count c) 0 nd.children in
              next := cid + count child;
              cid
            ) n.children
          in
          collect_child_ids b_id b_node
        in
        let all_matched = List.for_all (Gumtree.is_matched_b matching) all_children_ids in
        if all_matched && b_child_count >= 1 then
          wrappers_inserted := Wrapper_inserted { path = b_path; wrapper_tag = b_node.tag }
                               :: !wrappers_inserted
      end
    end
  done;
  (* Wrapper removed: unmatched node in A with children that are all matched *)
  for a_id = 0 to n_a - 1 do
    if not (Gumtree.is_matched_a matching a_id) then begin
      let (a_node, a_path) = Hashtbl.find tbl_a a_id in
      let a_child_count = List.length a_node.children in
      if a_child_count > 0 then begin
        let all_children_ids =
          let collect_child_ids parent_id n =
            let next = ref (parent_id + 1) in
            List.map (fun child ->
              let cid = !next in
              let rec count nd = 1 + List.fold_left (fun acc c -> acc + count c) 0 nd.children in
              next := cid + count child;
              cid
            ) n.children
          in
          collect_child_ids a_id a_node
        in
        let all_matched = List.for_all (Gumtree.is_matched_a matching) all_children_ids in
        if all_matched && a_child_count >= 1 then
          wrappers_removed := Wrapper_removed { path = a_path; wrapper_tag = a_node.tag }
                              :: !wrappers_removed
      end
    end
  done;
  (List.rev !wrappers_inserted, List.rev !wrappers_removed)

(* Detect moved nodes: matched nodes whose paths differ and whose parents
   are matched to different partners *)
let detect_moves matching tbl_a tbl_b =
  let moves = ref [] in
  let n_a = Gumtree.size_a matching in
  for a_id = 0 to n_a - 1 do
    match Gumtree.partner_of_a matching a_id with
    | None -> ()
    | Some b_id ->
      let (_a_node, a_path) = Hashtbl.find tbl_a a_id in
      let (_b_node, b_path) = Hashtbl.find tbl_b b_id in
      if a_path <> b_path then begin
        (* Only report as moved if not explainable by wrapper insertion/removal.
           Simple check: if path lengths differ by exactly 1, it's likely a
           wrapper change, not a move. We report moves when the parent
           relationship changed. *)
        let parent_changed =
          match a_path, b_path with
          | _ :: _, _ :: _ ->
            (* Compare parent paths *)
            let a_parent = List.rev (List.tl (List.rev a_path)) in
            let b_parent = List.rev (List.tl (List.rev b_path)) in
            a_parent <> b_parent
          | _ -> false
        in
        if parent_changed then
          moves := Moved_node { old_path = a_path; new_path = b_path } :: !moves
      end
  done;
  List.rev !moves

let compare_matched_node config matching tbl_a tbl_b =
  let diffs = ref [] in
  let n_a = Gumtree.size_a matching in
  (* For each matched pair, compare properties *)
  for a_id = 0 to n_a - 1 do
    match Gumtree.partner_of_a matching a_id with
    | None -> ()
    | Some b_id ->
      let (a_node, a_path) = Hashtbl.find tbl_a a_id in
      let (b_node, _b_path) = Hashtbl.find tbl_b b_id in
      if not (String.equal a_node.tag b_node.tag) then
        diffs := Tag_mismatch { path = a_path; a = a_node.tag; b = b_node.tag } :: !diffs
      else begin
        if config.check_bounds then
          diffs := !diffs @ compare_bounds config a_path a_node.bounds b_node.bounds;
        if config.check_visual then
          diffs := !diffs @ compare_styles config a_path a_node.styles b_node.styles;
        if config.check_text && a_node.text <> b_node.text then
          diffs := !diffs @ [ Text_diff { path = a_path; a = a_node.text; b = b_node.text } ];
        if config.check_paint_order && a_node.paint_order <> b_node.paint_order then
          diffs := !diffs @ [ Paint_order_diff { path = a_path; a = a_node.paint_order;
                                                  b = b_node.paint_order } ]
      end
  done;
  (* Unmatched nodes in A (not wrappers) → Extra_node Left *)
  for a_id = 0 to n_a - 1 do
    if not (Gumtree.is_matched_a matching a_id) then begin
      let (a_node, a_path) = Hashtbl.find tbl_a a_id in
      diffs := Extra_node { path = a_path; side = `Left; tag = a_node.tag } :: !diffs
    end
  done;
  (* Unmatched nodes in B → Extra_node Right *)
  let n_b = Gumtree.size_b matching in
  for b_id = 0 to n_b - 1 do
    if not (Gumtree.is_matched_b matching b_id) then begin
      let (b_node, b_path) = Hashtbl.find tbl_b b_id in
      diffs := Extra_node { path = b_path; side = `Right; tag = b_node.tag } :: !diffs
    end
  done;
  List.rev !diffs

let compare_matched config (a : snapshot) (b : snapshot) =
  let matching = Gumtree.match_trees a.root b.root in
  let tbl_a = index_tree a.root in
  let tbl_b = index_tree b.root in
  let prop_diffs = compare_matched_node config matching tbl_a tbl_b in
  let (wrappers_ins, wrappers_rem) = detect_wrappers matching tbl_a tbl_b in
  let moves = detect_moves matching tbl_a tbl_b in
  (* Filter out Extra_node diffs for nodes that are explained by wrapper
     insertion/removal *)
  let wrapper_paths_b = List.map (function
    | Wrapper_inserted { path; _ } -> path
    | _ -> assert false
  ) wrappers_ins in
  let wrapper_paths_a = List.map (function
    | Wrapper_removed { path; _ } -> path
    | _ -> assert false
  ) wrappers_rem in
  let prop_diffs = List.filter (fun d ->
    match d with
    | Extra_node { path; side = `Right; _ } ->
      not (List.mem path wrapper_paths_b)
    | Extra_node { path; side = `Left; _ } ->
      not (List.mem path wrapper_paths_a)
    | _ -> true
  ) prop_diffs in
  prop_diffs @ wrappers_ins @ wrappers_rem @ moves
