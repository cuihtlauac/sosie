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

(* Reftest links are parsed in two steps: find each <link> tag, then pull
   its rel and href attributes out of the tag. This handles what a single
   regex cannot: either attribute order, quoted or unquoted values, and
   rel token lists ("match stylesheet"). Attribute names and the rel value
   are case-insensitive per HTML; the href is taken verbatim. *)

(* A tag span ends at the next '<' or '>' rather than requiring a closing
   '>': WPT sources contain malformed link tags with a missing '>', and a
   greedy [^>]* would swallow the following (well-formed) match link. *)
let link_tag_re = Re.compile (Re.Pcre.re ~flags:[ `CASELESS ] {|<link\s[^<>]*|})

(* Value alternatives: group 2 = double-quoted, 3 = single-quoted, 4 = bare
   (any run of non-whitespace; hrefs routinely contain '/').
   The leading \s anchors the attribute name so e.g. norel= cannot match. *)
let attr_re name =
  Re.compile
    (Re.Pcre.re ~flags:[ `CASELESS ]
       (Printf.sprintf {|\s%s\s*=\s*("([^"]*)"|'([^']*)'|([^\s>]+))|} name))

let rel_attr_re = attr_re "rel"
let href_attr_re = attr_re "href"

let get_attr re tag =
  match Re.exec_opt re tag with
  | None -> None
  | Some g ->
      let pick i = if Re.Group.test g i then Some (Re.Group.get g i) else None in
      (match pick 2 with
      | Some _ as v -> v
      | None -> ( match pick 3 with Some _ as v -> v | None -> pick 4))

let rel_has_token tag token =
  match get_attr rel_attr_re tag with
  | None -> false
  | Some rel ->
      String.lowercase_ascii rel
      |> String.map (function '\t' | '\n' | '\r' -> ' ' | c -> c)
      |> String.split_on_char ' '
      |> List.mem token

let parse_links_with_rel token html =
  let hrefs =
    Re.all link_tag_re html
    |> List.filter_map (fun g ->
           let tag = Re.Group.get g 0 in
           if rel_has_token tag token then
             match get_attr href_attr_re tag with
             | Some href when href <> "" -> Some href
             | _ -> None
           else None)
  in
  (* Dedupe, preserving document order (duplicates would just be compared
     twice). *)
  List.fold_left
    (fun acc href -> if List.mem href acc then acc else href :: acc)
    [] hrefs
  |> List.rev

let parse_reftest_links = parse_links_with_rel "match"
let parse_mismatch_links = parse_links_with_rel "mismatch"

(* ── Determinism filter ──────────────────────────────────────────── *)

let nondeterministic_re =
  Re.compile
    (Re.Pcre.re {|@keyframes|animation\s*:|transition\s*:|transition-|})

let is_deterministic_test html = not (Re.execp nondeterministic_re html)

(* ── File I/O helpers ────────────────────────────────────────────── *)

let read_file path =
  let ic = open_in path in
  Fun.protect
    ~finally:(fun () -> close_in_noerr ic)
    (fun () ->
      let len = in_channel_length ic in
      let buf = Bytes.create len in
      really_input ic buf 0 len;
      Bytes.to_string buf)

(* ── Reftest discovery ───────────────────────────────────────────── *)

type reftest_kind = Match | Mismatch

type reftest = {
  rel_path : string;
  kind : reftest_kind;
  ref_hrefs : string list;
}

let rec walk_dir root prefix acc =
  let dir = Filename.concat root prefix in
  if not (Sys.file_exists dir && Sys.is_directory dir) then acc
  else
    let entries = Sys.readdir dir in
    Array.fold_left
      (fun acc entry ->
        let rel = if prefix = "" then entry else Filename.concat prefix entry in
        let full = Filename.concat root rel in
        if Sys.is_directory full then walk_dir root rel acc
        else acc_if_reftest root rel full acc)
      acc entries

and acc_if_reftest wpt_dir rel_path full_path acc =
  let is_html =
    Filename.check_suffix rel_path ".html"
    || Filename.check_suffix rel_path ".xhtml"
    || Filename.check_suffix rel_path ".xht"
  in
  if not is_html then acc
  else
    (* Skip files in reference/ or support/ subdirectories *)
    let parts = String.split_on_char '/' rel_path in
    let in_support =
      List.exists (fun p -> p = "reference" || p = "support") parts
    in
    if in_support then acc
    else
      let ref_exists ref_href =
        let ref_file =
          if String.length ref_href > 0 && ref_href.[0] = '/' then
            Filename.concat wpt_dir (String.sub ref_href 1 (String.length ref_href - 1))
          else
            Filename.concat (Filename.dirname full_path) ref_href
        in
        Sys.file_exists ref_file
      in
      (* Keep every reference that exists on disk; the runner tries them in
         order. A test whose references are all absent cannot be run and is
         skipped. *)
      match reftest_links_from_file full_path with
      | None -> acc
      | Some (kind, hrefs) -> (
          match List.filter ref_exists hrefs with
          | [] -> acc
          | ref_hrefs -> { rel_path; kind; ref_hrefs } :: acc)

(* A file with any rel=match link is a Match test — its mismatch links, if
   any, are ignored (mixed tests stay match-only for now). Only files whose
   sole reftest links are rel=mismatch become Mismatch tests. *)
and reftest_links_from_file path =
  try
    let html = read_file path in
    if not (is_deterministic_test html) then None
    else
      match parse_reftest_links html with
      | _ :: _ as hrefs -> Some (Match, hrefs)
      | [] -> (
          match parse_mismatch_links html with
          | [] -> None
          | hrefs -> Some (Mismatch, hrefs))
  with _ -> None

let discover_reftests ~wpt_dir ~group =
  let tests = walk_dir wpt_dir group [] in
  List.sort (fun a b -> String.compare a.rel_path b.rel_path) tests

let discover_all_reftests ~wpt_dir ~groups =
  List.concat_map (fun group -> discover_reftests ~wpt_dir ~group) groups

(* ── Manifest groups loading ─────────────────────────────────────── *)

let load_manifest_groups () =
  let manifest = Filename.concat (Lazy.force external_dir) "manifest.json" in
  let json = Yojson.Safe.from_file manifest in
  match json with
  | `Assoc top -> (
      match List.assoc_opt "wpt" top with
      | Some (`Assoc fields) -> (
          match List.assoc_opt "groups" fields with
          | Some (`List items) ->
              List.filter_map (function `String s -> Some s | _ -> None) items
          | _ -> [])
      | _ -> [])
  | _ -> []

(* ── Result cache ────────────────────────────────────────────────── *)

type cached_result = {
  status : string;
  diffs : string list;
  elapsed_s : float;
  timestamp : string;
}

(* The verdict inversion for mismatch tests lives here, in outcome space:
   a Mismatch test passes when sosie reports a Diff (it sees the difference
   WPT asserts) and fails when it reports Equivalent — a false negative.
   The cached status is already in verdict space, so report mode needs no
   kind awareness. The "sensitivity:" prefix is recognized by
   wpt_classify.py bulk-xfail when deriving xfail reasons. *)
let cache_status ~kind ~expectation outcome =
  let verdict =
    match (kind, outcome) with
    | _, Error msg -> `Error msg
    | Match, Equivalent -> `Pass []
    | Match, Diff descs -> `Fail descs
    | Mismatch, Diff descs -> `Pass descs
    | Mismatch, Equivalent ->
        `Fail
          [
            "sensitivity: mismatch pair rendered equivalent under the \
             comparison whitelist (false negative)";
          ]
  in
  match (expectation, verdict) with
  | (Pass | Skip _), `Pass diffs -> ("pass", diffs)
  | (Pass | Skip _), `Fail diffs -> ("fail", diffs)
  | (Pass | Skip _), `Error msg -> ("error", [ msg ])
  | Xfail _, `Fail diffs -> ("xfail", diffs)
  | Xfail _, `Error msg -> ("xfail", [ msg ])
  | Xfail _, `Pass diffs -> ("pass", diffs) (* unexpected pass — stale xfail *)

let results_dir () =
  Filename.concat (Lazy.force external_dir) "wpt-results"

let result_path rel_path =
  Filename.concat (results_dir ()) (rel_path ^ ".json")

let mkdir_p path =
  let rec ensure dir =
    if Sys.file_exists dir then ()
    else begin
      ensure (Filename.dirname dir);
      (try Unix.mkdir dir 0o755 with Unix.Unix_error (Unix.EEXIST, _, _) -> ())
    end
  in
  ensure path

let read_cached_result rel_path =
  let path = result_path rel_path in
  if not (Sys.file_exists path) then None
  else
    try
      let json = Yojson.Safe.from_file path in
      match json with
      | `Assoc fields ->
          let status =
            match List.assoc_opt "status" fields with
            | Some (`String s) -> s
            | _ -> "error"
          in
          let diffs =
            match List.assoc_opt "diffs" fields with
            | Some (`List items) ->
                List.filter_map
                  (function `String s -> Some s | _ -> None)
                  items
            | _ -> []
          in
          let elapsed_s =
            match List.assoc_opt "elapsed_s" fields with
            | Some (`Float f) -> f
            | Some (`Int i) -> Float.of_int i
            | _ -> 0.0
          in
          let timestamp =
            match List.assoc_opt "timestamp" fields with
            | Some (`String s) -> s
            | _ -> ""
          in
          Some { status; diffs; elapsed_s; timestamp }
      | _ -> None
    with _ -> None

let iso8601_now () =
  let t = Unix.gettimeofday () in
  let tm = Unix.gmtime t in
  Printf.sprintf "%04d-%02d-%02dT%02d:%02d:%02dZ" (1900 + tm.Unix.tm_year)
    (tm.Unix.tm_mon + 1) tm.Unix.tm_mday tm.Unix.tm_hour tm.Unix.tm_min
    tm.Unix.tm_sec

let write_cached_result rel_path result =
  let path = result_path rel_path in
  mkdir_p (Filename.dirname path);
  let diffs_json =
    `List (List.map (fun s -> `String s) result.diffs)
  in
  let json =
    `Assoc
      [
        ("status", `String result.status);
        ("diffs", diffs_json);
        ("elapsed_s", `Float result.elapsed_s);
        ("timestamp", `String result.timestamp);
      ]
  in
  let oc = open_out path in
  Fun.protect
    ~finally:(fun () -> close_out_noerr oc)
    (fun () -> output_string oc (Yojson.Safe.pretty_to_string json ^ "\n"))

let clear_cached_result rel_path =
  let path = result_path rel_path in
  if Sys.file_exists path then Sys.remove path

let clear_cached_group group =
  let dir = Filename.concat (results_dir ()) group in
  if Sys.file_exists dir then begin
    let rec rm_rf path =
      if Sys.is_directory path then begin
        Array.iter
          (fun entry -> rm_rf (Filename.concat path entry))
          (Sys.readdir path);
        Unix.rmdir path
      end
      else Sys.remove path
    in
    rm_rf dir
  end

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
