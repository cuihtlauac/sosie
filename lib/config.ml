(** Configuration file parser for sosie.json. *)

type t = {
  normalize : Normalize.rule list;
  compare : Compare.config;
}

let default =
  { normalize = []; compare = Compare.default_config }

(* --- JSON helpers --- *)

let member key = function
  | `Assoc l -> List.assoc_opt key l
  | _ -> None

let to_bool = function `Bool b -> Some b | _ -> None
let to_float = function `Float f -> Some f | `Int i -> Some (Float.of_int i) | _ -> None
let to_string = function `String s -> Some s | _ -> None

let bool_field key default obj =
  match member key obj with
  | Some v -> (match to_bool v with Some b -> Ok b | None -> Error (key ^ " must be a bool"))
  | None -> Ok default

let float_field key default obj =
  match member key obj with
  | Some v -> (match to_float v with Some f -> Ok f | None -> Error (key ^ " must be a number"))
  | None -> Ok default

(* --- Selector parsing --- *)

let parse_selector s =
  if s = "*" then Normalize.Universal
  else if String.length s > 0 && s.[0] = '#' then
    Normalize.Id (String.sub s 1 (String.length s - 1))
  else if String.length s > 0 && s.[0] = '.' then
    Normalize.Class (String.sub s 1 (String.length s - 1))
  else
    Normalize.Tag (String.uppercase_ascii s)

(* --- Attribute pattern parsing --- *)

let parse_attr_pattern s =
  let len = String.length s in
  if len > 0 && s.[len - 1] = '*' then
    Normalize.Prefix (String.sub s 0 (len - 1))
  else
    Normalize.Exact s

(* --- Normalize rules parsing --- *)

let parse_normalize_rules obj =
  let rules = ref [] in
  let add r = rules := r :: !rules in
  let err = ref None in
  let set_err msg = if !err = None then err := Some msg in
  (* drop_attributes *)
  (match member "drop_attributes" obj with
   | Some (`List l) ->
     let pats = List.filter_map (fun v ->
       match to_string v with
       | Some s -> Some (parse_attr_pattern s)
       | None -> set_err "drop_attributes items must be strings"; None
     ) l in
     if pats <> [] then add (Normalize.Drop_attributes pats)
   | Some _ -> set_err "drop_attributes must be an array"
   | None -> ());
  (* sort_attributes *)
  (match member "sort_attributes" obj with
   | Some v ->
     (match to_bool v with
      | Some true -> add Normalize.Sort_attributes
      | Some false -> ()
      | None -> set_err "sort_attributes must be a bool")
   | None -> ());
  (* round_bounds *)
  (match member "round_bounds" obj with
   | Some v ->
     (match to_float v with
      | Some f -> add (Normalize.Round_bounds f)
      | None -> set_err "round_bounds must be a number")
   | None -> ());
  (* canonicalize_colors *)
  (match member "canonicalize_colors" obj with
   | Some v ->
     (match to_bool v with
      | Some true -> add Normalize.Canonicalize_colors
      | Some false -> ()
      | None -> set_err "canonicalize_colors must be a bool")
   | None -> ());
  (* canonicalize_fonts *)
  (match member "canonicalize_fonts" obj with
   | Some v ->
     (match to_bool v with
      | Some true -> add Normalize.Canonicalize_fonts
      | Some false -> ()
      | None -> set_err "canonicalize_fonts must be a bool")
   | None -> ());
  (* mask_text *)
  (match member "mask_text" obj with
   | Some (`List l) ->
     List.iter (fun item ->
       match member "selector" item, member "replacement" item with
       | Some (`String sel), Some (`String repl) ->
         add (Normalize.Mask_text { selector = parse_selector sel; replacement = repl })
       | _ -> set_err "mask_text items must have string selector and replacement"
     ) l
   | Some _ -> set_err "mask_text must be an array"
   | None -> ());
  (* mask_text_matching *)
  (match member "mask_text_matching" obj with
   | Some (`List l) ->
     List.iter (fun item ->
       match member "pattern" item, member "replacement" item with
       | Some (`String pat), Some (`String repl) ->
         (match Re.Pcre.re pat |> Re.compile with
          | re -> add (Normalize.Mask_text_matching { pattern = re; replacement = repl })
          | exception _ -> set_err ("invalid regex: " ^ pat))
       | _ -> set_err "mask_text_matching items must have string pattern and replacement"
     ) l
   | Some _ -> set_err "mask_text_matching must be an array"
   | None -> ());
  (* drop_subtrees *)
  (match member "drop_subtrees" obj with
   | Some (`List l) ->
     List.iter (fun v ->
       match to_string v with
       | Some s -> add (Normalize.Drop_subtree (parse_selector s))
       | None -> set_err "drop_subtrees items must be strings"
     ) l
   | Some _ -> set_err "drop_subtrees must be an array"
   | None -> ());
  match !err with
  | Some msg -> Error msg
  | None -> Ok (List.rev !rules)

(* --- Compare config parsing --- *)

let parse_compare obj =
  let ( >>= ) = Result.bind in
  bool_field "check_bounds" true obj >>= fun check_bounds ->
  bool_field "check_visual" true obj >>= fun check_visual ->
  bool_field "check_text" true obj >>= fun check_text ->
  bool_field "check_paint_order" true obj >>= fun check_paint_order ->
  float_field "bounds_tolerance" 0.0 obj >>= fun bounds_tolerance ->
  float_field "value_tolerance" 0.0 obj >>= fun value_tolerance ->
  Ok { Compare.check_bounds; check_visual; check_text; check_paint_order;
       bounds_tolerance; value_tolerance }

(* --- Top-level --- *)

let of_json json =
  match json with
  | `Assoc _ ->
    let ( >>= ) = Result.bind in
    (match member "normalize" json with
     | Some (`Assoc _ as obj) -> parse_normalize_rules obj
     | Some _ -> Error "normalize must be an object"
     | None -> Ok [])
    >>= fun normalize ->
    (match member "compare" json with
     | Some (`Assoc _ as obj) -> parse_compare obj
     | Some _ -> Error "compare must be an object"
     | None -> Ok Compare.default_config)
    >>= fun compare ->
    Ok { normalize; compare }
  | _ -> Error "config must be a JSON object"

let load path =
  match Yojson.Safe.from_file path with
  | json -> of_json json
  | exception Yojson.Json_error msg -> Error ("JSON parse error: " ^ msg)
  | exception Sys_error msg -> Error msg
