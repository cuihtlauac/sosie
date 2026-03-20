open Cmdliner

let version = Sosie.version

(* --- Shared argument converters --- *)

let parse_viewport s =
  match String.split_on_char 'x' s with
  | [ w; h ] -> (
      match (int_of_string_opt w, int_of_string_opt h) with
      | Some w, Some h -> Ok (w, h)
      | _ -> Error (`Msg ("invalid viewport dimensions: " ^ s)))
  | _ -> Error (`Msg ("viewport must be WxH, e.g. 1920x1080: " ^ s))

let viewport_conv = Arg.conv (parse_viewport, fun fmt (w, h) ->
    Format.fprintf fmt "%dx%d" w h)

let scheme_enum = Arg.enum [ ("light", `Light); ("dark", `Dark) ]

(* --- Helpers --- *)

let read_snapshot path =
  let json = Yojson.Safe.from_file path in
  Sosie.Snapshot.of_json json

let load_config = function
  | None -> Ok Sosie.Config.default
  | Some path -> Sosie.Config.load path

let route_slug route =
  if route = "/" then "index"
  else
    let s = String.map (fun c -> if c = '/' then '-' else c) route in
    (* Strip leading dash *)
    if String.length s > 0 && s.[0] = '-' then
      String.sub s 1 (String.length s - 1)
    else s

let write_json_file path json =
  let pretty = Yojson.Safe.pretty_to_string json in
  let oc = open_out path in
  output_string oc pretty;
  output_char oc '\n';
  close_out oc

(* --- capture command --- *)

let run_capture url viewport color_scheme output =
  Sosie.Cdp_launcher.with_chromium (fun ws_url ->
    let conn = Sosie.Cdp.connect ws_url in
    let extractor_js = Sosie.Extractor_js_source.source in
    let json =
      Sosie.Capture.capture conn ~extractor_js ~url ~viewport ~color_scheme ()
    in
    let pretty = Yojson.Safe.pretty_to_string json in
    (match output with
    | None -> print_string pretty; print_newline ()
    | Some path ->
        let oc = open_out path in
        output_string oc pretty;
        output_char oc '\n';
        close_out oc);
    Sosie.Cdp.close conn)

let capture_cmd =
  let doc = "Capture a DOM snapshot from a URL." in
  let info = Cmd.info "capture" ~doc in
  let url_arg =
    Arg.(required & opt (some string) None & info [ "url" ] ~docv:"URL"
           ~doc:"Page URL to capture.")
  in
  let viewport_arg =
    Arg.(value & opt viewport_conv (1920, 1080) & info [ "viewport" ]
           ~docv:"WxH" ~doc:"Viewport dimensions (default: 1920x1080).")
  in
  let scheme_arg =
    Arg.(value & opt scheme_enum `Light & info [ "scheme" ] ~docv:"SCHEME"
           ~doc:"Color scheme: light or dark (default: light).")
  in
  let output_arg =
    Arg.(value & opt (some string) None & info [ "output"; "o" ] ~docv:"FILE"
           ~doc:"Output file (default: stdout).")
  in
  Cmd.v info Term.(const run_capture $ url_arg $ viewport_arg $ scheme_arg $ output_arg)

(* --- compare command --- *)

let run_compare baseline modified config_path =
  match load_config config_path with
  | Error msg ->
    Printf.eprintf "Error: %s\n" msg;
    exit 2
  | Ok config ->
    let snap_a = read_snapshot baseline in
    let snap_b = read_snapshot modified in
    let norm_a = Sosie.Normalize.apply config.normalize snap_a in
    let norm_b = Sosie.Normalize.apply config.normalize snap_b in
    let diffs = Sosie.Compare.compare_matched config.compare norm_a norm_b in
    if diffs = [] then (
      print_endline (Sosie.Diff_fmt.summary diffs);
      exit 0)
    else (
      print_endline (Sosie.Diff_fmt.format_diffs ~root_b:norm_b.root norm_a.root diffs);
      print_newline ();
      print_endline (Sosie.Diff_fmt.summary diffs);
      exit 1)

let compare_cmd =
  let doc = "Compare two DOM snapshots." in
  let info = Cmd.info "compare" ~doc in
  let baseline_arg =
    Arg.(required & opt (some string) None & info [ "baseline" ] ~docv:"FILE"
           ~doc:"Baseline snapshot JSON file.")
  in
  let modified_arg =
    Arg.(required & opt (some string) None & info [ "modified" ] ~docv:"FILE"
           ~doc:"Modified snapshot JSON file.")
  in
  let config_arg =
    Arg.(value & opt (some string) None & info [ "config" ] ~docv:"FILE"
           ~doc:"Config file (sosie.json). Optional.")
  in
  Cmd.v info Term.(const run_compare $ baseline_arg $ modified_arg $ config_arg)

(* --- capture-all command --- *)

let run_capture_all base_url routes viewports schemes output_dir =
  (* Ensure output dir exists *)
  (try Unix.mkdir output_dir 0o755 with Unix.Unix_error (Unix.EEXIST, _, _) -> ());
  Sosie.Cdp_launcher.with_chromium (fun ws_url ->
    let conn = Sosie.Cdp.connect ws_url in
    let extractor_js = Sosie.Extractor_js_source.source in
    List.iter (fun route ->
      List.iter (fun (vw, vh) ->
        List.iter (fun scheme ->
          let url =
            (* Strip trailing slash from base, avoid double slash *)
            let base =
              if String.length base_url > 0 &&
                 base_url.[String.length base_url - 1] = '/' then
                String.sub base_url 0 (String.length base_url - 1)
              else base_url
            in
            base ^ route
          in
          let scheme_str = match scheme with `Light -> "light" | `Dark -> "dark" in
          let filename = Printf.sprintf "%s-%dx%d-%s.json"
              (route_slug route) vw vh scheme_str in
          let path = Filename.concat output_dir filename in
          Printf.printf "Capturing %s (%dx%d, %s) -> %s\n%!" url vw vh scheme_str path;
          let json =
            Sosie.Capture.capture conn ~extractor_js ~url
              ~viewport:(vw, vh) ~color_scheme:scheme ()
          in
          write_json_file path json
        ) schemes
      ) viewports
    ) routes;
    Sosie.Cdp.close conn)

let capture_all_cmd =
  let doc = "Batch capture: routes x viewports x color schemes." in
  let info = Cmd.info "capture-all" ~doc in
  let base_url_arg =
    Arg.(required & opt (some string) None & info [ "base-url" ] ~docv:"URL"
           ~doc:"Base URL (e.g. https://example.com).")
  in
  let routes_arg =
    Arg.(value & opt (list string) ["/"] & info [ "routes" ] ~docv:"ROUTES"
           ~doc:"Comma-separated routes (default: /).")
  in
  let viewports_arg =
    Arg.(value & opt (list viewport_conv) [(1920, 1080)] & info [ "viewports" ]
           ~docv:"WxH,..." ~doc:"Comma-separated viewports (default: 1920x1080).")
  in
  let schemes_arg =
    Arg.(value & opt (list scheme_enum) [`Light] & info [ "schemes" ]
           ~docv:"SCHEMES" ~doc:"Comma-separated color schemes (default: light).")
  in
  let output_arg =
    Arg.(required & opt (some string) None & info [ "output"; "o" ] ~docv:"DIR"
           ~doc:"Output directory for snapshot files.")
  in
  Cmd.v info Term.(const run_capture_all $ base_url_arg $ routes_arg
                   $ viewports_arg $ schemes_arg $ output_arg)

(* Main command *)

let main_cmd =
  let doc =
    "DOM equivalence checker for UI-conservative HTML/CSS refactoring"
  in
  let info = Cmd.info "sosie" ~version ~doc in
  Cmd.group info [ capture_cmd; compare_cmd; capture_all_cmd ]

let () = exit (Cmd.eval main_cmd)
