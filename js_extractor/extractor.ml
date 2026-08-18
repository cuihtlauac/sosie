(** js_of_ocaml DOM snapshot extractor for sosie.

    Compiles to JavaScript via js_of_ocaml and exports a [sosieCapture]
    function that walks the DOM, captures resolved layout+style, and returns
    a JS object matching the sosie snapshot schema.

    Uses {!Sosie_shared.Snapshot_types} and {!Sosie_shared.Property_whitelist}
    so that types and the property whitelist are shared with native code. *)

open Js_of_ocaml
open Sosie_shared

(* -- Page freeze/unfreeze ------------------------------------------------- *)

(** Inject a <style> element that disables transitions and animations,
    preventing layout shifts during the DOM walk. Returns the style element
    so it can be removed later. *)
let freeze_page () =
  let doc = Dom_html.document in
  let style = Dom_html.createStyle doc in
  style##.textContent :=
    Js.some
      (Js.string "* { transition: none !important; animation: none !important; }");
  (* [document.head] is null on XML-parsed documents without an explicit
     <head> (the XML parser does not synthesize one) and on SVG-rooted
     documents. The binding types [head] as non-optional, so coerce to an
     opt to null-check and fall back to the document element. *)
  let head : Dom.node Js.t Js.opt = Js.Unsafe.get doc (Js.string "head") in
  let parent =
    Js.Opt.get head (fun () -> (doc##.documentElement :> Dom.node Js.t))
  in
  ignore (Dom.appendChild parent (style :> Dom.node Js.t));
  (* Force reflow so the freeze takes effect before measuring. *)
  ignore (doc##.documentElement##.offsetHeight);
  style

let unfreeze_page style =
  (* Remove from the actual parent rather than re-deriving the insertion
     point, so this stays correct under the [document.head] fallback. *)
  Js.Opt.iter style##.parentNode (fun parent ->
      ignore (Dom.removeChild parent (style :> Dom.node Js.t)))

(* -- Bounds --------------------------------------------------------------- *)

let get_bounds (el : Dom_html.element Js.t) : Snapshot_types.rect =
  let r = el##getBoundingClientRect in
  {
    x = Js.float_of_number r##.left;
    y = Js.float_of_number r##.top;
    w = Js.float_of_number r##.width;
    h = Js.float_of_number r##.height;
  }

(* -- Styles --------------------------------------------------------------- *)

(** Read the value of a single CSS property from a computed style. All
    resolved values are captured as [Str] — parsing into [Px], [Num],
    [Color] is deferred to the native comparison phase. *)
let get_property (style : Dom_html.cssStyleDeclaration Js.t) (css_name : string)
    : Snapshot_types.css_value =
  Str (Js.to_string (style##getPropertyValue (Js.string css_name)))

let get_border (style : Dom_html.cssStyleDeclaration Js.t) (side : string)
    : Snapshot_types.border =
  {
    width = get_property style (side ^ "-width");
    style = get_property style (side ^ "-style");
    color = get_property style (side ^ "-color");
  }

let get_styles (style : Dom_html.cssStyleDeclaration Js.t)
    : Snapshot_types.visual_properties =
  let p name = get_property style name in
  {
    display = p "display";
    visibility = p "visibility";
    opacity = p "opacity";
    color = p "color";
    background_color = p "background-color";
    font_family = p "font-family";
    font_size = p "font-size";
    font_weight = p "font-weight";
    line_height = p "line-height";
    text_align = p "text-align";
    text_decoration = p "text-decoration";
    border_top = get_border style "border-top";
    border_right = get_border style "border-right";
    border_bottom = get_border style "border-bottom";
    border_left = get_border style "border-left";
    border_radius = p "border-radius";
    box_shadow = p "box-shadow";
    overflow_x = p "overflow-x";
    overflow_y = p "overflow-y";
    z_index = p "z-index";
    cursor = p "cursor";
    text_align_last = p "text-align-last";
    text_decoration_skip_ink = p "text-decoration-skip-ink";
    text_underline_offset = p "text-underline-offset";
    text_shadow = p "text-shadow";
    text_combine_upright = p "text-combine-upright";
    text_emphasis_style = p "text-emphasis-style";
    text_emphasis_color = p "text-emphasis-color";
    text_emphasis_position = p "text-emphasis-position";
    webkit_text_stroke_width = p "-webkit-text-stroke-width";
    webkit_text_stroke_color = p "-webkit-text-stroke-color";
    font_palette = p "font-palette";
    writing_mode = p "writing-mode";
    direction = p "direction";
    appearance = p "appearance";
    accent_color = p "accent-color";
    image_rendering = p "image-rendering";
    outline_width = p "outline-width";
    outline_style = p "outline-style";
    outline_color = p "outline-color";
    outline_offset = p "outline-offset";
    fill = p "fill";
    stroke = p "stroke";
    stroke_width = p "stroke-width";
  }

(* -- Pseudo-elements ------------------------------------------------------ *)

(** Capture a pseudo-element (::before or ::after) if it has visible content.
    Returns [None] if content is "none", empty, or bare quotes. *)
let capture_pseudo (el : Dom_html.element Js.t) (selector : string)
    (paint_order : int ref) : Snapshot_types.node option =
  let style =
    Dom_html.window##getComputedStyle_pseudoElt el (Js.string selector)
  in
  let content =
    Js.to_string (style##getPropertyValue (Js.string "content"))
  in
  if content = "none" || content = "" || content = "\"\"" then None
  else begin
    let order = !paint_order in
    incr paint_order;
    Some
      {
        tag = selector;
        attributes = [];
        bounds = get_bounds el;
        styles = get_styles style;
        text = Some content;
        paint_order = order;
        children = [];
      }
  end

(** UA shadow pseudo-elements to capture per element type. Mirrors
    [applicablePseudos] in the canonical js/sosie-capture.js.

    getComputedStyle cannot reliably tell whether these generate a box
    (it returns a full declaration for almost any element+pseudo pair), so
    we do NOT detect existence. We capture a fixed, element-type-gated set
    unconditionally: since sosie compares before-vs-after on the SAME
    element, a pseudo with no real box resolves identically on both sides
    and adds no spurious diff — the gating only bounds tree size. Modern
    ::slider-* are unsupported in Chromium, so the -webkit- names are used.
    See plans/pseudo-element-capture.md. *)
let text_input_types =
  [ "text"; "search"; "url"; "tel"; "email"; "password"; "number" ]

let applicable_pseudos (el : Dom_html.element Js.t) : string list =
  match Js.to_string el##.tagName with
  | "INPUT" ->
      let t =
        Js.Opt.case
          (Dom_html.CoerceTo.input el)
          (fun () -> "text")
          (fun inp -> String.lowercase_ascii (Js.to_string inp##._type))
      in
      if t = "file" then [ "::file-selector-button" ]
      else if t = "range" then
        [ "::-webkit-slider-runnable-track"; "::-webkit-slider-thumb" ]
      else if List.mem t text_input_types then [ "::placeholder" ]
      else []
  | "TEXTAREA" -> [ "::placeholder" ]
  | "PROGRESS" -> [ "::-webkit-progress-bar"; "::-webkit-progress-value" ]
  | "METER" -> [ "::-webkit-meter-bar"; "::-webkit-meter-inner-element" ]
  (* Permission elements (PEPC): the type-specific tags and the generic
     <permission>. Their ::permission-icon reflects cascaded fill/stroke via
     getComputedStyle (verified: <geolocation> icon fill = author value). *)
  | "GEOLOCATION" | "CAMERA" | "MICROPHONE" | "PERMISSION" ->
      [ "::permission-icon" ]
  | _ -> []

(** Capture a UA shadow pseudo-element unconditionally (no content gate;
    these structural pseudos carry content "normal"/"none"). *)
let capture_ua_pseudo (el : Dom_html.element Js.t) (selector : string)
    (paint_order : int ref) : Snapshot_types.node =
  let style =
    Dom_html.window##getComputedStyle_pseudoElt el (Js.string selector)
  in
  let order = !paint_order in
  incr paint_order;
  {
    tag = selector;
    attributes = [];
    bounds = get_bounds el;
    styles = get_styles style;
    text = None;
    paint_order = order;
    children = [];
  }

(* -- DOM walk ------------------------------------------------------------- *)

(** Recursively capture an element and all its descendants. *)
let rec capture_element (el : Dom_html.element Js.t) (paint_order : int ref)
    : Snapshot_types.node =
  let computed = Dom_html.window##getComputedStyle el in
  let order = !paint_order in
  incr paint_order;
  let bounds = get_bounds el in
  let styles = get_styles computed in
  let tag = Js.to_string el##.tagName in
  (* Capture significant attributes for identification. *)
  let attributes =
    let acc = ref [] in
    (* Use getAttribute instead of .className to avoid SVGAnimatedString
       on SVG elements — getAttribute always returns a plain string. *)
    Js.Opt.iter (el##getAttribute (Js.string "class")) (fun cls_js ->
        let cls = Js.to_string cls_js in
        if cls <> "" then acc := ("class", cls) :: !acc);
    let id = Js.to_string el##.id in
    if id <> "" then acc := ("id", id) :: !acc;
    List.rev !acc
  in
  (* Collect children: ::before, child nodes, ::after. *)
  let children = ref [] in
  (* ::before pseudo-element. *)
  (match capture_pseudo el "::before" paint_order with
   | Some n -> children := n :: !children
   | None -> ());
  (* UA shadow pseudo-elements (element-type-gated, unconditional). Emitted
     after ::before, before light-DOM children; the list order is preserved
     because [children] is reversed once at the end. *)
  List.iter
    (fun sel -> children := capture_ua_pseudo el sel paint_order :: !children)
    (applicable_pseudos el);
  (* Walk child nodes: elements and text nodes. *)
  let child_nodes = el##.childNodes in
  let len = child_nodes##.length in
  for i = 0 to len - 1 do
    Js.Opt.iter (child_nodes##item i) (fun child ->
        match Dom.nodeType child with
        | Dom.Element dom_el ->
            let child_el = Dom_html.element dom_el in
            children :=
              capture_element child_el paint_order :: !children
        | Dom.Text text_node ->
            Js.Opt.iter text_node##.nodeValue (fun text_js ->
                let text = Js.to_string text_js in
                if String.trim text <> "" then begin
                  let text_order = !paint_order in
                  incr paint_order;
                  children :=
                    {
                      Snapshot_types.tag = "#text";
                      attributes = [];
                      bounds;
                      styles = get_styles computed;
                      text = Some text;
                      paint_order = text_order;
                      children = [];
                    }
                    :: !children
                end)
        | _ -> ())
  done;
  (* ::after pseudo-element. *)
  (match capture_pseudo el "::after" paint_order with
   | Some n -> children := n :: !children
   | None -> ());
  {
    tag;
    attributes;
    bounds;
    styles;
    text = None;
    paint_order = order;
    children = List.rev !children;
  }

(* -- Snapshot to JS object ------------------------------------------------ *)

(** Convert a css_value to a JS string (all values are Str in capture). *)
let css_value_to_js (v : Snapshot_types.css_value) : Js.Unsafe.any =
  match v with
  | Str s -> Js.Unsafe.inject (Js.string s)
  | Px f -> Js.Unsafe.inject (Js.string (Printf.sprintf "%gpx" f))
  | Num f -> Js.Unsafe.inject (Js.string (Printf.sprintf "%g" f))
  | Color c -> Js.Unsafe.inject (Js.string (Printf.sprintf "#%08x" c))

(** Convert visual_properties to a flat JS object keyed by CSS property
    names, matching the raw JS extractor's output format. *)
let styles_to_js (vp : Snapshot_types.visual_properties) : Js.Unsafe.any =
  Js.Unsafe.inject
    (Js.Unsafe.obj
       [|
         ("display", css_value_to_js vp.display);
         ("visibility", css_value_to_js vp.visibility);
         ("opacity", css_value_to_js vp.opacity);
         ("color", css_value_to_js vp.color);
         ("background-color", css_value_to_js vp.background_color);
         ("font-family", css_value_to_js vp.font_family);
         ("font-size", css_value_to_js vp.font_size);
         ("font-weight", css_value_to_js vp.font_weight);
         ("line-height", css_value_to_js vp.line_height);
         ("text-align", css_value_to_js vp.text_align);
         ("text-decoration", css_value_to_js vp.text_decoration);
         ("border-top-width", css_value_to_js vp.border_top.width);
         ("border-top-style", css_value_to_js vp.border_top.style);
         ("border-top-color", css_value_to_js vp.border_top.color);
         ("border-right-width", css_value_to_js vp.border_right.width);
         ("border-right-style", css_value_to_js vp.border_right.style);
         ("border-right-color", css_value_to_js vp.border_right.color);
         ("border-bottom-width", css_value_to_js vp.border_bottom.width);
         ("border-bottom-style", css_value_to_js vp.border_bottom.style);
         ("border-bottom-color", css_value_to_js vp.border_bottom.color);
         ("border-left-width", css_value_to_js vp.border_left.width);
         ("border-left-style", css_value_to_js vp.border_left.style);
         ("border-left-color", css_value_to_js vp.border_left.color);
         ("border-radius", css_value_to_js vp.border_radius);
         ("box-shadow", css_value_to_js vp.box_shadow);
         ("overflow-x", css_value_to_js vp.overflow_x);
         ("overflow-y", css_value_to_js vp.overflow_y);
         ("z-index", css_value_to_js vp.z_index);
         ("cursor", css_value_to_js vp.cursor);
         ("text-align-last", css_value_to_js vp.text_align_last);
         ("text-decoration-skip-ink", css_value_to_js vp.text_decoration_skip_ink);
         ("text-underline-offset", css_value_to_js vp.text_underline_offset);
         ("text-shadow", css_value_to_js vp.text_shadow);
         ("text-combine-upright", css_value_to_js vp.text_combine_upright);
         ("text-emphasis-style", css_value_to_js vp.text_emphasis_style);
         ("text-emphasis-color", css_value_to_js vp.text_emphasis_color);
         ("text-emphasis-position", css_value_to_js vp.text_emphasis_position);
         ("-webkit-text-stroke-width", css_value_to_js vp.webkit_text_stroke_width);
         ("-webkit-text-stroke-color", css_value_to_js vp.webkit_text_stroke_color);
         ("font-palette", css_value_to_js vp.font_palette);
         ("writing-mode", css_value_to_js vp.writing_mode);
         ("direction", css_value_to_js vp.direction);
         ("appearance", css_value_to_js vp.appearance);
         ("accent-color", css_value_to_js vp.accent_color);
         ("image-rendering", css_value_to_js vp.image_rendering);
         ("outline-width", css_value_to_js vp.outline_width);
         ("outline-style", css_value_to_js vp.outline_style);
         ("outline-color", css_value_to_js vp.outline_color);
         ("outline-offset", css_value_to_js vp.outline_offset);
         ("fill", css_value_to_js vp.fill);
         ("stroke", css_value_to_js vp.stroke);
         ("stroke-width", css_value_to_js vp.stroke_width);
       |])

let rec node_to_js (n : Snapshot_types.node) : Js.Unsafe.any =
  let attrs =
    Js.array
      (Array.of_list
         (List.map
            (fun (k, v) ->
              Js.Unsafe.inject
                (Js.array [| Js.Unsafe.inject (Js.string k);
                             Js.Unsafe.inject (Js.string v) |]))
            n.attributes))
  in
  let children_arr =
    Js.array (Array.of_list (List.map node_to_js n.children))
  in
  let text =
    match n.text with
    | None -> Js.Unsafe.inject Js.null
    | Some s -> Js.Unsafe.inject (Js.string s)
  in
  Js.Unsafe.inject
    (Js.Unsafe.obj
       [|
         ("tag", Js.Unsafe.inject (Js.string n.tag));
         ("attributes", Js.Unsafe.inject attrs);
         ("bounds",
          Js.Unsafe.inject
            (Js.Unsafe.obj
               [|
                 ("x", Js.Unsafe.inject (Js.float n.bounds.x));
                 ("y", Js.Unsafe.inject (Js.float n.bounds.y));
                 ("w", Js.Unsafe.inject (Js.float n.bounds.w));
                 ("h", Js.Unsafe.inject (Js.float n.bounds.h));
               |]));
         ("styles", styles_to_js n.styles);
         ("text", text);
         ("paintOrder", Js.Unsafe.inject n.paint_order);
         ("children", Js.Unsafe.inject children_arr);
       |])

let snapshot_to_js (s : Snapshot_types.snapshot) : Js.Unsafe.any =
  let vw, vh = s.viewport in
  let color_scheme =
    match s.color_scheme with `Light -> "light" | `Dark -> "dark"
  in
  Js.Unsafe.inject
    (Js.Unsafe.obj
       [|
         ("version", Js.Unsafe.inject s.version);
         ("url", Js.Unsafe.inject (Js.string s.url));
         ("viewport",
          Js.Unsafe.inject (Js.array [| Js.Unsafe.inject vw; Js.Unsafe.inject vh |]));
         ("colorScheme", Js.Unsafe.inject (Js.string color_scheme));
         ("root", node_to_js s.root);
       |])

(* -- Entry point ---------------------------------------------------------- *)

let capture () : Snapshot_types.snapshot =
  let style = freeze_page () in
  let paint_order = ref 0 in
  let doc = Dom_html.document in
  let root_el = doc##.documentElement in
  let root = capture_element (root_el :> Dom_html.element Js.t) paint_order in
  unfreeze_page style;
  let win = Dom_html.window in
  let url =
    Js.to_string win##.location##.href
  in
  let vw = win##.innerWidth in
  let vh = win##.innerHeight in
  let dark =
    Js.to_bool
      (win##matchMedia (Js.string "(prefers-color-scheme: dark)"))##.matches
  in
  {
    version = 1;
    url;
    viewport = (vw, vh);
    color_scheme = (if dark then `Dark else `Light);
    root;
  }

let () =
  Js.export "sosieCapture"
    (Js.wrap_callback (fun () -> snapshot_to_js (capture ())))
