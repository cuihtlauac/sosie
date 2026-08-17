(** WPT reftest runner — discovery-based with filesystem result cache.

    Discovers all reftests by walking the sparse checkout, runs only uncached
    tests, and writes per-test result files. Resumable: safe to Ctrl-C and
    restart.

    Usage:
      dune exec test/external/test_wpt_reftests.exe
      dune exec test/external/test_wpt_reftests.exe -- --group css-flexbox
      dune exec test/external/test_wpt_reftests.exe -- --report
      dune exec test/external/test_wpt_reftests.exe -- --rerun css/css-color/a98rgb-001.html
      dune exec test/external/test_wpt_reftests.exe -- --rerun-group css-flexbox *)

open Sosie

let extractor_js = Extractor_js_source.source
let ext_dir () = Lazy.force Ext_test_lib.external_dir
let wpt_dir () = Filename.concat (ext_dir ()) "wpt"
let expectations_file () = Filename.concat (ext_dir ()) "expectations.json"

(** WPT reftests compare test vs. reference HTML that achieve the same visual
    result via different CSS. The two pages have different HEAD content
    (different <link>/<style>/<title>) and different DOM sizes, so:
    - Drop HEAD subtree (metadata, not visual).
    - Disable paint_order check (node count differs). *)
let wpt_config =
  { Compare.default_config with
    check_paint_order = false;
    check_text = false;
    bounds_tolerance = 1.0;
  }

let wpt_normalize =
  [
    Normalize.Drop_subtree (Tag "head");
    Normalize.Drop_subtree (Tag "script");
    Normalize.Drop_subtree (Tag "style");
    Normalize.Drop_subtree (Tag "noscript");
    Normalize.Drop_invisible;
    Normalize.Round_bounds 1.0;
    Normalize.Canonicalize_colors;
    Normalize.Canonicalize_fonts;
    Normalize.Sort_attributes;
  ]

(* ── CLI argument parsing ────────────────────────────────────────── *)

type mode =
  | Run_all
  | Run_group of string
  | Report
  | Rerun of string
  | Rerun_group of string

let parse_args () =
  let argv = Sys.argv in
  let n = Array.length argv in
  if n <= 1 then Run_all
  else
    match argv.(1) with
    | "--report" -> Report
    | "--group" when n > 2 -> Run_group argv.(2)
    | "--rerun" when n > 2 -> Rerun argv.(2)
    | "--rerun-group" when n > 2 -> Rerun_group argv.(2)
    | arg ->
        Printf.eprintf
          "Unknown argument: %s\n\
           Usage:\n\
          \  test_wpt_reftests.exe                      Run all uncached tests\n\
          \  test_wpt_reftests.exe --group GROUP         Run uncached tests in group\n\
          \  test_wpt_reftests.exe --report              Report cached results\n\
          \  test_wpt_reftests.exe --rerun PATH          Re-run a specific test\n\
          \  test_wpt_reftests.exe --rerun-group GROUP   Re-run all tests in group\n"
          arg;
        exit 2

(* ── Timeout wrapper ─────────────────────────────────────────────── *)

exception Test_timeout

let with_timeout seconds f =
  let old_handler = Sys.signal Sys.sigalrm (Sys.Signal_handle (fun _ -> raise Test_timeout)) in
  Fun.protect
    ~finally:(fun () ->
      ignore (Unix.alarm 0);
      Sys.set_signal Sys.sigalrm old_handler)
    (fun () ->
      ignore (Unix.alarm seconds);
      f ())

(* ── Single test execution ───────────────────────────────────────── *)

let run_one_test conn ~port ~viewport ~all_expectations
    (test : Ext_test_lib.reftest) =
  let rel_path = test.rel_path in
  let expectation =
    match List.assoc_opt rel_path all_expectations with
    | Some e -> e
    | None -> Ext_test_lib.Pass
  in
  match expectation with
  | Skip reason ->
      (* Don't cache skips — they're policy, not measurements *)
      Printf.printf "  SKIP  %s (%s)\n%!" rel_path reason;
      ({ status = "skip"; diffs = []; elapsed_s = 0.0; timestamp = "" }
        : Ext_test_lib.cached_result)
  | _ ->
      let t0 = Unix.gettimeofday () in
      let test_url =
        Printf.sprintf "http://127.0.0.1:%d/%s" port rel_path
      in
      let ref_url_of ref_href =
        let ref_path =
          if String.length ref_href > 0 && ref_href.[0] = '/' then ref_href
          else
            let dir = Filename.dirname rel_path in
            "/" ^ Filename.concat dir ref_href
        in
        Printf.sprintf "http://127.0.0.1:%d%s" port ref_path
      in
      let compare_against ref_href =
        match
          Ext_test_lib.capture_pair conn ~extractor_js ~viewport ~test_url
            ~ref_url:(ref_url_of ref_href)
        with
        | Error msg -> Ext_test_lib.Error msg
        | Ok (test_snap, ref_snap) ->
            Ext_test_lib.compare_pair ~normalize:wpt_normalize ~matched:true
              wpt_config test_snap ref_snap
      in
      (* Try references in order, stopping at the first Equivalent; else
         return the first reference's outcome (canonical, keeps diffs stable
         across runs). This one loop serves both kinds: a Match test passes
         on ANY Equivalent, a Mismatch test fails on ANY Equivalent and
         passes only if every reference yields Diff — the interpretation is
         applied afterwards by Ext_test_lib.cache_status. *)
      let rec try_refs first = function
        | [] -> (
            match first with
            | Some o -> o
            | None -> Ext_test_lib.Error "no reference available")
        | href :: rest -> (
            match compare_against href with
            | Ext_test_lib.Equivalent -> Ext_test_lib.Equivalent
            | o ->
                let first = if first = None then Some o else first in
                try_refs first rest)
      in
      let outcome =
        try with_timeout 30 (fun () -> try_refs None test.ref_hrefs) with
        | Test_timeout -> Ext_test_lib.Error "timeout (30s)"
        | exn -> Ext_test_lib.Error (Printexc.to_string exn)
      in
      let elapsed_s = Unix.gettimeofday () -. t0 in
      let timestamp = Ext_test_lib.iso8601_now () in
      let status, diffs =
        Ext_test_lib.cache_status ~kind:test.kind ~expectation outcome
      in
      let result : Ext_test_lib.cached_result =
        { status; diffs; elapsed_s; timestamp }
      in
      Ext_test_lib.write_cached_result rel_path result;
      let tag =
        match status with
        | "pass" -> "  PASS "
        | "fail" -> "  FAIL "
        | "xfail" -> "  XFAIL"
        | "error" -> "  ERROR"
        | _ -> "  ???? "
      in
      Printf.printf "%s %s (%.1fs)\n%!" tag rel_path elapsed_s;
      result

(* ── Cached result → outcome for reporting ───────────────────────── *)

let cached_to_outcome (r : Ext_test_lib.cached_result) : Ext_test_lib.outcome =
  match r.status with
  | "pass" -> Ext_test_lib.Equivalent
  | "fail" | "xfail" -> Ext_test_lib.Diff r.diffs
  | "error" ->
      Ext_test_lib.Error
        (match r.diffs with d :: _ -> d | [] -> "cached error")
  | "skip" -> Ext_test_lib.Equivalent  (* skips don't count *)
  | _ -> Ext_test_lib.Error "unknown cached status"

(* ── Report mode ─────────────────────────────────────────────────── *)

let report_results all_tests all_expectations =
  let r = ref Ext_test_lib.empty_result in
  let cached = ref 0 in
  let uncached = ref 0 in
  List.iter
    (fun (test : Ext_test_lib.reftest) ->
      let expectation =
        match List.assoc_opt test.rel_path all_expectations with
        | Some e -> e
        | None -> Ext_test_lib.Pass
      in
      match Ext_test_lib.read_cached_result test.rel_path with
      | Some cr ->
          incr cached;
          let outcome = cached_to_outcome cr in
          r :=
            Ext_test_lib.add_result !r ~test_path:test.rel_path ~expectation
              ~outcome
      | None -> incr uncached)
    all_tests;
  Printf.printf "=== WPT Reftest Report ===\n";
  Printf.printf "Discovered: %d | Cached: %d | Uncached: %d\n"
    (List.length all_tests) !cached !uncached;
  Printf.printf "%s" (Ext_test_lib.report !r);
  if !r.failed > 0 || !r.errors > 0 then exit 1

(* ── Main execution ──────────────────────────────────────────────── *)

let () =
  let mode = parse_args () in
  Ext_test_lib.ensure_resources ~suite:"wpt";
  let wpt_dir = wpt_dir () in
  let all_expectations =
    Ext_test_lib.load_expectations (expectations_file ())
  in

  (* Handle --rerun / --rerun-group: clear cache entries first *)
  (match mode with
   | Rerun path -> Ext_test_lib.clear_cached_result path
   | Rerun_group group -> Ext_test_lib.clear_cached_group ("css/" ^ group)
   | _ -> ());

  (* Discover tests *)
  let groups =
    match mode with
    | Run_group g | Rerun_group g -> [ "css/" ^ g ]
    | _ -> Ext_test_lib.load_manifest_groups ()
  in
  Printf.printf "Discovering reftests in %d groups...\n%!" (List.length groups);
  let all_tests =
    Ext_test_lib.discover_all_reftests ~wpt_dir ~groups
  in
  Printf.printf "Found %d reftests\n%!" (List.length all_tests);

  (* Report mode: just summarize cached results *)
  if mode = Report then begin
    report_results all_tests all_expectations;
    exit 0
  end;

  (* Partition into cached and uncached *)
  let uncached, n_cached =
    List.fold_left
      (fun (uncached, n_cached) (test : Ext_test_lib.reftest) ->
        match Ext_test_lib.read_cached_result test.rel_path with
        | Some _ -> (uncached, n_cached + 1)
        | None -> (test :: uncached, n_cached))
      ([], 0) all_tests
  in
  let uncached = List.rev uncached in
  Printf.printf "Cached: %d | To run: %d\n%!" n_cached (List.length uncached);

  if uncached = [] then begin
    Printf.printf "All tests cached. Use --report for summary.\n%!";
    report_results all_tests all_expectations;
    exit 0
  end;

  let viewport = (1024, 768) in
  let r = ref Ext_test_lib.empty_result in

  (* Count cached results into the summary *)
  List.iter
    (fun (test : Ext_test_lib.reftest) ->
      match Ext_test_lib.read_cached_result test.rel_path with
      | Some cr ->
          let expectation =
            match List.assoc_opt test.rel_path all_expectations with
            | Some e -> e
            | None -> Ext_test_lib.Pass
          in
          let outcome = cached_to_outcome cr in
          r :=
            Ext_test_lib.add_result !r ~test_path:test.rel_path ~expectation
              ~outcome
      | None -> ())
    all_tests;

  File_server.with_server ~root:wpt_dir (fun port ->
      Cdp_launcher.with_chromium (fun ws_url ->
          let conn = Cdp.connect ws_url in
          Fun.protect
            ~finally:(fun () -> Cdp.close conn)
            (fun () ->
              Printf.printf "\n--- Running %d uncached tests ---\n%!"
                (List.length uncached);
              List.iter
                (fun test ->
                  let expectation =
                    match List.assoc_opt test.Ext_test_lib.rel_path all_expectations with
                    | Some e -> e
                    | None -> Ext_test_lib.Pass
                  in
                  let cr = run_one_test conn ~port ~viewport ~all_expectations test in
                  let outcome = cached_to_outcome cr in
                  r :=
                    Ext_test_lib.add_result !r
                      ~test_path:test.rel_path ~expectation ~outcome)
                uncached)));

  Printf.printf "\n=== Summary ===\n%!";
  Printf.printf "%s%!" (Ext_test_lib.report !r);
  if !r.failed > 0 || !r.errors > 0 then exit 1
