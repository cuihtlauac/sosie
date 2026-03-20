(** CDP integration tests.

    These tests require a running Chromium instance or the ability to
    launch one. They are NOT run by default with [dune runtest].

    Run with: [dune build @integration] *)

open Sosie

let browser_get_version () =
  Cdp_launcher.with_chromium (fun ws_url ->
    let conn = Cdp.connect ws_url in
    let result = Cdp.send conn "Browser.getVersion" (`Assoc []) in
    (match result with
    | `Assoc fields ->
        Alcotest.(check bool) "has product" true
          (List.mem_assoc "product" fields);
        let product =
          match List.assoc_opt "product" fields with
          | Some (`String s) -> s
          | _ -> ""
        in
        Alcotest.(check bool) "product contains Chrome" true
          (String.starts_with ~prefix:"Chrome" product
          || String.starts_with ~prefix:"Headless" product)
    | _ -> Alcotest.fail "expected JSON object from Browser.getVersion");
    Cdp.close conn)

let evaluate_simple_expression () =
  Cdp_launcher.with_chromium (fun ws_url ->
    let conn = Cdp.connect ws_url in
    let result = Cdp.evaluate_js conn "1 + 1" in
    Alcotest.(check string) "1 + 1 = 2" "2"
      (Yojson.Safe.to_string result);
    Cdp.close conn)

let () =
  Alcotest.run "cdp-integration"
    [
      ( "cdp",
        [
          Alcotest.test_case "browser_get_version" `Slow
            browser_get_version;
          Alcotest.test_case "evaluate_simple_expression" `Slow
            evaluate_simple_expression;
        ] );
    ]
