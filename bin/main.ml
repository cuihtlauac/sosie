open Cmdliner

let version = Sosie.version

(* Subcommands *)

let capture_cmd =
  let doc = "Capture a DOM snapshot from a URL." in
  let info = Cmd.info "capture" ~doc in
  Cmd.v info
    Term.(const (fun () -> failwith "capture: not yet implemented") $ const ())

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
