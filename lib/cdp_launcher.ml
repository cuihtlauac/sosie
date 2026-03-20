(** Launch and manage headless Chromium instances for CDP.

    See {!Cdp_launcher} (the .mli) for the public interface
    documentation. *)

let chromium_paths =
  [
    "/usr/bin/chromium";
    "/usr/bin/chromium-browser";
    "/usr/bin/google-chrome";
    "/usr/bin/google-chrome-stable";
    "/snap/bin/chromium";
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
    "/Applications/Chromium.app/Contents/MacOS/Chromium";
  ]

let find_chromium () =
  match Sys.getenv_opt "SOSIE_CHROMIUM_PATH" with
  | Some path ->
      if Sys.file_exists path then path
      else failwith ("SOSIE_CHROMIUM_PATH does not exist: " ^ path)
  | None -> (
      match List.find_opt Sys.file_exists chromium_paths with
      | Some path -> path
      | None ->
          failwith
            "No Chromium binary found. Set SOSIE_CHROMIUM_PATH or install \
             Chromium.")

(** Read the actual listening port from Chromium's stderr output.
    Chromium prints a line like:
    [DevTools listening on ws://127.0.0.1:PORT/devtools/browser/UUID] *)
let read_debug_port stderr_r =
  let buf = Eio.Buf_read.of_flow ~max_size:(64 * 1024) stderr_r in
  let rec find_line () =
    let line = Eio.Buf_read.line buf in
    if String.length line > 0
       && String.starts_with ~prefix:"DevTools listening on " line
    then
      (* Extract port from ws://127.0.0.1:PORT/... *)
      let url_start = String.length "DevTools listening on " in
      let url = String.sub line url_start (String.length line - url_start) in
      let rest =
        if String.starts_with ~prefix:"ws://" url then
          String.sub url 5 (String.length url - 5)
        else url
      in
      match String.index_opt rest ':' with
      | None -> failwith ("cannot parse port from DevTools URL: " ^ url)
      | Some colon ->
          let after_colon =
            String.sub rest (colon + 1) (String.length rest - colon - 1)
          in
          let port_str =
            match String.index_opt after_colon '/' with
            | None -> after_colon
            | Some slash -> String.sub after_colon 0 slash
          in
          int_of_string port_str
    else find_line ()
  in
  find_line ()

(** Fetch the WebSocket debugger URL from Chromium's /json/version HTTP
    endpoint using a raw HTTP/1.1 request over Eio. *)
let fetch_ws_url ~sw ~net port =
  let addr =
    `Tcp (Eio.Net.Ipaddr.V4.loopback, port)
  in
  let socket = Eio.Net.connect ~sw net addr in
  let request =
    Printf.sprintf
      "GET /json/version HTTP/1.1\r\nHost: 127.0.0.1:%d\r\nConnection: \
       close\r\n\r\n"
      port
  in
  Eio.Flow.copy_string request socket;
  Eio.Flow.shutdown socket `Send;
  let buf = Eio.Buf_read.of_flow ~max_size:(64 * 1024) socket in
  let response = Eio.Buf_read.take_all buf in
  (* Find the JSON body after the HTTP headers (separated by \r\n\r\n). *)
  let body =
    match String.split_on_char '\n' response with
    | _ ->
        let sep = "\r\n\r\n" in
        let sep_len = String.length sep in
        let rec find_body pos =
          if pos + sep_len > String.length response then
            failwith "no HTTP body in /json/version response"
          else if String.sub response pos sep_len = sep then
            String.sub response (pos + sep_len)
              (String.length response - pos - sep_len)
          else find_body (pos + 1)
        in
        find_body 0
  in
  let json = Yojson.Safe.from_string body in
  match json with
  | `Assoc fields -> (
      match List.assoc_opt "webSocketDebuggerUrl" fields with
      | Some (`String url) -> url
      | _ ->
          failwith
            "webSocketDebuggerUrl not found in /json/version response")
  | _ -> failwith "/json/version did not return a JSON object"

let launch ~sw ~proc_mgr ~net ?(port = 0) ?(headless = true) () =
  let chromium = find_chromium () in
  let stderr_r, stderr_w = Eio.Process.pipe ~sw proc_mgr in
  let args =
    [
      chromium;
      Printf.sprintf "--remote-debugging-port=%d" port;
      (if headless then "--headless=new" else "--no-first-run");
      "--no-first-run";
      "--no-default-browser-check";
      "--disable-gpu";
      "--disable-extensions";
      "--disable-background-networking";
      "about:blank";
    ]
  in
  let _proc =
    Eio.Process.spawn ~sw proc_mgr ~stderr:stderr_w args
  in
  Eio.Flow.close stderr_w;
  let actual_port = read_debug_port stderr_r in
  fetch_ws_url ~sw ~net actual_port
