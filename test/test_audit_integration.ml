(** Audit whitelist integration tests.

    These tests require a running Chromium instance or the ability to
    launch one. They are NOT run by default with [dune runtest].

    Run with: [dune build @integration] *)

open Sosie

let all_css_properties_returns_known () =
  Cdp_launcher.with_chromium (fun ws_url ->
    let conn = Cdp.connect ws_url in
    let props = Audit_whitelist.all_css_properties conn in
    Alcotest.(check bool) "non-empty" true (List.length props > 0);
    List.iter
      (fun expected ->
        Alcotest.(check bool) (expected ^ " present") true
          (List.mem expected props))
      [ "color"; "display"; "font-size" ];
    Cdp.close conn)

let () =
  Alcotest.run "audit-integration"
    [
      ( "all_css_properties",
        [
          Alcotest.test_case "returns known properties" `Quick
            all_css_properties_returns_known;
        ] );
    ]
