(** Chrome DevTools Protocol bridge.

    See {!Cdp} (the .mli) for the public interface documentation. *)

(* -- Pure serialization/parsing functions -------------------------------- *)

let make_request id method_ params =
  `Assoc
    [ ("id", `Int id); ("method", `String method_); ("params", params) ]

let parse_response json =
  match json with
  | `Assoc fields -> (
      match List.assoc_opt "error" fields with
      | Some err -> Error err
      | None -> (
          match List.assoc_opt "result" fields with
          | Some result -> Ok result
          | None -> Error (`String "response has neither result nor error")))
  | _ -> Error (`String "expected JSON object")

let response_id json =
  match json with
  | `Assoc fields -> (
      match List.assoc_opt "id" fields with
      | Some (`Int id) -> Some id
      | _ -> None)
  | _ -> None

let is_event json =
  match json with
  | `Assoc fields ->
      List.mem_assoc "method" fields && not (List.mem_assoc "id" fields)
  | _ -> false

(* -- WebSocket URL parsing ----------------------------------------------- *)

let parse_ws_url url =
  let rest =
    match String.starts_with ~prefix:"ws://" url with
    | true -> String.sub url 5 (String.length url - 5)
    | false -> failwith ("expected ws:// URL: " ^ url)
  in
  let slash_pos =
    match String.index_opt rest '/' with
    | Some i -> i
    | None -> String.length rest
  in
  let host_port = String.sub rest 0 slash_pos in
  let resource =
    if slash_pos < String.length rest then
      String.sub rest slash_pos (String.length rest - slash_pos)
    else "/"
  in
  let colon_pos =
    match String.index_opt host_port ':' with
    | Some i -> i
    | None -> failwith ("no port in WebSocket URL: " ^ url)
  in
  let host = String.sub host_port 0 colon_pos in
  let port_str =
    String.sub host_port (colon_pos + 1)
      (String.length host_port - colon_pos - 1)
  in
  let port =
    match int_of_string_opt port_str with
    | Some p -> p
    | None -> failwith ("invalid port in WebSocket URL: " ^ port_str)
  in
  (host, port, resource)

(* -- WebSocket connection ------------------------------------------------ *)

type connection = {
  wsd : Httpun_ws.Wsd.t;
  mutable next_id : int;
  pending : (int, Yojson.Safe.t Eio.Promise.u) Hashtbl.t;
  events : Yojson.Safe.t Queue.t;
  mutex : Eio.Mutex.t;
}

(** Dispatch an incoming CDP message to the correct pending request or
    event queue. *)
let dispatch conn msg =
  let json = Yojson.Safe.from_string msg in
  match response_id json with
  | Some id -> (
      match Hashtbl.find_opt conn.pending id with
      | Some resolver ->
          Hashtbl.remove conn.pending id;
          Eio.Promise.resolve resolver json
      | None ->
          (* Response for unknown id — treat as event. *)
          Queue.push json conn.events)
  | None -> Queue.push json conn.events

(** Generate a random Base64-encoded nonce for the WebSocket handshake. *)
let generate_nonce () =
  let buf = Bytes.create 16 in
  for i = 0 to 15 do
    Bytes.set_uint8 buf i (Random.int 256)
  done;
  Base64.encode_exn (Bytes.to_string buf)

let connect ~sw ~net url =
  let host, port, resource = parse_ws_url url in
  let addrs = Eio.Net.getaddrinfo_stream net host ~service:(string_of_int port) in
  let addr =
    match addrs with
    | addr :: _ -> addr
    | [] -> failwith ("cannot resolve host: " ^ host)
  in
  let socket = Eio.Net.connect ~sw net addr in
  (* Promise to receive the Wsd.t from the websocket_handler callback. *)
  let conn_promise, conn_resolver = Eio.Promise.create () in
  let pending = Hashtbl.create 16 in
  let events = Queue.create () in
  let websocket_handler wsd =
    let conn =
      { wsd; next_id = 1; pending; events; mutex = Eio.Mutex.create () }
    in
    Eio.Promise.resolve conn_resolver conn;
    let frame ~opcode:_ ~is_fin:_ ~len:_ payload =
      let buf = Buffer.create 256 in
      let rec drain () =
        Httpun_ws.Payload.schedule_read payload
          ~on_eof:(fun () -> dispatch conn (Buffer.contents buf))
          ~on_read:(fun bs ~off ~len ->
            let chunk = Bytes.create len in
            Bigstringaf.blit_to_bytes bs ~src_off:off chunk ~dst_off:0 ~len;
            Buffer.add_bytes buf chunk;
            drain ())
      in
      drain ()
    in
    let eof ?error:_ () = () in
    { Httpun_ws.Websocket_connection.frame; eof }
  in
  let error_handler err =
    let msg =
      match err with
      | `Handshake_failure (resp, _body) ->
          Printf.sprintf "WebSocket handshake failed: %s"
            (Httpun.Status.to_string resp.Httpun.Response.status)
      | `Exn exn -> Printf.sprintf "WebSocket error: %s" (Printexc.to_string exn)
      | `Invalid_response_body_length _ ->
          "WebSocket error: invalid response body length"
      | `Malformed_response msg ->
          Printf.sprintf "WebSocket error: malformed response: %s" msg
    in
    failwith msg
  in
  let _client =
    Httpun_ws_eio.Client.connect ~config:(Httpun.Config.default) ~sw
      ~nonce:(generate_nonce ()) ~host ~port ~resource ~error_handler
      ~websocket_handler socket
  in
  Eio.Promise.await conn_promise

let send conn method_ params =
  let id, promise =
    Eio.Mutex.use_rw ~protect:true conn.mutex (fun () ->
        let id = conn.next_id in
        conn.next_id <- id + 1;
        let promise, resolver = Eio.Promise.create () in
        Hashtbl.add conn.pending id resolver;
        let request = make_request id method_ params in
        let msg = Yojson.Safe.to_string request in
        let payload = Bytes.of_string msg in
        Httpun_ws.Wsd.send_bytes conn.wsd ~kind:`Text payload ~off:0
          ~len:(Bytes.length payload);
        (id, promise))
  in
  let response = Eio.Promise.await promise in
  match parse_response response with
  | Ok result -> result
  | Error err ->
      failwith
        (Printf.sprintf "CDP error (request %d): %s" id
           (Yojson.Safe.to_string err))

let close conn = Httpun_ws.Wsd.close conn.wsd

let event_method json =
  match json with
  | `Assoc fields -> (
      match List.assoc_opt "method" fields with
      | Some (`String m) -> Some m
      | _ -> None)
  | _ -> None

let event_params json =
  match json with
  | `Assoc fields -> (
      match List.assoc_opt "params" fields with
      | Some p -> p
      | None -> `Assoc [])
  | _ -> `Assoc []

let wait_event conn method_ ?(timeout = 30.0) () =
  let deadline = Unix.gettimeofday () +. timeout in
  let rec poll () =
    (* Check events already in the queue. *)
    let found = ref None in
    let keep = Queue.create () in
    Eio.Mutex.use_rw ~protect:true conn.mutex (fun () ->
        while not (Queue.is_empty conn.events) do
          let ev = Queue.pop conn.events in
          match event_method ev with
          | Some m when m = method_ && Option.is_none !found ->
              found := Some ev
          | _ -> Queue.push ev keep
        done;
        Queue.transfer keep conn.events);
    match !found with
    | Some ev -> event_params ev
    | None ->
        if Unix.gettimeofday () >= deadline then
          failwith (Printf.sprintf "timeout waiting for CDP event: %s" method_)
        else begin
          (* Yield briefly to allow the WebSocket reader fiber to run. *)
          Eio.Fiber.yield ();
          poll ()
        end
  in
  poll ()

let evaluate_js conn expr =
  let params =
    `Assoc
      [
        ("expression", `String expr);
        ("returnByValue", `Bool true);
        ("awaitPromise", `Bool false);
      ]
  in
  let result = send conn "Runtime.evaluate" params in
  match result with
  | `Assoc fields -> (
      match List.assoc_opt "exceptionDetails" fields with
      | Some details ->
          failwith
            (Printf.sprintf "JS evaluation exception: %s"
               (Yojson.Safe.to_string details))
      | None -> (
          match List.assoc_opt "result" fields with
          | Some (`Assoc result_fields) -> (
              match List.assoc_opt "value" result_fields with
              | Some value -> value
              | None -> `Null)
          | Some other -> other
          | None -> `Null))
  | other -> other
