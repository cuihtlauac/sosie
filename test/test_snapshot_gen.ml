(** Unit tests for Snapshot_gen — HTML generation from snapshots.

    These tests are pure: no browser, no network. They verify the structural
    correctness of the generated HTML. *)

open Sosie
open Sosie.Snapshot_types

(* -- Test helpers -------------------------------------------------------- *)

let default_border : border =
  { width = Str "0px"; style = Str "none"; color = Str "rgb(0, 0, 0)" }

let default_styles : visual_properties =
  {
    display = Str "block";
    visibility = Str "visible";
    opacity = Str "1";
    color = Str "rgb(0, 0, 0)";
    background_color = Str "rgba(0, 0, 0, 0)";
    font_family = Str "serif";
    font_size = Str "16px";
    font_weight = Str "400";
    line_height = Str "20px";
    text_align = Str "start";
    text_decoration = Str "none solid rgb(0, 0, 0)";
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
    text_emphasis_position = Str "over";
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
    fill = Str "rgb(0, 0, 0)";
    stroke = Str "none";
    stroke_width = Str "1px";
  }

let make_node ?(tag = "DIV") ?(attributes = [])
    ?(bounds = { x = 0.0; y = 0.0; w = 100.0; h = 50.0 })
    ?(styles = default_styles) ?(text = None) ?(paint_order = 0)
    ?(children = []) () : node =
  { tag; attributes; bounds; styles; text; paint_order; children }

let make_snapshot ?(viewport = (800, 600)) ?(root = make_node ()) () : Snapshot_gen.t =
  {
    version = 1;
    url = "about:blank";
    viewport;
    color_scheme = `Light;
    root;
  }

(* -- Tests --------------------------------------------------------------- *)

let produces_valid_html () =
  let html = Snapshot_gen.to_html (make_snapshot ()) in
  Alcotest.(check bool) "starts with DOCTYPE"
    true (String.length html > 15 &&
          String.sub html 0 15 = "<!DOCTYPE html>");
  Alcotest.(check bool) "contains </html>"
    true (String.length html > 0 &&
          let pat = "</html>" in
          let rec search i =
            if i + String.length pat > String.length html then false
            else if String.sub html i (String.length pat) = pat then true
            else search (i + 1)
          in search 0)

let contains_sosie_root () =
  let html = Snapshot_gen.to_html (make_snapshot ()) in
  Alcotest.(check bool) "contains sosie-root div"
    true (let pat = "id=\"sosie-root\"" in
          let rec search i =
            if i + String.length pat > String.length html then false
            else if String.sub html i (String.length pat) = pat then true
            else search (i + 1)
          in search 0)

let contains_substring s pat =
  let plen = String.length pat in
  let slen = String.length s in
  if plen > slen then false
  else
    let rec search i =
      if i + plen > slen then false
      else if String.sub s i plen = pat then true
      else search (i + 1)
    in
    search 0

let viewport_dimensions_in_body () =
  let html = Snapshot_gen.to_html (make_snapshot ~viewport:(1024, 768) ()) in
  Alcotest.(check bool) "body width"
    true (contains_substring html "width:1024px");
  Alcotest.(check bool) "body height"
    true (contains_substring html "height:768px")

let child_node_rendered () =
  let child =
    make_node ~bounds:{ x = 10.0; y = 20.0; w = 50.0; h = 30.0 } ()
  in
  let root = make_node ~children:[ child ] () in
  let html = Snapshot_gen.to_html (make_snapshot ~root ()) in
  (* The child is nested inside the root. Its CSS left/top should be
     relative to the root's position (0,0), so left:10px top:20px. *)
  Alcotest.(check bool) "child left relative to parent"
    true (contains_substring html "left:10px");
  Alcotest.(check bool) "child top relative to parent"
    true (contains_substring html "top:20px")

let nested_positioning () =
  let grandchild =
    make_node ~bounds:{ x = 30.0; y = 40.0; w = 20.0; h = 10.0 } ()
  in
  let child =
    make_node
      ~bounds:{ x = 10.0; y = 20.0; w = 80.0; h = 60.0 }
      ~children:[ grandchild ] ()
  in
  let root = make_node ~children:[ child ] () in
  let html = Snapshot_gen.to_html (make_snapshot ~root ()) in
  (* Grandchild: absolute (30,40), parent at (10,20) → relative (20,20). *)
  Alcotest.(check bool) "grandchild relative left"
    true (contains_substring html "left:20px");
  Alcotest.(check bool) "grandchild relative top"
    true (contains_substring html "top:20px")

let all_css_properties_present () =
  let child = make_node () in
  let root = make_node ~children:[ child ] () in
  let html = Snapshot_gen.to_html (make_snapshot ~root ()) in
  let required = [
    "display:"; "visibility:"; "opacity:"; "color:"; "background-color:";
    "font-family:"; "font-size:"; "font-weight:"; "line-height:";
    "text-align:"; "text-decoration:";
    "border-top-width:"; "border-top-style:"; "border-top-color:";
    "border-right-width:"; "border-right-style:"; "border-right-color:";
    "border-bottom-width:"; "border-bottom-style:"; "border-bottom-color:";
    "border-left-width:"; "border-left-style:"; "border-left-color:";
    "border-radius:"; "box-shadow:"; "overflow-x:"; "overflow-y:";
    "z-index:"; "cursor:";
    "text-align-last:"; "text-decoration-skip-ink:"; "text-underline-offset:";
    "text-shadow:"; "text-combine-upright:";
    "text-emphasis-style:"; "text-emphasis-color:"; "text-emphasis-position:";
    "-webkit-text-stroke-width:"; "-webkit-text-stroke-color:";
    "font-palette:"; "writing-mode:"; "direction:"; "appearance:";
    "accent-color:"; "image-rendering:";
    "outline-width:"; "outline-style:"; "outline-color:"; "outline-offset:";
    "fill:"; "stroke:"; "stroke-width:";
  ] in
  List.iter
    (fun prop ->
      Alcotest.(check bool)
        (Printf.sprintf "contains %s" prop)
        true (contains_substring html prop))
    required

let text_nodes_skipped () =
  let text_node =
    make_node ~tag:"#text" ~text:(Some "hello") ()
  in
  let root = make_node ~children:[ text_node ] () in
  let html = Snapshot_gen.to_html (make_snapshot ~root ()) in
  (* Text nodes should not produce any <div> beyond the wrapper. *)
  Alcotest.(check bool) "no text node div"
    false (contains_substring html "hello")

let text_content_emitted () =
  let child =
    make_node ~text:(Some "Hello world") ()
  in
  let root = make_node ~children:[ child ] () in
  let html = Snapshot_gen.to_html (make_snapshot ~root ()) in
  Alcotest.(check bool) "text content present"
    true (contains_substring html "Hello world")

let text_content_escaped () =
  let child =
    make_node ~text:(Some "a<b&c") ()
  in
  let root = make_node ~children:[ child ] () in
  let html = Snapshot_gen.to_html (make_snapshot ~root ()) in
  Alcotest.(check bool) "text content escaped"
    true (contains_substring html "a&lt;b&amp;c")

let attributes_emitted () =
  let child =
    make_node ~attributes:[ ("class", "foo"); ("id", "bar") ] ()
  in
  let root = make_node ~children:[ child ] () in
  let html = Snapshot_gen.to_html (make_snapshot ~root ()) in
  Alcotest.(check bool) "class attribute"
    true (contains_substring html "class=\"foo\"");
  Alcotest.(check bool) "id attribute"
    true (contains_substring html "id=\"bar\"")

let html_special_chars_escaped () =
  let child =
    make_node ~attributes:[ ("data-x", "a<b&c\"d") ] ()
  in
  let root = make_node ~children:[ child ] () in
  let html = Snapshot_gen.to_html (make_snapshot ~root ()) in
  Alcotest.(check bool) "no raw < in attribute"
    false (contains_substring html "a<b");
  Alcotest.(check bool) "escaped <"
    true (contains_substring html "a&lt;b")

let empty_snapshot () =
  let root = make_node ~children:[] () in
  let html = Snapshot_gen.to_html (make_snapshot ~root ()) in
  Alcotest.(check bool) "produces valid HTML for empty tree"
    true (contains_substring html "sosie-root")

let multiple_siblings () =
  let c1 = make_node ~bounds:{ x = 0.0; y = 0.0; w = 50.0; h = 50.0 } () in
  let c2 = make_node ~bounds:{ x = 50.0; y = 0.0; w = 50.0; h = 50.0 } () in
  let root = make_node ~children:[ c1; c2 ] () in
  let html = Snapshot_gen.to_html (make_snapshot ~root ()) in
  (* Both children should produce divs. Count <div occurrences:
     sosie-root div + 2 children = at least 3 <div tags. *)
  let count_divs s =
    let pat = "<div" in
    let plen = String.length pat in
    let slen = String.length s in
    let rec go i acc =
      if i + plen > slen then acc
      else if String.sub s i plen = pat then go (i + 1) (acc + 1)
      else go (i + 1) acc
    in
    go 0 0
  in
  Alcotest.(check bool) "at least 3 divs (root wrapper + 2 siblings)"
    true (count_divs html >= 3)

let css_value_forms () =
  let styles =
    { default_styles with
      opacity = Str "0.5";
      font_weight = Str "700";
      z_index = Str "42";
    }
  in
  let child = make_node ~styles () in
  let root = make_node ~children:[ child ] () in
  let html = Snapshot_gen.to_html (make_snapshot ~root ()) in
  Alcotest.(check bool) "opacity value"
    true (contains_substring html "opacity:0.5");
  Alcotest.(check bool) "font-weight value"
    true (contains_substring html "font-weight:700");
  Alcotest.(check bool) "z-index value"
    true (contains_substring html "z-index:42")

(* -- Test runner --------------------------------------------------------- *)

let () =
  Alcotest.run "snapshot_gen"
    [
      ( "html-structure",
        [
          Alcotest.test_case "valid HTML wrapper" `Quick produces_valid_html;
          Alcotest.test_case "contains sosie-root" `Quick contains_sosie_root;
          Alcotest.test_case "viewport in body" `Quick viewport_dimensions_in_body;
          Alcotest.test_case "empty snapshot" `Quick empty_snapshot;
        ] );
      ( "node-rendering",
        [
          Alcotest.test_case "child rendered with relative coords" `Quick child_node_rendered;
          Alcotest.test_case "nested positioning" `Quick nested_positioning;
          Alcotest.test_case "multiple siblings" `Quick multiple_siblings;
          Alcotest.test_case "text nodes skipped" `Quick text_nodes_skipped;
          Alcotest.test_case "text content emitted" `Quick text_content_emitted;
          Alcotest.test_case "text content escaped" `Quick text_content_escaped;
        ] );
      ( "style-output",
        [
          Alcotest.test_case "all 52 CSS properties" `Quick all_css_properties_present;
          Alcotest.test_case "CSS value forms" `Quick css_value_forms;
        ] );
      ( "attributes",
        [
          Alcotest.test_case "attributes emitted" `Quick attributes_emitted;
          Alcotest.test_case "HTML special chars escaped" `Quick html_special_chars_escaped;
        ] );
    ]
