(** Snapshot types for sosie's resolved layout+style trees.

    These types represent the captured DOM state: geometry (bounding rects),
    resolved CSS property values, and tree structure. They are the canonical
    representation shared between the native code and the js_of_ocaml
    extractor.

    No JSON encoding here — serialization is platform-specific (Yojson on
    native, Js.Unsafe on JSOO). *)

type rect = { x : float; y : float; w : float; h : float }
(** Bounding rectangle from [getBoundingClientRect]. *)

type css_value =
  | Px of float  (** Pixel value, e.g. ["16px"] *)
  | Num of float  (** Bare number, e.g. ["400"] for font-weight *)
  | Color of int  (** RGBA packed as 0xRRGGBBAA *)
  | Str of string  (** Any other resolved value as a string *)
(** A resolved CSS property value. *)

type border = {
  width : css_value;
  style : css_value;
  color : css_value;
}
(** Resolved border properties for one side. *)

type visual_properties = {
  display : css_value;
  visibility : css_value;
  opacity : css_value;
  color : css_value;
  background_color : css_value;
  font_family : css_value;
  font_size : css_value;
  font_weight : css_value;
  line_height : css_value;
  text_align : css_value;
  text_decoration : css_value;
  border_top : border;
  border_right : border;
  border_bottom : border;
  border_left : border;
  border_radius : css_value;
  box_shadow : css_value;
  overflow_x : css_value;
  overflow_y : css_value;
  z_index : css_value;
  cursor : css_value;
  text_align_last : css_value;
  text_decoration_skip_ink : css_value;
  text_underline_offset : css_value;
  text_shadow : css_value;
  text_combine_upright : css_value;
  text_emphasis_style : css_value;
  text_emphasis_color : css_value;
  text_emphasis_position : css_value;
  webkit_text_stroke_width : css_value;
  webkit_text_stroke_color : css_value;
  font_palette : css_value;
  writing_mode : css_value;
  direction : css_value;
  appearance : css_value;
  accent_color : css_value;
  image_rendering : css_value;
  outline_width : css_value;
  outline_style : css_value;
  outline_color : css_value;
  outline_offset : css_value;
}
(** The whitelisted visual properties captured for each element. *)

type node = {
  tag : string;
  attributes : (string * string) list;
  bounds : rect;
  styles : visual_properties;
  text : string option;
  paint_order : int;
  children : node list;
}
(** A single node in the snapshot tree. Corresponds to a DOM element,
    text node, or pseudo-element. *)

type snapshot = {
  version : int;
  url : string;
  viewport : int * int;
  color_scheme : [ `Light | `Dark ];
  root : node;
}
(** A complete page snapshot: metadata plus the root of the resolved
    layout+style tree. *)
