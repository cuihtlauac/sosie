(** Unit tests for Diff_report.

    Tests the pure report generation: HTML structure, diff JSON
    serialization, base64 encoding, and escaping. *)

open Alcotest
open Sosie_shared.Snapshot_types

(* -- Test fixtures ------------------------------------------------------- *)

let default_styles =
  let v = Str "" in
  let border = { width = v; style = v; color = v } in
  {
    display = v; visibility = v; opacity = v; color = v;
    background_color = v; font_family = v; font_size = v;
    font_weight = v; line_height = v; text_align = v;
    text_decoration = v; border_top = border; border_right = border;
    border_bottom = border; border_left = border; border_radius = v;
    box_shadow = v; overflow_x = v; overflow_y = v; z_index = v;
    cursor = v;
  }

let make_node ?(tag = "DIV") ?(children = []) ?(text = None)
    ?(bounds = { x = 0.; y = 0.; w = 100.; h = 50. }) () =
  { tag; attributes = []; bounds; styles = default_styles;
    text; paint_order = 0; children }

let root_a =
  make_node ~tag:"HTML"
    ~children:[
      make_node ~tag:"BODY"
        ~children:[
          make_node ~tag:"P" ~text:(Some "hello") ();
          make_node ~tag:"DIV" ~bounds:{ x = 10.; y = 20.; w = 200.; h = 100. } ();
        ] ();
    ] ()

let root_b =
  make_node ~tag:"HTML"
    ~children:[
      make_node ~tag:"BODY"
        ~children:[
          make_node ~tag:"P" ~text:(Some "world") ();
          make_node ~tag:"DIV" ~bounds:{ x = 15.; y = 20.; w = 200.; h = 100. } ();
        ] ();
    ] ()

(* Minimal PNG: 1x1 pixel transparent *)
let tiny_png =
  "\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\
   \x08\x06\x00\x00\x00\x1f\x15\xc4\x89\x00\x00\x00\nIDATx\x9cc\x00\x01\
   \x00\x00\x05\x00\x01\r\n\xb4\x00\x00\x00\x00IEND\xaeB`\x82"

(* -- Tests --------------------------------------------------------------- *)

let empty_diffs_valid_html () =
  let html =
    Sosie.Diff_report.generate ~root_a ~root_b ~diffs:[]
      ~screenshot_a:tiny_png ~screenshot_b:tiny_png
  in
  check bool "starts with DOCTYPE" true
    (String.length html > 15 &&
     String.sub (String.uppercase_ascii html) 0 15 = "<!DOCTYPE HTML>");
  check bool "contains both data URIs" true
    (let re = Re.compile (Re.str "data:image/png;base64,") in
     let matches = Re.all re html in
     List.length matches >= 2);
  check bool "contains 0 diffs" true
    (let re = Re.compile (Re.str "0 diffs") in
     Re.execp re html)

let style_diff_in_json () =
  let diffs : Sosie.Compare.diff list =
    [ Style_diff { path = [0; 0]; property = "color";
                   a = Str "red"; b = Str "blue" } ]
  in
  let json_str = Sosie.Diff_report.diffs_to_json ~root_a ~root_b diffs in
  check bool "contains property name" true
    (let re = Re.compile (Re.str {|"color"|}) in
     Re.execp re json_str);
  check bool "contains type style" true
    (let re = Re.compile (Re.str {|"style"|}) in
     Re.execp re json_str)

let screenshot_encoding () =
  let html =
    Sosie.Diff_report.generate ~root_a ~root_b ~diffs:[]
      ~screenshot_a:tiny_png ~screenshot_b:tiny_png
  in
  let b64 = Base64.encode_exn tiny_png in
  check bool "base64 PNG present in output" true
    (let re = Re.compile (Re.str b64) in
     Re.execp re html)

let all_diff_types () =
  let diffs : Sosie.Compare.diff list =
    [
      Bounds_diff { path = [0; 1]; property = "x"; a = 10.; b = 15. };
      Style_diff { path = [0; 0]; property = "color";
                   a = Str "red"; b = Str "blue" };
      Text_diff { path = [0; 0]; a = Some "hello"; b = Some "world" };
      Paint_order_diff { path = [0; 0]; a = 1; b = 2 };
      Tag_mismatch { path = [0; 0]; a = "P"; b = "SPAN" };
      Extra_node { path = [0; 0]; side = `Left; tag = "P" };
      Moved_node { old_path = [0; 0]; new_path = [0; 1] };
      Wrapper_inserted { path = [0; 0]; wrapper_tag = "DIV" };
      Wrapper_removed { path = [0; 0]; wrapper_tag = "SPAN" };
    ]
  in
  let json_str = Sosie.Diff_report.diffs_to_json ~root_a ~root_b diffs in
  List.iter
    (fun typ ->
      check bool (typ ^ " in JSON") true
        (let re = Re.compile (Re.str (Printf.sprintf {|"%s"|} typ)) in
         Re.execp re json_str))
    ["bounds"; "style"; "text"; "paint_order"; "structural"; "moved"]

let html_escaping () =
  let diffs : Sosie.Compare.diff list =
    [ Style_diff { path = [0; 0]; property = "font-family";
                   a = Str {|"Arial", <sans>|}; b = Str {|"Helvetica"|} } ]
  in
  let html =
    Sosie.Diff_report.generate ~root_a ~root_b ~diffs
      ~screenshot_a:tiny_png ~screenshot_b:tiny_png
  in
  (* The JSON is inside a <script type="application/json"> tag, which is
     HTML-escaped. Check that angle brackets are escaped. *)
  check bool "no raw < in diff-data script" true
    (let re = Re.compile (Re.str "<sans>") in
     not (Re.execp re html))

let () =
  run "Diff_report"
    [
      ( "generate",
        [
          test_case "empty diffs produce valid HTML" `Quick empty_diffs_valid_html;
          test_case "style diff appears in JSON" `Quick style_diff_in_json;
          test_case "screenshots correctly base64 encoded" `Quick
            screenshot_encoding;
          test_case "all diff types in JSON" `Quick all_diff_types;
          test_case "special chars HTML-escaped" `Quick html_escaping;
        ] );
    ]
