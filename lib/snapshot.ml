(** Snapshot parsing and serialization.

    See {!Snapshot} (the .mli) for documentation. *)

open Sosie_shared.Snapshot_types

type t = snapshot

(* -- JSON helpers -------------------------------------------------------- *)

let fail_field name = failwith (Printf.sprintf "missing or invalid field: %s" name)

let get key = function
  | `Assoc fields -> (
      match List.assoc_opt key fields with
      | Some v -> v
      | None -> fail_field key)
  | _ -> fail_field key

let to_string = function
  | `String s -> s
  | _ -> failwith "expected string"

let to_int = function
  | `Int i -> i
  | _ -> failwith "expected int"

let to_float = function
  | `Float f -> f
  | `Int i -> Float.of_int i
  | _ -> failwith "expected number"

(* -- Parsing ------------------------------------------------------------- *)

let rect_of_json j : rect =
  {
    x = to_float (get "x" j);
    y = to_float (get "y" j);
    w = to_float (get "w" j);
    h = to_float (get "h" j);
  }

let css_str key j : css_value =
  Str (to_string (get key j))

let border_of_json side j : border =
  {
    width = css_str (side ^ "-width") j;
    style = css_str (side ^ "-style") j;
    color = css_str (side ^ "-color") j;
  }

let styles_of_json j : visual_properties =
  {
    display = css_str "display" j;
    visibility = css_str "visibility" j;
    opacity = css_str "opacity" j;
    color = css_str "color" j;
    background_color = css_str "background-color" j;
    font_family = css_str "font-family" j;
    font_size = css_str "font-size" j;
    font_weight = css_str "font-weight" j;
    line_height = css_str "line-height" j;
    text_align = css_str "text-align" j;
    text_decoration = css_str "text-decoration" j;
    border_top = border_of_json "border-top" j;
    border_right = border_of_json "border-right" j;
    border_bottom = border_of_json "border-bottom" j;
    border_left = border_of_json "border-left" j;
    border_radius = css_str "border-radius" j;
    box_shadow = css_str "box-shadow" j;
    overflow_x = css_str "overflow-x" j;
    overflow_y = css_str "overflow-y" j;
    z_index = css_str "z-index" j;
    cursor = css_str "cursor" j;
    text_align_last = css_str "text-align-last" j;
    text_decoration_skip_ink = css_str "text-decoration-skip-ink" j;
    text_underline_offset = css_str "text-underline-offset" j;
    text_shadow = css_str "text-shadow" j;
    text_combine_upright = css_str "text-combine-upright" j;
    text_emphasis_style = css_str "text-emphasis-style" j;
    text_emphasis_color = css_str "text-emphasis-color" j;
    text_emphasis_position = css_str "text-emphasis-position" j;
    webkit_text_stroke_width = css_str "-webkit-text-stroke-width" j;
    webkit_text_stroke_color = css_str "-webkit-text-stroke-color" j;
    font_palette = css_str "font-palette" j;
    writing_mode = css_str "writing-mode" j;
    direction = css_str "direction" j;
    appearance = css_str "appearance" j;
    accent_color = css_str "accent-color" j;
    image_rendering = css_str "image-rendering" j;
    outline_width = css_str "outline-width" j;
    outline_style = css_str "outline-style" j;
    outline_color = css_str "outline-color" j;
    outline_offset = css_str "outline-offset" j;
  }

let attributes_of_json = function
  | `List pairs ->
      List.filter_map
        (function
          | `List [ `String k; `String v ] -> Some (k, v)
          | _ -> None)
        pairs
  | _ -> failwith "attributes must be an array"

let rec node_of_json j : node =
  let text =
    match get "text" j with
    | `Null -> None
    | `String s -> Some s
    | _ -> failwith "text must be string or null"
  in
  let children =
    match get "children" j with
    | `List cs -> List.map node_of_json cs
    | _ -> failwith "children must be an array"
  in
  {
    tag = to_string (get "tag" j);
    attributes = attributes_of_json (get "attributes" j);
    bounds = rect_of_json (get "bounds" j);
    styles = styles_of_json (get "styles" j);
    text;
    paint_order = to_int (get "paintOrder" j);
    children;
  }

let color_scheme_of_json = function
  | `String "light" -> `Light
  | `String "dark" -> `Dark
  | _ -> failwith "colorScheme must be \"light\" or \"dark\""

let viewport_of_json = function
  | `List [ w; h ] -> (to_int w, to_int h)
  | _ -> failwith "viewport must be a 2-element array"

let of_json j : t =
  let version = to_int (get "version" j) in
  if version <> 1 then
    failwith (Printf.sprintf "unsupported snapshot version: %d" version);
  {
    version;
    url = to_string (get "url" j);
    viewport = viewport_of_json (get "viewport" j);
    color_scheme = color_scheme_of_json (get "colorScheme" j);
    root = node_of_json (get "root" j);
  }

(* -- Serialization ------------------------------------------------------- *)

let json_of_rect (r : rect) : Yojson.Safe.t =
  `Assoc [
    ("x", `Float r.x);
    ("y", `Float r.y);
    ("w", `Float r.w);
    ("h", `Float r.h);
  ]

let json_of_css_value (v : css_value) : Yojson.Safe.t =
  match v with
  | Str s -> `String s
  | Px f -> `String (Printf.sprintf "%gpx" f)
  | Num f -> `String (Printf.sprintf "%g" f)
  | Color c -> `String (Printf.sprintf "#%08x" c)

let json_of_styles (vp : visual_properties) : Yojson.Safe.t =
  `Assoc [
    ("display", json_of_css_value vp.display);
    ("visibility", json_of_css_value vp.visibility);
    ("opacity", json_of_css_value vp.opacity);
    ("color", json_of_css_value vp.color);
    ("background-color", json_of_css_value vp.background_color);
    ("font-family", json_of_css_value vp.font_family);
    ("font-size", json_of_css_value vp.font_size);
    ("font-weight", json_of_css_value vp.font_weight);
    ("line-height", json_of_css_value vp.line_height);
    ("text-align", json_of_css_value vp.text_align);
    ("text-decoration", json_of_css_value vp.text_decoration);
    ("border-top-width", json_of_css_value vp.border_top.width);
    ("border-top-style", json_of_css_value vp.border_top.style);
    ("border-top-color", json_of_css_value vp.border_top.color);
    ("border-right-width", json_of_css_value vp.border_right.width);
    ("border-right-style", json_of_css_value vp.border_right.style);
    ("border-right-color", json_of_css_value vp.border_right.color);
    ("border-bottom-width", json_of_css_value vp.border_bottom.width);
    ("border-bottom-style", json_of_css_value vp.border_bottom.style);
    ("border-bottom-color", json_of_css_value vp.border_bottom.color);
    ("border-left-width", json_of_css_value vp.border_left.width);
    ("border-left-style", json_of_css_value vp.border_left.style);
    ("border-left-color", json_of_css_value vp.border_left.color);
    ("border-radius", json_of_css_value vp.border_radius);
    ("box-shadow", json_of_css_value vp.box_shadow);
    ("overflow-x", json_of_css_value vp.overflow_x);
    ("overflow-y", json_of_css_value vp.overflow_y);
    ("z-index", json_of_css_value vp.z_index);
    ("cursor", json_of_css_value vp.cursor);
    ("text-align-last", json_of_css_value vp.text_align_last);
    ("text-decoration-skip-ink", json_of_css_value vp.text_decoration_skip_ink);
    ("text-underline-offset", json_of_css_value vp.text_underline_offset);
    ("text-shadow", json_of_css_value vp.text_shadow);
    ("text-combine-upright", json_of_css_value vp.text_combine_upright);
    ("text-emphasis-style", json_of_css_value vp.text_emphasis_style);
    ("text-emphasis-color", json_of_css_value vp.text_emphasis_color);
    ("text-emphasis-position", json_of_css_value vp.text_emphasis_position);
    ("-webkit-text-stroke-width", json_of_css_value vp.webkit_text_stroke_width);
    ("-webkit-text-stroke-color", json_of_css_value vp.webkit_text_stroke_color);
    ("font-palette", json_of_css_value vp.font_palette);
    ("writing-mode", json_of_css_value vp.writing_mode);
    ("direction", json_of_css_value vp.direction);
    ("appearance", json_of_css_value vp.appearance);
    ("accent-color", json_of_css_value vp.accent_color);
    ("image-rendering", json_of_css_value vp.image_rendering);
    ("outline-width", json_of_css_value vp.outline_width);
    ("outline-style", json_of_css_value vp.outline_style);
    ("outline-color", json_of_css_value vp.outline_color);
    ("outline-offset", json_of_css_value vp.outline_offset);
  ]

let rec json_of_node (n : node) : Yojson.Safe.t =
  let text = match n.text with None -> `Null | Some s -> `String s in
  `Assoc [
    ("tag", `String n.tag);
    ("attributes",
     `List (List.map (fun (k, v) -> `List [ `String k; `String v ]) n.attributes));
    ("bounds", json_of_rect n.bounds);
    ("styles", json_of_styles n.styles);
    ("text", text);
    ("paintOrder", `Int n.paint_order);
    ("children", `List (List.map json_of_node n.children));
  ]

let to_json (s : t) : Yojson.Safe.t =
  let vw, vh = s.viewport in
  let scheme = match s.color_scheme with `Light -> "light" | `Dark -> "dark" in
  `Assoc [
    ("version", `Int s.version);
    ("url", `String s.url);
    ("viewport", `List [ `Int vw; `Int vh ]);
    ("colorScheme", `String scheme);
    ("root", json_of_node s.root);
  ]

(* -- Pretty-printer ------------------------------------------------------ *)

let pp_css fmt (v : css_value) =
  match v with
  | Str s -> Format.fprintf fmt "%s" s
  | Px f -> Format.fprintf fmt "%gpx" f
  | Num f -> Format.fprintf fmt "%g" f
  | Color c -> Format.fprintf fmt "#%08x" c

let rec pp_node indent fmt (n : node) =
  let pad = String.make (indent * 2) ' ' in
  Format.fprintf fmt "%s<%s" pad n.tag;
  List.iter (fun (k, v) -> Format.fprintf fmt " %s=%S" k v) n.attributes;
  Format.fprintf fmt ">@\n";
  Format.fprintf fmt "%s  bounds: %.1f,%.1f %.1fx%.1f@\n"
    pad n.bounds.x n.bounds.y n.bounds.w n.bounds.h;
  (match n.text with
   | Some t -> Format.fprintf fmt "%s  text: %S@\n" pad t
   | None -> ());
  Format.fprintf fmt "%s  display: %a@\n" pad pp_css n.styles.display;
  List.iter (pp_node (indent + 1) fmt) n.children

let pp fmt (s : t) =
  let vw, vh = s.viewport in
  let scheme = match s.color_scheme with `Light -> "light" | `Dark -> "dark" in
  Format.fprintf fmt "snapshot v%d %s %dx%d %s@\n"
    s.version s.url vw vh scheme;
  pp_node 0 fmt s.root
