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
