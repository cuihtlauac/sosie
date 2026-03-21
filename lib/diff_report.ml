(** Self-contained HTML diff report with side-by-side screenshots.

    See {!Diff_report} (the .mli) for documentation. *)

open Sosie_shared.Snapshot_types

(* -- Node lookup by path ------------------------------------------------- *)

let node_at_path root path =
  List.fold_left
    (fun node i ->
      if i >= 0 && i < List.length node.children then List.nth node.children i
      else node)
    root path

let bounds_json (r : rect) : Yojson.Safe.t =
  `Assoc [
    ("x", `Float r.x); ("y", `Float r.y);
    ("w", `Float r.w); ("h", `Float r.h);
  ]

(* -- Diff type classification -------------------------------------------- *)

let diff_type_string (d : Compare.diff) =
  match d with
  | Bounds_diff _ -> "bounds"
  | Style_diff _ -> "style"
  | Text_diff _ -> "text"
  | Paint_order_diff _ -> "paint_order"
  | Tag_mismatch _ -> "structural"
  | Extra_node _ -> "structural"
  | Moved_node _ -> "moved"
  | Wrapper_inserted _ -> "structural"
  | Wrapper_removed _ -> "structural"

(* -- Diff to JSON -------------------------------------------------------- *)

let css_value_json (v : css_value) =
  `String (Diff_fmt.css_value_to_string v)

let diff_to_json ~root_a ~root_b (d : Compare.diff) =
  let typ = `String (diff_type_string d) in
  match d with
  | Bounds_diff { path; property; a; b } ->
      let node = node_at_path root_a path in
      `Assoc [
        ("type", typ);
        ("path", `String (Compare.path_to_string root_a path));
        ("property", `String property);
        ("a", `Float a); ("b", `Float b);
        ("bounds", bounds_json node.bounds);
      ]
  | Style_diff { path; property; a; b } ->
      let node = node_at_path root_a path in
      `Assoc [
        ("type", typ);
        ("path", `String (Compare.path_to_string root_a path));
        ("property", `String property);
        ("a", css_value_json a); ("b", css_value_json b);
        ("bounds", bounds_json node.bounds);
      ]
  | Text_diff { path; a; b } ->
      let node = node_at_path root_a path in
      let opt_json = function None -> `Null | Some s -> `String s in
      `Assoc [
        ("type", typ);
        ("path", `String (Compare.path_to_string root_a path));
        ("a", opt_json a); ("b", opt_json b);
        ("bounds", bounds_json node.bounds);
      ]
  | Paint_order_diff { path; a; b } ->
      let node = node_at_path root_a path in
      `Assoc [
        ("type", typ);
        ("path", `String (Compare.path_to_string root_a path));
        ("a", `Int a); ("b", `Int b);
        ("bounds", bounds_json node.bounds);
      ]
  | Tag_mismatch { path; a; b } ->
      let node = node_at_path root_a path in
      `Assoc [
        ("type", typ);
        ("path", `String (Compare.path_to_string root_a path));
        ("tag_a", `String a); ("tag_b", `String b);
        ("bounds", bounds_json node.bounds);
      ]
  | Extra_node { path; side; tag } ->
      let side_str = match side with `Left -> "left" | `Right -> "right" in
      let root = match side with `Left -> root_a | `Right -> root_b in
      let parent_path = match List.rev path with _ :: tl -> List.rev tl | [] -> [] in
      let node = node_at_path root parent_path in
      `Assoc [
        ("type", typ);
        ("path", `String (Compare.path_to_string root path));
        ("side", `String side_str);
        ("tag", `String tag);
        ("bounds", bounds_json node.bounds);
      ]
  | Moved_node { old_path; new_path } ->
      let node_a = node_at_path root_a old_path in
      let node_b = node_at_path root_b new_path in
      `Assoc [
        ("type", typ);
        ("old_path", `String (Compare.path_to_string root_a old_path));
        ("new_path", `String (Compare.path_to_string root_b new_path));
        ("bounds_a", bounds_json node_a.bounds);
        ("bounds_b", bounds_json node_b.bounds);
      ]
  | Wrapper_inserted { path; wrapper_tag } ->
      let node = node_at_path root_b path in
      `Assoc [
        ("type", typ);
        ("path", `String (Compare.path_to_string root_b path));
        ("wrapper_tag", `String wrapper_tag);
        ("bounds", bounds_json node.bounds);
      ]
  | Wrapper_removed { path; wrapper_tag } ->
      let node = node_at_path root_a path in
      `Assoc [
        ("type", typ);
        ("path", `String (Compare.path_to_string root_a path));
        ("wrapper_tag", `String wrapper_tag);
        ("bounds", bounds_json node.bounds);
      ]

let diffs_to_json ~root_a ~root_b diffs =
  let json = `List (List.map (diff_to_json ~root_a ~root_b) diffs) in
  Yojson.Safe.to_string json

(* -- HTML escaping ------------------------------------------------------- *)

let html_escape s =
  let buf = Buffer.create (String.length s) in
  String.iter
    (fun c ->
      match c with
      | '&' -> Buffer.add_string buf "&amp;"
      | '<' -> Buffer.add_string buf "&lt;"
      | '>' -> Buffer.add_string buf "&gt;"
      | '"' -> Buffer.add_string buf "&quot;"
      | '\'' -> Buffer.add_string buf "&#39;"
      | c -> Buffer.add_char buf c)
    s;
  Buffer.contents buf

(* -- Inline JavaScript --------------------------------------------------- *)

let report_js = {|
(function() {
  'use strict';

  const diffs = window.__sosie_diffs;
  const imgA = document.getElementById('screenshot-a');
  const imgB = document.getElementById('screenshot-b');
  const svgA = document.getElementById('overlay-a');
  const svgB = document.getElementById('overlay-b');
  const tooltip = document.getElementById('tooltip');
  const filterForm = document.getElementById('filters');

  const TYPE_COLORS = {
    style: '#e53e3e',
    bounds: '#ed8936',
    structural: '#3182ce',
    moved: '#805ad5',
    text: '#e53e3e',
    paint_order: '#ed8936',
  };

  function getActiveTypes() {
    const checks = filterForm.querySelectorAll('input[type=checkbox]:checked');
    return new Set(Array.from(checks).map(c => c.value));
  }

  function scaleRect(rect, img) {
    const sx = img.clientWidth / img.naturalWidth;
    const sy = img.clientHeight / img.naturalHeight;
    return {
      x: rect.x * sx,
      y: rect.y * sy,
      w: rect.w * sx,
      h: rect.h * sy,
    };
  }

  function createRect(svg, rect, color, diffIdx) {
    const r = document.createElementNS('http://www.w3.org/2000/svg', 'rect');
    r.setAttribute('x', rect.x);
    r.setAttribute('y', rect.y);
    r.setAttribute('width', rect.w);
    r.setAttribute('height', rect.h);
    r.setAttribute('fill', 'none');
    r.setAttribute('stroke', color);
    r.setAttribute('stroke-width', '2');
    r.setAttribute('data-diff-idx', diffIdx);
    r.style.cursor = 'pointer';
    r.addEventListener('click', function(e) {
      showTooltip(e, diffs[diffIdx]);
    });
    svg.appendChild(r);
    return r;
  }

  function showTooltip(e, diff) {
    let html = '<strong>' + diff.type + '</strong><br>';
    if (diff.path) html += 'Path: ' + diff.path + '<br>';
    if (diff.property) html += 'Property: ' + diff.property + '<br>';
    if (diff.a !== undefined && diff.b !== undefined) {
      html += 'A: ' + diff.a + '<br>';
      html += 'B: ' + diff.b + '<br>';
    }
    if (diff.tag_a) html += 'Tag A: ' + diff.tag_a + '<br>';
    if (diff.tag_b) html += 'Tag B: ' + diff.tag_b + '<br>';
    if (diff.side) html += 'Side: ' + diff.side + '<br>';
    if (diff.tag) html += 'Tag: ' + diff.tag + '<br>';
    if (diff.old_path) html += 'From: ' + diff.old_path + '<br>';
    if (diff.new_path) html += 'To: ' + diff.new_path + '<br>';
    if (diff.wrapper_tag) html += 'Wrapper: ' + diff.wrapper_tag + '<br>';
    tooltip.innerHTML = html;
    tooltip.style.left = e.pageX + 10 + 'px';
    tooltip.style.top = e.pageY + 10 + 'px';
    tooltip.style.display = 'block';
  }

  function renderOverlays() {
    svgA.innerHTML = '';
    svgB.innerHTML = '';
    const active = getActiveTypes();

    svgA.setAttribute('width', imgA.clientWidth);
    svgA.setAttribute('height', imgA.clientHeight);
    svgB.setAttribute('width', imgB.clientWidth);
    svgB.setAttribute('height', imgB.clientHeight);

    diffs.forEach(function(diff, idx) {
      if (!active.has(diff.type)) return;
      const color = TYPE_COLORS[diff.type] || '#888';

      if (diff.bounds) {
        const rA = scaleRect(diff.bounds, imgA);
        createRect(svgA, rA, color, idx);
        const rB = scaleRect(diff.bounds, imgB);
        createRect(svgB, rB, color, idx);
      }
      if (diff.bounds_a) {
        const rA = scaleRect(diff.bounds_a, imgA);
        createRect(svgA, rA, color, idx);
      }
      if (diff.bounds_b) {
        const rB = scaleRect(diff.bounds_b, imgB);
        createRect(svgB, rB, color, idx);
      }
    });
  }

  document.addEventListener('click', function(e) {
    if (!e.target.closest('#tooltip') && !e.target.closest('rect')) {
      tooltip.style.display = 'none';
    }
  });

  filterForm.addEventListener('change', renderOverlays);

  imgA.addEventListener('load', renderOverlays);
  imgB.addEventListener('load', renderOverlays);
  window.addEventListener('resize', renderOverlays);

  if (imgA.complete && imgB.complete) renderOverlays();
})();
|}

(* -- Report generation --------------------------------------------------- *)

let generate ~root_a ~root_b ~diffs ~screenshot_a ~screenshot_b =
  let b64_a = Base64.encode_exn screenshot_a in
  let b64_b = Base64.encode_exn screenshot_b in
  let json_str =
    html_escape (diffs_to_json ~root_a ~root_b diffs)
  in
  let diff_count = List.length diffs in
  let type_counts =
    let tbl = Hashtbl.create 8 in
    List.iter
      (fun d ->
        let t = diff_type_string d in
        let n = try Hashtbl.find tbl t with Not_found -> 0 in
        Hashtbl.replace tbl t (n + 1))
      diffs;
    tbl
  in
  let types = ["style"; "bounds"; "structural"; "moved"; "text"; "paint_order"] in
  let filter_checkboxes =
    List.filter_map
      (fun t ->
        let n = try Hashtbl.find type_counts t with Not_found -> 0 in
        if n > 0 then
          Some (Printf.sprintf
            {|<label><input type="checkbox" value="%s" checked> %s (%d)</label>|}
            t t n)
        else None)
      types
  in
  Printf.sprintf
    {|<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>sosie diff report — %d diff%s</title>
<style>
  * { margin: 0; padding: 0; box-sizing: border-box; }
  body { font-family: system-ui, sans-serif; background: #1a1a2e; color: #eee; }
  h1 { padding: 16px 24px; font-size: 20px; background: #16213e; }
  .panels { display: flex; gap: 8px; padding: 8px; }
  .panel { flex: 1; position: relative; }
  .panel img { width: 100%%; display: block; }
  .panel svg { position: absolute; top: 0; left: 0; pointer-events: none; }
  .panel svg rect { pointer-events: all; }
  .panel h2 { text-align: center; font-size: 14px; padding: 4px; background: #0f3460; }
  #filters { padding: 8px 24px; display: flex; gap: 16px; flex-wrap: wrap; }
  #filters label { cursor: pointer; font-size: 14px; }
  #tooltip {
    display: none; position: absolute; z-index: 100;
    background: #16213e; border: 1px solid #0f3460; border-radius: 4px;
    padding: 8px 12px; font-size: 13px; line-height: 1.5;
    max-width: 400px; word-break: break-all;
  }
  .summary { padding: 8px 24px; font-size: 14px; color: #aaa; }
</style>
</head>
<body>
<h1>sosie diff report</h1>
<div class="summary">%d diff%s found</div>
<form id="filters">%s</form>
<div class="panels">
  <div class="panel">
    <h2>Baseline (A)</h2>
    <img id="screenshot-a" src="data:image/png;base64,%s" alt="Baseline screenshot">
    <svg id="overlay-a"></svg>
  </div>
  <div class="panel">
    <h2>Modified (B)</h2>
    <img id="screenshot-b" src="data:image/png;base64,%s" alt="Modified screenshot">
    <svg id="overlay-b"></svg>
  </div>
</div>
<div id="tooltip"></div>
<script type="application/json" id="diff-data">%s</script>
<script>
window.__sosie_diffs = JSON.parse(document.getElementById('diff-data').textContent);
%s
</script>
</body>
</html>|}
    diff_count (if diff_count = 1 then "" else "s")
    diff_count (if diff_count = 1 then "" else "s")
    (String.concat "\n" filter_checkboxes)
    b64_a b64_b
    json_str report_js
