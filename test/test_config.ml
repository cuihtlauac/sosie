(** Unit tests for the configuration file parser. *)

open Sosie

let parse s =
  Config.of_json (Yojson.Safe.from_string s)

(* --- Defaults --- *)

let empty_object_uses_defaults () =
  match parse "{}" with
  | Ok cfg ->
    Alcotest.(check (list pass)) "no rules" [] cfg.normalize;
    Alcotest.(check bool) "check_bounds" true cfg.compare.check_bounds;
    Alcotest.(check bool) "check_visual" true cfg.compare.check_visual;
    Alcotest.(check bool) "check_text" true cfg.compare.check_text;
    Alcotest.(check bool) "check_paint_order" true cfg.compare.check_paint_order;
    Alcotest.(check (float 0.0)) "bounds_tolerance" 0.0 cfg.compare.bounds_tolerance;
    Alcotest.(check (float 0.0)) "value_tolerance" 0.0 cfg.compare.value_tolerance
  | Error msg -> Alcotest.fail msg

let minimal_normalize () =
  match parse {|{"normalize": {}}|} with
  | Ok cfg -> Alcotest.(check (list pass)) "no rules" [] cfg.normalize
  | Error msg -> Alcotest.fail msg

(* --- Invalid JSON --- *)

let not_an_object () =
  match parse {|"hello"|} with
  | Error _ -> ()
  | Ok _ -> Alcotest.fail "expected error for non-object"

let invalid_json () =
  match Config.of_json (`String "bad") with
  | Error _ -> ()
  | Ok _ -> Alcotest.fail "expected error"

(* --- Compare config --- *)

let compare_all_false () =
  match parse {|{"compare": {"check_bounds": false, "check_visual": false, "check_text": false, "check_paint_order": false, "bounds_tolerance": 1.5, "value_tolerance": 0.01}}|} with
  | Ok cfg ->
    Alcotest.(check bool) "bounds" false cfg.compare.check_bounds;
    Alcotest.(check bool) "visual" false cfg.compare.check_visual;
    Alcotest.(check bool) "text" false cfg.compare.check_text;
    Alcotest.(check bool) "paint" false cfg.compare.check_paint_order;
    Alcotest.(check (float 0.01)) "bounds_tol" 1.5 cfg.compare.bounds_tolerance;
    Alcotest.(check (float 0.001)) "value_tol" 0.01 cfg.compare.value_tolerance
  | Error msg -> Alcotest.fail msg

let compare_bad_field () =
  match parse {|{"compare": {"check_bounds": "yes"}}|} with
  | Error _ -> ()
  | Ok _ -> Alcotest.fail "expected error for bad bool"

(* --- Selector parsing --- *)

let selector_tag () =
  match parse {|{"normalize": {"drop_subtrees": ["div"]}}|} with
  | Ok cfg ->
    (match cfg.normalize with
     | [Normalize.Drop_subtree (Tag "DIV")] -> ()
     | _ -> Alcotest.fail "expected Tag DIV")
  | Error msg -> Alcotest.fail msg

let selector_id () =
  match parse {|{"normalize": {"drop_subtrees": ["#foo"]}}|} with
  | Ok cfg ->
    (match cfg.normalize with
     | [Normalize.Drop_subtree (Id "foo")] -> ()
     | _ -> Alcotest.fail "expected Id foo")
  | Error msg -> Alcotest.fail msg

let selector_class () =
  match parse {|{"normalize": {"drop_subtrees": [".bar"]}}|} with
  | Ok cfg ->
    (match cfg.normalize with
     | [Normalize.Drop_subtree (Class "bar")] -> ()
     | _ -> Alcotest.fail "expected Class bar")
  | Error msg -> Alcotest.fail msg

let selector_universal () =
  match parse {|{"normalize": {"drop_subtrees": ["*"]}}|} with
  | Ok cfg ->
    (match cfg.normalize with
     | [Normalize.Drop_subtree Universal] -> ()
     | _ -> Alcotest.fail "expected Universal")
  | Error msg -> Alcotest.fail msg

(* --- Attribute patterns --- *)

let attr_exact () =
  match parse {|{"normalize": {"drop_attributes": ["class"]}}|} with
  | Ok cfg ->
    (match cfg.normalize with
     | [Normalize.Drop_attributes [Exact "class"]] -> ()
     | _ -> Alcotest.fail "expected Exact class")
  | Error msg -> Alcotest.fail msg

let attr_prefix () =
  match parse {|{"normalize": {"drop_attributes": ["data-*"]}}|} with
  | Ok cfg ->
    (match cfg.normalize with
     | [Normalize.Drop_attributes [Prefix "data-"]] -> ()
     | _ -> Alcotest.fail "expected Prefix data-")
  | Error msg -> Alcotest.fail msg

(* --- Full config --- *)

let full_config () =
  let json = {|{
    "normalize": {
      "drop_attributes": ["class", "style"],
      "sort_attributes": true,
      "round_bounds": 0.5,
      "canonicalize_colors": true,
      "canonicalize_fonts": true,
      "mask_text": [{"selector": "time", "replacement": "[DATE]"}],
      "mask_text_matching": [{"pattern": "\\d{4}", "replacement": "[YEAR]"}],
      "drop_subtrees": ["#planet-feed"]
    },
    "compare": {
      "check_bounds": true,
      "bounds_tolerance": 0.5
    }
  }|} in
  match parse json with
  | Ok cfg ->
    Alcotest.(check int) "rule count" 8 (List.length cfg.normalize);
    Alcotest.(check (float 0.01)) "bounds_tol" 0.5 cfg.compare.bounds_tolerance
  | Error msg -> Alcotest.fail msg

(* --- Unknown fields ignored --- *)

let unknown_fields_ignored () =
  match parse {|{"normalize": {"unknown_field": true}, "extra": 42}|} with
  | Ok cfg -> Alcotest.(check (list pass)) "no rules" [] cfg.normalize
  | Error msg -> Alcotest.fail msg

(* --- Bad normalize types --- *)

let bad_normalize_type () =
  match parse {|{"normalize": "bad"}|} with
  | Error _ -> ()
  | Ok _ -> Alcotest.fail "expected error"

let bad_drop_attributes_type () =
  match parse {|{"normalize": {"drop_attributes": "class"}}|} with
  | Error _ -> ()
  | Ok _ -> Alcotest.fail "expected error"

(* --- Tests --- *)

let () =
  Alcotest.run "config" [
    "defaults", [
      Alcotest.test_case "empty object uses defaults" `Quick empty_object_uses_defaults;
      Alcotest.test_case "minimal normalize" `Quick minimal_normalize;
    ];
    "invalid", [
      Alcotest.test_case "not an object" `Quick not_an_object;
      Alcotest.test_case "invalid json value" `Quick invalid_json;
      Alcotest.test_case "bad normalize type" `Quick bad_normalize_type;
      Alcotest.test_case "bad drop_attributes type" `Quick bad_drop_attributes_type;
    ];
    "compare", [
      Alcotest.test_case "all checks disabled with tolerances" `Quick compare_all_false;
      Alcotest.test_case "bad field type" `Quick compare_bad_field;
    ];
    "selectors", [
      Alcotest.test_case "tag selector" `Quick selector_tag;
      Alcotest.test_case "id selector" `Quick selector_id;
      Alcotest.test_case "class selector" `Quick selector_class;
      Alcotest.test_case "universal selector" `Quick selector_universal;
    ];
    "attr_patterns", [
      Alcotest.test_case "exact pattern" `Quick attr_exact;
      Alcotest.test_case "prefix pattern" `Quick attr_prefix;
    ];
    "full", [
      Alcotest.test_case "full config parses" `Quick full_config;
      Alcotest.test_case "unknown fields ignored" `Quick unknown_fields_ignored;
    ];
  ]
