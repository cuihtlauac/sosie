(** Snapshot types for sosie's resolved layout+style trees.

    See {!Snapshot_types} (the .mli) for documentation. *)

type rect = { x : float; y : float; w : float; h : float }

type css_value =
  | Px of float
  | Num of float
  | Color of int
  | Str of string

type border = {
  width : css_value;
  style : css_value;
  color : css_value;
}

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
  fill : css_value;
  stroke : css_value;
  stroke_width : css_value;
}

type node = {
  tag : string;
  attributes : (string * string) list;
  bounds : rect;
  styles : visual_properties;
  text : string option;
  paint_order : int;
  children : node list;
}

type snapshot = {
  version : int;
  url : string;
  viewport : int * int;
  color_scheme : [ `Light | `Dark ];
  root : node;
}
