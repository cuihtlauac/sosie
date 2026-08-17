(** Unit and property tests for the lockstep comparison module. *)

open Sosie
open Snapshot_types

(* --- Test helpers --- *)

let default_border : border =
  { width = Px 0.0; style = Str "none"; color = Color 0x000000FF }

let default_styles : visual_properties =
  { display = Str "block"; visibility = Str "visible"; opacity = Num 1.0;
    color = Color 0x000000FF; background_color = Color 0x00000000;
    font_family = Str "serif"; font_size = Px 16.0; font_weight = Num 400.0;
    line_height = Px 20.0; text_align = Str "start";
    text_decoration = Str "none";
    border_top = default_border; border_right = default_border;
    border_bottom = default_border; border_left = default_border;
    border_radius = Px 0.0; box_shadow = Str "none";
    overflow_x = Str "visible"; overflow_y = Str "visible";
    z_index = Str "auto"; cursor = Str "auto";
    text_align_last = Str "auto"; text_decoration_skip_ink = Str "auto";
    text_underline_offset = Str "auto"; text_shadow = Str "none";
    text_combine_upright = Str "none"; text_emphasis_style = Str "none";
    text_emphasis_color = Str "rgb(0, 0, 0)";
    text_emphasis_position = Str "over right";
    webkit_text_stroke_width = Str "0px";
    webkit_text_stroke_color = Str "rgb(0, 0, 0)";
    font_palette = Str "normal"; writing_mode = Str "horizontal-tb";
    direction = Str "ltr"; appearance = Str "none"; accent_color = Str "auto";
    image_rendering = Str "auto"; outline_width = Str "0px";
    outline_style = Str "none"; outline_color = Str "rgb(0, 0, 0)";
    outline_offset = Str "0px" }

let make_node ?(tag = "DIV") ?(text = None) ?(children = [])
    ?(bounds = { x = 0.0; y = 0.0; w = 100.0; h = 50.0 })
    ?(styles = default_styles) ?(paint_order = 0) () : node =
  { tag; attributes = []; bounds; styles; text; paint_order; children }

let make_snapshot root : snapshot =
  { version = 1; url = "https://example.com"; viewport = (1024, 768);
    color_scheme = `Light; root }

let cfg = Compare.default_config

(* --- path_to_string tests --- *)

let path_root () =
  let root = make_node ~tag:"HTML" () in
  Alcotest.(check string) "root" "/HTML"
    (Compare.path_to_string root [])

let path_single_level () =
  let child = make_node ~tag:"BODY" () in
  let root = make_node ~tag:"HTML" ~children:[child] () in
  Alcotest.(check string) "single" "/HTML/BODY"
    (Compare.path_to_string root [0])

let path_sibling_disambiguation () =
  let d1 = make_node ~tag:"DIV" () in
  let d2 = make_node ~tag:"DIV" () in
  let body = make_node ~tag:"BODY" ~children:[d1; d2] () in
  let root = make_node ~tag:"HTML" ~children:[body] () in
  Alcotest.(check string) "second div" "/HTML/BODY/DIV[2]"
    (Compare.path_to_string root [0; 1])

let path_unique_tag_no_index () =
  let p = make_node ~tag:"P" () in
  let span = make_node ~tag:"SPAN" () in
  let body = make_node ~tag:"BODY" ~children:[p; span] () in
  let root = make_node ~tag:"HTML" ~children:[body] () in
  Alcotest.(check string) "unique" "/HTML/BODY/P"
    (Compare.path_to_string root [0; 0])

(* --- Unit tests --- *)

let identical_trees () =
  let n = make_node () in
  let s = make_snapshot n in
  Alcotest.(check int) "no diffs" 0 (List.length (Compare.compare cfg s s))

let text_change () =
  let a = make_node ~text:(Some "hello") () in
  let b = make_node ~text:(Some "world") () in
  let diffs = Compare.compare cfg (make_snapshot a) (make_snapshot b) in
  Alcotest.(check int) "one diff" 1 (List.length diffs);
  match diffs with
  | [ Compare.Text_diff { a = Some "hello"; b = Some "world"; _ } ] -> ()
  | _ -> Alcotest.fail "expected Text_diff"

let style_change () =
  let sa = { default_styles with font_size = Px 16.0 } in
  let sb = { default_styles with font_size = Px 18.0 } in
  let a = make_node ~styles:sa () in
  let b = make_node ~styles:sb () in
  let diffs = Compare.compare cfg (make_snapshot a) (make_snapshot b) in
  Alcotest.(check int) "one diff" 1 (List.length diffs);
  match diffs with
  | [ Compare.Style_diff { property = "font-size"; _ } ] -> ()
  | _ -> Alcotest.fail "expected Style_diff for font-size"

let bounds_within_tolerance () =
  let c = { cfg with bounds_tolerance = 0.5 } in
  let a = make_node ~bounds:{ x = 100.0; y = 0.0; w = 50.0; h = 50.0 } () in
  let b = make_node ~bounds:{ x = 100.3; y = 0.0; w = 50.0; h = 50.0 } () in
  let diffs = Compare.compare c (make_snapshot a) (make_snapshot b) in
  Alcotest.(check int) "within tolerance" 0 (List.length diffs)

let bounds_exceeding_tolerance () =
  let c = { cfg with bounds_tolerance = 0.5 } in
  let a = make_node ~bounds:{ x = 100.0; y = 0.0; w = 50.0; h = 50.0 } () in
  let b = make_node ~bounds:{ x = 101.0; y = 0.0; w = 50.0; h = 50.0 } () in
  let diffs = Compare.compare c (make_snapshot a) (make_snapshot b) in
  Alcotest.(check int) "exceeds tolerance" 1 (List.length diffs);
  match diffs with
  | [ Compare.Bounds_diff { property = "x"; _ } ] -> ()
  | _ -> Alcotest.fail "expected Bounds_diff for x"

let tag_mismatch () =
  let a = make_node ~tag:"P" ~text:(Some "hi") () in
  let b = make_node ~tag:"SPAN" ~text:(Some "bye") () in
  let diffs = Compare.compare cfg (make_snapshot a) (make_snapshot b) in
  (* Tag_mismatch stops recursion, so text diff not reported *)
  Alcotest.(check int) "one diff" 1 (List.length diffs);
  match diffs with
  | [ Compare.Tag_mismatch { a = "P"; b = "SPAN"; _ } ] -> ()
  | _ -> Alcotest.fail "expected Tag_mismatch"

let extra_child_right () =
  let c1 = make_node ~tag:"P" () in
  let c2 = make_node ~tag:"SPAN" () in
  let a = make_node ~children:[c1] () in
  let b = make_node ~children:[c1; c2] () in
  let diffs = Compare.compare cfg (make_snapshot a) (make_snapshot b) in
  let extras =
    List.filter
      (fun d -> match d with Compare.Extra_node _ -> true | _ -> false)
      diffs
  in
  Alcotest.(check int) "one extra" 1 (List.length extras);
  match extras with
  | [ Compare.Extra_node { side = `Right; tag = "SPAN"; _ } ] -> ()
  | _ -> Alcotest.fail "expected Extra_node Right"

let extra_child_left () =
  let c1 = make_node ~tag:"P" () in
  let c2 = make_node ~tag:"SPAN" () in
  let a = make_node ~children:[c1; c2] () in
  let b = make_node ~children:[c1] () in
  let diffs = Compare.compare cfg (make_snapshot a) (make_snapshot b) in
  let extras =
    List.filter
      (fun d -> match d with Compare.Extra_node _ -> true | _ -> false)
      diffs
  in
  Alcotest.(check int) "one extra" 1 (List.length extras);
  match extras with
  | [ Compare.Extra_node { side = `Left; tag = "SPAN"; _ } ] -> ()
  | _ -> Alcotest.fail "expected Extra_node Left"

let paint_order_change () =
  let a = make_node ~paint_order:1 () in
  let b = make_node ~paint_order:2 () in
  let diffs = Compare.compare cfg (make_snapshot a) (make_snapshot b) in
  Alcotest.(check int) "one diff" 1 (List.length diffs);
  match diffs with
  | [ Compare.Paint_order_diff { a = 1; b = 2; _ } ] -> ()
  | _ -> Alcotest.fail "expected Paint_order_diff"

let all_checks_disabled () =
  let c : Compare.config =
    { check_bounds = false; check_visual = false; check_text = false;
      check_paint_order = false; bounds_tolerance = 0.0;
      value_tolerance = 0.0 }
  in
  let sa = { default_styles with font_size = Px 16.0 } in
  let sb = { default_styles with font_size = Px 99.0 } in
  let a = make_node ~styles:sa ~text:(Some "a") ~paint_order:1
    ~bounds:{ x = 0.0; y = 0.0; w = 10.0; h = 10.0 } () in
  let b = make_node ~styles:sb ~text:(Some "b") ~paint_order:2
    ~bounds:{ x = 99.0; y = 99.0; w = 99.0; h = 99.0 } () in
  let diffs = Compare.compare c (make_snapshot a) (make_snapshot b) in
  Alcotest.(check int) "no diffs" 0 (List.length diffs)

let value_tolerance_px () =
  let c = { cfg with value_tolerance = 0.5 } in
  let sa = { default_styles with font_size = Px 16.0 } in
  let sb = { default_styles with font_size = Px 16.4 } in
  let a = make_node ~styles:sa () in
  let b = make_node ~styles:sb () in
  let diffs = Compare.compare c (make_snapshot a) (make_snapshot b) in
  Alcotest.(check int) "within tolerance" 0 (List.length diffs)

let value_tolerance_num () =
  let c = { cfg with value_tolerance = 1.0 } in
  let sa = { default_styles with font_weight = Num 400.0 } in
  let sb = { default_styles with font_weight = Num 400.5 } in
  let a = make_node ~styles:sa () in
  let b = make_node ~styles:sb () in
  let diffs = Compare.compare c (make_snapshot a) (make_snapshot b) in
  Alcotest.(check int) "within tolerance" 0 (List.length diffs)

let color_mismatch () =
  let sa = { default_styles with color = Color 0xFF0000FF } in
  let sb = { default_styles with color = Color 0x00FF00FF } in
  let a = make_node ~styles:sa () in
  let b = make_node ~styles:sb () in
  let diffs = Compare.compare cfg (make_snapshot a) (make_snapshot b) in
  Alcotest.(check int) "one diff" 1 (List.length diffs);
  match diffs with
  | [ Compare.Style_diff { property = "color"; _ } ] -> ()
  | _ -> Alcotest.fail "expected Style_diff for color"

let border_subfield_diff () =
  let bt = { default_border with width = Px 2.0 } in
  let sa = { default_styles with border_top = bt } in
  let a = make_node ~styles:sa () in
  let b = make_node () in
  let diffs = Compare.compare cfg (make_snapshot a) (make_snapshot b) in
  let border_diffs =
    List.filter
      (fun d ->
        match d with
        | Compare.Style_diff { property; _ } ->
          String.length property > 10
          && String.sub property 0 10 = "border-top"
        | _ -> false)
      diffs
  in
  Alcotest.(check int) "border width diff" 1 (List.length border_diffs);
  match border_diffs with
  | [ Compare.Style_diff { property = "border-top-width"; _ } ] -> ()
  | _ -> Alcotest.fail "expected border-top-width diff"

let nested_diff () =
  let leaf_a = make_node ~tag:"P" ~text:(Some "a") () in
  let leaf_b = make_node ~tag:"P" ~text:(Some "b") () in
  let mid_a = make_node ~tag:"SECTION" ~children:[leaf_a] () in
  let mid_b = make_node ~tag:"SECTION" ~children:[leaf_b] () in
  let root_a = make_node ~tag:"BODY" ~children:[mid_a] () in
  let root_b = make_node ~tag:"BODY" ~children:[mid_b] () in
  let diffs = Compare.compare cfg (make_snapshot root_a) (make_snapshot root_b) in
  Alcotest.(check int) "one diff" 1 (List.length diffs);
  match diffs with
  | [ Compare.Text_diff { path = [ 0; 0 ]; _ } ] -> ()
  | _ -> Alcotest.fail "expected nested path [0;0]"

let empty_snapshots () =
  let a = make_node () in
  let b = make_node () in
  let diffs = Compare.compare cfg (make_snapshot a) (make_snapshot b) in
  Alcotest.(check int) "no diffs" 0 (List.length diffs)

let multiple_diffs () =
  let sa = { default_styles with font_size = Px 16.0; color = Color 0xFF0000FF } in
  let sb = { default_styles with font_size = Px 20.0; color = Color 0x00FF00FF } in
  let a = make_node ~styles:sa ~text:(Some "a") () in
  let b = make_node ~styles:sb ~text:(Some "b") () in
  let diffs = Compare.compare cfg (make_snapshot a) (make_snapshot b) in
  (* font-size + color + text = 3 diffs *)
  Alcotest.(check int) "three diffs" 3 (List.length diffs)

let text_none_vs_some () =
  let a = make_node ~text:None () in
  let b = make_node ~text:(Some "hello") () in
  let diffs = Compare.compare cfg (make_snapshot a) (make_snapshot b) in
  Alcotest.(check int) "one diff" 1 (List.length diffs);
  match diffs with
  | [ Compare.Text_diff { a = None; b = Some "hello"; _ } ] -> ()
  | _ -> Alcotest.fail "expected Text_diff None vs Some"

let css_value_variant_mismatch () =
  let sa = { default_styles with font_size = Px 16.0 } in
  let sb = { default_styles with font_size = Str "1em" } in
  let a = make_node ~styles:sa () in
  let b = make_node ~styles:sb () in
  let diffs = Compare.compare cfg (make_snapshot a) (make_snapshot b) in
  Alcotest.(check int) "variant mismatch" 1 (List.length diffs);
  match diffs with
  | [ Compare.Style_diff { property = "font-size"; a = Px 16.0; b = Str "1em"; _ } ] -> ()
  | _ -> Alcotest.fail "expected Style_diff for variant mismatch"

(* --- QCheck property tests --- *)

let gen_css_value =
  QCheck.Gen.(oneof [
    map (fun f -> Px f) (float_bound_inclusive 1000.0);
    map (fun f -> Num f) (float_bound_inclusive 1000.0);
    map (fun i -> Color i) (int_bound 0xFFFFFFFF);
    map (fun s -> Str s) (oneof_list ["block"; "none"; "visible"; "auto"]);
  ])

let gen_border =
  QCheck.Gen.(map3 (fun w s c -> { width = w; style = s; color = c })
    gen_css_value gen_css_value gen_css_value)

let gen_styles =
  QCheck.Gen.(
    let* display = gen_css_value in
    let* visibility = gen_css_value in
    let* opacity = gen_css_value in
    let* color = gen_css_value in
    let* background_color = gen_css_value in
    let* font_family = gen_css_value in
    let* font_size = gen_css_value in
    let* font_weight = gen_css_value in
    let* line_height = gen_css_value in
    let* text_align = gen_css_value in
    let* text_decoration = gen_css_value in
    let* border_top = gen_border in
    let* border_right = gen_border in
    let* border_bottom = gen_border in
    let* border_left = gen_border in
    let* border_radius = gen_css_value in
    let* box_shadow = gen_css_value in
    let* overflow_x = gen_css_value in
    let* overflow_y = gen_css_value in
    let* z_index = gen_css_value in
    let* cursor = gen_css_value in
    let* text_align_last = gen_css_value in
    let* text_decoration_skip_ink = gen_css_value in
    let* text_underline_offset = gen_css_value in
    let* text_shadow = gen_css_value in
    let* text_combine_upright = gen_css_value in
    let* text_emphasis_style = gen_css_value in
    let* text_emphasis_color = gen_css_value in
    let* text_emphasis_position = gen_css_value in
    let* webkit_text_stroke_width = gen_css_value in
    let* webkit_text_stroke_color = gen_css_value in
    let* font_palette = gen_css_value in
    let* writing_mode = gen_css_value in
    let* direction = gen_css_value in
    let* appearance = gen_css_value in
    let* accent_color = gen_css_value in
    let* image_rendering = gen_css_value in
    let* outline_width = gen_css_value in
    let* outline_style = gen_css_value in
    let* outline_color = gen_css_value in
    let* outline_offset = gen_css_value in
    return { display; visibility; opacity; color; background_color;
             font_family; font_size; font_weight; line_height; text_align;
             text_decoration; border_top; border_right; border_bottom;
             border_left; border_radius; box_shadow; overflow_x; overflow_y;
             z_index; cursor; text_align_last; text_decoration_skip_ink;
             text_underline_offset; text_shadow; text_combine_upright;
             text_emphasis_style; text_emphasis_color; text_emphasis_position;
             webkit_text_stroke_width; webkit_text_stroke_color; font_palette;
             writing_mode; direction; appearance; accent_color; image_rendering;
             outline_width; outline_style; outline_color; outline_offset })

let gen_rect =
  QCheck.Gen.(map4 (fun x y w h -> { x; y; w; h })
    (float_bound_inclusive 1000.0)
    (float_bound_inclusive 1000.0)
    (float_bound_inclusive 1000.0)
    (float_bound_inclusive 1000.0))

let gen_node =
  QCheck.Gen.(
    let* tag = oneof_list ["DIV"; "P"; "SPAN"; "SECTION"; "A"; "H1"] in
    let* bounds = gen_rect in
    let* styles = gen_styles in
    let* text = oneof_weighted
      [(1, return None);
       (2, map (fun s -> Some s) (oneof_list ["hello"; "world"; "test"]))] in
    let* paint_order = int_bound 100 in
    return { tag; attributes = []; bounds; styles;
             text; paint_order; children = [] })

let gen_snapshot =
  QCheck.Gen.(map (fun root ->
    { version = 1; url = "https://example.com"; viewport = (1024, 768);
      color_scheme = `Light; root })
    gen_node)

let self_comparison_empty =
  QCheck.Test.make ~count:100
    ~name:"self_comparison_is_empty"
    (QCheck.make gen_snapshot)
    (fun s -> Compare.compare cfg s s = [])

let symmetry_of_diff_count =
  QCheck.Test.make ~count:100
    ~name:"symmetry_of_diff_count"
    (QCheck.make (QCheck.Gen.pair gen_snapshot gen_snapshot))
    (fun (a, b) ->
      List.length (Compare.compare cfg a b)
      = List.length (Compare.compare cfg b a))

let all_disabled_no_diffs =
  let c : Compare.config =
    { check_bounds = false; check_visual = false; check_text = false;
      check_paint_order = false; bounds_tolerance = 0.0;
      value_tolerance = 0.0 }
  in
  (* Use same-tag leaf nodes: tag/structure mismatches are always reported *)
  let gen_same_tag_pair =
    QCheck.Gen.(
      let* s1 = gen_snapshot in
      let* s2 = gen_snapshot in
      let s2 = { s2 with root = { s2.root with tag = s1.root.tag; children = [] } } in
      let s1 = { s1 with root = { s1.root with children = [] } } in
      return (s1, s2))
  in
  QCheck.Test.make ~count:100
    ~name:"all_checks_disabled_produces_no_diffs"
    (QCheck.make gen_same_tag_pair)
    (fun (a, b) -> Compare.compare c a b = [])

let tolerance_monotonicity =
  QCheck.Test.make ~count:100
    ~name:"tolerance_monotonicity"
    (QCheck.make (QCheck.Gen.pair gen_snapshot gen_snapshot))
    (fun (a, b) ->
      let c0 = { cfg with bounds_tolerance = 0.0; value_tolerance = 0.0 } in
      let c1 = { cfg with bounds_tolerance = 100.0; value_tolerance = 100.0 } in
      List.length (Compare.compare c1 a b)
      <= List.length (Compare.compare c0 a b))

(* --- Test registration --- *)

let () =
  Alcotest.run "compare"
    [
      ( "path_to_string",
        [
          Alcotest.test_case "root path" `Quick path_root;
          Alcotest.test_case "single level" `Quick path_single_level;
          Alcotest.test_case "sibling disambiguation" `Quick
            path_sibling_disambiguation;
          Alcotest.test_case "unique tag no index" `Quick
            path_unique_tag_no_index;
        ] );
      ( "compare",
        [
          Alcotest.test_case "identical trees" `Quick identical_trees;
          Alcotest.test_case "text change" `Quick text_change;
          Alcotest.test_case "style change" `Quick style_change;
          Alcotest.test_case "bounds within tolerance" `Quick
            bounds_within_tolerance;
          Alcotest.test_case "bounds exceeding tolerance" `Quick
            bounds_exceeding_tolerance;
          Alcotest.test_case "tag mismatch" `Quick tag_mismatch;
          Alcotest.test_case "extra child right" `Quick extra_child_right;
          Alcotest.test_case "extra child left" `Quick extra_child_left;
          Alcotest.test_case "paint order change" `Quick paint_order_change;
          Alcotest.test_case "all checks disabled" `Quick all_checks_disabled;
          Alcotest.test_case "value tolerance px" `Quick value_tolerance_px;
          Alcotest.test_case "value tolerance num" `Quick value_tolerance_num;
          Alcotest.test_case "color mismatch" `Quick color_mismatch;
          Alcotest.test_case "border subfield diff" `Quick border_subfield_diff;
          Alcotest.test_case "nested diff" `Quick nested_diff;
          Alcotest.test_case "empty snapshots" `Quick empty_snapshots;
          Alcotest.test_case "multiple diffs" `Quick multiple_diffs;
          Alcotest.test_case "text none vs some" `Quick text_none_vs_some;
          Alcotest.test_case "css value variant mismatch" `Quick
            css_value_variant_mismatch;
        ] );
      ( "properties",
        List.map QCheck_alcotest.to_alcotest
          [
            self_comparison_empty;
            symmetry_of_diff_count;
            all_disabled_no_diffs;
            tolerance_monotonicity;
          ] );
    ]
