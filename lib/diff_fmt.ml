(** Human-readable diff formatting. *)

open Sosie_shared.Snapshot_types

let css_value_to_string = function
  | Px f -> Printf.sprintf "%.4gpx" f
  | Num f -> Printf.sprintf "%.4g" f
  | Color c ->
    let r = (c lsr 24) land 0xFF in
    let g = (c lsr 16) land 0xFF in
    let b = (c lsr 8) land 0xFF in
    let a = c land 0xFF in
    if a = 255 then Printf.sprintf "rgb(%d, %d, %d)" r g b
    else Printf.sprintf "rgba(%d, %d, %d, %.2g)" r g b (Float.of_int a /. 255.0)
  | Str s -> s

let opt_to_string = function Some s -> Printf.sprintf "%S" s | None -> "(none)"

let format_diff root diff =
  let path_str path = Compare.path_to_string root path in
  match diff with
  | Compare.Bounds_diff { path; property; a; b } ->
    Printf.sprintf "%s  bounds %s: %.4g -> %.4g" (path_str path) property a b
  | Compare.Style_diff { path; property; a; b } ->
    Printf.sprintf "%s  style %s: %s -> %s"
      (path_str path) property (css_value_to_string a) (css_value_to_string b)
  | Compare.Text_diff { path; a; b } ->
    Printf.sprintf "%s  text: %s -> %s" (path_str path) (opt_to_string a) (opt_to_string b)
  | Compare.Paint_order_diff { path; a; b } ->
    Printf.sprintf "%s  paint-order: %d -> %d" (path_str path) a b
  | Compare.Tag_mismatch { path; a; b } ->
    Printf.sprintf "%s  tag mismatch: %s vs %s" (path_str path) a b
  | Compare.Extra_node { path; side; tag } ->
    let side_str = match side with `Left -> "baseline" | `Right -> "modified" in
    Printf.sprintf "%s  extra %s node: %s" (path_str path) side_str tag

let format_diffs root diffs =
  String.concat "\n" (List.map (format_diff root) diffs)

let summary diffs =
  match diffs with
  | [] -> "no diffs"
  | _ ->
    let bounds = ref 0 in
    let style = ref 0 in
    let text = ref 0 in
    let paint = ref 0 in
    let tag = ref 0 in
    let extra = ref 0 in
    List.iter (function
      | Compare.Bounds_diff _ -> incr bounds
      | Compare.Style_diff _ -> incr style
      | Compare.Text_diff _ -> incr text
      | Compare.Paint_order_diff _ -> incr paint
      | Compare.Tag_mismatch _ -> incr tag
      | Compare.Extra_node _ -> incr extra
    ) diffs;
    let parts = ref [] in
    let add n label = if n > 0 then parts := Printf.sprintf "%d %s" n label :: !parts in
    add !extra "extra";
    add !tag "tag";
    add !paint "paint-order";
    add !text "text";
    add !style "style";
    add !bounds "bounds";
    Printf.sprintf "%d diffs (%s)" (List.length diffs) (String.concat ", " !parts)
