(** CSS Zen Garden test runner.

    Identical HTML, different CSS. Validates the GumTree matcher: structural
    match must be perfect (zero Tag_mismatch / Extra_node), with only Style_diff
    and Bounds_diff differences.

    Each design is compared against the base page. Tests against the live Zen
    Garden URL, producing one test case per design.

    Run with: [test/external/fetch.sh && dune build @external] *)

open Sosie

let extractor_js = Extractor_js_source.source
let base_url = "http://www.csszengarden.com/"
let designs = [ 1; 2; 3; 5; 8 ]

(** Check if a diff is structural (tag mismatch or extra node). *)
let is_structural_diff = function
  | Compare.Tag_mismatch _ | Compare.Extra_node _ -> true
  | _ -> false

let normalize =
  [
    Normalize.Round_bounds 1.0;
    Normalize.Canonicalize_colors;
    Normalize.Canonicalize_fonts;
    Normalize.Sort_attributes;
  ]

(** Compare one design against the base page. *)
let test_design ~conn ~viewport ~config design_id () =
  let design_url =
    Printf.sprintf "http://www.csszengarden.com/?cssfile=/designs/%d/%d.css"
      design_id design_id
  in

  let json_base =
    Capture.capture conn ~extractor_js ~url:base_url ~viewport ()
  in
  let snap_base = Snapshot.of_json json_base in

  let json_design =
    Capture.capture conn ~extractor_js ~url:design_url ~viewport ()
  in
  let snap_design = Snapshot.of_json json_design in

  let snap_base' = Normalize.apply normalize snap_base in
  let snap_design' = Normalize.apply normalize snap_design in
  let diffs = Compare.compare_matched config snap_base' snap_design' in

  let structural_diffs = List.filter is_structural_diff diffs in
  let style_diffs =
    List.filter
      (function
        | Compare.Style_diff _ | Compare.Bounds_diff _ -> true | _ -> false)
      diffs
  in

  Printf.printf
    "  design %d: %d total diffs, %d structural, %d style/bounds\n%!" design_id
    (List.length diffs)
    (List.length structural_diffs)
    (List.length style_diffs);

  Alcotest.(check bool)
    (Printf.sprintf "design %d: zero structural diffs" design_id)
    true
    (List.length structural_diffs = 0);

  Alcotest.(check bool)
    (Printf.sprintf "design %d: style/bounds diffs present" design_id)
    true
    (List.length style_diffs > 0)

let () =
  let viewport = (1024, 768) in
  let config = Compare.default_config in
  Cdp_launcher.with_chromium (fun ws_url ->
      let conn = Cdp.connect ws_url in
      Fun.protect
        ~finally:(fun () -> Cdp.close conn)
        (fun () ->
          let cases =
            List.map
              (fun id ->
                Alcotest.test_case
                  (Printf.sprintf "design_%d_structure_identical" id)
                  `Slow
                  (test_design ~conn ~viewport ~config id))
              designs
          in
          Alcotest.run "zen-garden" [ ("zen_garden", cases) ]))
