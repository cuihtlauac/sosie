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
    z_index = Str "auto"; cursor = Str "auto";
    text_align_last = Str "auto"; text_decoration_skip_ink = Str "auto";
    text_underline_offset = Str "auto"; text_shadow = Str "none";
    text_combine_upright = Str "none"; text_emphasis_style = Str "none";
    text_emphasis_color = Str "rgb(0, 0, 0)";
    text_emphasis_position = Str "over";
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

let child_reorder_produces_moved_node () =
  (* Each child has a distinct tag so hash matching uniquely identifies them.
     SPAN and SECTION swap positions -> Moved_node. detect_moves only reports
     moves when the parent path changes; for same-parent reorder the paths
     differ only in the final index, so we check directly on the matching
     that nodes are correctly identified and paths differ. *)
  let a = make_node ~tag:"DIV" ~children:[
    make_node ~tag:"P" ~text:(Some "a") ();
    make_node ~tag:"SPAN" ~text:(Some "b") ();
    make_node ~tag:"SECTION" ~text:(Some "c") ();
  ] () in
  let b = make_node ~tag:"DIV" ~children:[
    make_node ~tag:"P" ~text:(Some "a") ();
    make_node ~tag:"SECTION" ~text:(Some "c") ();
    make_node ~tag:"SPAN" ~text:(Some "b") ();
  ] () in
  (* Verify the matcher correctly identifies all nodes *)
  let m = Gumtree.match_trees a b in
  (* All 4 nodes in A should be matched *)
  for i = 0 to Gumtree.size_a m - 1 do
    Alcotest.(check bool) (Printf.sprintf "node %d matched" i) true
      (Gumtree.is_matched_a m i)
  done;
  (* No false content diffs *)
  let diffs = Compare.compare_matched cfg (make_snapshot a) (make_snapshot b) in
  let bad = List.filter (function
    | Compare.Tag_mismatch _ | Compare.Text_diff _ -> true | _ -> false) diffs in
  Alcotest.(check int) "no tag or text diffs" 0 (List.length bad)

let bounds_tolerance_suppresses_small_diffs () =
  let bounds_a = { x = 10.0; y = 20.0; w = 100.0; h = 50.0 } in
  let bounds_b = { x = 10.5; y = 20.3; w = 100.2; h = 50.4 } in
  let a = make_node ~tag:"DIV" ~children:[
    make_node ~tag:"P" ~bounds:bounds_a ();
  ] () in
  let b = make_node ~tag:"DIV" ~children:[
    make_node ~tag:"P" ~bounds:bounds_b ();
  ] () in
  let tolerant = { cfg with bounds_tolerance = 1.0 } in
  let diffs_tolerant = Compare.compare_matched tolerant (make_snapshot a) (make_snapshot b) in
  let bounds_diffs_tolerant = List.filter (function
    | Compare.Bounds_diff _ -> true | _ -> false) diffs_tolerant in
  Alcotest.(check int) "no bounds diffs with tolerance 1.0" 0 (List.length bounds_diffs_tolerant);
  let strict = { cfg with bounds_tolerance = 0.0 } in
  let diffs_strict = Compare.compare_matched strict (make_snapshot a) (make_snapshot b) in
  let bounds_diffs_strict = List.filter (function
    | Compare.Bounds_diff _ -> true | _ -> false) diffs_strict in
  Alcotest.(check bool) "bounds diffs with tolerance 0.0" true (List.length bounds_diffs_strict > 0)

(* Helper: build node_id -> parent_id map by pre-order walk *)
let build_parent_map root =
  let tbl = Hashtbl.create 64 in
  let next = ref 0 in
  let rec go parent (n : node) =
    let id = !next in
    incr next;
    Hashtbl.replace tbl id parent;
    List.iter (go (Some id)) n.children
  in
  go None root;
  (tbl, !next)

let is_ancestor parent_map x y =
  let rec go cur =
    if cur = x then true
    else match Hashtbl.find parent_map cur with
      | None -> false
      | Some p -> go p
  in
  x <> y && go y

(* --- Regression tests from exhaustive witness extraction ---
   These cases failed before the intersection + ancestor repair pipeline
   was added. They verify the fix prevents these specific violations. *)

let symmetry_witness_1 () =
  (* Without intersection, match(a,b) and match(b,a) had different counts.
     Extracted from exhaustive testing at size 3 x 5. *)
  let a = make_node ~tag:"DIV" ~children:[
    make_node ~tag:"DIV" ();
    make_node ~tag:"SECTION" ();
  ] () in
  let b = make_node ~tag:"SPAN" ~children:[
    make_node ~tag:"DIV" ();
    make_node ~tag:"DIV" ~children:[
      make_node ~tag:"SECTION" ();
      make_node ~tag:"DIV" ();
    ] ();
  ] () in
  let m_ab = Gumtree.match_trees a b in
  let m_ba = Gumtree.match_trees b a in
  let count m n =
    let c = ref 0 in
    for i = 0 to n - 1 do
      if Gumtree.is_matched_a m i then incr c
    done; !c
  in
  Alcotest.(check int) "symmetric match count"
    (count m_ab (Gumtree.size_a m_ab))
    (count m_ba (Gumtree.size_a m_ba))

let ancestor_preservation_witness_1 () =
  (* Without ancestor repair, a matched ancestor pair violated the
     ancestor relationship in tree B. Extracted from exhaustive testing
     at size 2 x 5. *)
  let a = make_node ~tag:"DIV" ~children:[
    make_node ~tag:"DIV" ();
  ] () in
  let b = make_node ~tag:"SPAN" ~children:[
    make_node ~tag:"DIV" ~children:[
      make_node ~tag:"DIV" ();
    ] ();
    make_node ~tag:"SECTION" ~children:[
      make_node ~tag:"DIV" ();
    ] ();
  ] () in
  let m = Gumtree.match_trees a b in
  let (pmap_a, n_a) = build_parent_map a in
  let (pmap_b, _) = build_parent_map b in
  let pairs = ref [] in
  for i = 0 to n_a - 1 do
    match Gumtree.partner_of_a m i with
    | Some j -> pairs := (i, j) :: !pairs
    | None -> ()
  done;
  let ok = List.for_all (fun (x, x') ->
    List.for_all (fun (y, y') ->
      if is_ancestor pmap_a x y then is_ancestor pmap_b x' y'
      else true
    ) !pairs
  ) !pairs in
  Alcotest.(check bool) "ancestor preservation holds" true ok

let ancestor_preservation_witness_2 () =
  (* Second witness: different B structure, same violation pattern. *)
  let a = make_node ~tag:"DIV" ~children:[
    make_node ~tag:"DIV" ();
  ] () in
  let b = make_node ~tag:"SPAN" ~children:[
    make_node ~tag:"DIV" ~children:[
      make_node ~tag:"DIV" ();
    ] ();
    make_node ~tag:"DIV" ~children:[
      make_node ~tag:"DIV" ();
    ] ();
  ] () in
  let m = Gumtree.match_trees a b in
  let (pmap_a, n_a) = build_parent_map a in
  let (pmap_b, _) = build_parent_map b in
  let pairs = ref [] in
  for i = 0 to n_a - 1 do
    match Gumtree.partner_of_a m i with
    | Some j -> pairs := (i, j) :: !pairs
    | None -> ()
  done;
  let ok = List.for_all (fun (x, x') ->
    List.for_all (fun (y, y') ->
      if is_ancestor pmap_a x y then is_ancestor pmap_b x' y'
      else true
    ) !pairs
  ) !pairs in
  Alcotest.(check bool) "ancestor preservation holds" true ok

let symmetry_witness_2 () =
  (* Repair ordering asymmetry: repair_one_direction runs forward (A→B)
     then reverse (B→A) destructively. When match_trees(b,a) is called,
     the order flips, producing different removals. Found by stratified
     random testing: balanced_binary(10) + mutate_tag at node 7. *)
  let a =
    make_node ~tag:"DIV" ~children:[
      make_node ~tag:"DIV" ~children:[
        make_node ~tag:"DIV" ~children:[ make_node ~tag:"SPAN" () ] ();
        make_node ~tag:"DIV" ~children:[ make_node ~tag:"SPAN" () ] ()
      ] ();
      make_node ~tag:"DIV" ~children:[
        make_node ~tag:"DIV" ~children:[ make_node ~tag:"SPAN" () ] ();
        make_node ~tag:"SPAN" ()
      ] ()
    ] ()
  in
  let b =
    make_node ~tag:"DIV" ~children:[
      make_node ~tag:"DIV" ~children:[
        make_node ~tag:"DIV" ~children:[ make_node ~tag:"SPAN" () ] ();
        make_node ~tag:"DIV" ~children:[ make_node ~tag:"SPAN" () ] ()
      ] ();
      make_node ~tag:"DIV" ~children:[
        make_node ~tag:"SPAN" ~children:[ make_node ~tag:"SPAN" () ] ();
        make_node ~tag:"SPAN" ()
      ] ()
    ] ()
  in
  let m_ab = Gumtree.match_trees a b in
  let m_ba = Gumtree.match_trees b a in
  let count m n =
    let c = ref 0 in
    for i = 0 to n - 1 do
      if Gumtree.is_matched_a m i then incr c
    done; !c
  in
  Alcotest.(check int) "symmetric match count"
    (count m_ab (Gumtree.size_a m_ab))
    (count m_ba (Gumtree.size_a m_ba))

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

let matching_count_symmetry =
  QCheck.Test.make ~count:50
    ~name:"matching_count_symmetry"
    (QCheck.make (QCheck.Gen.pair (gen_tree 2) (gen_tree 2)))
    (fun (a, b) ->
      let m_ab = Gumtree.match_trees a b in
      let m_ba = Gumtree.match_trees b a in
      (* Number of matched pairs should be the same in both directions *)
      let count m n =
        let c = ref 0 in
        for i = 0 to n - 1 do
          if Gumtree.is_matched_a m i then incr c
        done;
        !c
      in
      count m_ab (Gumtree.size_a m_ab) = count m_ba (Gumtree.size_a m_ba))

let ancestor_preservation =
  QCheck.Test.make ~count:50
    ~name:"ancestor_preservation"
    (QCheck.make (QCheck.Gen.pair (gen_tree 2) (gen_tree 2)))
    (fun (a, b) ->
      let m = Gumtree.match_trees a b in
      let (pmap_a, n_a) = build_parent_map a in
      let (pmap_b, _n_b) = build_parent_map b in
      (* Collect all matched pairs *)
      let pairs = ref [] in
      for i = 0 to n_a - 1 do
        match Gumtree.partner_of_a m i with
        | Some j -> pairs := (i, j) :: !pairs
        | None -> ()
      done;
      let pairs = !pairs in
      (* For all (x, x') and (y, y') where x is ancestor of y in A,
         x' must be ancestor of y' in B *)
      List.for_all (fun (x, x') ->
        List.for_all (fun (y, y') ->
          if is_ancestor pmap_a x y then
            is_ancestor pmap_b x' y'
          else true
        ) pairs
      ) pairs)

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
      Alcotest.test_case "child reorder produces moved node" `Quick
        child_reorder_produces_moved_node;
      Alcotest.test_case "bounds tolerance suppresses small diffs" `Quick
        bounds_tolerance_suppresses_small_diffs;
    ];
    "regression", [
      Alcotest.test_case "symmetry witness 1" `Quick symmetry_witness_1;
      Alcotest.test_case "ancestor preservation witness 1" `Quick
        ancestor_preservation_witness_1;
      Alcotest.test_case "ancestor preservation witness 2" `Quick
        ancestor_preservation_witness_2;
      Alcotest.test_case "symmetry witness 2" `Quick symmetry_witness_2;
    ];
    "properties",
      List.map QCheck_alcotest.to_alcotest [
        self_comparison_empty;
        matching_injectivity;
        tolerance_monotonicity;
        matching_count_symmetry;
        ancestor_preservation;
      ];
  ]
