(** Minimal static file server over Unix sockets.

    See {!File_server} (the .mli) for the public interface documentation. *)

let content_type_of path =
  if Filename.check_suffix path ".html" then "text/html; charset=utf-8"
  else if
    (* XHTML must be served as XML: under text/html the parser treats
       <![CDATA[...]]> in <style> as CSS garbage and drops the rules,
       so test AND reference render unstyled — silently equal. Found by
       a mismatch reftest (t31-color-text-a) reporting Equivalent. *)
    Filename.check_suffix path ".xhtml" || Filename.check_suffix path ".xht"
  then "application/xhtml+xml; charset=utf-8"
  else if Filename.check_suffix path ".css" then "text/css; charset=utf-8"
  else if Filename.check_suffix path ".js" then
    "application/javascript; charset=utf-8"
  else if Filename.check_suffix path ".json" then
    "application/json; charset=utf-8"
  else if Filename.check_suffix path ".png" then "image/png"
  else if
    Filename.check_suffix path ".jpg" || Filename.check_suffix path ".jpeg"
  then "image/jpeg"
  else if Filename.check_suffix path ".svg" then "image/svg+xml"
  else if Filename.check_suffix path ".woff" then "font/woff"
  else if Filename.check_suffix path ".woff2" then "font/woff2"
  else if Filename.check_suffix path ".ttf" then "font/ttf"
  else "application/octet-stream"

(** Read the first line of an HTTP request and extract the GET path.
    @return [Some path] or [None] if not a valid GET request. *)
let parse_get_path ic =
  try
    let line = input_line ic in
    let trimmed = String.trim line in
    if String.starts_with ~prefix:"GET " trimmed then
      let rest = String.sub trimmed 4 (String.length trimmed - 4) in
      match String.index_opt rest ' ' with
      | Some sp -> Some (String.sub rest 0 sp)
      | None -> Some rest
    else None
  with End_of_file -> None

(** Resolve a URL path against the server root, rejecting traversal. *)
let resolve_path ~root url_path =
  (* Percent-decode is not needed for WPT paths; just reject ".." *)
  let segments = String.split_on_char '/' url_path in
  if List.exists (fun s -> s = "..") segments then None
  else
    let rel =
      if String.starts_with ~prefix:"/" url_path then
        String.sub url_path 1 (String.length url_path - 1)
      else url_path
    in
    let full = Filename.concat root rel in
    if Sys.file_exists full && not (Sys.is_directory full) then Some full
    else None

(** Read file contents as bytes. *)
let read_file path =
  let ic = open_in_bin path in
  Fun.protect
    ~finally:(fun () -> close_in_noerr ic)
    (fun () ->
      let len = in_channel_length ic in
      let buf = Bytes.create len in
      really_input ic buf 0 len;
      Bytes.to_string buf)

(** Send an HTTP response on a file descriptor. *)
let send_response fd ~status ~content_type ~body =
  let header =
    Printf.sprintf
      "HTTP/1.1 %s\r\n\
       Content-Length: %d\r\n\
       Content-Type: %s\r\n\
       Connection: close\r\n\
       \r\n"
      status (String.length body) content_type
  in
  let msg = header ^ body in
  let bytes = Bytes.of_string msg in
  let len = Bytes.length bytes in
  let rec write_all off =
    if off < len then
      let n = Unix.write fd bytes off (len - off) in
      write_all (off + n)
  in
  write_all 0

(** Handle a single client connection. *)
let handle_client ~root client_fd =
  let ic = Unix.in_channel_of_descr client_fd in
  (match parse_get_path ic with
  | None ->
      send_response client_fd ~status:"400 Bad Request"
        ~content_type:"text/plain" ~body:"Bad Request"
  | Some url_path -> (
      (* Consume remaining headers *)
      (try
         while true do
           let line = input_line ic in
           if String.trim line = "" then raise Exit
         done
       with Exit | End_of_file -> ());
      match resolve_path ~root url_path with
      | None ->
          send_response client_fd ~status:"404 Not Found"
            ~content_type:"text/plain"
            ~body:(Printf.sprintf "Not Found: %s" url_path)
      | Some file_path ->
          let body = read_file file_path in
          let ct = content_type_of file_path in
          send_response client_fd ~status:"200 OK" ~content_type:ct ~body));
  Unix.close client_fd

(** Server accept loop (runs in child process, never returns). The [exit 0]
    after the infinite loop is unreachable but gives the function return type
    [unit] without triggering warning 21. *)
let[@warning "-21"] serve_forever ~root listen_fd =
  while true do
    let client_fd, _addr = Unix.accept listen_fd in
    try handle_client ~root client_fd
    with exn ->
      (try Unix.close client_fd with Unix.Unix_error _ -> ());
      Printf.eprintf "file_server: %s\n%!" (Printexc.to_string exn)
  done;
  exit 0

let with_server ~root f =
  let listen_fd = Unix.socket PF_INET SOCK_STREAM 0 in
  Unix.setsockopt listen_fd SO_REUSEADDR true;
  Unix.bind listen_fd (ADDR_INET (Unix.inet_addr_loopback, 0));
  Unix.listen listen_fd 8;
  let port =
    match Unix.getsockname listen_fd with
    | ADDR_INET (_, p) -> p
    | ADDR_UNIX _ -> failwith "file_server: unexpected unix socket"
  in
  let pipe_r, pipe_w = Unix.pipe () in
  let pid = Unix.fork () in
  if pid = 0 then begin
    (* Child: close pipe read end, signal ready, serve forever *)
    Unix.close pipe_r;
    let msg = string_of_int port in
    ignore (Unix.write_substring pipe_w msg 0 (String.length msg));
    Unix.close pipe_w;
    serve_forever ~root listen_fd
  end
  else begin
    (* Parent: close pipe write end, wait for child to be ready *)
    Unix.close pipe_w;
    let buf = Bytes.create 16 in
    let n = Unix.read pipe_r buf 0 16 in
    Unix.close pipe_r;
    Unix.close listen_fd;
    let _child_port = int_of_string (Bytes.sub_string buf 0 n) in
    Fun.protect
      ~finally:(fun () ->
        (try Unix.kill pid Sys.sigterm with Unix.Unix_error _ -> ());
        try ignore (Unix.waitpid [] pid) with Unix.Unix_error _ -> ())
      (fun () -> f port)
  end
