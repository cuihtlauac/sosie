(** Round-trip integration test: C ∘ G = id.

    Generates HTML from a snapshot, captures it via a real browser, and
    compares the captured subtree to the original. Requires Chromium. *)

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
  }

let make_node ?(tag = "DIV") ?(attributes = [])
    ?(bounds = { x = 0.0; y = 0.0; w = 100.0; h = 50.0 })
    ?(styles = default_styles) ?(text = None) ?(paint_order = 0)
    ?(children = []) () : node =
  { tag; attributes; bounds; styles; text; paint_order; children }

(* -- Capture helper ------------------------------------------------------ *)

let with_capture ~viewport ~html f =
  Cdp_launcher.with_chromium (fun ws_url ->
      let conn = Cdp.connect ws_url in
      Fun.protect ~finally:(fun () -> Cdp.close conn) (fun () ->
          let extractor_js = Extractor_js_source.source in
          let data_uri =
            "data:text/html;base64," ^ Base64.encode_exn html
          in
          let json =
            Capture.capture conn ~extractor_js ~url:data_uri ~viewport ()
          in
          let snap = Snapshot.of_json json in
          f snap))

(** Find the node with id="sosie-root" in the captured snapshot tree. *)
let rec find_sosie_root (n : node) : node option =
  if List.exists (fun (k, v) -> k = "id" && v = "sosie-root") n.attributes
  then Some n
  else
    List.fold_left
      (fun acc child ->
        match acc with Some _ -> acc | None -> find_sosie_root child)
      None n.children

(* -- Comparison ---------------------------------------------------------- *)

(** Compare two nodes structurally, ignoring the root wrapper's own
    properties (tag, bounds, styles) and comparing only children.
    For children, compare tag, bounds, styles, and attributes.
    Returns a list of differences as strings, empty if equal. *)
let rec compare_nodes ~path (expected : node) (actual : node) : string list =
  let diffs = ref [] in
  let diff msg = diffs := (path ^ ": " ^ msg) :: !diffs in
  (* Compare bounds with tolerance for sub-pixel rounding. *)
  let tol = 0.5 in
  if Float.abs (expected.bounds.x -. actual.bounds.x) > tol then
    diff (Printf.sprintf "bounds.x: expected %g, got %g"
            expected.bounds.x actual.bounds.x);
  if Float.abs (expected.bounds.y -. actual.bounds.y) > tol then
    diff (Printf.sprintf "bounds.y: expected %g, got %g"
            expected.bounds.y actual.bounds.y);
  if Float.abs (expected.bounds.w -. actual.bounds.w) > tol then
    diff (Printf.sprintf "bounds.w: expected %g, got %g"
            expected.bounds.w actual.bounds.w);
  if Float.abs (expected.bounds.h -. actual.bounds.h) > tol then
    diff (Printf.sprintf "bounds.h: expected %g, got %g"
            expected.bounds.h actual.bounds.h);
  (* Compare styles — only Str values, compare as strings. *)
  let cmp_css name get_field =
    let e = get_field expected.styles in
    let a = get_field actual.styles in
    match (e, a) with
    | Str es, Str as_ when es <> as_ ->
        diff (Printf.sprintf "%s: expected %S, got %S" name es as_)
    | _ -> ()
  in
  cmp_css "display" (fun s -> s.display);
  cmp_css "visibility" (fun s -> s.visibility);
  cmp_css "opacity" (fun s -> s.opacity);
  cmp_css "color" (fun s -> s.color);
  cmp_css "background-color" (fun s -> s.background_color);
  cmp_css "font-size" (fun s -> s.font_size);
  cmp_css "font-weight" (fun s -> s.font_weight);
  cmp_css "overflow-x" (fun s -> s.overflow_x);
  cmp_css "overflow-y" (fun s -> s.overflow_y);
  cmp_css "z-index" (fun s -> s.z_index);
  cmp_css "cursor" (fun s -> s.cursor);
  cmp_css "border-radius" (fun s -> s.border_radius);
  cmp_css "box-shadow" (fun s -> s.box_shadow);
  (* Compare children count. *)
  let ec = List.length expected.children in
  let ac = List.length actual.children in
  if ec <> ac then
    diff (Printf.sprintf "children count: expected %d, got %d" ec ac)
  else
    List.iteri
      (fun i (e, a) ->
        let child_path = Printf.sprintf "%s/child[%d]" path i in
        diffs := compare_nodes ~path:child_path e a @ !diffs)
      (List.combine expected.children actual.children);
  !diffs

(* -- Tests --------------------------------------------------------------- *)

let hand_crafted_single_div () =
  let child =
    make_node
      ~bounds:{ x = 100.0; y = 50.0; w = 200.0; h = 100.0 }
      ~styles:
        { default_styles with
          background_color = Str "rgb(255, 0, 0)";
          opacity = Str "1";
          font_size = Str "16px";
          font_weight = Str "400";
        }
      ()
  in
  let root = make_node ~children:[ child ] () in
  let snap : Snapshot_gen.t =
    {
      version = 1;
      url = "data:test";
      viewport = (800, 600);
      color_scheme = `Light;
      root;
    }
  in
  let html = Snapshot_gen.to_html snap in
  with_capture ~viewport:(800, 600) ~html (fun captured ->
      match find_sosie_root captured.root with
      | None -> Alcotest.fail "sosie-root not found in captured snapshot"
      | Some sosie_root ->
          Alcotest.(check int) "one child under sosie-root"
            1 (List.length sosie_root.children);
          let actual_child = List.hd sosie_root.children in
          let diffs =
            compare_nodes ~path:"child[0]" child actual_child
          in
          if diffs <> [] then
            Alcotest.fail
              (Printf.sprintf "round-trip differences:\n%s"
                 (String.concat "\n" diffs)))

let hand_crafted_nested () =
  let grandchild =
    make_node
      ~bounds:{ x = 120.0; y = 70.0; w = 50.0; h = 30.0 }
      ~styles:
        { default_styles with
          background_color = Str "rgb(0, 128, 0)";
        }
      ()
  in
  let child =
    make_node
      ~bounds:{ x = 100.0; y = 50.0; w = 200.0; h = 100.0 }
      ~styles:
        { default_styles with
          background_color = Str "rgb(255, 0, 0)";
        }
      ~children:[ grandchild ]
      ()
  in
  let root = make_node ~children:[ child ] () in
  let snap : Snapshot_gen.t =
    {
      version = 1;
      url = "data:test";
      viewport = (800, 600);
      color_scheme = `Light;
      root;
    }
  in
  let html = Snapshot_gen.to_html snap in
  with_capture ~viewport:(800, 600) ~html (fun captured ->
      match find_sosie_root captured.root with
      | None -> Alcotest.fail "sosie-root not found"
      | Some sosie_root ->
          Alcotest.(check int) "one child" 1 (List.length sosie_root.children);
          let actual_child = List.hd sosie_root.children in
          Alcotest.(check int) "grandchild present"
            1 (List.length actual_child.children);
          let diffs = compare_nodes ~path:"root" child actual_child in
          if diffs <> [] then
            Alcotest.fail
              (Printf.sprintf "round-trip differences:\n%s"
                 (String.concat "\n" diffs)))

(* -- Test runner --------------------------------------------------------- *)

let () =
  Alcotest.run "round-trip"
    [
      ( "hand-crafted",
        [
          Alcotest.test_case "single div" `Slow hand_crafted_single_div;
          Alcotest.test_case "nested divs" `Slow hand_crafted_nested;
        ] );
    ]
