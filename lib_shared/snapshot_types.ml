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
