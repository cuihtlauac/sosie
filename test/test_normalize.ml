(** Unit and property tests for the normalization module. *)

open Sosie
open Snapshot_types

(* --- Test helpers --- *)

let default_border : border =
  { width = Str "0px"; style = Str "none"; color = Str "rgb(0, 0, 0)" }

let default_styles : visual_properties =
  { display = Str "block"; visibility = Str "visible"; opacity = Str "1";
    color = Str "rgb(0, 0, 0)"; background_color = Str "rgba(0, 0, 0, 0)";
    font_family = Str "serif"; font_size = Str "16px"; font_weight = Str "400";
    line_height = Str "normal"; text_align = Str "start";
    text_decoration = Str "none";
    border_top = default_border; border_right = default_border;
    border_bottom = default_border; border_left = default_border;
    border_radius = Str "0px"; box_shadow = Str "none";
    overflow_x = Str "visible"; overflow_y = Str "visible";
    z_index = Str "auto"; cursor = Str "auto" }

let make_node ?(tag = "DIV") ?(attrs = []) ?(text = None) ?(children = [])
    ?(bounds = { x = 0.0; y = 0.0; w = 100.0; h = 50.0 })
    ?(styles = default_styles) () : node =
  { tag; attributes = attrs; bounds; styles; text; paint_order = 0; children }

let make_snapshot root : snapshot =
  { version = 1; url = "https://example.com"; viewport = (1024, 768);
    color_scheme = `Light; root }

let snapshot_eq = Alcotest.testable
  (fun fmt _ -> Format.fprintf fmt "<snapshot>")
  (=)

(* ========================================================================= *)
(* Drop_attributes                                                           *)
(* ========================================================================= *)

let drop_attr_exact_match () =
  let n = make_node ~attrs:[("class", "foo"); ("id", "bar")] () in
  let s = make_snapshot n in
  let s' = Normalize.apply [Drop_attributes [Exact "class"]] s in
  Alcotest.(check (list (pair string string))) "class removed"
    [("id", "bar")] s'.root.attributes

let drop_attr_prefix_match () =
  let n = make_node ~attrs:[("data-x", "1"); ("data-y", "2"); ("id", "z")] () in
  let s = make_snapshot n in
  let s' = Normalize.apply [Drop_attributes [Prefix "data-"]] s in
  Alcotest.(check (list (pair string string))) "data-* removed"
    [("id", "z")] s'.root.attributes

let drop_attr_no_match () =
  let n = make_node ~attrs:[("id", "x")] () in
  let s = make_snapshot n in
  let s' = Normalize.apply [Drop_attributes [Exact "class"]] s in
  Alcotest.(check (list (pair string string))) "unchanged"
    [("id", "x")] s'.root.attributes

let drop_attr_multiple_patterns () =
  let n = make_node ~attrs:[("class", "a"); ("data-v", "b"); ("id", "c")] () in
  let s = make_snapshot n in
  let s' = Normalize.apply [Drop_attributes [Exact "class"; Prefix "data-"]] s in
  Alcotest.(check (list (pair string string))) "class and data-* removed"
    [("id", "c")] s'.root.attributes

let drop_attr_empty_attributes () =
  let n = make_node ~attrs:[] () in
  let s = make_snapshot n in
  let s' = Normalize.apply [Drop_attributes [Exact "class"]] s in
  Alcotest.(check (list (pair string string))) "still empty"
    [] s'.root.attributes

(* ========================================================================= *)
(* Sort_attributes                                                           *)
(* ========================================================================= *)

let sort_attr_already_sorted () =
  let n = make_node ~attrs:[("a", "1"); ("b", "2"); ("c", "3")] () in
  let s = make_snapshot n in
  let s' = Normalize.apply [Sort_attributes] s in
  Alcotest.(check (list (pair string string))) "unchanged"
    [("a", "1"); ("b", "2"); ("c", "3")] s'.root.attributes

let sort_attr_reverse_order () =
  let n = make_node ~attrs:[("z", "1"); ("a", "2")] () in
  let s = make_snapshot n in
  let s' = Normalize.apply [Sort_attributes] s in
  Alcotest.(check (list (pair string string))) "sorted"
    [("a", "2"); ("z", "1")] s'.root.attributes

let sort_attr_duplicates () =
  let n = make_node ~attrs:[("b", "2"); ("a", "1"); ("b", "3")] () in
  let s = make_snapshot n in
  let s' = Normalize.apply [Sort_attributes] s in
  Alcotest.(check (list (pair string string))) "sorted with dups"
    [("a", "1"); ("b", "2"); ("b", "3")] s'.root.attributes

(* ========================================================================= *)
(* Round_bounds                                                              *)
(* ========================================================================= *)

let round_bounds_exact_values () =
  let n = make_node ~bounds:{ x = 10.0; y = 20.0; w = 100.0; h = 50.0 } () in
  let s = make_snapshot n in
  let s' = Normalize.apply [Round_bounds 10.0] s in
  let b = s'.root.bounds in
  Alcotest.(check (float 0.0)) "x" 10.0 b.x;
  Alcotest.(check (float 0.0)) "y" 20.0 b.y;
  Alcotest.(check (float 0.0)) "w" 100.0 b.w;
  Alcotest.(check (float 0.0)) "h" 50.0 b.h

let round_bounds_midpoint_rounding () =
  let n = make_node ~bounds:{ x = 3.7; y = 8.2; w = 101.6; h = 49.9 } () in
  let s = make_snapshot n in
  let s' = Normalize.apply [Round_bounds 5.0] s in
  let b = s'.root.bounds in
  Alcotest.(check (float 0.001)) "x" 5.0 b.x;
  Alcotest.(check (float 0.001)) "y" 10.0 b.y;
  Alcotest.(check (float 0.001)) "w" 100.0 b.w;
  Alcotest.(check (float 0.001)) "h" 50.0 b.h

let round_bounds_negative_coords () =
  let n = make_node ~bounds:{ x = -3.2; y = -7.8; w = 10.0; h = 10.0 } () in
  let s = make_snapshot n in
  let s' = Normalize.apply [Round_bounds 5.0] s in
  let b = s'.root.bounds in
  Alcotest.(check (float 0.001)) "x" (-5.0) b.x;
  Alcotest.(check (float 0.001)) "y" (-10.0) b.y

(* ========================================================================= *)
(* Mask_text                                                                 *)
(* ========================================================================= *)

let mask_text_matching_selector () =
  let n = make_node ~tag:"SPAN" ~text:(Some "hello") () in
  let s = make_snapshot n in
  let s' = Normalize.apply [Mask_text { selector = Tag "span"; replacement = "***" }] s in
  Alcotest.(check (option string)) "masked" (Some "***") s'.root.text

let mask_text_non_matching () =
  let n = make_node ~tag:"DIV" ~text:(Some "hello") () in
  let s = make_snapshot n in
  let s' = Normalize.apply [Mask_text { selector = Tag "span"; replacement = "***" }] s in
  Alcotest.(check (option string)) "unchanged" (Some "hello") s'.root.text

let mask_text_children () =
  let child = make_node ~tag:"#text" ~text:(Some "date: 2024-01-01") () in
  let parent = make_node ~tag:"P" ~children:[child] () in
  let s = make_snapshot parent in
  let s' = Normalize.apply [Mask_text { selector = Tag "P"; replacement = "***" }] s in
  let child' = List.hd s'.root.children in
  Alcotest.(check (option string)) "child masked" (Some "***") child'.text

let mask_text_no_text () =
  let n = make_node ~tag:"SPAN" ~text:None () in
  let s = make_snapshot n in
  let s' = Normalize.apply [Mask_text { selector = Tag "span"; replacement = "***" }] s in
  Alcotest.(check (option string)) "still none" None s'.root.text

(* ========================================================================= *)
(* Mask_text_matching                                                        *)
(* ========================================================================= *)

let mask_text_regex_match () =
  let re = Re.compile (Re.Pcre.re {|\d{4}-\d{2}-\d{2}|}) in
  let n = make_node ~text:(Some "date: 2024-01-15") () in
  let s = make_snapshot n in
  let s' = Normalize.apply [Mask_text_matching { pattern = re; replacement = "YYYY-MM-DD" }] s in
  Alcotest.(check (option string)) "regex replaced"
    (Some "date: YYYY-MM-DD") s'.root.text

let mask_text_regex_no_match () =
  let re = Re.compile (Re.Pcre.re {|\d{4}-\d{2}-\d{2}|}) in
  let n = make_node ~text:(Some "no date here") () in
  let s = make_snapshot n in
  let s' = Normalize.apply [Mask_text_matching { pattern = re; replacement = "X" }] s in
  Alcotest.(check (option string)) "unchanged"
    (Some "no date here") s'.root.text

let mask_text_regex_multiple_matches () =
  let re = Re.compile (Re.Pcre.re {|\d+|}) in
  let n = make_node ~text:(Some "a1b2c3") () in
  let s = make_snapshot n in
  let s' = Normalize.apply [Mask_text_matching { pattern = re; replacement = "N" }] s in
  Alcotest.(check (option string)) "all replaced"
    (Some "aNbNcN") s'.root.text

let mask_text_regex_partial_match () =
  let re = Re.compile (Re.Pcre.re {|foo|}) in
  let n = make_node ~text:(Some "foobarfoo") () in
  let s = make_snapshot n in
  let s' = Normalize.apply [Mask_text_matching { pattern = re; replacement = "X" }] s in
  Alcotest.(check (option string)) "partial"
    (Some "XbarX") s'.root.text

(* ========================================================================= *)
(* Drop_subtree                                                              *)
(* ========================================================================= *)

let drop_subtree_at_root_child () =
  let ad = make_node ~tag:"DIV" ~attrs:[("class", "ad-banner")] () in
  let content = make_node ~tag:"MAIN" () in
  let root = make_node ~children:[ad; content] () in
  let s = make_snapshot root in
  let s' = Normalize.apply [Drop_subtree (Class "ad-banner")] s in
  Alcotest.(check int) "one child left" 1 (List.length s'.root.children);
  Alcotest.(check string) "content kept" "MAIN" (List.hd s'.root.children).tag

let drop_subtree_nested () =
  let deep = make_node ~tag:"SCRIPT" () in
  let mid = make_node ~tag:"DIV" ~children:[deep] () in
  let root = make_node ~children:[mid] () in
  let s = make_snapshot root in
  let s' = Normalize.apply [Drop_subtree (Tag "SCRIPT")] s in
  (* SCRIPT is a child of mid, so mid should have no children *)
  let mid' = List.hd s'.root.children in
  Alcotest.(check int) "script removed" 0 (List.length mid'.children)

let drop_subtree_no_match () =
  let child = make_node ~tag:"P" () in
  let root = make_node ~children:[child] () in
  let s = make_snapshot root in
  let s' = Normalize.apply [Drop_subtree (Tag "SCRIPT")] s in
  Alcotest.(check int) "unchanged" 1 (List.length s'.root.children)

(* ========================================================================= *)
(* Canonicalize_colors                                                       *)
(* ========================================================================= *)

let canon_color_whitespace () =
  let styles = { default_styles with color = Str "rgb( 59 , 130 , 246 )" } in
  let n = make_node ~styles () in
  let s = make_snapshot n in
  let s' = Normalize.apply [Canonicalize_colors] s in
  Alcotest.(check string) "whitespace normalized" "rgb(59, 130, 246)"
    (match s'.root.styles.color with Str s -> s | _ -> "")

let canon_color_rgba_opaque () =
  let styles = { default_styles with color = Str "rgba(255, 0, 0, 1)" } in
  let n = make_node ~styles () in
  let s = make_snapshot n in
  let s' = Normalize.apply [Canonicalize_colors] s in
  Alcotest.(check string) "rgba->rgb" "rgb(255, 0, 0)"
    (match s'.root.styles.color with Str s -> s | _ -> "")

let canon_color_already_canonical () =
  let styles = { default_styles with color = Str "rgb(0, 0, 0)" } in
  let n = make_node ~styles () in
  let s = make_snapshot n in
  let s' = Normalize.apply [Canonicalize_colors] s in
  Alcotest.(check string) "unchanged" "rgb(0, 0, 0)"
    (match s'.root.styles.color with Str s -> s | _ -> "")

let canon_color_border () =
  let border = { default_border with color = Str "rgba( 0, 0, 0, 1 )" } in
  let styles = { default_styles with border_top = border } in
  let n = make_node ~styles () in
  let s = make_snapshot n in
  let s' = Normalize.apply [Canonicalize_colors] s in
  Alcotest.(check string) "border color canonicalized" "rgb(0, 0, 0)"
    (match s'.root.styles.border_top.color with Str s -> s | _ -> "")

(* ========================================================================= *)
(* Canonicalize_fonts                                                        *)
(* ========================================================================= *)

let canon_font_multi_with_generic () =
  let styles =
    { default_styles with font_family =
        Str "Inter, ui-sans-serif, system-ui, sans-serif" }
  in
  let n = make_node ~styles () in
  let s = make_snapshot n in
  let s' = Normalize.apply [Canonicalize_fonts] s in
  Alcotest.(check string) "first named + first generic" "Inter, ui-sans-serif"
    (match s'.root.styles.font_family with Str s -> s | _ -> "")

let canon_font_pure_generic () =
  let styles = { default_styles with font_family = Str "monospace" } in
  let n = make_node ~styles () in
  let s = make_snapshot n in
  let s' = Normalize.apply [Canonicalize_fonts] s in
  Alcotest.(check string) "generic only" "monospace"
    (match s'.root.styles.font_family with Str s -> s | _ -> "")

let canon_font_single () =
  let styles = { default_styles with font_family = Str "Arial" } in
  let n = make_node ~styles () in
  let s = make_snapshot n in
  let s' = Normalize.apply [Canonicalize_fonts] s in
  Alcotest.(check string) "single font" "Arial"
    (match s'.root.styles.font_family with Str s -> s | _ -> "")

let canon_font_already_canonical () =
  let styles = { default_styles with font_family = Str "Inter, sans-serif" } in
  let n = make_node ~styles () in
  let s = make_snapshot n in
  let s' = Normalize.apply [Canonicalize_fonts] s in
  Alcotest.(check string) "unchanged" "Inter, sans-serif"
    (match s'.root.styles.font_family with Str s -> s | _ -> "")

(* ========================================================================= *)
(* Edge cases                                                                *)
(* ========================================================================= *)

let empty_snapshot_identity () =
  let root = make_node ~children:[] () in
  let s = make_snapshot root in
  let s' = Normalize.apply [] s in
  Alcotest.check snapshot_eq "identity" s s'

let empty_text_preserved () =
  let n = make_node ~text:(Some "") () in
  let s = make_snapshot n in
  let re = Re.compile (Re.Pcre.re {|foo|}) in
  let s' = Normalize.apply [Mask_text_matching { pattern = re; replacement = "X" }] s in
  Alcotest.(check (option string)) "empty preserved" (Some "") s'.root.text

let deeply_nested_recursion () =
  (* Build a chain of 50 nested nodes *)
  let rec build depth =
    if depth = 0 then make_node ~tag:"LEAF" ~attrs:[("data-x", "1")] ()
    else make_node ~children:[build (depth - 1)] ()
  in
  let root = build 50 in
  let s = make_snapshot root in
  let s' = Normalize.apply [Drop_attributes [Prefix "data-"]] s in
  (* Walk to the leaf *)
  let rec leaf (n : node) =
    match n.children with [] -> n | c :: _ -> leaf c
  in
  Alcotest.(check (list (pair string string))) "leaf attrs cleared"
    [] (leaf s'.root).attributes

let empty_rules_identity () =
  let child = make_node ~tag:"P" ~text:(Some "hi")
    ~attrs:[("class", "x")] () in
  let root = make_node ~children:[child] () in
  let s = make_snapshot root in
  let s' = Normalize.apply [] s in
  Alcotest.check snapshot_eq "identity" s s'

(* ========================================================================= *)
(* QCheck property tests                                                     *)
(* ========================================================================= *)

(* Generator for small snapshot trees *)
let gen_rect =
  QCheck.Gen.(map4
    (fun x y w h -> { x; y; w; h })
    (float_range (-100.0) 1000.0)
    (float_range (-100.0) 1000.0)
    (float_range 0.0 500.0)
    (float_range 0.0 500.0))

let gen_attrs =
  QCheck.Gen.(list_size (int_range 0 3)
    (pair
      (oneof_list ["id"; "class"; "data-x"; "role"; "style"])
      (oneof_list ["a"; "b c"; "1"; "foo"])))

let gen_text =
  QCheck.Gen.(oneof_weighted
    [(1, return None); (2, map (fun s -> Some s) (oneof_list ["hi"; "date: 2024-01-01"; "42"; ""]))])

let rec gen_node depth =
  QCheck.Gen.(
    let* tag = oneof_list ["DIV"; "SPAN"; "P"; "#text"; "SECTION"] in
    let* attrs = gen_attrs in
    let* bounds = gen_rect in
    let* text = gen_text in
    let* children =
      if depth <= 0 then return []
      else list_size (int_range 0 3) (gen_node (depth - 1))
    in
    return (make_node ~tag ~attrs ~text ~bounds ~children ()))

let gen_snapshot =
  QCheck.Gen.(map make_snapshot (gen_node 3))

let arb_snapshot = QCheck.make gen_snapshot

(* Idempotency: apply rules twice = apply once *)
let idempotent_drop_attributes =
  QCheck.Test.make ~name:"drop_attributes_idempotent" ~count:100 arb_snapshot
    (fun s ->
      let rules = [Normalize.Drop_attributes [Exact "class"; Prefix "data-"]] in
      Normalize.apply rules (Normalize.apply rules s) = Normalize.apply rules s)

let idempotent_sort_attributes =
  QCheck.Test.make ~name:"sort_attributes_idempotent" ~count:100 arb_snapshot
    (fun s ->
      let rules = [Normalize.Sort_attributes] in
      Normalize.apply rules (Normalize.apply rules s) = Normalize.apply rules s)

let idempotent_round_bounds =
  QCheck.Test.make ~name:"round_bounds_idempotent" ~count:100 arb_snapshot
    (fun s ->
      let rules = [Normalize.Round_bounds 5.0] in
      Normalize.apply rules (Normalize.apply rules s) = Normalize.apply rules s)

let idempotent_canonicalize_colors =
  QCheck.Test.make ~name:"canonicalize_colors_idempotent" ~count:100 arb_snapshot
    (fun s ->
      let rules = [Normalize.Canonicalize_colors] in
      Normalize.apply rules (Normalize.apply rules s) = Normalize.apply rules s)

let idempotent_canonicalize_fonts =
  QCheck.Test.make ~name:"canonicalize_fonts_idempotent" ~count:100 arb_snapshot
    (fun s ->
      let rules = [Normalize.Canonicalize_fonts] in
      Normalize.apply rules (Normalize.apply rules s) = Normalize.apply rules s)

let idempotent_mask_text =
  QCheck.Test.make ~name:"mask_text_idempotent" ~count:100 arb_snapshot
    (fun s ->
      let rules = [Normalize.Mask_text { selector = Universal; replacement = "***" }] in
      Normalize.apply rules (Normalize.apply rules s) = Normalize.apply rules s)

let idempotent_drop_subtree =
  QCheck.Test.make ~name:"drop_subtree_idempotent" ~count:100 arb_snapshot
    (fun s ->
      let rules = [Normalize.Drop_subtree (Tag "SPAN")] in
      Normalize.apply rules (Normalize.apply rules s) = Normalize.apply rules s)

let idempotent_combined =
  QCheck.Test.make ~name:"combined_rules_idempotent" ~count:100 arb_snapshot
    (fun s ->
      let rules = [
        Normalize.Drop_attributes [Exact "class"];
        Normalize.Sort_attributes;
        Normalize.Round_bounds 1.0;
        Normalize.Canonicalize_colors;
        Normalize.Canonicalize_fonts;
      ] in
      Normalize.apply rules (Normalize.apply rules s) = Normalize.apply rules s)

(* Drop_attributes subset: more patterns removes more *)
let rec count_attrs (n : node) =
  List.length n.attributes + List.fold_left (fun acc c -> acc + count_attrs c) 0 n.children

let drop_attr_subset_property =
  QCheck.Test.make ~name:"drop_attributes_more_patterns_fewer_attrs" ~count:100 arb_snapshot
    (fun s ->
      let fewer = [Normalize.Drop_attributes [Exact "class"]] in
      let more = [Normalize.Drop_attributes [Exact "class"; Prefix "data-"]] in
      let s_fewer = Normalize.apply fewer s in
      let s_more = Normalize.apply more s in
      count_attrs s_more.root <= count_attrs s_fewer.root)

(* ========================================================================= *)
(* Test runner                                                               *)
(* ========================================================================= *)

let () =
  Alcotest.run "normalize"
    [
      ( "drop_attributes",
        [
          Alcotest.test_case "exact match" `Quick drop_attr_exact_match;
          Alcotest.test_case "prefix match" `Quick drop_attr_prefix_match;
          Alcotest.test_case "no match passthrough" `Quick drop_attr_no_match;
          Alcotest.test_case "multiple patterns" `Quick drop_attr_multiple_patterns;
          Alcotest.test_case "empty attributes" `Quick drop_attr_empty_attributes;
        ] );
      ( "sort_attributes",
        [
          Alcotest.test_case "already sorted" `Quick sort_attr_already_sorted;
          Alcotest.test_case "reverse order" `Quick sort_attr_reverse_order;
          Alcotest.test_case "duplicates" `Quick sort_attr_duplicates;
        ] );
      ( "round_bounds",
        [
          Alcotest.test_case "exact values unchanged" `Quick round_bounds_exact_values;
          Alcotest.test_case "midpoint rounding" `Quick round_bounds_midpoint_rounding;
          Alcotest.test_case "negative coords" `Quick round_bounds_negative_coords;
        ] );
      ( "mask_text",
        [
          Alcotest.test_case "matching selector" `Quick mask_text_matching_selector;
          Alcotest.test_case "non-matching selector" `Quick mask_text_non_matching;
          Alcotest.test_case "text node children" `Quick mask_text_children;
          Alcotest.test_case "node with no text" `Quick mask_text_no_text;
        ] );
      ( "mask_text_matching",
        [
          Alcotest.test_case "regex match" `Quick mask_text_regex_match;
          Alcotest.test_case "no match" `Quick mask_text_regex_no_match;
          Alcotest.test_case "multiple matches" `Quick mask_text_regex_multiple_matches;
          Alcotest.test_case "partial match" `Quick mask_text_regex_partial_match;
        ] );
      ( "drop_subtree",
        [
          Alcotest.test_case "match at root child" `Quick drop_subtree_at_root_child;
          Alcotest.test_case "nested match" `Quick drop_subtree_nested;
          Alcotest.test_case "no match" `Quick drop_subtree_no_match;
        ] );
      ( "canonicalize_colors",
        [
          Alcotest.test_case "whitespace normalization" `Quick canon_color_whitespace;
          Alcotest.test_case "rgba opaque to rgb" `Quick canon_color_rgba_opaque;
          Alcotest.test_case "already canonical" `Quick canon_color_already_canonical;
          Alcotest.test_case "border color" `Quick canon_color_border;
        ] );
      ( "canonicalize_fonts",
        [
          Alcotest.test_case "multi with generic" `Quick canon_font_multi_with_generic;
          Alcotest.test_case "pure generic" `Quick canon_font_pure_generic;
          Alcotest.test_case "single font" `Quick canon_font_single;
          Alcotest.test_case "already canonical" `Quick canon_font_already_canonical;
        ] );
      ( "edge_cases",
        [
          Alcotest.test_case "empty snapshot identity" `Quick empty_snapshot_identity;
          Alcotest.test_case "empty text preserved" `Quick empty_text_preserved;
          Alcotest.test_case "deeply nested recursion" `Quick deeply_nested_recursion;
          Alcotest.test_case "empty rules identity" `Quick empty_rules_identity;
        ] );
      ( "properties",
        List.map QCheck_alcotest.to_alcotest
          [
            idempotent_drop_attributes;
            idempotent_sort_attributes;
            idempotent_round_bounds;
            idempotent_canonicalize_colors;
            idempotent_canonicalize_fonts;
            idempotent_mask_text;
            idempotent_drop_subtree;
            idempotent_combined;
            drop_attr_subset_property;
          ] );
    ]
