(** Unit tests for Audit_whitelist.

    Tests the pure functions: reset_stylesheet and its edge cases.
    Integration tests (all_css_properties, full audit) require Chromium
    and live in the integration test suite. *)

open Alcotest

let whitelist_names = Sosie.Property_whitelist.css_names

(* -- reset_stylesheet tests ---------------------------------------------- *)

let reset_excludes_whitelisted () =
  let all = [ "color"; "display"; "margin"; "padding" ] in
  let whitelist = [ "color"; "display" ] in
  let css = Sosie.Audit_whitelist.reset_stylesheet ~whitelist ~all_properties:all in
  check bool "contains margin" true (String.length css > 0);
  check bool "margin in output" true
    (let idx = ref false in
     String.split_on_char '\n' css
     |> List.iter (fun line ->
          if String.length line > 0 then
            let trimmed = String.trim line in
            if String.length trimmed > 6 &&
               String.sub trimmed 0 6 = "margin" then
              idx := true);
     !idx);
  check bool "padding in output" true
    (let found = ref false in
     String.split_on_char '\n' css
     |> List.iter (fun line ->
          if String.length line > 0 then
            let trimmed = String.trim line in
            if String.length trimmed > 7 &&
               String.sub trimmed 0 7 = "padding" then
              found := true);
     !found);
  check bool "color not in output" false
    (let found = ref false in
     String.split_on_char '\n' css
     |> List.iter (fun line ->
          if String.length line > 0 then
            let trimmed = String.trim line in
            (* Match "color:" but not "background-color:" *)
            if String.length trimmed >= 6 &&
               String.sub trimmed 0 6 = "color:" then
              found := true);
     !found)

let reset_empty_whitelist () =
  let all = [ "color"; "display"; "margin" ] in
  let css = Sosie.Audit_whitelist.reset_stylesheet ~whitelist:[] ~all_properties:all in
  check bool "non-empty" true (String.length css > 0);
  List.iter
    (fun prop ->
      check bool (prop ^ " in output") true
        (let re = Re.compile (Re.str (prop ^ ": initial !important;")) in
         Re.execp re css))
    all

let reset_full_whitelist () =
  let all = [ "color"; "display" ] in
  let whitelist = [ "color"; "display" ] in
  let css = Sosie.Audit_whitelist.reset_stylesheet ~whitelist ~all_properties:all in
  check string "empty output" "" css

let reset_format () =
  let all = [ "margin"; "padding" ] in
  let css = Sosie.Audit_whitelist.reset_stylesheet ~whitelist:[] ~all_properties:all in
  check bool "starts with * {" true
    (String.length css >= 3 && String.sub css 0 3 = "* {");
  check bool "contains initial !important" true
    (let re = Re.compile (Re.str "initial !important;") in
     Re.execp re css);
  check bool "ends with }" true
    (css.[String.length css - 1] = '}')

let handles_vendor_prefixed () =
  let all = [ "-webkit-transform"; "color"; "-moz-appearance" ] in
  let whitelist = [ "color" ] in
  let css = Sosie.Audit_whitelist.reset_stylesheet ~whitelist ~all_properties:all in
  check bool "-webkit-transform in output" true
    (let re = Re.compile (Re.str "-webkit-transform: initial !important;") in
     Re.execp re css);
  check bool "-moz-appearance in output" true
    (let re = Re.compile (Re.str "-moz-appearance: initial !important;") in
     Re.execp re css)

let whitelist_has_expected_count () =
  check bool "whitelist has 49 properties" true
    (List.length whitelist_names = 49);
  check (list string) "whitelist_css_names matches Property_whitelist"
    whitelist_names Sosie.Audit_whitelist.whitelist_css_names

let () =
  run "Audit_whitelist"
    [
      ( "reset_stylesheet",
        [
          test_case "excludes whitelisted properties" `Quick
            reset_excludes_whitelisted;
          test_case "empty whitelist includes all" `Quick reset_empty_whitelist;
          test_case "full whitelist produces empty" `Quick reset_full_whitelist;
          test_case "correct CSS format" `Quick reset_format;
          test_case "handles vendor-prefixed names" `Quick
            handles_vendor_prefixed;
          test_case "whitelist count is 49" `Quick whitelist_has_expected_count;
        ] );
    ]
