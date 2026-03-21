(** Shared infrastructure for external CSS test suites.

    Provides resource checking, expectation loading, reftest parsing,
    determinism filtering, and capture/compare helpers for use by the individual
    test runners (WPT, Acid3, Zen Garden, ARIA APG). *)

type outcome =
  | Equivalent
  | Diff of string list
  | Error of string  (** Result of comparing a pair of snapshots. *)

type expectation =
  | Pass
  | Xfail of string
  | Skip of string  (** Expected outcome for a test case. *)

val external_dir : string Lazy.t
(** Path to the [test/external/] directory, resolved by walking up from CWD to
    find the project root (directory containing [dune-project]). *)

val ensure_resources : suite:string -> unit
(** Check that downloaded resources exist for the given suite.
    @raise Failure with instructions if resources are missing. *)

val load_manifest_paths : suite:string -> string list
(** [load_manifest_paths ~suite] reads the curated test paths from
    [manifest.json] for the given suite.
    @return list of relative paths (e.g., ["css/css-color/color-001.html"]) *)

val load_expectations : string -> (string * expectation) list
(** [load_expectations path] reads an expectations JSON file and returns a list
    of [(test_path, expectation)] pairs for a given suite.
    @param path path to the expectations.json file
    @return association list of test path to expectation *)

val capture_pair :
  Sosie.Cdp.connection ->
  extractor_js:string ->
  viewport:int * int ->
  test_url:string ->
  ref_url:string ->
  (Sosie.Snapshot.t * Sosie.Snapshot.t, string) result
(** [capture_pair conn ~extractor_js ~viewport ~test_url ~ref_url] captures
    snapshots of both URLs and returns them as a pair.
    @return [Ok (test_snap, ref_snap)] on success, [Error msg] on failure *)

val wait_reftest_ready : Sosie.Cdp.connection -> unit
(** Poll until the html element no longer has [class="reftest-wait"]. Returns
    immediately if the class is absent. Timeout: 10 seconds.
    @raise Failure on timeout. *)

val compare_pair :
  ?normalize:Sosie.Normalize.rule list ->
  ?matched:bool ->
  Sosie.Compare.config ->
  Sosie.Snapshot.t ->
  Sosie.Snapshot.t ->
  outcome
(** [compare_pair ?normalize ?matched config a b] normalizes and compares two
    snapshots. When [matched] is [true], uses GumTree-matched comparison to
    tolerate structural differences. Returns {!Equivalent} if no diffs are
    found, [Diff descriptions] otherwise. Default: [matched = false]. *)

val parse_reftest_link : string -> string option
(** [parse_reftest_link html] extracts the [href] from the first
    [<link rel="match" href="...">] in the HTML string.
    @return [Some href] or [None] if no reftest link is found. *)

val is_deterministic_test : string -> bool
(** [is_deterministic_test html] returns [true] if the HTML content does not
    contain [\@keyframes], [animation:], or [transition:] properties that would
    make rendering non-deterministic. Scripts are allowed. *)

type suite_result = {
  total : int;
  passed : int;
  xfailed : int;
  failed : int;
  skipped : int;
  errors : int;
  failures : (string * string) list;
}
(** Aggregate results from running a test suite. *)

val empty_result : suite_result
(** All counts zero, empty failures list. *)

val add_result :
  suite_result ->
  test_path:string ->
  expectation:expectation ->
  outcome:outcome ->
  suite_result
(** Update suite results with one test's outcome vs. its expectation. *)

val report : suite_result -> string
(** Format suite results as a human-readable summary. *)
