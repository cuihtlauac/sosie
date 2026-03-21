(** Shared infrastructure for external CSS test suites.

    See {!Ext_test_lib} (the .mli) for the public interface documentation. *)

open Sosie

type outcome = Equivalent | Diff of string list | Error of string
type expectation = Pass | Xfail of string | Skip of string

(* ── Path resolution ──────────────────────────────────────────────
   Dune runs executables from _build/, so we walk up from CWD to find
   the project root (directory containing dune-project), then resolve
   test/external/ relative to it. *)

let find_project_root () =
  let rec walk dir =
    if Sys.file_exists (Filename.concat dir "dune-project") then dir
    else
      let parent = Filename.dirname dir in
      if parent = dir then failwith "cannot find project root (dune-project)"
      else walk parent
  in
  walk (Sys.getcwd ())

let external_dir = lazy (Filename.concat (find_project_root ()) "test/external")

(* ── Resource checking ───────────────────────────────────────────── *)

let ensure_resources ~suite =
  let dir = Filename.concat (Lazy.force external_dir) suite in
  if not (Sys.file_exists dir) then
    failwith
      (Printf.sprintf
         "External resources for %S not found.\n\
          Run: test/external/fetch.sh\n\
          Expected directory: %s"
         suite dir)

(* ── Manifest loading ─────────────────────────────────────────────── *)

let load_manifest_paths ~suite =
  let manifest = Filename.concat (Lazy.force external_dir) "manifest.json" in
  let json = Yojson.Safe.from_file manifest in
  match json with
  | `Assoc top -> (
      match List.assoc_opt suite top with
      | Some (`Assoc fields) -> (
          match List.assoc_opt "paths" fields with
          | Some (`List items) ->
              List.filter_map (function `String s -> Some s | _ -> None) items
          | _ -> [])
      | _ -> [])
  | _ -> []

(* ── Expectation loading ─────────────────────────────────────────── *)

let load_expectations path =
  if not (Sys.file_exists path) then []
  else
    let json = Yojson.Safe.from_file path in
    match json with
    | `Assoc suites ->
        List.concat_map
          (fun (_suite_name, tests) ->
            match tests with
            | `Assoc entries ->
                List.filter_map
                  (fun (test_path, spec) ->
                    match spec with
                    | `Assoc fields -> (
                        match List.assoc_opt "status" fields with
                        | Some (`String "xfail") ->
                            let reason =
                              match List.assoc_opt "reason" fields with
                              | Some (`String r) -> r
                              | _ -> "unknown"
                            in
                            Some (test_path, Xfail reason)
                        | Some (`String "skip") ->
                            let reason =
                              match List.assoc_opt "reason" fields with
                              | Some (`String r) -> r
                              | _ -> "unknown"
                            in
                            Some (test_path, Skip reason)
                        | _ -> None)
                    | _ -> None)
                  entries
            | _ -> [])
          suites
    | _ -> []

(* ── Reftest parsing ─────────────────────────────────────────────── *)

let reftest_link_re =
  Re.compile
    (Re.Pcre.re
       {|<link\s[^>]*rel\s*=\s*["']match["'][^>]*href\s*=\s*["']([^"']+)["']|})

let reftest_link_re_alt =
  Re.compile
    (Re.Pcre.re
       {|<link\s[^>]*href\s*=\s*["']([^"']+)["'][^>]*rel\s*=\s*["']match["']|})

let parse_reftest_link html =
  match Re.exec_opt reftest_link_re html with
  | Some group -> Some (Re.Group.get group 1)
  | None -> (
      match Re.exec_opt reftest_link_re_alt html with
      | Some group -> Some (Re.Group.get group 1)
      | None -> None)

(* ── Determinism filter ──────────────────────────────────────────── *)

let nondeterministic_re =
  Re.compile
    (Re.Pcre.re {|@keyframes|animation\s*:|transition\s*:|transition-|})

let is_deterministic_test html = not (Re.execp nondeterministic_re html)

(* ── Capture helpers ─────────────────────────────────────────────── *)

let wait_reftest_ready conn =
  let poll_js =
    {|document.documentElement.classList.contains('reftest-wait')|}
  in
  let deadline = Unix.gettimeofday () +. 10.0 in
  let rec loop () =
    let result = Cdp.evaluate_js conn poll_js in
    match result with
    | `Bool false -> ()
    | _ ->
        if Unix.gettimeofday () > deadline then
          failwith "timeout waiting for reftest-wait to be removed"
        else begin
          Unix.sleepf 0.1;
          loop ()
        end
  in
  loop ()

let capture_one conn ~extractor_js ~viewport url =
  let json = Capture.capture conn ~extractor_js ~url ~viewport () in
  Snapshot.of_json json

let capture_pair conn ~extractor_js ~viewport ~test_url ~ref_url =
  try
    let test_snap = capture_one conn ~extractor_js ~viewport test_url in
    wait_reftest_ready conn;
    let ref_snap = capture_one conn ~extractor_js ~viewport ref_url in
    wait_reftest_ready conn;
    Ok (test_snap, ref_snap)
  with exn -> Error (Printexc.to_string exn)

(* ── Comparison ──────────────────────────────────────────────────── *)

let safe_format_diff ~root_b root d =
  try Diff_fmt.format_diff ~root_b root d with _ -> "<unformattable diff>"

let compare_pair
    ?(normalize = [ Normalize.Round_bounds 1.0; Normalize.Canonicalize_colors ])
    ?(matched = false) config a b =
  try
    let a' = Normalize.apply normalize a in
    let b' = Normalize.apply normalize b in
    let diffs =
      if matched then Compare.compare_matched config a' b'
      else Compare.compare config a' b'
    in
    if diffs = [] then Equivalent
    else
      Diff
        (List.map (fun d -> safe_format_diff ~root_b:b'.root a'.root d) diffs)
  with exn -> Error (Printexc.to_string exn)

(* ── Suite results ───────────────────────────────────────────────── *)

type suite_result = {
  total : int;
  passed : int;
  xfailed : int;
  failed : int;
  skipped : int;
  errors : int;
  failures : (string * string) list;
}

let empty_result =
  {
    total = 0;
    passed = 0;
    xfailed = 0;
    failed = 0;
    skipped = 0;
    errors = 0;
    failures = [];
  }

let add_result r ~test_path ~expectation ~outcome =
  let r = { r with total = r.total + 1 } in
  match (expectation, outcome) with
  | Skip _, _ -> { r with skipped = r.skipped + 1 }
  | Pass, Equivalent -> { r with passed = r.passed + 1 }
  | Pass, Diff descs ->
      {
        r with
        failed = r.failed + 1;
        failures =
          ( test_path,
            Printf.sprintf "unexpected diffs: %s"
              (String.concat "; " (List.filteri (fun i _ -> i < 3) descs)) )
          :: r.failures;
      }
  | Pass, Error msg ->
      {
        r with
        errors = r.errors + 1;
        failures = (test_path, Printf.sprintf "error: %s" msg) :: r.failures;
      }
  | Xfail _, Diff _ -> { r with xfailed = r.xfailed + 1 }
  | Xfail _, Error _ -> { r with xfailed = r.xfailed + 1 }
  | Xfail reason, Equivalent ->
      (* Unexpected pass — the xfail annotation is stale *)
      {
        r with
        failed = r.failed + 1;
        failures =
          (test_path, Printf.sprintf "unexpected pass (xfail: %s)" reason)
          :: r.failures;
      }

let report r =
  let lines = Buffer.create 256 in
  Buffer.add_string lines
    (Printf.sprintf
       "Total: %d | Passed: %d | XFailed: %d | Failed: %d | Skipped: %d | \
        Errors: %d\n"
       r.total r.passed r.xfailed r.failed r.skipped r.errors);
  List.iter
    (fun (path, msg) ->
      Buffer.add_string lines (Printf.sprintf "  FAIL: %s — %s\n" path msg))
    (List.rev r.failures);
  Buffer.contents lines
