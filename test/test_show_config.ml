(** Unit tests for Show_config.

    Tests the pure functions: selector_to_css and overlay_js generation.
    The full show function requires a headed Chromium and is tested
    manually. *)

open Alcotest

(* -- selector_to_css tests ----------------------------------------------- *)

let selector_tag () =
  check string "tag selector" "div"
    (Sosie.Show_config.selector_to_css (Tag "div"))

let selector_tag_uppercase () =
  check string "tag uppercase" "div"
    (Sosie.Show_config.selector_to_css (Tag "DIV"))

let selector_id () =
  check string "id selector" "#main"
    (Sosie.Show_config.selector_to_css (Id "main"))

let selector_class () =
  check string "class selector" ".active"
    (Sosie.Show_config.selector_to_css (Class "active"))

let selector_universal () =
  check string "universal selector" "*"
    (Sosie.Show_config.selector_to_css Universal)

(* -- overlay_js tests ---------------------------------------------------- *)

let overlay_js_contains_selector () =
  let rules : Sosie.Normalize.rule list =
    [ Drop_subtree (Tag "NAV") ]
  in
  let js = Sosie.Show_config.overlay_js rules in
  check bool "contains querySelectorAll" true
    (let re = Re.compile (Re.str "querySelectorAll") in
     Re.execp re js);
  check bool "contains nav selector" true
    (let re = Re.compile (Re.str "'nav'") in
     Re.execp re js)

let overlay_js_mask_text () =
  let rules : Sosie.Normalize.rule list =
    [ Mask_text { selector = Class "date"; replacement = "MASKED" } ]
  in
  let js = Sosie.Show_config.overlay_js rules in
  check bool "contains replacement text" true
    (let re = Re.compile (Re.str "MASKED") in
     Re.execp re js);
  check bool "contains class selector" true
    (let re = Re.compile (Re.str ".date") in
     Re.execp re js)

let overlay_js_grid_lines () =
  let rules : Sosie.Normalize.rule list = [ Round_bounds 8.0 ] in
  let js = Sosie.Show_config.overlay_js rules in
  check bool "contains grid line code" true
    (let re = Re.compile (Re.str "line") in
     Re.execp re js);
  check bool "contains quantum value" true
    (let re = Re.compile (Re.str "8") in
     Re.execp re js)

let overlay_js_drop_attributes () =
  let rules : Sosie.Normalize.rule list =
    [ Drop_attributes [ Exact "class"; Prefix "data-" ] ]
  in
  let js = Sosie.Show_config.overlay_js rules in
  check bool "contains dashed border style" true
    (let re = Re.compile (Re.str "dashed") in
     Re.execp re js);
  check bool "contains attribute check" true
    (let re = Re.compile (Re.str "data-") in
     Re.execp re js)

let overlay_js_legend () =
  let rules : Sosie.Normalize.rule list =
    [ Canonicalize_colors; Sort_attributes ]
  in
  let js = Sosie.Show_config.overlay_js rules in
  check bool "contains legend" true
    (let re = Re.compile (Re.str "sosie config overlay") in
     Re.execp re js)

let () =
  run "Show_config"
    [
      ( "selector_to_css",
        [
          test_case "tag selector" `Quick selector_tag;
          test_case "tag uppercase lowered" `Quick selector_tag_uppercase;
          test_case "id selector" `Quick selector_id;
          test_case "class selector" `Quick selector_class;
          test_case "universal selector" `Quick selector_universal;
        ] );
      ( "overlay_js",
        [
          test_case "contains querySelectorAll for selector" `Quick
            overlay_js_contains_selector;
          test_case "mask_text shows replacement" `Quick overlay_js_mask_text;
          test_case "round_bounds produces grid lines" `Quick
            overlay_js_grid_lines;
          test_case "drop_attributes produces dashed border" `Quick
            overlay_js_drop_attributes;
          test_case "legend always present" `Quick overlay_js_legend;
        ] );
    ]
