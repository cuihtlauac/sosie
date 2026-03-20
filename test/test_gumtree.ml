(** Unit and property tests for the GumTree matcher and compare_matched. *)

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

let make_node ?(tag = "DIV") ?(text = None) ?(children = [])
    ?(bounds = { x = 0.0; y = 0.0; w = 100.0; h = 50.0 })
    ?(styles = default_styles) ?(paint_order = 0) () : node =
  { tag; attributes = []; bounds; styles; text; paint_order; children }

let make_snapshot root : snapshot =
  { version = 1; url = "https://example.com"; viewport = (1024, 768);
    color_scheme = `Light; root }

let cfg = Compare.default_config

(* --- GumTree matching unit tests --- *)

let identical_trees_matching () =
  let a = make_node ~tag:"DIV" ~children:[
    make_node ~tag:"P" ~text:(Some "hello") ();
    make_node ~tag:"SPAN" ~text:(Some "world") ();
  ] () in
  let m = Gumtree.match_trees a a in
  (* All nodes should be matched *)
  Alcotest.(check bool) "root matched" true (Gumtree.is_matched_a m 0);
  Alcotest.(check bool) "first child matched" true (Gumtree.is_matched_a m 1);
  Alcotest.(check bool) "second child matched" true (Gumtree.is_matched_a m 2)

let identical_trees_no_diffs () =
  let n = make_node ~tag:"DIV" ~children:[
    make_node ~tag:"P" ~text:(Some "hello") ();
  ] () in
  let s = make_snapshot n in
  let diffs = Compare.compare_matched cfg s s in
  Alcotest.(check int) "no diffs" 0 (List.length diffs)

let text_change_matched () =
  let a = make_node ~tag:"DIV" ~children:[
    make_node ~tag:"P" ~text:(Some "hello") ();
  ] () in
  let b = make_node ~tag:"DIV" ~children:[
    make_node ~tag:"P" ~text:(Some "world") ();
  ] () in
  let diffs = Compare.compare_matched cfg (make_snapshot a) (make_snapshot b) in
  let text_diffs = List.filter (function Compare.Text_diff _ -> true | _ -> false) diffs in
  Alcotest.(check int) "one text diff" 1 (List.length text_diffs)

let style_change_matched () =
  let sa = { default_styles with font_size = Px 16.0 } in
  let sb = { default_styles with font_size = Px 20.0 } in
  let a = make_node ~tag:"DIV" ~children:[
    make_node ~tag:"P" ~styles:sa ();
  ] () in
  let b = make_node ~tag:"DIV" ~children:[
    make_node ~tag:"P" ~styles:sb ();
  ] () in
  let diffs = Compare.compare_matched cfg (make_snapshot a) (make_snapshot b) in
  let style_diffs = List.filter (function Compare.Style_diff _ -> true | _ -> false) diffs in
  Alcotest.(check int) "one style diff" 1 (List.length style_diffs)

let wrapper_inserted () =
  (* A: <div> <P>a</P> <P>b</P> <P>c</P> </div> *)
  let p1 = make_node ~tag:"P" ~text:(Some "a") () in
  let p2 = make_node ~tag:"P" ~text:(Some "b") () in
  let p3 = make_node ~tag:"P" ~text:(Some "c") () in
  let a = make_node ~tag:"DIV" ~children:[p1; p2; p3] () in
  (* B: <div> <section> <P>a</P> <P>b</P> <P>c</P> </section> </div> *)
  let p1b = make_node ~tag:"P" ~text:(Some "a") () in
  let p2b = make_node ~tag:"P" ~text:(Some "b") () in
  let p3b = make_node ~tag:"P" ~text:(Some "c") () in
  let section = make_node ~tag:"SECTION" ~children:[p1b; p2b; p3b] () in
  let b = make_node ~tag:"DIV" ~children:[section] () in
  let diffs = Compare.compare_matched cfg (make_snapshot a) (make_snapshot b) in
  let wrapper_diffs = List.filter (function
    | Compare.Wrapper_inserted _ -> true | _ -> false) diffs in
  Alcotest.(check int) "one wrapper inserted" 1 (List.length wrapper_diffs);
  (* No false content diffs *)
  let content_diffs = List.filter (function
    | Compare.Text_diff _ | Compare.Tag_mismatch _ -> true | _ -> false) diffs in
  Alcotest.(check int) "no content diffs" 0 (List.length content_diffs)

let wrapper_removed () =
  (* Inverse of wrapper_inserted *)
  let p1 = make_node ~tag:"P" ~text:(Some "a") () in
  let p2 = make_node ~tag:"P" ~text:(Some "b") () in
  let p3 = make_node ~tag:"P" ~text:(Some "c") () in
  let section = make_node ~tag:"SECTION" ~children:[p1; p2; p3] () in
  let a = make_node ~tag:"DIV" ~children:[section] () in
  let p1b = make_node ~tag:"P" ~text:(Some "a") () in
  let p2b = make_node ~tag:"P" ~text:(Some "b") () in
  let p3b = make_node ~tag:"P" ~text:(Some "c") () in
  let b = make_node ~tag:"DIV" ~children:[p1b; p2b; p3b] () in
  let diffs = Compare.compare_matched cfg (make_snapshot a) (make_snapshot b) in
  let wrapper_diffs = List.filter (function
    | Compare.Wrapper_removed _ -> true | _ -> false) diffs in
  Alcotest.(check int) "one wrapper removed" 1 (List.length wrapper_diffs)

let extra_child_matched () =
  let p1 = make_node ~tag:"P" ~text:(Some "a") () in
  let a = make_node ~tag:"DIV" ~children:[p1] () in
  let p1b = make_node ~tag:"P" ~text:(Some "a") () in
  let span = make_node ~tag:"SPAN" ~text:(Some "new") () in
  let b = make_node ~tag:"DIV" ~children:[p1b; span] () in
  let diffs = Compare.compare_matched cfg (make_snapshot a) (make_snapshot b) in
  let extra_diffs = List.filter (function
    | Compare.Extra_node { side = `Right; _ } -> true | _ -> false) diffs in
  Alcotest.(check int) "one extra node" 1 (List.length extra_diffs)

let deep_identical_subtrees () =
  (* Large shared subtree should be matched by hash *)
  let deep =
    let leaf = make_node ~tag:"SPAN" ~text:(Some "leaf") () in
    let mid = make_node ~tag:"P" ~children:[leaf] () in
    make_node ~tag:"SECTION" ~children:[mid] ()
  in
  let a = make_node ~tag:"DIV" ~children:[deep] () in
  let deep_b =
    let leaf = make_node ~tag:"SPAN" ~text:(Some "leaf") () in
    let mid = make_node ~tag:"P" ~children:[leaf] () in
    make_node ~tag:"SECTION" ~children:[mid] ()
  in
  let extra = make_node ~tag:"ASIDE" () in
  let b = make_node ~tag:"DIV" ~children:[deep_b; extra] () in
  let diffs = Compare.compare_matched cfg (make_snapshot a) (make_snapshot b) in
  (* Only diff should be the extra ASIDE *)
  let content_diffs = List.filter (function
    | Compare.Text_diff _ | Compare.Style_diff _ | Compare.Tag_mismatch _ -> true
    | _ -> false) diffs in
  Alcotest.(check int) "no content diffs for shared subtree" 0 (List.length content_diffs)

let hash_collision_siblings () =
  (* Two identical <div></div> siblings — should be matched by position *)
  let d1 = make_node ~tag:"DIV" () in
  let d2 = make_node ~tag:"DIV" () in
  let a = make_node ~tag:"BODY" ~children:[d1; d2] () in
  let d1b = make_node ~tag:"DIV" () in
  let d2b = make_node ~tag:"DIV" () in
  let b = make_node ~tag:"BODY" ~children:[d1b; d2b] () in
  let diffs = Compare.compare_matched cfg (make_snapshot a) (make_snapshot b) in
  Alcotest.(check int) "no diffs" 0 (List.length diffs)

let sibling_tag_change () =
  let a = make_node ~tag:"DIV" ~children:[
    make_node ~tag:"P" ~text:(Some "hello") ();
    make_node ~tag:"SPAN" ~text:(Some "world") ();
  ] () in
  let b = make_node ~tag:"DIV" ~children:[
    make_node ~tag:"H1" ~text:(Some "hello") ();
    make_node ~tag:"SPAN" ~text:(Some "world") ();
  ] () in
  let diffs = Compare.compare_matched cfg (make_snapshot a) (make_snapshot b) in
  (* P->H1 should produce some structural diff *)
  Alcotest.(check bool) "has diffs" true (List.length diffs > 0)

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
    return { display; visibility; opacity; color; background_color;
             font_family; font_size; font_weight; line_height; text_align;
             text_decoration; border_top; border_right; border_bottom;
             border_left; border_radius; box_shadow; overflow_x; overflow_y;
             z_index; cursor })

let gen_rect =
  QCheck.Gen.(map4 (fun x y w h -> { x; y; w; h })
    (float_bound_inclusive 1000.0)
    (float_bound_inclusive 1000.0)
    (float_bound_inclusive 1000.0)
    (float_bound_inclusive 1000.0))

let rec gen_tree depth =
  QCheck.Gen.(
    let* tag = oneof_list ["DIV"; "P"; "SPAN"; "SECTION"; "A"; "H1"] in
    let* bounds = gen_rect in
    let* styles = gen_styles in
    let* text = oneof_weighted
      [(1, return None);
       (2, map (fun s -> Some s) (oneof_list ["hello"; "world"; "test"]))] in
    let* paint_order = int_bound 100 in
    let* children =
      if depth <= 0 then return []
      else
        let* n = int_range 0 3 in
        list_size (return n) (gen_tree (depth - 1))
    in
    return { tag; attributes = []; bounds; styles;
             text; paint_order; children })

let gen_snapshot_tree =
  QCheck.Gen.(map (fun root ->
    { version = 1; url = "https://example.com"; viewport = (1024, 768);
      color_scheme = `Light; root })
    (gen_tree 2))

let self_comparison_empty =
  QCheck.Test.make ~count:50
    ~name:"self_comparison_is_empty_matched"
    (QCheck.make gen_snapshot_tree)
    (fun s -> Compare.compare_matched cfg s s = [])

let matching_injectivity =
  QCheck.Test.make ~count:50
    ~name:"matching_is_injective"
    (QCheck.make (QCheck.Gen.pair gen_snapshot_tree gen_snapshot_tree))
    (fun (a, b) ->
      let m = Gumtree.match_trees a.root b.root in
      (* Check no B node is matched twice *)
      let seen = Hashtbl.create 16 in
      let ok = ref true in
      let n_a = Gumtree.size_a m in
      for i = 0 to n_a - 1 do
        match Gumtree.partner_of_a m i with
        | None -> ()
        | Some b_id ->
          if Hashtbl.mem seen b_id then ok := false
          else Hashtbl.replace seen b_id ()
      done;
      !ok)

let tolerance_monotonicity =
  QCheck.Test.make ~count:50
    ~name:"tolerance_monotonicity_matched"
    (QCheck.make (QCheck.Gen.pair gen_snapshot_tree gen_snapshot_tree))
    (fun (a, b) ->
      let c0 = { cfg with bounds_tolerance = 0.0; value_tolerance = 0.0 } in
      let c1 = { cfg with bounds_tolerance = 100.0; value_tolerance = 100.0 } in
      List.length (Compare.compare_matched c1 a b)
      <= List.length (Compare.compare_matched c0 a b))

(* --- Test registration --- *)

let () =
  Alcotest.run "gumtree" [
    "matching", [
      Alcotest.test_case "identical trees matched" `Quick identical_trees_matching;
      Alcotest.test_case "identical trees no diffs" `Quick identical_trees_no_diffs;
      Alcotest.test_case "text change" `Quick text_change_matched;
      Alcotest.test_case "style change" `Quick style_change_matched;
      Alcotest.test_case "wrapper inserted" `Quick wrapper_inserted;
      Alcotest.test_case "wrapper removed" `Quick wrapper_removed;
      Alcotest.test_case "extra child" `Quick extra_child_matched;
      Alcotest.test_case "deep identical subtrees" `Quick deep_identical_subtrees;
      Alcotest.test_case "hash collision siblings" `Quick hash_collision_siblings;
      Alcotest.test_case "sibling tag change" `Quick sibling_tag_change;
    ];
    "properties",
      List.map QCheck_alcotest.to_alcotest [
        self_comparison_empty;
        matching_injectivity;
        tolerance_monotonicity;
      ];
  ]
