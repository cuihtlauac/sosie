(** Capture integration tests.

    These tests require a running Chromium instance or the ability to
    launch one. They are NOT run by default with [dune runtest].

    Run with: [dune build @integration] *)

open Sosie

let extractor_js = Extractor_js_source.source

(** Helper: launch Chromium, connect, capture, close. *)
let with_capture ?viewport ?color_scheme url f =
  Cdp_launcher.with_chromium (fun ws_url ->
    let conn = Cdp.connect ws_url in
    let json =
      Capture.capture conn ~extractor_js ~url ?viewport ?color_scheme ()
    in
    f json;
    Cdp.close conn)

(** Extract a string field from a JSON object. *)
let json_string key json =
  match json with
  | `Assoc fields -> (
      match List.assoc_opt key fields with
      | Some (`String s) -> s
      | _ -> Alcotest.failf "missing or non-string field: %s" key)
  | _ -> Alcotest.fail "expected JSON object"

(** Extract an int field from a JSON object. *)
let json_int key json =
  match json with
  | `Assoc fields -> (
      match List.assoc_opt key fields with
      | Some (`Int i) -> i
      | _ -> Alcotest.failf "missing or non-int field: %s" key)
  | _ -> Alcotest.fail "expected JSON object"

(** Extract a field from a JSON object. *)
let json_field key json =
  match json with
  | `Assoc fields -> (
      match List.assoc_opt key fields with
      | Some v -> v
      | None -> Alcotest.failf "missing field: %s" key)
  | _ -> Alcotest.fail "expected JSON object"

let capture_about_blank_has_expected_schema () =
  with_capture "about:blank" (fun json ->
      let version = json_int "version" json in
      Alcotest.(check int) "version is 1" 1 version;
      let url = json_string "url" json in
      Alcotest.(check bool) "url contains about:blank" true
        (String.starts_with ~prefix:"about:blank" url);
      let _viewport = json_field "viewport" json in
      let color_scheme = json_string "colorScheme" json in
      Alcotest.(check string) "color scheme is light" "light" color_scheme;
      let root = json_field "root" json in
      let tag = json_string "tag" root in
      Alcotest.(check string) "root tag is HTML" "HTML" tag)

let capture_parses_to_typed_snapshot () =
  with_capture "about:blank" (fun json ->
      let s = Snapshot.of_json json in
      Alcotest.(check int) "version" 1 s.version;
      Alcotest.(check bool) "url starts with about:blank" true
        (String.starts_with ~prefix:"about:blank" s.url);
      Alcotest.(check string) "root tag" "HTML" s.root.tag;
      Alcotest.(check bool) "light scheme" true (s.color_scheme = `Light);
      (* Round-trip: to_json then of_json produces the same snapshot *)
      let json' = Snapshot.to_json s in
      let s' = Snapshot.of_json json' in
      Alcotest.(check string) "round-trip tag" s.root.tag s'.root.tag;
      Alcotest.(check int) "round-trip version" s.version s'.version)

let capture_custom_viewport () =
  with_capture ~viewport:(800, 600) "about:blank" (fun json ->
      let viewport = json_field "viewport" json in
      match viewport with
      | `List [ `Int w; `Int h ] ->
          Alcotest.(check int) "viewport width" 800 w;
          Alcotest.(check int) "viewport height" 600 h
      | _ -> Alcotest.fail "viewport is not [int, int]")

let capture_dark_scheme () =
  with_capture ~color_scheme:`Dark "about:blank" (fun json ->
      let color_scheme = json_string "colorScheme" json in
      Alcotest.(check string) "color scheme is dark" "dark" color_scheme)

(* An XHTML document served as application/xhtml+xml is XML-parsed, so the
   parser does not synthesize a <head> (the HTML parser does). This makes
   [document.head] null, which previously crashed the freeze step with
   "Cannot read properties of null (reading 'appendChild')". The extractor
   must fall back to the document element and still produce a valid snapshot. *)
let headless_xhtml =
  "data:application/xhtml+xml,"
  ^ "<html%20xmlns=%22http://www.w3.org/1999/xhtml%22>"
  ^ "<body>headless</body></html>"

let capture_headless_document_does_not_crash () =
  with_capture headless_xhtml (fun json ->
      (* Reaching here means the freeze step did not raise on a null head. *)
      let s = Snapshot.of_json json in
      Alcotest.(check int) "version" 1 s.version;
      (* Round-trips through the schema despite the missing <head>. *)
      let s' = Snapshot.of_json (Snapshot.to_json s) in
      Alcotest.(check string) "round-trip root tag" s.root.tag s'.root.tag)

let () =
  Alcotest.run "capture-integration"
    [
      ( "capture",
        [
          Alcotest.test_case "about_blank_has_expected_schema" `Slow
            capture_about_blank_has_expected_schema;
          Alcotest.test_case "custom_viewport" `Slow
            capture_custom_viewport;
          Alcotest.test_case "dark_scheme" `Slow
            capture_dark_scheme;
          Alcotest.test_case "parses_to_typed_snapshot" `Slow
            capture_parses_to_typed_snapshot;
          Alcotest.test_case "headless_document_does_not_crash" `Slow
            capture_headless_document_does_not_crash;
        ] );
    ]
