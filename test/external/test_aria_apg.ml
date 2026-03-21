(** ARIA APG test runner.

    Semantic DOM changes (aria attributes, roles) that shouldn't affect visual
    layout. Validates normalization rules: after dropping ARIA attributes,
    before and after must be equivalent.

    Uses self-contained HTML fixtures served locally. Each fixture exercises a
    different ARIA pattern, producing one test case per fixture.

    Run with: [test/external/fetch.sh && dune build @external] *)

open Sosie

let extractor_js = Extractor_js_source.source

let normalize =
  [
    Normalize.Drop_attributes [ Prefix "aria-"; Exact "role" ];
    Normalize.Round_bounds 1.0;
    Normalize.Canonicalize_colors;
    Normalize.Sort_attributes;
  ]

(** Self-contained HTML fixtures with ARIA roles. *)
let fixtures =
  [
    ( "button",
      {|<!DOCTYPE html>
<html><head><style>
  .btn { padding: 8px 16px; background: #2196f3; color: white;
         border: none; border-radius: 4px; font-size: 14px; cursor: pointer; }
</style></head><body>
  <div role="toolbar" aria-label="Formatting">
    <button class="btn" role="button" aria-pressed="false">Bold</button>
    <button class="btn" role="button" aria-pressed="false">Italic</button>
    <button class="btn" role="button" aria-pressed="true">Underline</button>
  </div>
</body></html>|}
    );
    ( "checkbox",
      {|<!DOCTYPE html>
<html><head><style>
  .cb { display: flex; align-items: center; gap: 8px; margin: 8px; }
  .box { width: 16px; height: 16px; border: 2px solid #333; }
  .box.checked { background: #4caf50; }
</style></head><body>
  <div role="group" aria-labelledby="title">
    <h2 id="title">Options</h2>
    <div class="cb"><div class="box" role="checkbox" aria-checked="false"></div><span>Option A</span></div>
    <div class="cb"><div class="box checked" role="checkbox" aria-checked="true"></div><span>Option B</span></div>
    <div class="cb"><div class="box" role="checkbox" aria-checked="false"></div><span>Option C</span></div>
  </div>
</body></html>|}
    );
    ( "tabs",
      {|<!DOCTYPE html>
<html><head><style>
  .tablist { display: flex; border-bottom: 2px solid #ccc; }
  .tab { padding: 8px 16px; cursor: pointer; border: 1px solid transparent; }
  .tab.active { border-color: #ccc; border-bottom-color: white; margin-bottom: -2px; }
  .panel { padding: 16px; border: 1px solid #ccc; border-top: none; }
</style></head><body>
  <div role="tablist" aria-label="Sections">
    <div class="tab active" role="tab" aria-selected="true" aria-controls="p1">Tab 1</div>
    <div class="tab" role="tab" aria-selected="false" aria-controls="p2">Tab 2</div>
    <div class="tab" role="tab" aria-selected="false" aria-controls="p3">Tab 3</div>
  </div>
  <div class="panel" id="p1" role="tabpanel">Content for tab 1.</div>
</body></html>|}
    );
    ( "navigation",
      {|<!DOCTYPE html>
<html><head><style>
  nav { background: #333; padding: 8px; }
  nav a { color: white; text-decoration: none; padding: 8px 12px; }
  nav a[aria-current] { font-weight: bold; text-decoration: underline; }
</style></head><body>
  <nav role="navigation" aria-label="Main">
    <a href="#" aria-current="page">Home</a>
    <a href="#">About</a>
    <a href="#">Contact</a>
  </nav>
  <main role="main"><p>Page content here.</p></main>
</body></html>|}
    );
  ]

(** Write all fixtures to a temp directory and return the path. *)
let write_fixtures () =
  let dir = Filename.temp_dir "sosie-aria" "" in
  List.iter
    (fun (name, html) ->
      let path = Filename.concat dir (name ^ ".html") in
      let oc = open_out path in
      output_string oc html;
      close_out oc)
    fixtures;
  dir

(** Test one ARIA fixture: capture baseline, inject aria changes, recapture,
    compare with ARIA attributes dropped. *)
let test_fixture ~conn ~port ~viewport ~config (name, _html) () =
  let url = Printf.sprintf "http://127.0.0.1:%d/%s.html" port name in

  let json1 = Capture.capture conn ~extractor_js ~url ~viewport () in
  let snap1 = Snapshot.of_json json1 in

  (* Inject aria attribute changes via JS *)
  let _inject =
    Cdp.evaluate_js conn
      {|
      (function() {
        var els = document.querySelectorAll('[role]');
        els.forEach(function(el) {
          el.setAttribute('aria-expanded', 'true');
          el.setAttribute('aria-label', 'modified');
        });
        return els.length;
      })()
      |}
  in

  (* Recapture after modification *)
  let json2 = Capture.extract conn ~extractor_js in
  let snap2 = Snapshot.of_json json2 in

  let outcome = Ext_test_lib.compare_pair ~normalize config snap1 snap2 in

  match outcome with
  | Ext_test_lib.Equivalent ->
      Printf.printf "  PASS: %s — equivalent after normalization\n%!" name
  | Ext_test_lib.Diff descs ->
      Alcotest.fail
        (Printf.sprintf "%s: unexpected diffs after normalization: %s" name
           (String.concat "; " descs))
  | Ext_test_lib.Error msg ->
      Alcotest.fail (Printf.sprintf "%s: error: %s" name msg)

let () =
  let fixture_dir = write_fixtures () in
  let viewport = (1024, 768) in
  let config = Compare.default_config in

  Fun.protect
    ~finally:(fun () ->
      (* Clean up temp directory *)
      List.iter
        (fun (name, _) ->
          try Sys.remove (Filename.concat fixture_dir (name ^ ".html"))
          with _ -> ())
        fixtures;
      try Sys.rmdir fixture_dir with _ -> ())
    (fun () ->
      File_server.with_server ~root:fixture_dir (fun port ->
          Cdp_launcher.with_chromium (fun ws_url ->
              let conn = Cdp.connect ws_url in
              Fun.protect
                ~finally:(fun () -> Cdp.close conn)
                (fun () ->
                  let cases =
                    List.map
                      (fun ((name, _) as fixture) ->
                        Alcotest.test_case
                          (Printf.sprintf "%s_aria_invisible" name)
                          `Slow
                          (test_fixture ~conn ~port ~viewport ~config fixture))
                      fixtures
                  in
                  Alcotest.run "aria-apg" [ ("aria_apg", cases) ]))))
