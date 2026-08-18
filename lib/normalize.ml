(** Snapshot normalization rules.

    See {!Normalize} (the .mli) for documentation. *)

open Sosie_shared.Snapshot_types

type simple_selector = Tag of string | Id of string | Class of string | Universal

type attr_pattern = Exact of string | Prefix of string

type rule =
  | Drop_attributes of attr_pattern list
  | Mask_text of { selector : simple_selector; replacement : string }
  | Mask_text_matching of { pattern : Re.re; replacement : string }
  | Drop_subtree of simple_selector
  | Round_bounds of float
  | Canonicalize_colors
  | Canonicalize_fonts
  | Sort_attributes
  | Drop_invisible

(* --- Selector matching --- *)

let matches_selector sel (node : node) =
  match sel with
  | Tag t -> String.lowercase_ascii node.tag = String.lowercase_ascii t
  | Id id ->
    List.exists (fun (k, v) -> k = "id" && v = id) node.attributes
  | Class cls ->
    List.exists
      (fun (k, v) ->
        k = "class" && List.mem cls (String.split_on_char ' ' v))
      node.attributes
  | Universal -> true

(* --- Attribute pattern matching --- *)

let matches_attr_pattern pat name =
  match pat with
  | Exact s -> name = s
  | Prefix p ->
    let lp = String.length p in
    String.length name >= lp && String.sub name 0 lp = p

let attr_matches_any pats (name, _) =
  List.exists (fun pat -> matches_attr_pattern pat name) pats

(* --- Recursive node mapping --- *)

let rec map_node f (node : node) : node =
  let children = List.map (map_node f) node.children in
  f { node with children }

let apply_to_root f (snap : snapshot) : snapshot =
  { snap with root = map_node f snap.root }

(* --- Drop_attributes --- *)

let drop_attributes pats (node : node) : node =
  { node with attributes = List.filter (fun a -> not (attr_matches_any pats a)) node.attributes }

(* --- Sort_attributes --- *)

let sort_attributes (node : node) : node =
  { node with attributes = List.sort compare node.attributes }

(* --- Round_bounds --- *)

let round_to step v =
  if step <= 0.0 then v
  else Float.round (v /. step) *. step

let round_bounds step (node : node) : node =
  let b = node.bounds in
  let bounds =
    { x = round_to step b.x;
      y = round_to step b.y;
      w = round_to step b.w;
      h = round_to step b.h }
  in
  { node with bounds }

(* --- Mask_text --- *)

(** Mask text on the node itself (if it matches the selector) and on
    [#text] children whose parent matches. *)
let mask_text sel replacement (node : node) : node =
  let node =
    if matches_selector sel node then
      match node.text with
      | Some _ -> { node with text = Some replacement }
      | None -> node
    else node
  in
  (* Also mask #text children if parent matches the selector *)
  if matches_selector sel node then
    let children =
      List.map
        (fun (child : node) ->
          if child.tag = "#text" then
            match child.text with
            | Some _ -> { child with text = Some replacement }
            | None -> child
          else child)
        node.children
    in
    { node with children }
  else node

(* --- Mask_text_matching --- *)

let mask_text_matching pattern replacement (node : node) : node =
  match node.text with
  | Some t ->
    let t' = Re.replace pattern ~f:(fun _ -> replacement) t in
    { node with text = Some t' }
  | None -> node

(* --- Drop_subtree --- *)

let drop_subtree sel (node : node) : node =
  let children =
    List.filter (fun (child : node) -> not (matches_selector sel child)) node.children
  in
  { node with children }

(* --- Color canonicalization --- *)

let strip_spaces s =
  let buf = Buffer.create (String.length s) in
  String.iter (fun c -> if c <> ' ' then Buffer.add_char buf c) s;
  Buffer.contents buf

(** Parse an int from a string, returning None on failure. *)
let int_of_string_opt s =
  match int_of_string s with
  | n -> Some n
  | exception Failure _ -> None

(** Parse a float from a string, returning None on failure. *)
let float_of_string_opt' s =
  match float_of_string s with
  | f -> Some f
  | exception Failure _ -> None

(** Canonicalize a single color string. Normalizes whitespace and converts
    [rgba(r,g,b,1)] to [rgb(r,g,b)]. Returns the original string if it
    doesn't match a recognized color pattern. *)
let canonicalize_color_str s =
  let s = strip_spaces s in
  (* Try rgba(r,g,b,a) *)
  if String.length s > 5 && String.sub s 0 5 = "rgba(" && s.[String.length s - 1] = ')' then
    let inner = String.sub s 5 (String.length s - 6) in
    match String.split_on_char ',' inner with
    | [r; g; b; a] ->
      (match int_of_string_opt r, int_of_string_opt g,
             int_of_string_opt b, float_of_string_opt' a with
       | Some ri, Some gi, Some bi, Some af ->
         if af = 1.0 then
           Printf.sprintf "rgb(%d, %d, %d)" ri gi bi
         else
           Printf.sprintf "rgba(%d, %d, %d, %g)" ri gi bi af
       | _ -> s)
    | _ -> s
  (* Try rgb(r,g,b) *)
  else if String.length s > 4 && String.sub s 0 4 = "rgb(" && s.[String.length s - 1] = ')' then
    let inner = String.sub s 4 (String.length s - 5) in
    match String.split_on_char ',' inner with
    | [r; g; b] ->
      (match int_of_string_opt r, int_of_string_opt g, int_of_string_opt b with
       | Some ri, Some gi, Some bi ->
         Printf.sprintf "rgb(%d, %d, %d)" ri gi bi
       | _ -> s)
    | _ -> s
  else s

let canonicalize_color_value (v : css_value) : css_value =
  match v with
  | Str s -> Str (canonicalize_color_str s)
  | _ -> v

(** Apply color canonicalization to all color-bearing properties. *)
let canonicalize_colors_node (node : node) : node =
  let s = node.styles in
  let canon_border (b : border) : border =
    { b with color = canonicalize_color_value b.color }
  in
  let styles =
    { s with
      color = canonicalize_color_value s.color;
      background_color = canonicalize_color_value s.background_color;
      text_decoration = canonicalize_color_value s.text_decoration;
      box_shadow = canonicalize_color_value s.box_shadow;
      text_shadow = canonicalize_color_value s.text_shadow;
      text_emphasis_color = canonicalize_color_value s.text_emphasis_color;
      webkit_text_stroke_color = canonicalize_color_value s.webkit_text_stroke_color;
      accent_color = canonicalize_color_value s.accent_color;
      outline_color = canonicalize_color_value s.outline_color;
      fill = canonicalize_color_value s.fill;
      stroke = canonicalize_color_value s.stroke;
      border_top = canon_border s.border_top;
      border_right = canon_border s.border_right;
      border_bottom = canon_border s.border_bottom;
      border_left = canon_border s.border_left }
  in
  { node with styles }

(* --- Font canonicalization --- *)

let generic_families =
  [ "serif"; "sans-serif"; "monospace"; "cursive"; "fantasy";
    "system-ui"; "ui-serif"; "ui-sans-serif"; "ui-monospace";
    "ui-rounded"; "math"; "emoji"; "fangsong" ]

let is_generic family =
  List.mem (String.lowercase_ascii family) generic_families

let canonicalize_font_str s =
  let parts = String.split_on_char ',' s in
  let parts = List.map String.trim parts in
  let first_named = List.find_opt (fun p -> p <> "" && not (is_generic p)) parts in
  let first_generic = List.find_opt (fun p -> p <> "" && is_generic p) parts in
  match first_named, first_generic with
  | Some n, Some g -> n ^ ", " ^ g
  | Some n, None -> n
  | None, Some g -> g
  | None, None -> s

let canonicalize_font_value (v : css_value) : css_value =
  match v with
  | Str s -> Str (canonicalize_font_str s)
  | _ -> v

let canonicalize_fonts_node (node : node) : node =
  let s = node.styles in
  { node with styles = { s with font_family = canonicalize_font_value s.font_family } }

(* --- Drop_invisible --- *)

(** A node is invisible if it has [display: none], or if it has zero-size
    bounds and [visibility: hidden]. Such nodes do not affect visual output. *)
let is_invisible (node : node) : bool =
  match node.styles.display with
  | Str "none" -> true
  | _ ->
    node.bounds.w = 0.0 && node.bounds.h = 0.0
    && (match node.styles.visibility with Str "hidden" -> true | _ -> false)

let drop_invisible (node : node) : node =
  { node with children = List.filter (fun c -> not (is_invisible c)) node.children }

(* --- apply --- *)

let apply_rule (rule : rule) (snap : snapshot) : snapshot =
  match rule with
  | Drop_attributes pats -> apply_to_root (drop_attributes pats) snap
  | Sort_attributes -> apply_to_root sort_attributes snap
  | Round_bounds step -> apply_to_root (round_bounds step) snap
  | Mask_text { selector; replacement } ->
    apply_to_root (mask_text selector replacement) snap
  | Mask_text_matching { pattern; replacement } ->
    apply_to_root (mask_text_matching pattern replacement) snap
  | Drop_subtree sel -> apply_to_root (drop_subtree sel) snap
  | Canonicalize_colors -> apply_to_root canonicalize_colors_node snap
  | Canonicalize_fonts -> apply_to_root canonicalize_fonts_node snap
  | Drop_invisible -> apply_to_root drop_invisible snap

let apply rules snap =
  List.fold_left (fun s r -> apply_rule r s) snap rules
