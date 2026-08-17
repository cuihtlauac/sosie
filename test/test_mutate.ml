(** Unit tests for mutation operators and enumeration.

    Pure — no browser required. *)

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

let make_node ?(styles = default_styles) ?(children = []) () : node =
  {
    tag = "DIV";
    attributes = [];
    bounds = { x = 0.0; y = 0.0; w = 100.0; h = 50.0 };
    styles;
    text = None;
    paint_order = 0;
    children;
  }

let make_snap root : snapshot =
  {
    version = 1;
    url = "test:";
    viewport = (800, 600);
    color_scheme = `Light;
    root;
  }

(* -- Tests --------------------------------------------------------------- *)

let enumerate_on_3_node_tree () =
  let child1 =
    make_node
      ~styles:{ default_styles with
                  color = Str "rgb(255, 0, 0)";
                  font_size = Str "24px";
                  font_weight = Str "700";
                  text_align = Str "center" }
      ()
  in
  let child2 =
    make_node
      ~styles:{ default_styles with
                  color = Str "rgb(0, 128, 0)";
                  opacity = Str "0.5";
                  visibility = Str "hidden" }
      ()
  in
  let root = make_node ~children:[ child1; child2 ] () in
  let snap = make_snap root in
  let muts = Mutate.enumerate_mutations snap in
  (* Should produce mutations for all 3 nodes *)
  Alcotest.(check bool) "non-empty" true (List.length muts > 0);
  (* Every mutation should have a valid property *)
  List.iter
    (fun (m : Mutate.mutation) ->
      Alcotest.(check bool)
        (Printf.sprintf "valid property %S" m.property)
        true
        (List.mem_assoc m.property
           (* Just check it's a known property name *)
           [ ("display", ()); ("visibility", ()); ("opacity", ());
             ("color", ()); ("background-color", ()); ("font-family", ());
             ("font-size", ()); ("font-weight", ()); ("line-height", ());
             ("text-align", ()); ("text-decoration", ());
             ("border-top-width", ()); ("border-top-style", ());
             ("border-top-color", ()); ("border-right-width", ());
             ("border-right-style", ()); ("border-right-color", ());
             ("border-bottom-width", ()); ("border-bottom-style", ());
             ("border-bottom-color", ()); ("border-left-width", ());
             ("border-left-style", ()); ("border-left-color", ());
             ("border-radius", ()); ("box-shadow", ());
             ("overflow-x", ()); ("overflow-y", ());
             ("z-index", ()); ("cursor", ());
             ("text-align-last", ()); ("text-decoration-skip-ink", ());
             ("text-underline-offset", ()); ("text-shadow", ());
             ("text-combine-upright", ()); ("text-emphasis-style", ());
             ("text-emphasis-color", ()); ("text-emphasis-position", ());
             ("-webkit-text-stroke-width", ());
             ("-webkit-text-stroke-color", ()); ("font-palette", ());
             ("writing-mode", ()); ("direction", ()); ("appearance", ());
             ("accent-color", ()); ("image-rendering", ());
             ("outline-width", ()); ("outline-style", ());
             ("outline-color", ()); ("outline-offset", ()) ]))
    muts

let no_identity_mutations () =
  let child =
    make_node
      ~styles:{ default_styles with
                  color = Str "rgb(255, 0, 0)";
                  font_size = Str "24px";
                  opacity = Str "0.5" }
      ()
  in
  let root = make_node ~children:[ child ] () in
  let snap = make_snap root in
  let muts = Mutate.enumerate_mutations snap in
  List.iter
    (fun (m : Mutate.mutation) ->
      let eq =
        match (m.original, m.mutated) with
        | Str a, Str b -> String.equal a b
        | Px a, Px b -> a = b
        | Num a, Num b -> a = b
        | Color a, Color b -> a = b
        | _ -> false
      in
      Alcotest.(check bool)
        (Printf.sprintf "not identity: %s %s" m.property
           (Mutate.operator_to_string m.operator))
        false eq)
    muts

let apply_modifies_exactly_one_property () =
  let child1 =
    make_node
      ~styles:{ default_styles with color = Str "rgb(255, 0, 0)" }
      ()
  in
  let child2 =
    make_node
      ~styles:{ default_styles with color = Str "rgb(0, 128, 0)" }
      ()
  in
  let root = make_node ~children:[ child1; child2 ] () in
  let snap = make_snap root in
  let muts = Mutate.enumerate_mutations snap in
  (* Pick a mutation targeting child1's color (node_index=1) *)
  let m =
    List.find
      (fun (m : Mutate.mutation) ->
        m.node_index = 1 && m.property = "color")
      muts
  in
  let snap' = Mutate.apply_mutation snap m in
  (* The targeted property changed *)
  let child1' = List.hd snap'.root.children in
  Alcotest.(check bool) "color changed" true
    (child1'.styles.color <> child1.styles.color);
  (* The other child is untouched *)
  let child2' = List.nth snap'.root.children 1 in
  Alcotest.(check bool) "sibling unchanged" true
    (child2'.styles.color = child2.styles.color);
  (* Other properties on the same node unchanged *)
  Alcotest.(check bool) "font-size unchanged" true
    (child1'.styles.font_size = child1.styles.font_size)

let apply_result_differs_from_original () =
  let child =
    make_node
      ~styles:{ default_styles with font_size = Str "16px" }
      ()
  in
  let root = make_node ~children:[ child ] () in
  let snap = make_snap root in
  let muts = Mutate.enumerate_mutations snap in
  List.iter
    (fun m ->
      let snap' = Mutate.apply_mutation snap m in
      Alcotest.(check bool)
        (Printf.sprintf "mutation changes snapshot: node=%d prop=%s op=%s"
           m.Mutate.node_index m.Mutate.property
           (Mutate.operator_to_string m.Mutate.operator))
        true
        (snap'.root <> snap.root))
    muts

let each_operator_produces_valid_css () =
  (* Build a node with varied styles to exercise all operators *)
  let child1 =
    make_node
      ~styles:{ default_styles with
                  color = Str "rgb(255, 0, 0)";
                  font_size = Str "24px";
                  font_weight = Str "700";
                  opacity = Str "0.5";
                  visibility = Str "visible";
                  text_align = Str "center";
                  overflow_x = Str "hidden" }
      ()
  in
  let child2 =
    make_node
      ~styles:{ default_styles with
                  color = Str "rgb(0, 128, 0)";
                  font_size = Str "16px" }
      ()
  in
  let root = make_node ~children:[ child1; child2 ] () in
  let snap = make_snap root in
  let muts = Mutate.enumerate_mutations snap in
  (* Check that every mutated value is a non-empty Str *)
  List.iter
    (fun (m : Mutate.mutation) ->
      match m.mutated with
      | Str s ->
          Alcotest.(check bool)
            (Printf.sprintf "non-empty value for %s/%s"
               m.property (Mutate.operator_to_string m.operator))
            true (String.length s > 0)
      | Px _ | Num _ | Color _ ->
          (* Typed values are always valid *)
          ())
    muts

let report_formatting () =
  let root = make_node () in
  let results : Mutate.result list =
    [
      { mutation = { node_index = 0; property = "color"; operator = Replace_color;
                     original = Str "rgb(255, 0, 0)"; mutated = Str "rgb(0, 0, 255)" };
        outcome = Killed };
      { mutation = { node_index = 0; property = "font-size"; operator = Perturb_numeric;
                     original = Str "16px"; mutated = Str "17px" };
        outcome = Killed };
      { mutation = { node_index = 0; property = "opacity"; operator = Toggle_visibility;
                     original = Str "1"; mutated = Str "0" };
        outcome = Equivalent };
    ]
  in
  let text = Mutate.report ~root results in
  (* Check key content *)
  Alcotest.(check bool) "contains score"
    true (String.length text > 0);
  Alcotest.(check bool) "shows 2/2"
    true (let re = Re.(compile (str "2/2")) in Re.execp re text);
  Alcotest.(check bool) "shows 100.0%"
    true (let re = Re.(compile (str "100.0%")) in Re.execp re text);
  Alcotest.(check bool) "shows Equivalent: 1"
    true (let re = Re.(compile (str "Equivalent: 1")) in Re.execp re text);
  Alcotest.(check bool) "no surviving mutants section"
    true (not (let re = Re.(compile (str "Surviving mutants")) in Re.execp re text))

let report_shows_survivors () =
  let child =
    make_node
      ~styles:{ default_styles with font_size = Str "16px" }
      ()
  in
  let root = make_node ~children:[ child ] () in
  let results : Mutate.result list =
    [
      { mutation = { node_index = 1; property = "font-size";
                     operator = Perturb_numeric;
                     original = Str "16px"; mutated = Str "17px" };
        outcome = Survived };
    ]
  in
  let text = Mutate.report ~root results in
  Alcotest.(check bool) "shows surviving mutants"
    true (let re = Re.(compile (str "Surviving mutants")) in Re.execp re text);
  Alcotest.(check bool) "shows property"
    true (let re = Re.(compile (str "font-size")) in Re.execp re text);
  Alcotest.(check bool) "shows 0/1"
    true (let re = Re.(compile (str "0/1")) in Re.execp re text)

let sample_respects_count () =
  let muts : Mutate.mutation list =
    List.init 20 (fun i ->
      { Mutate.node_index = 0; property = "color"; operator = Replace_color;
        original = Str (Printf.sprintf "rgb(%d, 0, 0)" i);
        mutated = Str "rgb(0, 0, 255)" })
  in
  let rng = Random.State.make [| 42 |] in
  let sampled = Mutate.sample rng 5 muts in
  Alcotest.(check int) "sample size" 5 (List.length sampled)

let sample_returns_all_when_n_exceeds_length () =
  let muts : Mutate.mutation list =
    List.init 3 (fun i ->
      { Mutate.node_index = 0; property = "color"; operator = Replace_color;
        original = Str (Printf.sprintf "rgb(%d, 0, 0)" i);
        mutated = Str "rgb(0, 0, 255)" })
  in
  let rng = Random.State.make [| 42 |] in
  let sampled = Mutate.sample rng 10 muts in
  Alcotest.(check int) "returns all" 3 (List.length sampled)

let swap_siblings_requires_different_values () =
  (* Two children with SAME color — no swap mutation for color *)
  let child1 =
    make_node ~styles:{ default_styles with color = Str "rgb(0, 0, 0)" } ()
  in
  let child2 =
    make_node ~styles:{ default_styles with color = Str "rgb(0, 0, 0)" } ()
  in
  let root = make_node ~children:[ child1; child2 ] () in
  let snap = make_snap root in
  let muts = Mutate.enumerate_mutations snap in
  let swaps_on_color =
    List.filter
      (fun (m : Mutate.mutation) ->
        m.operator = Swap_siblings && m.property = "color"
        && (m.node_index = 1 || m.node_index = 2))
      muts
  in
  Alcotest.(check int) "no color swaps when identical" 0
    (List.length swaps_on_color)

let swap_siblings_generated_for_different_values () =
  let child1 =
    make_node ~styles:{ default_styles with color = Str "rgb(255, 0, 0)" } ()
  in
  let child2 =
    make_node ~styles:{ default_styles with color = Str "rgb(0, 128, 0)" } ()
  in
  let root = make_node ~children:[ child1; child2 ] () in
  let snap = make_snap root in
  let muts = Mutate.enumerate_mutations snap in
  let swaps_on_color =
    List.filter
      (fun (m : Mutate.mutation) ->
        m.operator = Swap_siblings && m.property = "color")
      muts
  in
  Alcotest.(check bool) "swap mutations exist" true
    (List.length swaps_on_color > 0)

(* -- Test runner --------------------------------------------------------- *)

let () =
  Alcotest.run "mutate"
    [
      ( "enumerate",
        [
          Alcotest.test_case "3-node tree produces mutations" `Quick
            enumerate_on_3_node_tree;
          Alcotest.test_case "no identity mutations" `Quick
            no_identity_mutations;
          Alcotest.test_case "swap requires different values" `Quick
            swap_siblings_requires_different_values;
          Alcotest.test_case "swap generated for different values" `Quick
            swap_siblings_generated_for_different_values;
        ] );
      ( "apply",
        [
          Alcotest.test_case "modifies exactly one property" `Quick
            apply_modifies_exactly_one_property;
          Alcotest.test_case "result differs from original" `Quick
            apply_result_differs_from_original;
        ] );
      ( "operators",
        [
          Alcotest.test_case "produce valid CSS values" `Quick
            each_operator_produces_valid_css;
        ] );
      ( "sample",
        [
          Alcotest.test_case "respects count" `Quick sample_respects_count;
          Alcotest.test_case "returns all when n exceeds length" `Quick
            sample_returns_all_when_n_exceeds_length;
        ] );
      ( "report",
        [
          Alcotest.test_case "formatting" `Quick report_formatting;
          Alcotest.test_case "shows survivors" `Quick report_shows_survivors;
        ] );
    ]
