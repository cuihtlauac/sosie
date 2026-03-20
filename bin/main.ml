open Cmdliner

let version = Sosie.version

(* Subcommands *)

let parse_viewport s =
  match String.split_on_char 'x' s with
  | [ w; h ] -> (
      match (int_of_string_opt w, int_of_string_opt h) with
      | Some w, Some h -> Ok (w, h)
      | _ -> Error (`Msg ("invalid viewport dimensions: " ^ s)))
  | _ -> Error (`Msg ("viewport must be WxH, e.g. 1920x1080: " ^ s))

let viewport_conv = Arg.conv (parse_viewport, fun fmt (w, h) ->
    Format.fprintf fmt "%dx%d" w h)

let run_capture url viewport color_scheme output =
  Eio_main.run @@ fun env ->
  Eio.Switch.run @@ fun sw ->
  let net = Eio.Stdenv.net env in
  let proc_mgr = Eio.Stdenv.process_mgr env in
  let clock = Eio.Stdenv.clock env in
  let ws_url = Sosie.Cdp_launcher.launch ~sw ~proc_mgr ~net ~clock () in
  let conn = Sosie.Cdp.connect ~sw ~net ws_url in
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
  Sosie.Cdp.close conn

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
    let scheme_enum = Arg.enum [ ("light", `Light); ("dark", `Dark) ] in
    Arg.(value & opt scheme_enum `Light & info [ "scheme" ] ~docv:"SCHEME"
           ~doc:"Color scheme: light or dark (default: light).")
  in
  let output_arg =
    Arg.(value & opt (some string) None & info [ "output"; "o" ] ~docv:"FILE"
           ~doc:"Output file (default: stdout).")
  in
  Cmd.v info Term.(const run_capture $ url_arg $ viewport_arg $ scheme_arg $ output_arg)

let compare_cmd =
  let doc = "Compare two DOM snapshots." in
  let info = Cmd.info "compare" ~doc in
  Cmd.v info
    Term.(const (fun () -> failwith "compare: not yet implemented") $ const ())

(* Main command *)

let main_cmd =
  let doc =
    "DOM equivalence checker for UI-conservative HTML/CSS refactoring"
  in
  let info = Cmd.info "sosie" ~version ~doc in
  Cmd.group info [ capture_cmd; compare_cmd ]

let () = exit (Cmd.eval main_cmd)
