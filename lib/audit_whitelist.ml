(** Whitelist blind-spot detection via CSS property complement reset.

    See {!Audit_whitelist} (the .mli) for documentation. *)

module String_set = Set.Make (String)

let whitelist_css_names = Sosie_shared.Property_whitelist.css_names

let all_css_properties conn =
  let _enable = Cdp.send conn "CSS.enable" (`Assoc []) in
  let result =
    Cdp.send conn "CSS.getSupportedCSSProperties" (`Assoc [])
  in
  match result with
  | `Assoc fields -> (
      match List.assoc_opt "cssProperties" fields with
      | Some (`List props) ->
          List.filter_map
            (fun p ->
              match p with
              | `Assoc pf -> (
                  match List.assoc_opt "name" pf with
                  | Some (`String name) -> Some name
                  | _ -> None)
              | _ -> None)
            props
      | _ -> failwith "CSS.getSupportedCSSProperties: missing cssProperties")
  | _ -> failwith "CSS.getSupportedCSSProperties: unexpected response"

let reset_stylesheet ~whitelist ~all_properties =
  let whiteset =
    List.fold_left
      (fun acc name -> String_set.add name acc)
      String_set.empty whitelist
  in
  let complement =
    List.filter (fun name -> not (String_set.mem name whiteset)) all_properties
  in
  match complement with
  | [] -> ""
  | props ->
      let decls =
        List.map (fun name -> Printf.sprintf "  %s: initial !important;" name) props
      in
      "* {\n" ^ String.concat "\n" decls ^ "\n}"

let write_bytes path data =
  let oc = open_out_bin path in
  output_string oc data;
  close_out oc

let imagemagick_diff ~baseline_path ~reset_path ~output =
  let cmd =
    Printf.sprintf "compare %s %s %s 2>/dev/null"
      (Filename.quote baseline_path)
      (Filename.quote reset_path)
      (Filename.quote output)
  in
  (* compare exits 0 when identical, 1 when different (diff image written),
     2 on error. We treat 0 and 1 as success. *)
  let code = Sys.command cmd in
  code = 0 || code = 1

let audit conn ~extractor_js ~url ~viewport ~color_scheme ~output =
  let _snap =
    Capture.capture conn ~extractor_js ~url ~viewport ~color_scheme ()
  in
  let baseline_png = Capture.screenshot conn in
  let all_props = all_css_properties conn in
  let whitelist = Sosie_shared.Property_whitelist.css_names in
  let css = reset_stylesheet ~whitelist ~all_properties:all_props in
  if css = "" then
    print_endline "No blind spots: whitelist covers all browser properties."
  else begin
    (* Inject reset CSS via a <style> element — no CDP CSS domain needed. *)
    let inject_js =
      Printf.sprintf
        {|(() => {
          const s = document.createElement('style');
          s.textContent = %s;
          document.head.appendChild(s);
          document.body.offsetHeight;
        })()|}
        (Yojson.Safe.to_string (`String css))
    in
    let _inject =
      Cdp.send conn "Runtime.evaluate"
        (`Assoc [
          ("expression", `String inject_js);
          ("returnByValue", `Bool true);
        ])
    in
    let reset_png = Capture.screenshot conn in
    if String.equal baseline_png reset_png then
      print_endline "No blind spots detected."
    else begin
      let baseline_path = output ^ "-baseline.png" in
      let reset_path = output ^ "-reset.png" in
      write_bytes baseline_path baseline_png;
      write_bytes reset_path reset_png;
      if imagemagick_diff ~baseline_path ~reset_path ~output then begin
        Printf.printf "Blind spots detected. Diff image: %s\n" output;
        Sys.remove baseline_path;
        Sys.remove reset_path
      end else
        Printf.printf
          "Blind spots detected (ImageMagick not available).\n\
           Baseline: %s\nReset: %s\n"
          baseline_path reset_path
    end
  end
