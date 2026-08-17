(** Snapshot round-trip generator.

    See {!Snapshot_gen} (the .mli) for documentation. *)

open Sosie_shared.Snapshot_types

type t = snapshot

(* -- CSS value to string ------------------------------------------------- *)

let css_value_to_string (v : css_value) =
  match v with
  | Str s -> s
  | Px f -> Printf.sprintf "%gpx" f
  | Num f -> Printf.sprintf "%g" f
  | Color c -> Printf.sprintf "#%08x" c

(* -- HTML escaping ------------------------------------------------------- *)

let escape_html s =
  let buf = Buffer.create (String.length s) in
  String.iter
    (function
      | '&' -> Buffer.add_string buf "&amp;"
      | '<' -> Buffer.add_string buf "&lt;"
      | '>' -> Buffer.add_string buf "&gt;"
      | '"' -> Buffer.add_string buf "&quot;"
      | c -> Buffer.add_char buf c)
    s;
  Buffer.contents buf

(* -- Style generation ---------------------------------------------------- *)

let border_styles buf side (b : border) =
  Printf.bprintf buf "border-%s-width:%s;" side (css_value_to_string b.width);
  Printf.bprintf buf "border-%s-style:%s;" side (css_value_to_string b.style);
  Printf.bprintf buf "border-%s-color:%s;" side (css_value_to_string b.color)

let style_attr (vp : visual_properties) ~left ~top ~width ~height =
  let buf = Buffer.create 512 in
  Printf.bprintf buf "position:absolute;";
  Printf.bprintf buf "left:%gpx;top:%gpx;width:%gpx;height:%gpx;" left top width height;
  Printf.bprintf buf "box-sizing:border-box;";
  Printf.bprintf buf "display:%s;" (css_value_to_string vp.display);
  Printf.bprintf buf "visibility:%s;" (css_value_to_string vp.visibility);
  Printf.bprintf buf "opacity:%s;" (css_value_to_string vp.opacity);
  Printf.bprintf buf "color:%s;" (css_value_to_string vp.color);
  Printf.bprintf buf "background-color:%s;" (css_value_to_string vp.background_color);
  Printf.bprintf buf "font-family:%s;" (css_value_to_string vp.font_family);
  Printf.bprintf buf "font-size:%s;" (css_value_to_string vp.font_size);
  Printf.bprintf buf "font-weight:%s;" (css_value_to_string vp.font_weight);
  Printf.bprintf buf "line-height:%s;" (css_value_to_string vp.line_height);
  Printf.bprintf buf "text-align:%s;" (css_value_to_string vp.text_align);
  Printf.bprintf buf "text-decoration:%s;" (css_value_to_string vp.text_decoration);
  border_styles buf "top" vp.border_top;
  border_styles buf "right" vp.border_right;
  border_styles buf "bottom" vp.border_bottom;
  border_styles buf "left" vp.border_left;
  Printf.bprintf buf "border-radius:%s;" (css_value_to_string vp.border_radius);
  Printf.bprintf buf "box-shadow:%s;" (css_value_to_string vp.box_shadow);
  Printf.bprintf buf "overflow-x:%s;" (css_value_to_string vp.overflow_x);
  Printf.bprintf buf "overflow-y:%s;" (css_value_to_string vp.overflow_y);
  Printf.bprintf buf "z-index:%s;" (css_value_to_string vp.z_index);
  Printf.bprintf buf "cursor:%s;" (css_value_to_string vp.cursor);
  Printf.bprintf buf "text-align-last:%s;" (css_value_to_string vp.text_align_last);
  Printf.bprintf buf "text-decoration-skip-ink:%s;" (css_value_to_string vp.text_decoration_skip_ink);
  Printf.bprintf buf "text-underline-offset:%s;" (css_value_to_string vp.text_underline_offset);
  Printf.bprintf buf "text-shadow:%s;" (css_value_to_string vp.text_shadow);
  Printf.bprintf buf "text-combine-upright:%s;" (css_value_to_string vp.text_combine_upright);
  Printf.bprintf buf "text-emphasis-style:%s;" (css_value_to_string vp.text_emphasis_style);
  Printf.bprintf buf "text-emphasis-color:%s;" (css_value_to_string vp.text_emphasis_color);
  Printf.bprintf buf "text-emphasis-position:%s;" (css_value_to_string vp.text_emphasis_position);
  Printf.bprintf buf "-webkit-text-stroke-width:%s;" (css_value_to_string vp.webkit_text_stroke_width);
  Printf.bprintf buf "-webkit-text-stroke-color:%s;" (css_value_to_string vp.webkit_text_stroke_color);
  Printf.bprintf buf "font-palette:%s;" (css_value_to_string vp.font_palette);
  Printf.bprintf buf "writing-mode:%s;" (css_value_to_string vp.writing_mode);
  Printf.bprintf buf "direction:%s;" (css_value_to_string vp.direction);
  Printf.bprintf buf "appearance:%s;" (css_value_to_string vp.appearance);
  Printf.bprintf buf "accent-color:%s;" (css_value_to_string vp.accent_color);
  Printf.bprintf buf "image-rendering:%s;" (css_value_to_string vp.image_rendering);
  Printf.bprintf buf "outline-width:%s;" (css_value_to_string vp.outline_width);
  Printf.bprintf buf "outline-style:%s;" (css_value_to_string vp.outline_style);
  Printf.bprintf buf "outline-color:%s;" (css_value_to_string vp.outline_color);
  Printf.bprintf buf "outline-offset:%s;" (css_value_to_string vp.outline_offset);
  Buffer.contents buf

(* -- Node rendering ------------------------------------------------------ *)

let rec render_node buf ~parent_x ~parent_y (n : node) =
  (* Skip text nodes — they depend on font metrics and can't round-trip. *)
  if n.tag = "#text" then ()
  else begin
    let left = n.bounds.x -. parent_x in
    let top = n.bounds.y -. parent_y in
    let style =
      style_attr n.styles ~left ~top ~width:n.bounds.w ~height:n.bounds.h
    in
    let attrs_str =
      List.fold_left
        (fun acc (k, v) ->
          Printf.sprintf "%s %s=\"%s\"" acc (escape_html k) (escape_html v))
        "" n.attributes
    in
    Printf.bprintf buf "<div%s style=\"%s\">" attrs_str (escape_html style);
    (match n.text with
     | Some t -> Buffer.add_string buf (escape_html t)
     | None -> ());
    List.iter
      (render_node buf ~parent_x:n.bounds.x ~parent_y:n.bounds.y)
      n.children;
    Printf.bprintf buf "</div>"
  end

(* -- Top-level ----------------------------------------------------------- *)

let to_html (s : t) =
  let vw, vh = s.viewport in
  let buf = Buffer.create 4096 in
  Buffer.add_string buf
    "<!DOCTYPE html>\n\
     <html>\n\
     <head><meta charset=\"utf-8\">\n\
     <style>*{margin:0;padding:0;box-sizing:border-box;}</style>\n\
     </head>\n";
  Printf.bprintf buf
    "<body style=\"position:relative;width:%dpx;height:%dpx;\">\n" vw vh;
  Printf.bprintf buf "<div id=\"sosie-root\" style=\"position:absolute;left:0px;top:0px;width:%dpx;height:%dpx;\">" vw vh;
  (* Render children of the snapshot root as children of sosie-root.
     The root node itself is the page (html/body) — we reproduce its
     children, not the root itself, since the browser controls the
     root element's properties. *)
  List.iter
    (render_node buf ~parent_x:s.root.bounds.x ~parent_y:s.root.bounds.y)
    s.root.children;
  Buffer.add_string buf "</div>\n</body>\n</html>\n";
  Buffer.contents buf
