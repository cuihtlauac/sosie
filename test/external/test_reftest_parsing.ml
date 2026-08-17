(* Unit tests for reftest link parsing, the determinism filter, and the
   kind-aware cache-status mapping (mismatch verdict inversion).

   Pure: no filesystem, no network, no browser. Exercises the parsing
   semantics that discovery relies on: quoted/unquoted attribute values,
   either attribute order, rel token lists, case-insensitivity, multiple
   links with order preservation and deduplication. *)

let links = Alcotest.(list string)

let check_links name expected html =
  Alcotest.check links name expected (Ext_test_lib.parse_reftest_links html)

let check_mismatch_links name expected html =
  Alcotest.check links name expected (Ext_test_lib.parse_mismatch_links html)

(* ── Edge cases ──────────────────────────────────────────────────── *)

let empty_input_yields_no_links () = check_links "empty" [] ""

let link_without_rel_is_ignored () =
  check_links "no rel" [] {|<link href="a.html">|}

let link_without_href_is_ignored () =
  check_links "no href" [] {|<link rel="match">|}

let empty_href_is_dropped () =
  check_links "empty href" [] {|<link rel="match" href="">|}

let mismatch_rel_is_not_a_match_link () =
  check_links "mismatch" [] {|<link rel="mismatch" href="a.html">|}

let rel_substring_does_not_match () =
  (* "match" must be a whole token of the rel value *)
  check_links "prefetch" [] {|<link rel="prefetch-match-x" href="a.html">|};
  check_links "norel" [] {|<link norel="match" href="a.html">|}

let stylesheet_link_is_ignored () =
  check_links "stylesheet" [] {|<link rel="stylesheet" href="style.css">|}

(* ── Quoting and attribute-order variants ────────────────────────── *)

let quoted_rel_and_href_parse () =
  check_links "double quotes" [ "a.html" ] {|<link rel="match" href="a.html">|}

let single_quoted_values_parse () =
  check_links "single quotes" [ "a.html" ] {|<link rel='match' href='a.html'>|}

let unquoted_rel_parses () =
  (* The pre-2026-08 regexes required quotes; 181 WPT tests use this form *)
  check_links "unquoted rel" [ "a-ref.html" ]
    {|<link rel=match href="a-ref.html">|}

let unquoted_href_parses () =
  check_links "unquoted href" [ "a-ref.html" ] {|<link rel="match" href=a-ref.html>|}

let fully_unquoted_parses () =
  check_links "fully unquoted" [ "a-ref.html" ] {|<link rel=match href=a-ref.html>|}

let href_before_rel_parses () =
  check_links "href first" [ "a.html" ] {|<link href="a.html" rel="match">|}

let self_closing_tag_parses () =
  check_links "self-closing" [ "a.xht" ] {|<link rel="match" href="a.xht"/>|}

let uppercase_names_and_rel_value_parse () =
  check_links "uppercase" [ "A-Ref.html" ] {|<LINK REL=MATCH HREF=A-Ref.html>|}

let href_case_is_preserved () =
  check_links "href verbatim" [ "Ref.HTML" ] {|<link rel="match" href="Ref.HTML">|}

let rel_token_list_containing_match_parses () =
  check_links "token list" [ "a.html" ]
    {|<link rel="match stylesheet" href="a.html">|}

let extra_attributes_are_tolerated () =
  check_links "extra attrs" [ "a.html" ]
    {|<link type="text/html" rel = "match" class=x href = "a.html" id=y>|}

(* ── Multiple links ──────────────────────────────────────────────── *)

let multiple_links_preserve_document_order () =
  check_links "order" [ "a.html"; "b.html" ]
    {|<link rel="match" href="a.html"><link rel="match" href="b.html">|}

let duplicate_hrefs_are_deduplicated () =
  check_links "dedupe" [ "a.html" ]
    {|<link rel="match" href="a.html"><link rel="match" href="a.html">|}

let mixed_match_and_mismatch_keeps_only_match () =
  check_links "mixed" [ "b.html" ]
    {|<link rel="mismatch" href="a.html"><link rel="match" href="b.html">|}

let links_across_lines_parse () =
  check_links "multiline" [ "a.html"; "b.html" ]
    "<head>\n  <link rel=\"match\" href=\"a.html\">\n  <link rel=match href=b.html>\n</head>"

(* ── Malformed input recovery ────────────────────────────────────── *)

let unclosed_tag_does_not_swallow_next_link () =
  (* Seen in WPT (css-contain): a help link missing its closing '>' directly
     before the match link. The match link must still be found. *)
  check_links "unclosed tag" [ "/css/reference/green.html" ]
    "<link rel=\"help\" href=\"https://example.org/#x\"\n<link rel=\"match\" href=\"/css/reference/green.html\">"

let unquoted_href_with_slashes_is_complete () =
  check_links "bare path" [ "support/a-ref.html" ]
    {|<link rel=match href=support/a-ref.html>|};
  check_links "bare absolute" [ "/css/reference/a-ref.html" ]
    {|<link rel=match href=/css/reference/a-ref.html>|}

(* ── Mismatch links ──────────────────────────────────────────────── *)

let mismatch_of_empty_input_is_empty () = check_mismatch_links "empty" [] ""

let match_rel_is_not_a_mismatch_link () =
  check_mismatch_links "match" [] {|<link rel="match" href="a.html">|}

let mismatch_substring_does_not_match () =
  (* "mismatch" must be a whole token; note "mismatch" contains "match" as a
     substring, so token splitting must not confuse the two *)
  check_mismatch_links "prefixed" [] {|<link rel="x-mismatch-y" href="a.html">|}

let quoted_mismatch_link_parses () =
  check_mismatch_links "quoted" [ "a-notref.html" ]
    {|<link rel="mismatch" href="a-notref.html">|}

let unquoted_mismatch_link_parses () =
  check_mismatch_links "unquoted" [ "a-notref.html" ]
    {|<link rel=mismatch href=a-notref.html>|}

let mismatch_rel_token_list_parses () =
  check_mismatch_links "token list" [ "a.html" ]
    {|<link rel="mismatch stylesheet" href="a.html">|}

let mixed_links_split_by_rel () =
  let html =
    {|<link rel="match" href="same.html"><link rel="mismatch" href="other.html">|}
  in
  check_links "match side" [ "same.html" ] html;
  check_mismatch_links "mismatch side" [ "other.html" ] html

let mismatch_links_preserve_order_and_dedupe () =
  check_mismatch_links "order+dedupe" [ "a.html"; "b.html" ]
    {|<link rel="mismatch" href="a.html"><link rel="mismatch" href="b.html"><link rel="mismatch" href="a.html">|}

(* ── Cache status: verdict mapping and mismatch inversion ────────── *)

let status = Alcotest.(pair string (list string))

let check_status name expected ~kind ~expectation outcome =
  Alcotest.check status name expected
    (Ext_test_lib.cache_status ~kind ~expectation outcome)

let sensitivity_marker (status, diffs) =
  status = "fail"
  && List.exists
       (fun d -> String.length d >= 12 && String.sub d 0 12 = "sensitivity:")
       diffs

let match_equivalent_is_pass () =
  check_status "pass" ("pass", []) ~kind:Ext_test_lib.Match
    ~expectation:Ext_test_lib.Pass Ext_test_lib.Equivalent

let match_diff_is_fail_with_diffs () =
  check_status "fail" ("fail", [ "d1"; "d2" ]) ~kind:Ext_test_lib.Match
    ~expectation:Ext_test_lib.Pass (Ext_test_lib.Diff [ "d1"; "d2" ])

let match_error_is_error () =
  check_status "error" ("error", [ "boom" ]) ~kind:Ext_test_lib.Match
    ~expectation:Ext_test_lib.Pass (Ext_test_lib.Error "boom")

let mismatch_diff_is_pass_keeping_diffs () =
  (* The diffs document WHAT sensitivity caught the asserted difference *)
  check_status "inverted pass" ("pass", [ "d1" ]) ~kind:Ext_test_lib.Mismatch
    ~expectation:Ext_test_lib.Pass (Ext_test_lib.Diff [ "d1" ])

let mismatch_equivalent_is_fail_with_sensitivity_marker () =
  (* The fatal case: sosie is blind to a difference WPT asserts *)
  let result =
    Ext_test_lib.cache_status ~kind:Ext_test_lib.Mismatch
      ~expectation:Ext_test_lib.Pass Ext_test_lib.Equivalent
  in
  Alcotest.(check bool) "fail with sensitivity: diff" true
    (sensitivity_marker result)

let mismatch_error_is_error () =
  check_status "error" ("error", [ "boom" ]) ~kind:Ext_test_lib.Mismatch
    ~expectation:Ext_test_lib.Pass (Ext_test_lib.Error "boom")

let xfail_downgrades_fail_to_xfail_for_both_kinds () =
  let xfail = Ext_test_lib.Xfail "known gap" in
  check_status "match xfail" ("xfail", [ "d" ]) ~kind:Ext_test_lib.Match
    ~expectation:xfail (Ext_test_lib.Diff [ "d" ]);
  let st, diffs =
    Ext_test_lib.cache_status ~kind:Ext_test_lib.Mismatch ~expectation:xfail
      Ext_test_lib.Equivalent
  in
  Alcotest.(check string) "mismatch xfail" "xfail" st;
  Alcotest.(check bool) "keeps sensitivity marker" true
    (List.exists
       (fun d -> String.length d >= 12 && String.sub d 0 12 = "sensitivity:")
       diffs)

let xfail_downgrades_error_to_xfail () =
  check_status "match" ("xfail", [ "boom" ]) ~kind:Ext_test_lib.Match
    ~expectation:(Ext_test_lib.Xfail "r") (Ext_test_lib.Error "boom");
  check_status "mismatch" ("xfail", [ "boom" ]) ~kind:Ext_test_lib.Mismatch
    ~expectation:(Ext_test_lib.Xfail "r") (Ext_test_lib.Error "boom")

let stale_xfail_surfaces_as_pass_for_both_kinds () =
  check_status "match stale" ("pass", []) ~kind:Ext_test_lib.Match
    ~expectation:(Ext_test_lib.Xfail "stale") Ext_test_lib.Equivalent;
  check_status "mismatch stale" ("pass", [ "d" ]) ~kind:Ext_test_lib.Mismatch
    ~expectation:(Ext_test_lib.Xfail "stale") (Ext_test_lib.Diff [ "d" ])

let skip_expectation_maps_like_pass () =
  (* The runner returns early on Skip; cache_status treats it as Pass *)
  check_status "skip" ("fail", [ "d" ]) ~kind:Ext_test_lib.Match
    ~expectation:(Ext_test_lib.Skip "policy") (Ext_test_lib.Diff [ "d" ])

(* ── Determinism filter ──────────────────────────────────────────── *)

let animation_content_is_nondeterministic () =
  Alcotest.(check bool) "keyframes" false
    (Ext_test_lib.is_deterministic_test "@keyframes spin { }");
  Alcotest.(check bool) "animation" false
    (Ext_test_lib.is_deterministic_test "div { animation: spin 1s; }");
  Alcotest.(check bool) "transition" false
    (Ext_test_lib.is_deterministic_test "div { transition: all 1s; }");
  Alcotest.(check bool) "transition-prop" false
    (Ext_test_lib.is_deterministic_test "div { transition-duration: 1s; }")

let static_content_is_deterministic () =
  Alcotest.(check bool) "static" true
    (Ext_test_lib.is_deterministic_test
       {|<link rel="match" href="a.html"><style>div { color: red }</style>|})

let () =
  Alcotest.run "reftest_parsing"
    [
      ( "edge cases",
        [
          Alcotest.test_case "empty input yields no links" `Quick
            empty_input_yields_no_links;
          Alcotest.test_case "link without rel is ignored" `Quick
            link_without_rel_is_ignored;
          Alcotest.test_case "link without href is ignored" `Quick
            link_without_href_is_ignored;
          Alcotest.test_case "empty href is dropped" `Quick empty_href_is_dropped;
          Alcotest.test_case "mismatch rel is not a match link" `Quick
            mismatch_rel_is_not_a_match_link;
          Alcotest.test_case "rel substring does not match" `Quick
            rel_substring_does_not_match;
          Alcotest.test_case "stylesheet link is ignored" `Quick
            stylesheet_link_is_ignored;
        ] );
      ( "quoting and order",
        [
          Alcotest.test_case "quoted rel and href parse" `Quick
            quoted_rel_and_href_parse;
          Alcotest.test_case "single-quoted values parse" `Quick
            single_quoted_values_parse;
          Alcotest.test_case "unquoted rel parses" `Quick unquoted_rel_parses;
          Alcotest.test_case "unquoted href parses" `Quick unquoted_href_parses;
          Alcotest.test_case "fully unquoted parses" `Quick fully_unquoted_parses;
          Alcotest.test_case "href before rel parses" `Quick href_before_rel_parses;
          Alcotest.test_case "self-closing tag parses" `Quick
            self_closing_tag_parses;
          Alcotest.test_case "uppercase names and rel value parse" `Quick
            uppercase_names_and_rel_value_parse;
          Alcotest.test_case "href case is preserved" `Quick href_case_is_preserved;
          Alcotest.test_case "rel token list containing match parses" `Quick
            rel_token_list_containing_match_parses;
          Alcotest.test_case "extra attributes are tolerated" `Quick
            extra_attributes_are_tolerated;
        ] );
      ( "multiple links",
        [
          Alcotest.test_case "multiple links preserve document order" `Quick
            multiple_links_preserve_document_order;
          Alcotest.test_case "duplicate hrefs are deduplicated" `Quick
            duplicate_hrefs_are_deduplicated;
          Alcotest.test_case "mixed match and mismatch keeps only match" `Quick
            mixed_match_and_mismatch_keeps_only_match;
          Alcotest.test_case "links across lines parse" `Quick
            links_across_lines_parse;
        ] );
      ( "malformed input",
        [
          Alcotest.test_case "unclosed tag does not swallow next link" `Quick
            unclosed_tag_does_not_swallow_next_link;
          Alcotest.test_case "unquoted href with slashes is complete" `Quick
            unquoted_href_with_slashes_is_complete;
        ] );
      ( "mismatch links",
        [
          Alcotest.test_case "mismatch of empty input is empty" `Quick
            mismatch_of_empty_input_is_empty;
          Alcotest.test_case "match rel is not a mismatch link" `Quick
            match_rel_is_not_a_mismatch_link;
          Alcotest.test_case "mismatch substring does not match" `Quick
            mismatch_substring_does_not_match;
          Alcotest.test_case "quoted mismatch link parses" `Quick
            quoted_mismatch_link_parses;
          Alcotest.test_case "unquoted mismatch link parses" `Quick
            unquoted_mismatch_link_parses;
          Alcotest.test_case "mismatch rel token list parses" `Quick
            mismatch_rel_token_list_parses;
          Alcotest.test_case "mixed links split by rel" `Quick
            mixed_links_split_by_rel;
          Alcotest.test_case "mismatch links preserve order and dedupe" `Quick
            mismatch_links_preserve_order_and_dedupe;
        ] );
      ( "cache status",
        [
          Alcotest.test_case "match equivalent is pass" `Quick
            match_equivalent_is_pass;
          Alcotest.test_case "match diff is fail with diffs" `Quick
            match_diff_is_fail_with_diffs;
          Alcotest.test_case "match error is error" `Quick match_error_is_error;
          Alcotest.test_case "mismatch diff is pass keeping diffs" `Quick
            mismatch_diff_is_pass_keeping_diffs;
          Alcotest.test_case
            "mismatch equivalent is fail with sensitivity marker" `Quick
            mismatch_equivalent_is_fail_with_sensitivity_marker;
          Alcotest.test_case "mismatch error is error" `Quick
            mismatch_error_is_error;
          Alcotest.test_case "xfail downgrades fail to xfail for both kinds"
            `Quick xfail_downgrades_fail_to_xfail_for_both_kinds;
          Alcotest.test_case "xfail downgrades error to xfail" `Quick
            xfail_downgrades_error_to_xfail;
          Alcotest.test_case "stale xfail surfaces as pass for both kinds"
            `Quick stale_xfail_surfaces_as_pass_for_both_kinds;
          Alcotest.test_case "skip expectation maps like pass" `Quick
            skip_expectation_maps_like_pass;
        ] );
      ( "determinism filter",
        [
          Alcotest.test_case "animation content is nondeterministic" `Quick
            animation_content_is_nondeterministic;
          Alcotest.test_case "static content is deterministic" `Quick
            static_content_is_deterministic;
        ] );
    ]
