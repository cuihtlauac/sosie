(** Visual normalization config overlay in a headed browser.

    See {!Show_config} (the .mli) for documentation. *)

let selector_to_css (sel : Normalize.simple_selector) =
  match sel with
  | Tag name -> String.lowercase_ascii name
  | Id id -> "#" ^ id
  | Class cls -> "." ^ cls
  | Universal -> "*"

let js_string_escape s =
  let buf = Buffer.create (String.length s + 8) in
  String.iter
    (fun c ->
      match c with
      | '\\' -> Buffer.add_string buf "\\\\"
      | '\'' -> Buffer.add_string buf "\\'"
      | '\n' -> Buffer.add_string buf "\\n"
      | '\r' -> Buffer.add_string buf "\\r"
      | c -> Buffer.add_char buf c)
    s;
  Buffer.contents buf

let overlay_js rules =
  let buf = Buffer.create 2048 in
  Buffer.add_string buf {|(function() {
  'use strict';

  /* Legend */
  const legend = document.createElement('div');
  legend.style.cssText = 'position:fixed;top:8px;right:8px;z-index:999999;' +
    'background:rgba(0,0,0,0.85);color:#fff;padding:12px 16px;border-radius:6px;' +
    'font:13px/1.6 system-ui,sans-serif;max-width:320px;pointer-events:none;';
  legend.innerHTML = '<strong>sosie config overlay</strong><br>';
  const items = [];
|};
  List.iter
    (fun (rule : Normalize.rule) ->
      match rule with
      | Mask_text { selector; replacement } ->
          let css_sel = js_string_escape (selector_to_css selector) in
          let repl = js_string_escape replacement in
          Buffer.add_string buf
            (Printf.sprintf
               {|
  document.querySelectorAll('%s').forEach(function(el) {
    el.style.outline = '2px solid #ecc94b';
    el.style.outlineOffset = '-2px';
    el.style.backgroundColor = 'rgba(236,201,75,0.15)';
    const badge = document.createElement('span');
    badge.textContent = '%s';
    badge.style.cssText = 'position:absolute;top:0;left:0;background:#ecc94b;' +
      'color:#000;font:10px/1 monospace;padding:1px 4px;z-index:999998;';
    el.style.position = el.style.position || 'relative';
    el.appendChild(badge);
  });
  items.push('<span style="color:#ecc94b">■</span> Mask_text: %s → "%s"');
|}
               css_sel repl css_sel repl)
      | Drop_subtree selector ->
          let css_sel = js_string_escape (selector_to_css selector) in
          Buffer.add_string buf
            (Printf.sprintf
               {|
  document.querySelectorAll('%s').forEach(function(el) {
    el.style.outline = '3px solid #e53e3e';
    el.style.outlineOffset = '-3px';
    el.style.backgroundColor = 'rgba(229,62,62,0.2)';
    const label = document.createElement('div');
    label.textContent = 'IGNORED';
    label.style.cssText = 'position:absolute;top:50%%;left:50%%;transform:translate(-50%%,-50%%);' +
      'background:#e53e3e;color:#fff;font:bold 14px/1 system-ui;padding:4px 8px;' +
      'border-radius:3px;z-index:999998;pointer-events:none;';
    el.style.position = el.style.position || 'relative';
    el.appendChild(label);
  });
  items.push('<span style="color:#e53e3e">■</span> Drop_subtree: %s');
|}
               css_sel css_sel)
      | Drop_attributes patterns ->
          let pat_strs =
            List.map
              (fun (p : Normalize.attr_pattern) ->
                match p with
                | Exact s -> Printf.sprintf "=%s" s
                | Prefix s -> Printf.sprintf "^%s" s)
              patterns
          in
          let label = js_string_escape (String.concat ", " pat_strs) in
          (* We can't efficiently query by attribute pattern with CSS alone.
             Mark all elements and let the user see which rule is active. *)
          Buffer.add_string buf
            (Printf.sprintf
               {|
  document.querySelectorAll('*').forEach(function(el) {
    for (const attr of el.attributes) {
      const name = attr.name;
      if (%s) {
        el.style.outline = '2px dashed #3182ce';
        el.style.outlineOffset = '-2px';
        break;
      }
    }
  });
  items.push('<span style="color:#3182ce">■</span> Drop_attributes: %s');
|}
               (let conditions =
                  List.map
                    (fun (p : Normalize.attr_pattern) ->
                      match p with
                      | Exact s ->
                          Printf.sprintf "name === '%s'" (js_string_escape s)
                      | Prefix s ->
                          Printf.sprintf "name.startsWith('%s')"
                            (js_string_escape s))
                    patterns
                in
                String.concat " || " conditions)
               label)
      | Round_bounds quantum ->
          Buffer.add_string buf
            (Printf.sprintf
               {|
  /* Draw grid lines at Round_bounds quantum = %g */
  (function() {
    const q = %g;
    const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
    svg.style.cssText = 'position:fixed;top:0;left:0;width:100vw;height:100vh;' +
      'pointer-events:none;z-index:999997;opacity:0.3;';
    const w = window.innerWidth, h = window.innerHeight;
    svg.setAttribute('viewBox', '0 0 ' + w + ' ' + h);
    for (let x = 0; x < w; x += q) {
      const line = document.createElementNS('http://www.w3.org/2000/svg', 'line');
      line.setAttribute('x1', x); line.setAttribute('y1', 0);
      line.setAttribute('x2', x); line.setAttribute('y2', h);
      line.setAttribute('stroke', '#68d391'); line.setAttribute('stroke-width', '0.5');
      svg.appendChild(line);
    }
    for (let y = 0; y < h; y += q) {
      const line = document.createElementNS('http://www.w3.org/2000/svg', 'line');
      line.setAttribute('x1', 0); line.setAttribute('y1', y);
      line.setAttribute('x2', w); line.setAttribute('y2', y);
      line.setAttribute('stroke', '#68d391'); line.setAttribute('stroke-width', '0.5');
      svg.appendChild(line);
    }
    document.body.appendChild(svg);
  })();
  items.push('<span style="color:#68d391">■</span> Round_bounds: %gpx grid');
|}
               quantum quantum quantum)
      | Canonicalize_colors ->
          Buffer.add_string buf
            {|  items.push('● Canonicalize_colors (no overlay)');
|}
      | Canonicalize_fonts ->
          Buffer.add_string buf
            {|  items.push('● Canonicalize_fonts (no overlay)');
|}
      | Sort_attributes ->
          Buffer.add_string buf
            {|  items.push('● Sort_attributes (no overlay)');
|}
      | Mask_text_matching _ ->
          Buffer.add_string buf
            {|  items.push('● Mask_text_matching (regex, no overlay)');
|})
    rules;
  Buffer.add_string buf
    {|
  legend.innerHTML += items.join('<br>');
  document.body.appendChild(legend);
})();
|};
  Buffer.contents buf

let show conn ~extractor_js ~url ~viewport ~color_scheme ~config =
  let _snap =
    Capture.capture conn ~extractor_js ~url ~viewport ~color_scheme ()
  in
  let js = overlay_js config.Config.normalize in
  let _inject =
    Cdp.send conn "Runtime.evaluate"
      (`Assoc [
        ("expression", `String js);
        ("returnByValue", `Bool true);
      ])
  in
  Printf.printf "Overlays injected. Press Enter to close the browser...%!";
  let _line = input_line stdin in
  ()
