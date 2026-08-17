(** Unit tests for shared snapshot types and property whitelist. *)

open Sosie_shared

let test_rect_construction () =
  let r : Snapshot_types.rect = { x = 1.0; y = 2.0; w = 100.0; h = 50.0 } in
  Alcotest.(check (float 0.0)) "x" 1.0 r.x;
  Alcotest.(check (float 0.0)) "y" 2.0 r.y;
  Alcotest.(check (float 0.0)) "w" 100.0 r.w;
  Alcotest.(check (float 0.0)) "h" 50.0 r.h

let test_css_value_px () =
  let v = Snapshot_types.Px 16.0 in
  match v with
  | Px f -> Alcotest.(check (float 0.0)) "px value" 16.0 f
  | _ -> Alcotest.fail "expected Px"

let test_css_value_num () =
  let v = Snapshot_types.Num 400.0 in
  match v with
  | Num f -> Alcotest.(check (float 0.0)) "num value" 400.0 f
  | _ -> Alcotest.fail "expected Num"

let test_css_value_color () =
  let v = Snapshot_types.Color 0xFF0000FF in
  match v with
  | Color c -> Alcotest.(check int) "color value" 0xFF0000FF c
  | _ -> Alcotest.fail "expected Color"

let test_css_value_str () =
  let v = Snapshot_types.Str "block" in
  match v with
  | Str s -> Alcotest.(check string) "str value" "block" s
  | _ -> Alcotest.fail "expected Str"

let test_border_construction () =
  let b : Snapshot_types.border =
    { width = Px 1.0; style = Str "solid"; color = Color 0x000000FF }
  in
  (match b.width with
   | Px f -> Alcotest.(check (float 0.0)) "border width" 1.0 f
   | _ -> Alcotest.fail "expected Px for width");
  (match b.style with
   | Str s -> Alcotest.(check string) "border style" "solid" s
   | _ -> Alcotest.fail "expected Str for style")

let default_border : Snapshot_types.border =
  { width = Str "0px"; style = Str "none"; color = Str "rgb(0, 0, 0)" }

let default_visual_properties : Snapshot_types.visual_properties =
  {
    display = Str "block";
    visibility = Str "visible";
    opacity = Str "1";
    color = Str "rgb(0, 0, 0)";
    background_color = Str "rgba(0, 0, 0, 0)";
    font_family = Str "serif";
    font_size = Str "16px";
    font_weight = Str "400";
    line_height = Str "normal";
    text_align = Str "start";
    text_decoration = Str "none";
    border_top = default_border;
    border_right = default_border;
    border_bottom = default_border;
    border_left = default_border;
    border_radius = Str "0px";
    box_shadow = Str "none";
    overflow_x = Str "visible";
    overflow_y = Str "visible";
    z_index = Str "auto";
    cursor = Str "auto";
    text_align_last = Str "auto";
    text_decoration_skip_ink = Str "auto";
    text_underline_offset = Str "auto";
    text_shadow = Str "none";
    text_combine_upright = Str "none";
    text_emphasis_style = Str "none";
    text_emphasis_color = Str "rgb(0, 0, 0)";
    text_emphasis_position = Str "over right";
    webkit_text_stroke_width = Str "0px";
    webkit_text_stroke_color = Str "rgb(0, 0, 0)";
    font_palette = Str "normal";
    writing_mode = Str "horizontal-tb";
    direction = Str "ltr";
    appearance = Str "none";
    accent_color = Str "auto";
    image_rendering = Str "auto";
    outline_width = Str "0px";
    outline_style = Str "none";
    outline_color = Str "rgb(0, 0, 0)";
    outline_offset = Str "0px";
  }

let test_visual_properties_construction () =
  let vp = default_visual_properties in
  (match vp.display with
   | Str s -> Alcotest.(check string) "display" "block" s
   | _ -> Alcotest.fail "expected Str for display");
  (match vp.cursor with
   | Str s -> Alcotest.(check string) "cursor" "auto" s
   | _ -> Alcotest.fail "expected Str for cursor")

let test_node_construction () =
  let n : Snapshot_types.node =
    {
      tag = "DIV";
      attributes = [ ("id", "main"); ("class", "container") ];
      bounds = { x = 0.0; y = 0.0; w = 800.0; h = 600.0 };
      styles = default_visual_properties;
      text = None;
      paint_order = 0;
      children = [];
    }
  in
  Alcotest.(check string) "tag" "DIV" n.tag;
  Alcotest.(check int) "attributes length" 2 (List.length n.attributes);
  Alcotest.(check (option string)) "text" None n.text;
  Alcotest.(check int) "paint_order" 0 n.paint_order;
  Alcotest.(check int) "children" 0 (List.length n.children)

let test_node_with_children () =
  let child : Snapshot_types.node =
    {
      tag = "#text";
      attributes = [];
      bounds = { x = 0.0; y = 0.0; w = 100.0; h = 20.0 };
      styles = default_visual_properties;
      text = Some "hello";
      paint_order = 1;
      children = [];
    }
  in
  let parent : Snapshot_types.node =
    {
      tag = "P";
      attributes = [];
      bounds = { x = 0.0; y = 0.0; w = 100.0; h = 20.0 };
      styles = default_visual_properties;
      text = None;
      paint_order = 0;
      children = [ child ];
    }
  in
  Alcotest.(check int) "children count" 1 (List.length parent.children);
  let c = List.hd parent.children in
  Alcotest.(check (option string)) "child text" (Some "hello") c.text

let test_snapshot_construction () =
  let root : Snapshot_types.node =
    {
      tag = "HTML";
      attributes = [];
      bounds = { x = 0.0; y = 0.0; w = 1024.0; h = 768.0 };
      styles = default_visual_properties;
      text = None;
      paint_order = 0;
      children = [];
    }
  in
  let s : Snapshot_types.snapshot =
    {
      version = 1;
      url = "https://example.com";
      viewport = (1024, 768);
      color_scheme = `Light;
      root;
    }
  in
  Alcotest.(check int) "version" 1 s.version;
  Alcotest.(check string) "url" "https://example.com" s.url;
  let vw, vh = s.viewport in
  Alcotest.(check int) "viewport width" 1024 vw;
  Alcotest.(check int) "viewport height" 768 vh;
  Alcotest.(check bool) "light scheme" true (s.color_scheme = `Light)

let test_snapshot_dark_scheme () =
  let root : Snapshot_types.node =
    {
      tag = "HTML";
      attributes = [];
      bounds = { x = 0.0; y = 0.0; w = 1024.0; h = 768.0 };
      styles = default_visual_properties;
      text = None;
      paint_order = 0;
      children = [];
    }
  in
  let s : Snapshot_types.snapshot =
    {
      version = 1;
      url = "about:blank";
      viewport = (1920, 1080);
      color_scheme = `Dark;
      root;
    }
  in
  Alcotest.(check bool) "dark scheme" true (s.color_scheme = `Dark)

let test_whitelist_count () =
  Alcotest.(check int) "49 properties" 49
    (List.length Property_whitelist.properties)

let test_css_names_count () =
  Alcotest.(check int) "49 css names" 49
    (List.length Property_whitelist.css_names)

let test_css_names_match_properties () =
  let from_props =
    List.map
      (fun (p : Property_whitelist.property) -> p.css_name)
      Property_whitelist.properties
  in
  Alcotest.(check (list string)) "css_names matches properties"
    from_props Property_whitelist.css_names

(** Verify that our whitelist matches the raw JS extractor's
    DEFAULT_PROPERTIES array exactly. *)
let test_whitelist_matches_raw_js () =
  let expected =
    [
      "display"; "visibility"; "opacity";
      "color"; "background-color";
      "font-family"; "font-size"; "font-weight"; "line-height";
      "text-align"; "text-decoration";
      "border-top-width"; "border-top-style"; "border-top-color";
      "border-right-width"; "border-right-style"; "border-right-color";
      "border-bottom-width"; "border-bottom-style"; "border-bottom-color";
      "border-left-width"; "border-left-style"; "border-left-color";
      "border-radius";
      "box-shadow";
      "overflow-x"; "overflow-y";
      "z-index"; "cursor";
      "text-align-last"; "text-decoration-skip-ink"; "text-underline-offset";
      "text-shadow"; "text-combine-upright";
      "text-emphasis-style"; "text-emphasis-color"; "text-emphasis-position";
      "-webkit-text-stroke-width"; "-webkit-text-stroke-color";
      "font-palette"; "writing-mode"; "direction"; "appearance";
      "accent-color"; "image-rendering";
      "outline-width"; "outline-style"; "outline-color"; "outline-offset";
    ]
  in
  Alcotest.(check (list string)) "matches raw JS DEFAULT_PROPERTIES"
    expected Property_whitelist.css_names

let test_whitelist_no_duplicates () =
  let names = Property_whitelist.css_names in
  let unique = List.sort_uniq String.compare names in
  Alcotest.(check int) "no duplicate css names"
    (List.length names) (List.length unique)

let test_whitelist_field_names_valid () =
  List.iter
    (fun (p : Property_whitelist.property) ->
      (* Field names must be non-empty and use snake_case (no hyphens). *)
      Alcotest.(check bool)
        (Printf.sprintf "field %s has no hyphens" p.field)
        true
        (not (String.contains p.field '-'));
      Alcotest.(check bool)
        (Printf.sprintf "field %s is non-empty" p.field)
        true
        (String.length p.field > 0))
    Property_whitelist.properties

let () =
  Alcotest.run "snapshot_types"
    [
      ( "rect",
        [
          Alcotest.test_case "construction and field access" `Quick
            test_rect_construction;
        ] );
      ( "css_value",
        [
          Alcotest.test_case "Px variant" `Quick test_css_value_px;
          Alcotest.test_case "Num variant" `Quick test_css_value_num;
          Alcotest.test_case "Color variant" `Quick test_css_value_color;
          Alcotest.test_case "Str variant" `Quick test_css_value_str;
        ] );
      ( "border",
        [
          Alcotest.test_case "construction" `Quick test_border_construction;
        ] );
      ( "visual_properties",
        [
          Alcotest.test_case "construction with all fields" `Quick
            test_visual_properties_construction;
        ] );
      ( "node",
        [
          Alcotest.test_case "construction" `Quick test_node_construction;
          Alcotest.test_case "with children" `Quick test_node_with_children;
        ] );
      ( "snapshot",
        [
          Alcotest.test_case "construction" `Quick
            test_snapshot_construction;
          Alcotest.test_case "dark color scheme" `Quick
            test_snapshot_dark_scheme;
        ] );
      ( "property_whitelist",
        [
          Alcotest.test_case "has 49 properties" `Quick
            test_whitelist_count;
          Alcotest.test_case "css_names has 49 entries" `Quick
            test_css_names_count;
          Alcotest.test_case "css_names matches properties" `Quick
            test_css_names_match_properties;
          Alcotest.test_case "matches raw JS DEFAULT_PROPERTIES" `Quick
            test_whitelist_matches_raw_js;
          Alcotest.test_case "no duplicate css names" `Quick
            test_whitelist_no_duplicates;
          Alcotest.test_case "field names are valid OCaml identifiers" `Quick
            test_whitelist_field_names_valid;
        ] );
    ]
