(** Mutation testing for snapshot sensitivity measurement.

    See {!Mutate} (the .mli) for documentation. *)

open Sosie_shared.Snapshot_types

(* -- Types -------------------------------------------------------------- *)

type operator =
  | Perturb_numeric
  | Replace_color
  | Reset_to_default
  | Swap_siblings
  | Change_keyword
  | Toggle_visibility

let operator_to_string = function
  | Perturb_numeric -> "Perturb_numeric"
  | Replace_color -> "Replace_color"
  | Reset_to_default -> "Reset_to_default"
  | Swap_siblings -> "Swap_siblings"
  | Change_keyword -> "Change_keyword"
  | Toggle_visibility -> "Toggle_visibility"

type mutation = {
  node_index : int;
  property : string;
  operator : operator;
  original : css_value;
  mutated : css_value;
}

type outcome = Equivalent | Killed | Survived

type result = {
  mutation : mutation;
  outcome : outcome;
}

(* -- CSS value helpers -------------------------------------------------- *)

let css_value_to_string (v : css_value) =
  match v with
  | Str s -> s
  | Px f -> Printf.sprintf "%gpx" f
  | Num f -> Printf.sprintf "%g" f
  | Color c -> Printf.sprintf "#%08x" c

let css_values_equal a b =
  match (a, b) with
  | Str a, Str b -> String.equal a b
  | Px a, Px b -> a = b
  | Num a, Num b -> a = b
  | Color a, Color b -> a = b
  | _ -> false

(* -- Mutation operators ------------------------------------------------- *)

(* Parse "NNpx" to float, returns None if not a px value. *)
let parse_px s =
  let len = String.length s in
  if len > 2 && String.sub s (len - 2) 2 = "px" then
    match float_of_string_opt (String.sub s 0 (len - 2)) with
    | Some f -> Some f
    | None -> None
  else None

(* Parse numeric-only string. *)
let parse_num s = float_of_string_opt s

(* Perturb a numeric CSS value by +1 unit. *)
let perturb_numeric (v : css_value) : css_value option =
  match v with
  | Str s -> (
      match parse_px s with
      | Some f ->
          let f' = f +. 1.0 in
          let mutated = Str (Printf.sprintf "%gpx" f') in
          if css_values_equal (Str s) mutated then None else Some mutated
      | None -> (
          match parse_num s with
          | Some f ->
              let f' = f +. 1.0 in
              let mutated = Str (Printf.sprintf "%g" f') in
              if css_values_equal (Str s) mutated then None else Some mutated
          | None -> None))
  | Px f -> Some (Px (f +. 1.0))
  | Num f -> Some (Num (f +. 1.0))
  | Color _ -> None

(* Replace a color with a visually distinct one. *)
let replace_color (v : css_value) : css_value option =
  match v with
  | Str s ->
      (* Match rgb(R, G, B) or rgba(R, G, B, A) *)
      let is_color =
        String.length s > 3
        && (String.sub s 0 3 = "rgb" || String.sub s 0 4 = "rgba")
      in
      if is_color then
        (* Replace with a contrasting color *)
        if String.equal s "rgb(0, 0, 255)" then Some (Str "rgb(255, 0, 0)")
        else Some (Str "rgb(0, 0, 255)")
      else None
  | Color c ->
      if c = 0x0000ffff then Some (Color 0xff0000ff)
      else Some (Color 0x0000ffff)
  | _ -> None

(* Property -> (default_value, applicable_operators) *)
type prop_info = {
  default : string;
  keywords : string list;
}

let prop_table =
  [
    ("display", { default = "block"; keywords = [ "block"; "inline"; "flex"; "grid"; "none"; "inline-block" ] });
    ("visibility", { default = "visible"; keywords = [ "visible"; "hidden"; "collapse" ] });
    ("opacity", { default = "1"; keywords = [] });
    ("color", { default = "rgb(0, 0, 0)"; keywords = [] });
    ("background-color", { default = "rgba(0, 0, 0, 0)"; keywords = [] });
    ("font-family", { default = "serif"; keywords = [] });
    ("font-size", { default = "16px"; keywords = [] });
    ("font-weight", { default = "400"; keywords = [ "400"; "700"; "100"; "900" ] });
    ("line-height", { default = "normal"; keywords = [] });
    ("text-align", { default = "start"; keywords = [ "start"; "center"; "end"; "left"; "right"; "justify" ] });
    ("text-decoration", { default = "none"; keywords = [] });
    ("border-top-width", { default = "0px"; keywords = [] });
    ("border-top-style", { default = "none"; keywords = [ "none"; "solid"; "dashed"; "dotted" ] });
    ("border-top-color", { default = "rgb(0, 0, 0)"; keywords = [] });
    ("border-right-width", { default = "0px"; keywords = [] });
    ("border-right-style", { default = "none"; keywords = [ "none"; "solid"; "dashed"; "dotted" ] });
    ("border-right-color", { default = "rgb(0, 0, 0)"; keywords = [] });
    ("border-bottom-width", { default = "0px"; keywords = [] });
    ("border-bottom-style", { default = "none"; keywords = [ "none"; "solid"; "dashed"; "dotted" ] });
    ("border-bottom-color", { default = "rgb(0, 0, 0)"; keywords = [] });
    ("border-left-width", { default = "0px"; keywords = [] });
    ("border-left-style", { default = "none"; keywords = [ "none"; "solid"; "dashed"; "dotted" ] });
    ("border-left-color", { default = "rgb(0, 0, 0)"; keywords = [] });
    ("border-radius", { default = "0px"; keywords = [] });
    ("box-shadow", { default = "none"; keywords = [] });
    ("overflow-x", { default = "visible"; keywords = [ "visible"; "hidden"; "scroll"; "auto" ] });
    ("overflow-y", { default = "visible"; keywords = [ "visible"; "hidden"; "scroll"; "auto" ] });
    ("z-index", { default = "auto"; keywords = [ "auto"; "0"; "1"; "10" ] });
    ("cursor", { default = "auto"; keywords = [ "auto"; "pointer"; "default"; "crosshair"; "text" ] });
    ("text-align-last", { default = "auto"; keywords = [ "auto"; "start"; "center"; "end"; "justify" ] });
    ("text-decoration-skip-ink", { default = "auto"; keywords = [ "auto"; "none"; "all" ] });
    ("text-underline-offset", { default = "auto"; keywords = [] });
    ("text-shadow", { default = "none"; keywords = [] });
    ("text-combine-upright", { default = "none"; keywords = [ "none"; "all" ] });
    ("text-emphasis-style", { default = "none"; keywords = [] });
    ("text-emphasis-color", { default = "rgb(0, 0, 0)"; keywords = [] });
    ("text-emphasis-position", { default = "over right"; keywords = [] });
    ("-webkit-text-stroke-width", { default = "0px"; keywords = [] });
    ("-webkit-text-stroke-color", { default = "rgb(0, 0, 0)"; keywords = [] });
    ("font-palette", { default = "normal"; keywords = [] });
    ("writing-mode", { default = "horizontal-tb"; keywords = [ "horizontal-tb"; "vertical-rl"; "vertical-lr" ] });
    ("direction", { default = "ltr"; keywords = [ "ltr"; "rtl" ] });
    ("appearance", { default = "none"; keywords = [ "none"; "auto" ] });
    ("accent-color", { default = "auto"; keywords = [] });
    ("image-rendering", { default = "auto"; keywords = [ "auto"; "pixelated"; "crisp-edges" ] });
    ("outline-width", { default = "0px"; keywords = [] });
    ("outline-style", { default = "none"; keywords = [ "none"; "solid"; "dashed"; "dotted" ] });
    ("outline-color", { default = "rgb(0, 0, 0)"; keywords = [] });
    ("outline-offset", { default = "0px"; keywords = [] });
  ]

(* Get the value of a named property from a node. *)
let get_property (n : node) (prop : string) : css_value option =
  let s = n.styles in
  match prop with
  | "display" -> Some s.display
  | "visibility" -> Some s.visibility
  | "opacity" -> Some s.opacity
  | "color" -> Some s.color
  | "background-color" -> Some s.background_color
  | "font-family" -> Some s.font_family
  | "font-size" -> Some s.font_size
  | "font-weight" -> Some s.font_weight
  | "line-height" -> Some s.line_height
  | "text-align" -> Some s.text_align
  | "text-decoration" -> Some s.text_decoration
  | "border-top-width" -> Some s.border_top.width
  | "border-top-style" -> Some s.border_top.style
  | "border-top-color" -> Some s.border_top.color
  | "border-right-width" -> Some s.border_right.width
  | "border-right-style" -> Some s.border_right.style
  | "border-right-color" -> Some s.border_right.color
  | "border-bottom-width" -> Some s.border_bottom.width
  | "border-bottom-style" -> Some s.border_bottom.style
  | "border-bottom-color" -> Some s.border_bottom.color
  | "border-left-width" -> Some s.border_left.width
  | "border-left-style" -> Some s.border_left.style
  | "border-left-color" -> Some s.border_left.color
  | "border-radius" -> Some s.border_radius
  | "box-shadow" -> Some s.box_shadow
  | "overflow-x" -> Some s.overflow_x
  | "overflow-y" -> Some s.overflow_y
  | "z-index" -> Some s.z_index
  | "cursor" -> Some s.cursor
  | "text-align-last" -> Some s.text_align_last
  | "text-decoration-skip-ink" -> Some s.text_decoration_skip_ink
  | "text-underline-offset" -> Some s.text_underline_offset
  | "text-shadow" -> Some s.text_shadow
  | "text-combine-upright" -> Some s.text_combine_upright
  | "text-emphasis-style" -> Some s.text_emphasis_style
  | "text-emphasis-color" -> Some s.text_emphasis_color
  | "text-emphasis-position" -> Some s.text_emphasis_position
  | "-webkit-text-stroke-width" -> Some s.webkit_text_stroke_width
  | "-webkit-text-stroke-color" -> Some s.webkit_text_stroke_color
  | "font-palette" -> Some s.font_palette
  | "writing-mode" -> Some s.writing_mode
  | "direction" -> Some s.direction
  | "appearance" -> Some s.appearance
  | "accent-color" -> Some s.accent_color
  | "image-rendering" -> Some s.image_rendering
  | "outline-width" -> Some s.outline_width
  | "outline-style" -> Some s.outline_style
  | "outline-color" -> Some s.outline_color
  | "outline-offset" -> Some s.outline_offset
  | _ -> None

(* Set the value of a named property on a node. *)
let set_property (n : node) (prop : string) (v : css_value) : node =
  let s = n.styles in
  let styles =
    match prop with
    | "display" -> { s with display = v }
    | "visibility" -> { s with visibility = v }
    | "opacity" -> { s with opacity = v }
    | "color" -> { s with color = v }
    | "background-color" -> { s with background_color = v }
    | "font-family" -> { s with font_family = v }
    | "font-size" -> { s with font_size = v }
    | "font-weight" -> { s with font_weight = v }
    | "line-height" -> { s with line_height = v }
    | "text-align" -> { s with text_align = v }
    | "text-decoration" -> { s with text_decoration = v }
    | "border-top-width" ->
        { s with border_top = { s.border_top with width = v } }
    | "border-top-style" ->
        { s with border_top = { s.border_top with style = v } }
    | "border-top-color" ->
        { s with border_top = { s.border_top with color = v } }
    | "border-right-width" ->
        { s with border_right = { s.border_right with width = v } }
    | "border-right-style" ->
        { s with border_right = { s.border_right with style = v } }
    | "border-right-color" ->
        { s with border_right = { s.border_right with color = v } }
    | "border-bottom-width" ->
        { s with border_bottom = { s.border_bottom with width = v } }
    | "border-bottom-style" ->
        { s with border_bottom = { s.border_bottom with style = v } }
    | "border-bottom-color" ->
        { s with border_bottom = { s.border_bottom with color = v } }
    | "border-left-width" ->
        { s with border_left = { s.border_left with width = v } }
    | "border-left-style" ->
        { s with border_left = { s.border_left with style = v } }
    | "border-left-color" ->
        { s with border_left = { s.border_left with color = v } }
    | "border-radius" -> { s with border_radius = v }
    | "box-shadow" -> { s with box_shadow = v }
    | "overflow-x" -> { s with overflow_x = v }
    | "overflow-y" -> { s with overflow_y = v }
    | "z-index" -> { s with z_index = v }
    | "cursor" -> { s with cursor = v }
    | "text-align-last" -> { s with text_align_last = v }
    | "text-decoration-skip-ink" -> { s with text_decoration_skip_ink = v }
    | "text-underline-offset" -> { s with text_underline_offset = v }
    | "text-shadow" -> { s with text_shadow = v }
    | "text-combine-upright" -> { s with text_combine_upright = v }
    | "text-emphasis-style" -> { s with text_emphasis_style = v }
    | "text-emphasis-color" -> { s with text_emphasis_color = v }
    | "text-emphasis-position" -> { s with text_emphasis_position = v }
    | "-webkit-text-stroke-width" -> { s with webkit_text_stroke_width = v }
    | "-webkit-text-stroke-color" -> { s with webkit_text_stroke_color = v }
    | "font-palette" -> { s with font_palette = v }
    | "writing-mode" -> { s with writing_mode = v }
    | "direction" -> { s with direction = v }
    | "appearance" -> { s with appearance = v }
    | "accent-color" -> { s with accent_color = v }
    | "image-rendering" -> { s with image_rendering = v }
    | "outline-width" -> { s with outline_width = v }
    | "outline-style" -> { s with outline_style = v }
    | "outline-color" -> { s with outline_color = v }
    | "outline-offset" -> { s with outline_offset = v }
    | _ -> invalid_arg (Printf.sprintf "set_property: unknown property %S" prop)
  in
  { n with styles }

(* -- Pre-order tree walk ------------------------------------------------ *)

(* Collect (index, node, siblings) in pre-order. siblings is the parent's
   children list (needed for Swap_siblings). *)
let preorder_with_siblings (root : node) :
    (int * node * node list) list =
  let acc = ref [] in
  let idx = ref 0 in
  let rec go siblings (n : node) =
    let i = !idx in
    incr idx;
    acc := (i, n, siblings) :: !acc;
    List.iter (go n.children) n.children
  in
  go [] root;
  List.rev !acc

(* -- Enumerate mutations for one node ----------------------------------- *)

let is_color_prop prop =
  match prop with
  | "color" | "background-color"
  | "border-top-color" | "border-right-color"
  | "border-bottom-color" | "border-left-color" -> true
  | _ -> false

let is_numeric_prop prop =
  match prop with
  | "font-size" | "line-height" | "border-radius"
  | "border-top-width" | "border-right-width"
  | "border-bottom-width" | "border-left-width" -> true
  | _ -> false

let is_visibility_prop prop =
  match prop with
  | "opacity" | "visibility" -> true
  | _ -> false

let mutations_for_node ~node_index (n : node) (siblings : node list) :
    mutation list =
  let muts = ref [] in
  let add op prop original mutated =
    if not (css_values_equal original mutated) then
      muts := { node_index; property = prop; operator = op;
                original; mutated } :: !muts
  in
  List.iter
    (fun (prop, info) ->
      match get_property n prop with
      | None -> ()
      | Some original ->
          (* Perturb_numeric: px and pure-numeric values *)
          if is_numeric_prop prop || prop = "opacity" || prop = "font-weight" then (
            match perturb_numeric original with
            | Some mutated -> add Perturb_numeric prop original mutated
            | None -> ());
          (* Replace_color *)
          if is_color_prop prop then (
            match replace_color original with
            | Some mutated -> add Replace_color prop original mutated
            | None -> ());
          (* Reset_to_default: if current value differs from default *)
          let default_val = Str info.default in
          if not (css_values_equal original default_val) then
            add Reset_to_default prop original default_val;
          (* Change_keyword: pick a different keyword *)
          if info.keywords <> [] then (
            let cur_str = css_value_to_string original in
            match
              List.find_opt (fun kw -> not (String.equal kw cur_str)) info.keywords
            with
            | Some kw -> add Change_keyword prop original (Str kw)
            | None -> ());
          (* Toggle_visibility *)
          if is_visibility_prop prop then (
            let toggled =
              match prop with
              | "opacity" ->
                  if css_value_to_string original = "1" then Some (Str "0")
                  else if css_value_to_string original = "0" then Some (Str "1")
                  else Some (Str "0")
              | "visibility" ->
                  if css_value_to_string original = "visible" then Some (Str "hidden")
                  else Some (Str "visible")
              | _ -> None
            in
            match toggled with
            | Some mutated -> add Toggle_visibility prop original mutated
            | None -> ());
          (* Swap_siblings: swap this property with a sibling that has a
             different value *)
          if List.length siblings >= 2 then (
            let other =
              List.find_opt
                (fun (sib : node) ->
                  match get_property sib prop with
                  | Some v -> not (css_values_equal v original)
                  | None -> false)
                siblings
            in
            match other with
            | Some sib -> (
                match get_property sib prop with
                | Some v -> add Swap_siblings prop original v
                | None -> ())
            | None -> ()))
    prop_table;
  List.rev !muts

(* -- Enumerate all mutations -------------------------------------------- *)

let enumerate_mutations (snap : snapshot) : mutation list =
  let entries = preorder_with_siblings snap.root in
  List.concat_map
    (fun (node_index, n, siblings) ->
      mutations_for_node ~node_index n siblings)
    entries

(* -- Apply a mutation --------------------------------------------------- *)

let apply_mutation (snap : snapshot) (m : mutation) : snapshot =
  let target_idx = ref 0 in
  let rec go (n : node) =
    let i = !target_idx in
    incr target_idx;
    if i = m.node_index then set_property n m.property m.mutated
    else { n with children = List.map go n.children }
  in
  { snap with root = go snap.root }

(* -- Sampling ----------------------------------------------------------- *)

let sample rng n mutations =
  let arr = Array.of_list mutations in
  let len = Array.length arr in
  if n >= len then mutations
  else begin
    (* Fisher-Yates partial shuffle *)
    for i = 0 to n - 1 do
      let j = i + Random.State.int rng (len - i) in
      let tmp = arr.(i) in
      arr.(i) <- arr.(j);
      arr.(j) <- tmp
    done;
    Array.to_list (Array.sub arr 0 n)
  end

(* -- Harness ------------------------------------------------------------ *)

let run conn ~extractor_js ~config ~viewport snap ~mutations ~on_progress =
  (* Render and capture the baseline. *)
  let html_base = Snapshot_gen.to_html snap in
  let vw, vh = viewport in
  let data_uri_base = "data:text/html;base64," ^ Base64.encode_exn html_base in
  let baseline_json =
    Capture.capture conn ~extractor_js ~url:data_uri_base ~viewport:(vw, vh) ()
  in
  let baseline_snap = Snapshot.of_json baseline_json in
  let baseline_norm = Normalize.apply config.Config.normalize baseline_snap in
  let px_base = Capture.screenshot conn in
  let total = List.length mutations in
  List.mapi
    (fun i m ->
      let snap' = apply_mutation snap m in
      let html' = Snapshot_gen.to_html snap' in
      let data_uri' = "data:text/html;base64," ^ Base64.encode_exn html' in
      (* Navigate to mutant page and screenshot. *)
      let _nav =
        Cdp.send conn "Page.navigate"
          (`Assoc [ ("url", `String data_uri') ])
      in
      let _load = Cdp.wait_event conn "Page.loadEventFired" () in
      let px_mutant = Capture.screenshot conn in
      let outcome =
        if String.equal px_base px_mutant then Equivalent
        else begin
          (* Page is already loaded from the screenshot step — extract
             without re-navigating. *)
          let mutant_json = Capture.extract conn ~extractor_js in
          let mutant_snap = Snapshot.of_json mutant_json in
          let mutant_norm = Normalize.apply config.Config.normalize mutant_snap in
          let diffs =
            Compare.compare_matched config.Config.compare baseline_norm mutant_norm
          in
          if diffs = [] then Survived else Killed
        end
      in
      on_progress (i + 1) total;
      { mutation = m; outcome })
    mutations

(* -- Report ------------------------------------------------------------- *)

(* Find the node at a pre-order index and return its path. *)
let path_of_index (root : node) (idx : int) : Compare.path =
  let found = ref None in
  let cur = ref 0 in
  let rec go path (n : node) =
    let i = !cur in
    incr cur;
    if i = idx then found := Some (List.rev path);
    List.iteri (fun ci child -> go (ci :: path) child) n.children
  in
  go [] root;
  match !found with Some p -> p | None -> []

let report ~root results =
  let buf = Buffer.create 512 in
  let total = List.length results in
  let equivalent = List.length (List.filter (fun r -> r.outcome = Equivalent) results) in
  let killed = List.length (List.filter (fun r -> r.outcome = Killed) results) in
  let survived = List.length (List.filter (fun r -> r.outcome = Survived) results) in
  let effective = total - equivalent in
  let score_pct =
    if effective = 0 then 100.0
    else 100.0 *. Float.of_int killed /. Float.of_int effective
  in
  Printf.bprintf buf "Mutation score: %d/%d (%.1f%%)\n" killed effective score_pct;
  Printf.bprintf buf "  Total: %d mutations\n" total;
  Printf.bprintf buf "  Equivalent: %d (filtered)\n" equivalent;
  Printf.bprintf buf "  Killed: %d\n" killed;
  Printf.bprintf buf "  Survived: %d\n" survived;
  (* Per-property breakdown *)
  let prop_stats = Hashtbl.create 32 in
  List.iter
    (fun r ->
      if r.outcome <> Equivalent then begin
        let prop = r.mutation.property in
        let (k, t) =
          match Hashtbl.find_opt prop_stats prop with
          | Some (k, t) -> (k, t)
          | None -> (0, 0)
        in
        let k' = if r.outcome = Killed then k + 1 else k in
        Hashtbl.replace prop_stats prop (k', t + 1)
      end)
    results;
  if Hashtbl.length prop_stats > 0 then begin
    Printf.bprintf buf "\nPer-property:\n";
    let props =
      Hashtbl.fold (fun k v acc -> (k, v) :: acc) prop_stats []
      |> List.sort (fun (a, _) (b, _) -> String.compare a b)
    in
    List.iter
      (fun (prop, (k, t)) ->
        let pct = if t = 0 then 100.0 else 100.0 *. Float.of_int k /. Float.of_int t in
        Printf.bprintf buf "  %-24s %d/%d (%.0f%%)\n" prop k t pct)
      props
  end;
  (* Surviving mutants *)
  let survivors =
    List.filter (fun r -> r.outcome = Survived) results
  in
  if survivors <> [] then begin
    Printf.bprintf buf "\nSurviving mutants:\n";
    List.iter
      (fun r ->
        let m = r.mutation in
        let path = path_of_index root m.node_index in
        let xpath = Compare.path_to_string root path in
        Printf.bprintf buf "  %s: %s %S -> %S (%s)\n" xpath m.property
          (css_value_to_string m.original)
          (css_value_to_string m.mutated)
          (operator_to_string m.operator))
      survivors
  end;
  Buffer.contents buf
