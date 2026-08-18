(** Mutation testing integration test.

    Requires Chromium. Two passes:
    1. Exhaustive on a small generated snapshot.
    2. Sampled on fixture_mutation.html.

    Run with: dune build @integration *)

open Sosie
open Sosie.Snapshot_types

(* -- Test helpers (same as test_round_trip.ml) --------------------------- *)

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

let make_node ?(bounds = { x = 0.0; y = 0.0; w = 100.0; h = 50.0 })
    ?(styles = default_styles) ?(children = []) () : node =
  {
    tag = "DIV";
    attributes = [];
    bounds;
    styles;
    text = None;
    paint_order = 0;
    children;
  }

(* -- Pass 1: Exhaustive on generated snapshot --------------------------- *)

let exhaustive_on_generated () =
  (* Build a 5-node snapshot with varied styles *)
  let child1 =
    { (make_node
      ~bounds:{ x = 10.0; y = 10.0; w = 380.0; h = 140.0 }
      ~styles:{ default_styles with
                  color = Str "rgb(255, 0, 0)";
                  font_size = Str "24px";
                  font_weight = Str "700";
                  background_color = Str "rgb(200, 200, 200)";
                  text_align = Str "center";
                  opacity = Str "0.8";
                  border_radius = Str "8px";
                  cursor = Str "pointer" }
      ()) with text = Some "Heading" }
  in
  let child2 =
    { (make_node
      ~bounds:{ x = 10.0; y = 160.0; w = 380.0; h = 140.0 }
      ~styles:{ default_styles with
                  color = Str "rgb(0, 128, 0)";
                  font_size = Str "18px";
                  background_color = Str "rgb(240, 240, 255)";
                  visibility = Str "visible";
                  overflow_x = Str "hidden";
                  overflow_y = Str "hidden";
                  border_top =
                    { width = Str "2px"; style = Str "solid";
                      color = Str "rgb(0, 100, 200)" };
                  z_index = Str "1" }
      ()) with text = Some "Content block" }
  in
  let grandchild =
    { (make_node
      ~bounds:{ x = 420.0; y = 10.0; w = 370.0; h = 100.0 }
      ~styles:{ default_styles with
                  color = Str "rgb(0, 0, 200)";
                  font_size = Str "14px";
                  line_height = Str "18px";
                  background_color = Str "rgb(255, 255, 200)" }
      ()) with text = Some "Detail text" }
  in
  let child3 =
    make_node
      ~bounds:{ x = 410.0; y = 10.0; w = 380.0; h = 290.0 }
      ~styles:{ default_styles with
                  color = Str "rgb(100, 50, 0)";
                  background_color = Str "rgb(255, 245, 238)";
                  font_weight = Str "700" }
      ~children:[ grandchild ]
      ()
  in
  (* Overlapping pair for z-index visibility: two siblings that overlap
     spatially with different z-index and background-color values. *)
  let overlap_back =
    make_node
      ~bounds:{ x = 10.0; y = 320.0; w = 200.0; h = 100.0 }
      ~styles:{ default_styles with
                  background_color = Str "rgb(255, 0, 0)";
                  z_index = Str "1" }
      ()
  in
  let overlap_front =
    { (make_node
      ~bounds:{ x = 60.0; y = 340.0; w = 200.0; h = 100.0 }
      ~styles:{ default_styles with
                  background_color = Str "rgb(0, 0, 255)";
                  z_index = Str "2" }
      ()) with text = Some "Overlap" }
  in
  let root =
    make_node
      ~bounds:{ x = 0.0; y = 0.0; w = 800.0; h = 600.0 }
      ~children:[ child1; child2; child3; overlap_back; overlap_front ]
      ()
  in
  let snap : snapshot =
    { version = 1; url = "data:test"; viewport = (800, 600);
      color_scheme = `Light; root }
  in
  let mutations = Mutate.enumerate_mutations snap in
  Printf.printf "Exhaustive pass: %d mutations enumerated\n%!"
    (List.length mutations);
  Cdp_launcher.with_chromium (fun ws_url ->
    let conn = Cdp.connect ws_url in
    Fun.protect ~finally:(fun () -> Cdp.close conn) (fun () ->
      let results =
        Mutate.run conn ~extractor_js:Extractor_js_source.source
          ~config:Config.default ~viewport:(800, 600)
          snap ~mutations
          ~on_progress:(fun i total ->
            if i mod 10 = 0 || i = total then
              Printf.printf "  [%d/%d]\n%!" i total)
      in
      let text = Mutate.report ~root:snap.root results in
      Printf.printf "%s\n%!" text;
      let survived =
        List.filter (fun (r : Mutate.result) -> r.outcome = Survived) results
      in
      if survived <> [] then
        Alcotest.fail
          (Printf.sprintf
             "Exhaustive pass: %d mutations survived (expected 0).\n%s"
             (List.length survived) text)))

(* -- Pass 2: Sampled on fixture page ------------------------------------ *)

let sampled_on_fixture () =
  let seed = int_of_float (Unix.gettimeofday () *. 1000.0) mod 1_000_000 in
  Printf.printf "Sampled pass: random seed = %d\n%!" seed;
  let rng = Random.State.make [| seed |] in
  let fixture_path =
    Sys.getcwd () ^ "/test/fixture_mutation.html"
  in
  let fixture_url = "file://" ^ fixture_path in
  Cdp_launcher.with_chromium (fun ws_url ->
    let conn = Cdp.connect ws_url in
    Fun.protect ~finally:(fun () -> Cdp.close conn) (fun () ->
      (* Capture the fixture as baseline *)
      let extractor_js = Extractor_js_source.source in
      let baseline_json =
        Capture.capture conn ~extractor_js ~url:fixture_url
          ~viewport:(800, 600) ()
      in
      let baseline_snap = Snapshot.of_json baseline_json in
      let all_mutations = Mutate.enumerate_mutations baseline_snap in
      Printf.printf "Sampled pass: %d mutations total, sampling 50\n%!"
        (List.length all_mutations);
      let sample_n = min 50 (List.length all_mutations) in
      let mutations = Mutate.sample rng sample_n all_mutations in
      let results =
        Mutate.run conn ~extractor_js ~config:Config.default
          ~viewport:(800, 600) baseline_snap ~mutations
          ~on_progress:(fun i total ->
            if i mod 10 = 0 || i = total then
              Printf.printf "  [%d/%d]\n%!" i total)
      in
      let text = Mutate.report ~root:baseline_snap.root results in
      Printf.printf "%s\n%!" text;
      let survived =
        List.filter (fun (r : Mutate.result) -> r.outcome = Survived) results
      in
      if survived <> [] then
        Alcotest.fail
          (Printf.sprintf
             "Sampled pass (seed=%d): %d mutations survived (expected 0).\n%s"
             seed (List.length survived) text)))

(* -- Test runner --------------------------------------------------------- *)

let () =
  Alcotest.run "mutation-integration"
    [
      ( "exhaustive",
        [
          Alcotest.test_case "generated snapshot" `Slow
            exhaustive_on_generated;
        ] );
      ( "sampled",
        [
          Alcotest.test_case "fixture page" `Slow sampled_on_fixture;
        ] );
    ]
