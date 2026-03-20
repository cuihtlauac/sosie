(** Unit tests for the diff formatter. *)

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
    z_index = Str "auto"; cursor = Str "auto" }

let make_node ?(tag = "DIV") ?(children = []) () : node =
  { tag; attributes = []; bounds = { x = 0.0; y = 0.0; w = 100.0; h = 50.0 };
    styles = default_styles; text = None; paint_order = 0; children }

let root = make_node ~tag:"HTML" ~children:[make_node ~tag:"BODY" ()] ()

(* --- css_value_to_string --- *)

let css_px () =
  Alcotest.(check string) "px" "16px" (Diff_fmt.css_value_to_string (Px 16.0))

let css_num () =
  Alcotest.(check string) "num" "400" (Diff_fmt.css_value_to_string (Num 400.0))

let css_color_opaque () =
  Alcotest.(check string) "color" "rgb(255, 0, 0)"
    (Diff_fmt.css_value_to_string (Color 0xFF0000FF))

let css_color_alpha () =
  Alcotest.(check string) "color+alpha" "rgba(0, 0, 0, 0.5)"
    (Diff_fmt.css_value_to_string (Color 0x0000007F))

let css_str () =
  Alcotest.(check string) "str" "block" (Diff_fmt.css_value_to_string (Str "block"))

(* --- format_diff --- *)

let format_bounds_diff () =
  let d = Compare.Bounds_diff { path = [0]; property = "x"; a = 10.0; b = 20.0 } in
  let s = Diff_fmt.format_diff root d in
  Alcotest.(check bool) "contains path" true (String.length s > 0);
  Alcotest.(check bool) "contains bounds" true
    (let r = Re.Pcre.re "bounds x" |> Re.compile in Re.execp r s)

let format_style_diff () =
  let d = Compare.Style_diff { path = []; property = "color"; a = Str "red"; b = Str "blue" } in
  let s = Diff_fmt.format_diff root d in
  Alcotest.(check bool) "contains style" true
    (let r = Re.Pcre.re "style color" |> Re.compile in Re.execp r s)

let format_text_diff () =
  let d = Compare.Text_diff { path = []; a = Some "hello"; b = Some "world" } in
  let s = Diff_fmt.format_diff root d in
  Alcotest.(check bool) "contains text" true
    (let r = Re.Pcre.re "text:" |> Re.compile in Re.execp r s)

let format_tag_mismatch () =
  let d = Compare.Tag_mismatch { path = []; a = "DIV"; b = "SPAN" } in
  let s = Diff_fmt.format_diff root d in
  Alcotest.(check bool) "contains tag" true
    (let r = Re.Pcre.re "tag mismatch" |> Re.compile in Re.execp r s)

let format_extra_node () =
  let d = Compare.Extra_node { path = [0]; side = `Left; tag = "P" } in
  let s = Diff_fmt.format_diff root d in
  Alcotest.(check bool) "contains extra" true
    (let r = Re.Pcre.re "extra baseline" |> Re.compile in Re.execp r s)

let format_paint_order () =
  let d = Compare.Paint_order_diff { path = []; a = 1; b = 2 } in
  let s = Diff_fmt.format_diff root d in
  Alcotest.(check bool) "contains paint-order" true
    (let r = Re.Pcre.re "paint-order" |> Re.compile in Re.execp r s)

let format_moved_node () =
  let root2 = make_node ~tag:"HTML" ~children:[
    make_node ~tag:"BODY" (); make_node ~tag:"HEAD" ()
  ] () in
  let d = Compare.Moved_node { old_path = [0]; new_path = [0] } in
  let s = Diff_fmt.format_diff ~root_b:root2 root d in
  Alcotest.(check bool) "contains moved" true
    (let r = Re.Pcre.re "moved to" |> Re.compile in Re.execp r s)

let format_wrapper_inserted () =
  let d = Compare.Wrapper_inserted { path = [0]; wrapper_tag = "SECTION" } in
  let s = Diff_fmt.format_diff root d in
  Alcotest.(check bool) "contains wrapper inserted" true
    (let r = Re.Pcre.re "wrapper inserted" |> Re.compile in Re.execp r s);
  Alcotest.(check bool) "contains tag" true
    (let r = Re.Pcre.re "SECTION" |> Re.compile in Re.execp r s)

let format_wrapper_removed () =
  let d = Compare.Wrapper_removed { path = [0]; wrapper_tag = "SECTION" } in
  let s = Diff_fmt.format_diff root d in
  Alcotest.(check bool) "contains wrapper removed" true
    (let r = Re.Pcre.re "wrapper removed" |> Re.compile in Re.execp r s)

(* --- summary --- *)

let summary_no_diffs () =
  Alcotest.(check string) "no diffs" "no diffs" (Diff_fmt.summary [])

let summary_counts () =
  let diffs = [
    Compare.Bounds_diff { path = []; property = "x"; a = 0.0; b = 1.0 };
    Compare.Bounds_diff { path = []; property = "y"; a = 0.0; b = 1.0 };
    Compare.Style_diff { path = []; property = "color"; a = Str "a"; b = Str "b" };
    Compare.Text_diff { path = []; a = Some "a"; b = Some "b" };
  ] in
  let s = Diff_fmt.summary diffs in
  Alcotest.(check bool) "starts with count" true
    (let r = Re.Pcre.re "^4 diffs" |> Re.compile in Re.execp r s);
  Alcotest.(check bool) "has bounds" true
    (let r = Re.Pcre.re "2 bounds" |> Re.compile in Re.execp r s);
  Alcotest.(check bool) "has style" true
    (let r = Re.Pcre.re "1 style" |> Re.compile in Re.execp r s);
  Alcotest.(check bool) "has text" true
    (let r = Re.Pcre.re "1 text" |> Re.compile in Re.execp r s)

let summary_structural () =
  let diffs = [
    Compare.Moved_node { old_path = [0]; new_path = [1] };
    Compare.Wrapper_inserted { path = [0]; wrapper_tag = "DIV" };
    Compare.Wrapper_removed { path = [1]; wrapper_tag = "SPAN" };
  ] in
  let s = Diff_fmt.summary diffs in
  Alcotest.(check bool) "has moved" true
    (let r = Re.Pcre.re "1 moved" |> Re.compile in Re.execp r s);
  Alcotest.(check bool) "has wrapper-inserted" true
    (let r = Re.Pcre.re "1 wrapper-inserted" |> Re.compile in Re.execp r s);
  Alcotest.(check bool) "has wrapper-removed" true
    (let r = Re.Pcre.re "1 wrapper-removed" |> Re.compile in Re.execp r s)

(* --- format_diffs --- *)

let format_diffs_empty () =
  Alcotest.(check string) "empty" "" (Diff_fmt.format_diffs root [])

let format_diffs_multiple () =
  let diffs = [
    Compare.Bounds_diff { path = []; property = "x"; a = 0.0; b = 1.0 };
    Compare.Text_diff { path = []; a = Some "a"; b = Some "b" };
  ] in
  let s = Diff_fmt.format_diffs root diffs in
  let lines = String.split_on_char '\n' s in
  Alcotest.(check int) "two lines" 2 (List.length lines)

(* --- Tests --- *)

let () =
  Alcotest.run "diff_fmt" [
    "css_value_to_string", [
      Alcotest.test_case "px" `Quick css_px;
      Alcotest.test_case "num" `Quick css_num;
      Alcotest.test_case "color opaque" `Quick css_color_opaque;
      Alcotest.test_case "color with alpha" `Quick css_color_alpha;
      Alcotest.test_case "str" `Quick css_str;
    ];
    "format_diff", [
      Alcotest.test_case "bounds diff" `Quick format_bounds_diff;
      Alcotest.test_case "style diff" `Quick format_style_diff;
      Alcotest.test_case "text diff" `Quick format_text_diff;
      Alcotest.test_case "tag mismatch" `Quick format_tag_mismatch;
      Alcotest.test_case "extra node" `Quick format_extra_node;
      Alcotest.test_case "paint order" `Quick format_paint_order;
      Alcotest.test_case "moved node" `Quick format_moved_node;
      Alcotest.test_case "wrapper inserted" `Quick format_wrapper_inserted;
      Alcotest.test_case "wrapper removed" `Quick format_wrapper_removed;
    ];
    "summary", [
      Alcotest.test_case "no diffs" `Quick summary_no_diffs;
      Alcotest.test_case "counts by type" `Quick summary_counts;
      Alcotest.test_case "counts structural types" `Quick summary_structural;
    ];
    "format_diffs", [
      Alcotest.test_case "empty list" `Quick format_diffs_empty;
      Alcotest.test_case "multiple diffs" `Quick format_diffs_multiple;
    ];
  ]
