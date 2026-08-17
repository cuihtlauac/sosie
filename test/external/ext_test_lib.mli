(** Shared infrastructure for external CSS test suites.

    Provides resource checking, expectation loading, reftest parsing,
    determinism filtering, capture/compare helpers, reftest discovery, and
    filesystem-based result caching for use by the individual test runners
    (WPT, Acid3, Zen Garden, ARIA APG). *)

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

val parse_reftest_links : string -> string list
(** [parse_reftest_links html] extracts the [href] of every
    [<link rel="match">] in the HTML string, in document order, deduplicated.
    Attribute names and the [rel] value are matched case-insensitively;
    values may be double-quoted, single-quoted, or bare; [rel] may be a
    token list (e.g. ["match stylesheet"]). Empty hrefs are dropped.
    @return the hrefs as written in the HTML, [[]] if none. *)

val parse_mismatch_links : string -> string list
(** [parse_mismatch_links html] extracts the [href] of every
    [<link rel="mismatch">], with the same lexical tolerance as
    {!parse_reftest_links}. A mismatch reference asserts the test must
    render DIFFERENTLY from it. *)

val is_deterministic_test : string -> bool
(** [is_deterministic_test html] returns [true] if the HTML content does not
    contain [\@keyframes], [animation:], or [transition:] properties that would
    make rendering non-deterministic. Scripts are allowed. *)

val read_file : string -> string
(** [read_file path] reads the entire file at [path] into a string.
    @raise Sys_error if the file cannot be read. *)

(** {1 Reftest discovery} *)

type reftest_kind =
  | Match  (** Test must render the SAME as some reference. *)
  | Mismatch
      (** Test must render DIFFERENTLY from every reference. An
          [Equivalent] verdict on any reference is a false negative —
          a measured sensitivity gap in the comparison whitelist. *)

type reftest = {
  rel_path : string;
      (** Path relative to wpt_dir, e.g. "css/css-color/a98rgb-001.html" *)
  kind : reftest_kind;
  ref_hrefs : string list;
      (** The hrefs from every reftest link of [kind] whose target exists on
          disk, in document order. Never empty. WPT semantics: a Match test
          passes if it matches ANY reference; a Mismatch test passes if it
          differs from EVERY reference. *)
}
(** A discovered reftest: a test file paired with its candidate references. *)

val discover_reftests : wpt_dir:string -> group:string -> reftest list
(** [discover_reftests ~wpt_dir ~group] walks [wpt_dir/group] and returns all
    valid reftests: files with a reftest link, deterministic content, and at
    least one existing reference file. Results are sorted by path.

    A file with any [<link rel="match">] is a [Match] test (its mismatch
    links, if any, are ignored for now — mixed tests are compared against
    their match references only). A file with only [<link rel="mismatch">]
    links is a [Mismatch] test. *)

val discover_all_reftests : wpt_dir:string -> groups:string list -> reftest list
(** [discover_all_reftests ~wpt_dir ~groups] discovers reftests across all
    groups. Equivalent to concatenating {!discover_reftests} for each group. *)

val load_manifest_groups : unit -> string list
(** [load_manifest_groups ()] reads the [groups] array from the [wpt] section
    of [manifest.json].
    @return list of group paths (e.g., ["css/css-color"; "css/css-flexbox"]) *)

(** {1 Result cache}

    Per-test result files stored in [test/external/wpt-results/]. Each test
    gets a JSON file recording its last execution status. Cache is keyed to
    the WPT commit: [fetch.sh] wipes results when the commit changes. *)

type cached_result = {
  status : string;      (** "pass", "fail", "xfail", "skip", or "error" *)
  diffs : string list;  (** Diff descriptions, empty for match-test passes *)
  elapsed_s : float;    (** Wall-clock time for this test *)
  timestamp : string;   (** ISO 8601 UTC timestamp *)
}

val cache_status :
  kind:reftest_kind ->
  expectation:expectation ->
  outcome ->
  string * string list
(** [cache_status ~kind ~expectation outcome] maps a comparison outcome to
    the cached (status, diffs) pair, inverting the verdict for [Mismatch]
    tests: [Diff] means sosie sees the difference WPT asserts (pass, diffs
    kept as documentation of what was detected), [Equivalent] means a false
    negative (fail, with a ["sensitivity: ..."] marker diff that downstream
    triage recognizes). [Xfail] turns fail/error into "xfail"; an expected
    failure that passes yields "pass" (stale xfail, reported as unexpected
    pass). [Skip] is handled by the runner before comparison and is treated
    like [Pass] here. *)

val iso8601_now : unit -> string
(** Current time as an ISO 8601 UTC string (e.g., "2026-03-21T10:00:00Z"). *)

val results_dir : unit -> string
(** Path to the [wpt-results/] directory. *)

val read_cached_result : string -> cached_result option
(** [read_cached_result rel_path] reads the cached result for a test.
    @return [None] if no cache entry exists or is malformed. *)

val write_cached_result : string -> cached_result -> unit
(** [write_cached_result rel_path result] writes a result file, creating
    parent directories as needed. *)

val clear_cached_result : string -> unit
(** [clear_cached_result rel_path] removes the cache entry for a single test. *)

val clear_cached_group : string -> unit
(** [clear_cached_group group] removes all cache entries under a group
    directory (e.g., "css/css-flexbox"). *)

(** {1 Suite results} *)

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
