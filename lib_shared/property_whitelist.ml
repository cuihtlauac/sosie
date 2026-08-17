(** Canonical CSS property whitelist.

    See {!Property_whitelist} (the .mli) for documentation. *)

type property = {
  css_name : string;
  field : string;
}

let properties =
  [
    { css_name = "display"; field = "display" };
    { css_name = "visibility"; field = "visibility" };
    { css_name = "opacity"; field = "opacity" };
    { css_name = "color"; field = "color" };
    { css_name = "background-color"; field = "background_color" };
    { css_name = "font-family"; field = "font_family" };
    { css_name = "font-size"; field = "font_size" };
    { css_name = "font-weight"; field = "font_weight" };
    { css_name = "line-height"; field = "line_height" };
    { css_name = "text-align"; field = "text_align" };
    { css_name = "text-decoration"; field = "text_decoration" };
    { css_name = "border-top-width"; field = "border_top_width" };
    { css_name = "border-top-style"; field = "border_top_style" };
    { css_name = "border-top-color"; field = "border_top_color" };
    { css_name = "border-right-width"; field = "border_right_width" };
    { css_name = "border-right-style"; field = "border_right_style" };
    { css_name = "border-right-color"; field = "border_right_color" };
    { css_name = "border-bottom-width"; field = "border_bottom_width" };
    { css_name = "border-bottom-style"; field = "border_bottom_style" };
    { css_name = "border-bottom-color"; field = "border_bottom_color" };
    { css_name = "border-left-width"; field = "border_left_width" };
    { css_name = "border-left-style"; field = "border_left_style" };
    { css_name = "border-left-color"; field = "border_left_color" };
    { css_name = "border-radius"; field = "border_radius" };
    { css_name = "box-shadow"; field = "box_shadow" };
    { css_name = "overflow-x"; field = "overflow_x" };
    { css_name = "overflow-y"; field = "overflow_y" };
    { css_name = "z-index"; field = "z_index" };
    { css_name = "cursor"; field = "cursor" };
    { css_name = "text-align-last"; field = "text_align_last" };
    { css_name = "text-decoration-skip-ink"; field = "text_decoration_skip_ink" };
    { css_name = "text-underline-offset"; field = "text_underline_offset" };
    { css_name = "text-shadow"; field = "text_shadow" };
    { css_name = "text-combine-upright"; field = "text_combine_upright" };
    { css_name = "text-emphasis-style"; field = "text_emphasis_style" };
    { css_name = "text-emphasis-color"; field = "text_emphasis_color" };
    { css_name = "text-emphasis-position"; field = "text_emphasis_position" };
    { css_name = "-webkit-text-stroke-width"; field = "webkit_text_stroke_width" };
    { css_name = "-webkit-text-stroke-color"; field = "webkit_text_stroke_color" };
    { css_name = "font-palette"; field = "font_palette" };
    { css_name = "writing-mode"; field = "writing_mode" };
    { css_name = "direction"; field = "direction" };
    { css_name = "appearance"; field = "appearance" };
    { css_name = "accent-color"; field = "accent_color" };
    { css_name = "image-rendering"; field = "image_rendering" };
    { css_name = "outline-width"; field = "outline_width" };
    { css_name = "outline-style"; field = "outline_style" };
    { css_name = "outline-color"; field = "outline_color" };
    { css_name = "outline-offset"; field = "outline_offset" };
  ]

let css_names = List.map (fun p -> p.css_name) properties
