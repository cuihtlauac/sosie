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
let read_debug_port stderr_ic =
  let rec find_line () =
    let line = input_line stderr_ic in
    if String.starts_with ~prefix:"DevTools listening on " line then
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

(** Send a simple HTTP GET to localhost and return the JSON body.

    Chrome's CDP HTTP server has two quirks that affect parsing:

    {b No space after colon in headers.} Chrome sends
    [Content-Length:413] rather than [Content-Length: 413]. The header
    parser must match on ["content-length:"] (15 chars) and trim the
    value, not assume a space.

    {b Connection not closed promptly.} Despite [Connection: close] in
    the request, Chrome does not close the TCP connection immediately
    after sending the response body. We must parse Content-Length from
    the headers and read exactly that many bytes. *)
let http_get_json ~port path =
  let host = "127.0.0.1" in
  let addr =
    Unix.ADDR_INET (Unix.inet_addr_of_string host, port)
  in
  let ic, oc = Unix.open_connection addr in
  Fun.protect ~finally:(fun () ->
      close_in_noerr ic; close_out_noerr oc)
    (fun () ->
       let request =
         Printf.sprintf
           "GET %s HTTP/1.1\r\nHost: %s:%d\r\nConnection: close\r\n\r\n"
           path host port
       in
       output_string oc request;
       flush oc;
       let _status_line = input_line ic in
       let content_length = ref 0 in
       let rec read_headers () =
         let line = input_line ic in
         let trimmed = String.trim line in
         if trimmed = "" then ()
         else begin
           let lower = String.lowercase_ascii trimmed in
           if String.starts_with ~prefix:"content-length:" lower then begin
             let v = String.sub lower 15 (String.length lower - 15) in
             content_length := int_of_string (String.trim v)
           end;
           read_headers ()
         end
       in
       read_headers ();
       if !content_length = 0 then failwith "no Content-Length in response"
       else begin
         let body = Bytes.create !content_length in
         really_input ic body 0 !content_length;
         Yojson.Safe.from_string (Bytes.to_string body)
       end)

(** Fetch the WebSocket debugger URL for the first page target, retrying
    until Chromium's HTTP endpoint becomes available.

    {b Browser vs. page targets.} Chrome exposes two kinds of WebSocket
    endpoints. The [/json/version] endpoint returns a browser-level URL
    ([/devtools/browser/UUID]) that only supports browser-wide commands
    like [Browser.getVersion]. Page-level commands ([Runtime.evaluate],
    [Emulation.*], [Page.*]) require connecting to a page target. The
    [/json/list] endpoint returns all targets; we pick the first one
    with ["type": "page"]. *)
let fetch_page_ws_url port =
  let max_attempts = 20 in
  let rec loop attempt =
    if attempt > max_attempts then
      failwith
        (Printf.sprintf
           "could not connect to Chromium on port %d after %d attempts"
           port max_attempts)
    else
      let result =
        try
          let json = http_get_json ~port "/json/list" in
          match json with
          | `List targets ->
              List.find_map
                (fun target ->
                  match target with
                  | `Assoc fields -> (
                      match
                        ( List.assoc_opt "type" fields,
                          List.assoc_opt "webSocketDebuggerUrl" fields )
                      with
                      | Some (`String "page"), Some (`String url) -> Some url
                      | _ -> None)
                  | _ -> None)
                targets
          | _ -> None
        with _ -> None
      in
      match result with
      | Some url -> url
      | None ->
          Unix.sleepf 0.2;
          loop (attempt + 1)
  in
  loop 1

let with_chromium ?(port = 0) ?(headless = true) f =
  let chromium = find_chromium () in
  let args =
    Array.of_list
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
  let stderr_r, stderr_w = Unix.pipe () in
  let pid =
    Unix.create_process chromium args Unix.stdin Unix.stdout stderr_w
  in
  Unix.close stderr_w;
  let stderr_ic = Unix.in_channel_of_descr stderr_r in
  Fun.protect ~finally:(fun () ->
      (try Unix.kill pid Sys.sigterm with Unix.Unix_error _ -> ());
      (try ignore (Unix.waitpid [] pid) with Unix.Unix_error _ -> ());
      close_in_noerr stderr_ic)
    (fun () ->
       let actual_port = read_debug_port stderr_ic in
       let ws_url = fetch_page_ws_url actual_port in
       f ws_url)
