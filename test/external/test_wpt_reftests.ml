(** WPT reftest runner.

    Runs curated W3C Web Platform Tests reftests through sosie. Only the paths
    listed in [manifest.json] are tested — not the entire sparse checkout.

    Each test declares [<link rel="match" href="ref.html">]; the test and
    reference must render identically. sosie captures both and compares:
    equivalence means pass.

    The file server and Chromium are launched outside of Alcotest to avoid
    fd-inheritance issues with [Unix.fork] under Alcotest's stdout capture.

    Run with: [test/external/fetch.sh && dune build @external] *)

open Sosie

let extractor_js = Extractor_js_source.source
let ext_dir () = Lazy.force Ext_test_lib.external_dir
let wpt_dir () = Filename.concat (ext_dir ()) "wpt"
let expectations_file () = Filename.concat (ext_dir ()) "expectations.json"

let read_file path =
  let ic = open_in path in
  Fun.protect
    ~finally:(fun () -> close_in_noerr ic)
    (fun () ->
      let len = in_channel_length ic in
      let buf = Bytes.create len in
      really_input ic buf 0 len;
      Bytes.to_string buf)

(** WPT reftests compare test vs. reference HTML that achieve the same visual
    result via different CSS. The two pages have different HEAD content
    (different <link>/<style>/<title>) and different DOM sizes, so:
    - Drop HEAD subtree (metadata, not visual).
    - Disable paint_order check (node count differs). *)
let wpt_config = { Compare.default_config with check_paint_order = false }

let wpt_normalize =
  [
    Normalize.Drop_subtree (Tag "head");
    Normalize.Round_bounds 1.0;
    Normalize.Canonicalize_colors;
    Normalize.Canonicalize_fonts;
    Normalize.Sort_attributes;
  ]

(** Build one Alcotest test case per manifest path. *)
let make_test_case ~conn ~port ~viewport ~all_expectations ~wpt_dir rel_path =
  let test_fn () =
    let file_path = Filename.concat wpt_dir rel_path in
    if not (Sys.file_exists file_path) then
      Alcotest.fail (Printf.sprintf "file missing: %s" rel_path)
    else
      let html = read_file file_path in
      let expectation =
        match List.assoc_opt rel_path all_expectations with
        | Some e -> e
        | None -> Ext_test_lib.Pass
      in
      match expectation with
      | Skip reason -> Printf.printf "  SKIP: %s (%s)\n%!" rel_path reason
      | _ -> (
          match Ext_test_lib.parse_reftest_link html with
          | None -> Printf.printf "  SKIP (no reftest link): %s\n%!" rel_path
          | Some ref_href -> (
              if not (Ext_test_lib.is_deterministic_test html) then
                Printf.printf "  SKIP (animation): %s\n%!" rel_path
              else
                let ref_path =
                  if String.starts_with ~prefix:"/" ref_href then ref_href
                  else
                    let dir = Filename.dirname rel_path in
                    "/" ^ Filename.concat dir ref_href
                in
                let test_url =
                  Printf.sprintf "http://127.0.0.1:%d/%s" port rel_path
                in
                let ref_url =
                  Printf.sprintf "http://127.0.0.1:%d%s" port ref_path
                in
                let outcome =
                  match
                    Ext_test_lib.capture_pair conn ~extractor_js ~viewport
                      ~test_url ~ref_url
                  with
                  | Error msg -> Ext_test_lib.Error msg
                  | Ok (test_snap, ref_snap) ->
                      Ext_test_lib.compare_pair ~normalize:wpt_normalize
                        ~matched:true wpt_config test_snap ref_snap
                in
                match (expectation, outcome) with
                | Pass, Ext_test_lib.Equivalent -> ()
                | Xfail _, (Ext_test_lib.Diff _ | Ext_test_lib.Error _) -> ()
                | Xfail reason, Ext_test_lib.Equivalent ->
                    Alcotest.fail
                      (Printf.sprintf "unexpected pass (xfail: %s)" reason)
                | _, Ext_test_lib.Diff descs ->
                    Alcotest.fail
                      (Printf.sprintf "unexpected diffs:\n  %s"
                         (String.concat "\n  "
                            (List.filteri (fun i _ -> i < 5) descs)))
                | _, Ext_test_lib.Error msg ->
                    Alcotest.fail (Printf.sprintf "error: %s" msg)
                | Skip _, _ -> ()))
  in
  Alcotest.test_case rel_path `Quick test_fn

let () =
  Ext_test_lib.ensure_resources ~suite:"wpt";
  let wpt_dir = wpt_dir () in
  let all_expectations =
    Ext_test_lib.load_expectations (expectations_file ())
  in
  let manifest_paths = Ext_test_lib.load_manifest_paths ~suite:"wpt" in
  let viewport = (1024, 768) in

  File_server.with_server ~root:wpt_dir (fun port ->
      Cdp_launcher.with_chromium (fun ws_url ->
          let conn = Cdp.connect ws_url in
          Fun.protect
            ~finally:(fun () -> Cdp.close conn)
            (fun () ->
              let cases =
                List.map
                  (make_test_case ~conn ~port ~viewport ~all_expectations
                     ~wpt_dir)
                  manifest_paths
              in
              Alcotest.run "wpt-reftests" [ ("wpt", cases) ])))
