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
  cmp_css "font-family" (fun s -> s.font_family);
  cmp_css "font-size" (fun s -> s.font_size);
  cmp_css "font-weight" (fun s -> s.font_weight);
  cmp_css "line-height" (fun s -> s.line_height);
  cmp_css "text-align" (fun s -> s.text_align);
  cmp_css "text-decoration" (fun s -> s.text_decoration);
  (* Borders — compare each side's width, style, and color. *)
  let cmp_border name get_border =
    let eb = get_border expected.styles in
    let ab = get_border actual.styles in
    let cmp_bfield field_name get_f =
      match (get_f eb, get_f ab) with
      | Str es, Str as_ when es <> as_ ->
          diff (Printf.sprintf "%s-%s: expected %S, got %S" name field_name es as_)
      | _ -> ()
    in
    cmp_bfield "width" (fun b -> b.width);
    cmp_bfield "style" (fun b -> b.style);
    cmp_bfield "color" (fun b -> b.color)
  in
  cmp_border "border-top" (fun s -> s.border_top);
  cmp_border "border-right" (fun s -> s.border_right);
  cmp_border "border-bottom" (fun s -> s.border_bottom);
  cmp_border "border-left" (fun s -> s.border_left);
  cmp_css "border-radius" (fun s -> s.border_radius);
  cmp_css "box-shadow" (fun s -> s.box_shadow);
  cmp_css "overflow-x" (fun s -> s.overflow_x);
  cmp_css "overflow-y" (fun s -> s.overflow_y);
  cmp_css "z-index" (fun s -> s.z_index);
  cmp_css "cursor" (fun s -> s.cursor);
  cmp_css "text-align-last" (fun s -> s.text_align_last);
  cmp_css "text-decoration-skip-ink" (fun s -> s.text_decoration_skip_ink);
  cmp_css "text-underline-offset" (fun s -> s.text_underline_offset);
  cmp_css "text-shadow" (fun s -> s.text_shadow);
  cmp_css "text-combine-upright" (fun s -> s.text_combine_upright);
  cmp_css "text-emphasis-style" (fun s -> s.text_emphasis_style);
  cmp_css "text-emphasis-color" (fun s -> s.text_emphasis_color);
  cmp_css "text-emphasis-position" (fun s -> s.text_emphasis_position);
  cmp_css "-webkit-text-stroke-width" (fun s -> s.webkit_text_stroke_width);
  cmp_css "-webkit-text-stroke-color" (fun s -> s.webkit_text_stroke_color);
  cmp_css "font-palette" (fun s -> s.font_palette);
  cmp_css "writing-mode" (fun s -> s.writing_mode);
  cmp_css "direction" (fun s -> s.direction);
  cmp_css "appearance" (fun s -> s.appearance);
  cmp_css "accent-color" (fun s -> s.accent_color);
  cmp_css "image-rendering" (fun s -> s.image_rendering);
  cmp_css "outline-width" (fun s -> s.outline_width);
  cmp_css "outline-style" (fun s -> s.outline_style);
  cmp_css "outline-color" (fun s -> s.outline_color);
  cmp_css "outline-offset" (fun s -> s.outline_offset);
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

(* -- QCheck round-trip generators ---------------------------------------- *)

(** Constrained snapshot generator for round-trip tests. Only produces
    values that survive a browser round-trip: all CSS values in Str form,
    in the canonical format returned by getComputedStyle. *)
module Gen_rt = struct
  open QCheck.Gen

  let gen_rgb =
    let* r = int_range 0 255 in
    let* g = int_range 0 255 in
    let* b = int_range 0 255 in
    return (Printf.sprintf "rgb(%d, %d, %d)" r g b)

  let gen_rgba =
    let* r = int_range 0 255 in
    let* g = int_range 0 255 in
    let* b = int_range 0 255 in
    (* Avoid alpha=1 — browsers normalize rgba(R,G,B,1) to rgb(R,G,B). *)
    let* a = oneof_list [ "0"; "0.1"; "0.2"; "0.5"; "0.8" ] in
    return (Printf.sprintf "rgba(%d, %d, %d, %s)" r g b a)

  let gen_color = oneof_weighted [ (3, gen_rgb); (1, gen_rgba) ]

  let gen_px_int lo hi =
    let* n = int_range lo hi in
    return (Printf.sprintf "%dpx" n)

  (* Border widths are kept at 0px to avoid bounds shift: position:absolute
     positions relative to the padding box, but snapshot bounds are relative
     to the border box. Non-zero parent borders would shift child positions. *)
  let gen_border =
    let* color = gen_color in
    return { width = Str "0px"; style = Str "none"; color = Str color }

  let gen_styles =
    let* opacity = oneof_list [ "1"; "0.5"; "0.2"; "0" ] in
    let* color = gen_color in
    let* bg_color = gen_color in
    let* font_family = oneof_list [ "serif"; "sans-serif"; "monospace" ] in
    let* font_size = gen_px_int 8 48 in
    let* font_weight = oneof_list [ "400"; "700" ] in
    let* line_height = gen_px_int 10 60 in
    let* text_align = oneof_list [ "start"; "center"; "end" ] in
    let* border_top = gen_border in
    let* border_right = gen_border in
    let* border_bottom = gen_border in
    let* border_left = gen_border in
    let* border_radius = gen_px_int 0 20 in
    (* CSS spec: if one overflow axis is visible and the other is not,
       the visible one is computed as auto. Generate matching pairs or
       avoid visible entirely to prevent normalization surprises. *)
    let* overflow_x, overflow_y =
      oneof_list [
        ("visible", "visible"); ("hidden", "hidden"); ("scroll", "scroll");
        ("auto", "auto"); ("hidden", "scroll"); ("scroll", "hidden");
        ("auto", "hidden"); ("hidden", "auto");
      ]
    in
    let* z_index = oneof_list [ "auto"; "0"; "1"; "10"; "100" ] in
    let* cursor = oneof_list [ "auto"; "pointer"; "default" ] in
    return
      {
        display = Str "block";
        visibility = Str "visible";
        opacity = Str opacity;
        color = Str color;
        background_color = Str bg_color;
        font_family = Str font_family;
        font_size = Str font_size;
        font_weight = Str font_weight;
        line_height = Str line_height;
        text_align = Str text_align;
        text_decoration = Str "none";
        border_top;
        border_right;
        border_bottom;
        border_left;
        border_radius = Str border_radius;
        box_shadow = Str "none";
        overflow_x = Str overflow_x;
        overflow_y = Str overflow_y;
        z_index = Str z_index;
        cursor = Str cursor;
        (* New whitelist properties: fixed round-trippable initial values.
           style_attr emits them as inline styles; getComputedStyle must
           read back the same string. *)
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
      }

  let float_bounds ~px ~py ~pw ~ph =
    { x = Float.of_int px; y = Float.of_int py;
      w = Float.of_int pw; h = Float.of_int ph }

  (** Generate a node tree with non-overlapping children within parent bounds.
      All parameters are integers (pixel values) to avoid sub-pixel rounding. *)
  let rec gen_node ~depth ~px ~py ~pw ~ph =
    let* styles = gen_styles in
    let max_kids = min 4 (min (pw / 20) (ph / 20)) in
    if depth <= 0 || max_kids <= 0 then
      return
        (make_node ~tag:"DIV" ~bounds:(float_bounds ~px ~py ~pw ~ph)
           ~styles ~paint_order:0 ())
    else
      let* n_children = int_range 0 max_kids in
      let* children =
        gen_children ~depth:(depth - 1) ~px ~py ~pw ~ph ~n:n_children
      in
      return
        (make_node ~tag:"DIV" ~bounds:(float_bounds ~px ~py ~pw ~ph)
           ~styles ~paint_order:0 ~children ())

  (** Generate [n] non-overlapping children stacked vertically within the
      parent's bounds. Each child gets an equal share of the parent height. *)
  and gen_children ~depth ~px ~py ~pw ~ph ~n =
    if n <= 0 || ph < n * 10 || pw < 10 then return []
    else
      let child_h = ph / n in
      let rec go i acc =
        if i >= n then return (List.rev acc)
        else
          let cx = px + 2 in
          let cy = py + (i * child_h) + 2 in
          let cw = max 10 (pw - 4) in
          let ch = max 10 (child_h - 4) in
          let* child = gen_node ~depth ~px:cx ~py:cy ~pw:cw ~ph:ch in
          go (i + 1) (child :: acc)
      in
      go 0 []

  (** Top-level snapshot generator for round-trip tests. Uses integer pixel
      values throughout and a fixed 800x600 viewport. *)
  let gen_snapshot =
    let* root_children_count = int_range 1 3 in
    let* children =
      gen_children ~depth:2 ~px:0 ~py:0 ~pw:800 ~ph:600
        ~n:root_children_count
    in
    let root =
      make_node ~tag:"HTML"
        ~bounds:{ x = 0.0; y = 0.0; w = 800.0; h = 600.0 }
        ~children ()
    in
    return
      ({
         version = 1;
         url = "data:qcheck";
         viewport = (800, 600);
         color_scheme = `Light;
         root;
       }
        : Snapshot_gen.t)
end

(** Check if the round-trip result matches the original, returning true
    on success or false (with printed diffs) on failure. *)
let round_trip_equal (original : node list) (captured : node list) : bool =
  let n_orig = List.length original in
  let n_capt = List.length captured in
  if n_orig <> n_capt then begin
    Printf.eprintf "children count mismatch: expected %d, got %d\n%!" n_orig n_capt;
    false
  end
  else
    let all_diffs =
      List.mapi
        (fun i (e, a) ->
          compare_nodes ~path:(Printf.sprintf "child[%d]" i) e a)
        (List.combine original captured)
    in
    let diffs = List.concat all_diffs in
    if diffs <> [] then begin
      Printf.eprintf "round-trip differences:\n%s\n%!"
        (String.concat "\n" diffs);
      false
    end
    else true

(** Capture helper that reuses an existing connection. *)
let capture_with_conn conn ~viewport ~html =
  let extractor_js = Extractor_js_source.source in
  let data_uri = "data:text/html;base64," ^ Base64.encode_exn html in
  let json = Capture.capture conn ~extractor_js ~url:data_uri ~viewport () in
  Snapshot.of_json json

(* -- QCheck property tests ----------------------------------------------- *)

(** Run a QCheck test, raising Alcotest.fail on counterexample. *)
let run_qcheck_test test =
  let rand = Random.State.make_self_init () in
  match QCheck.Test.check_exn ~rand test with
  | () -> ()
  | exception (QCheck.Test.Test_fail (name, msgs)) ->
      Alcotest.fail
        (Printf.sprintf "QCheck %s failed:\n%s" name (String.concat "\n" msgs))

(** Primary property: C ∘ G preserves structure and styles. *)
let qcheck_round_trip_preserves () =
  Cdp_launcher.with_chromium (fun ws_url ->
      let conn = Cdp.connect ws_url in
      Fun.protect ~finally:(fun () -> Cdp.close conn) (fun () ->
          let prop =
            QCheck.Test.make ~name:"C_∘_G_preserves_structure_and_styles"
              ~count:50
              (QCheck.make Gen_rt.gen_snapshot)
              (fun snap ->
                let html = Snapshot_gen.to_html snap in
                let captured =
                  capture_with_conn conn ~viewport:(800, 600) ~html
                in
                match find_sosie_root captured.root with
                | None -> QCheck.Test.fail_report "sosie-root not found"
                | Some sosie_root ->
                    round_trip_equal snap.root.children sosie_root.children)
          in
          run_qcheck_test prop))

(** Secondary property: round-trip idempotence C(G(C(G(s)))) = C(G(s)). *)
let qcheck_round_trip_idempotent () =
  Cdp_launcher.with_chromium (fun ws_url ->
      let conn = Cdp.connect ws_url in
      Fun.protect ~finally:(fun () -> Cdp.close conn) (fun () ->
          let prop =
            QCheck.Test.make ~name:"round_trip_is_idempotent" ~count:20
              (QCheck.make Gen_rt.gen_snapshot)
              (fun snap ->
                let html1 = Snapshot_gen.to_html snap in
                let captured1 =
                  capture_with_conn conn ~viewport:(800, 600) ~html:html1
                in
                let snap2 : Snapshot_gen.t =
                  match find_sosie_root captured1.root with
                  | None -> QCheck.Test.fail_report "sosie-root not found (pass 1)"
                  | Some sr ->
                      { snap with root = { snap.root with children = sr.children } }
                in
                let html2 = Snapshot_gen.to_html snap2 in
                let captured2 =
                  capture_with_conn conn ~viewport:(800, 600) ~html:html2
                in
                match (find_sosie_root captured1.root, find_sosie_root captured2.root) with
                | Some sr1, Some sr2 ->
                    round_trip_equal sr1.children sr2.children
                | _ -> QCheck.Test.fail_report "sosie-root not found (pass 2)")
          in
          run_qcheck_test prop))

(* -- Test runner --------------------------------------------------------- *)

let () =
  Alcotest.run "round-trip"
    [
      ( "hand-crafted",
        [
          Alcotest.test_case "single div" `Slow hand_crafted_single_div;
          Alcotest.test_case "nested divs" `Slow hand_crafted_nested;
        ] );
      ( "qcheck",
        [
          Alcotest.test_case "C ∘ G preserves structure" `Slow
            qcheck_round_trip_preserves;
          Alcotest.test_case "C ∘ G is idempotent" `Slow
            qcheck_round_trip_idempotent;
        ] );
    ]
