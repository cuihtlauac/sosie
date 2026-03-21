(** Acid3 test runner.

    Validates the extractor on a high-node-count DOM with pseudo-elements and
    complex CSS. Tests against the live Acid3 URL. Two test cases: node count
    verification and deterministic capture (same page captured twice must
    produce equivalent snapshots).

    Run with: [test/external/fetch.sh && dune build @external] *)

open Sosie

let extractor_js = Extractor_js_source.source
let acid3_url = "http://acid3.acidtests.org/"

(** Count nodes recursively. *)
let rec count_nodes (node : Snapshot_types.node) =
  1 + List.fold_left (fun acc c -> acc + count_nodes c) 0 node.children

let capture_acid3 conn ~viewport =
  let json = Capture.capture conn ~extractor_js ~url:acid3_url ~viewport () in
  Snapshot.of_json json

let high_node_count ~conn ~viewport () =
  let snap = capture_acid3 conn ~viewport in
  let n = count_nodes snap.root in
  Printf.printf "  Acid3: %d nodes in snapshot\n%!" n;
  Alcotest.(check bool) "node count > 50" true (n > 50)

let deterministic_capture ~conn ~viewport () =
  let snap1 = capture_acid3 conn ~viewport in
  Unix.sleepf 1.0;
  let snap2 = capture_acid3 conn ~viewport in
  let config = Compare.default_config in
  let outcome =
    Ext_test_lib.compare_pair
      ~normalize:[ Normalize.Round_bounds 1.0; Normalize.Canonicalize_colors ]
      config snap1 snap2
  in
  match outcome with
  | Ext_test_lib.Equivalent ->
      Printf.printf "  Acid3: deterministic capture confirmed\n%!"
  | Ext_test_lib.Diff descs ->
      Alcotest.fail
        (Printf.sprintf "not deterministic: %s" (String.concat "; " descs))
  | Ext_test_lib.Error msg -> Alcotest.fail (Printf.sprintf "error: %s" msg)

let () =
  let viewport = (1024, 768) in
  Cdp_launcher.with_chromium (fun ws_url ->
      let conn = Cdp.connect ws_url in
      Fun.protect
        ~finally:(fun () -> Cdp.close conn)
        (fun () ->
          Alcotest.run "acid3"
            [
              ( "acid3",
                [
                  Alcotest.test_case "high_node_count" `Slow
                    (high_node_count ~conn ~viewport);
                  Alcotest.test_case "deterministic_capture" `Slow
                    (deterministic_capture ~conn ~viewport);
                ] );
            ]))
