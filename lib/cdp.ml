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

(* -- Connection ----------------------------------------------------------- *)

type connection = {
  ws : Ws.t;
  mutable next_id : int;
  events : Yojson.Safe.t Queue.t;
}

let connect url =
  let ws = Ws.connect url in
  { ws; next_id = 1; events = Queue.create () }

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

(** Receive messages until we get a response matching [target_id].
    Stash events in the queue. *)
let recv_until_id conn target_id =
  let rec loop () =
    let msg = Ws.recv conn.ws in
    let json = Yojson.Safe.from_string msg in
    match response_id json with
    | Some id when id = target_id -> json
    | _ ->
        Queue.push json conn.events;
        loop ()
  in
  loop ()

let send conn method_ params =
  let id = conn.next_id in
  conn.next_id <- id + 1;
  let request = make_request id method_ params in
  Ws.send_text conn.ws (Yojson.Safe.to_string request);
  let response = recv_until_id conn id in
  match parse_response response with
  | Ok result -> result
  | Error err ->
      failwith
        (Printf.sprintf "CDP error (request %d): %s" id
           (Yojson.Safe.to_string err))

let close conn = Ws.close conn.ws

let wait_event conn method_ ?(timeout = 30.0) () =
  (* First check events already in the queue. *)
  let found = ref None in
  let keep = Queue.create () in
  while not (Queue.is_empty conn.events) do
    let ev = Queue.pop conn.events in
    match event_method ev with
    | Some m when m = method_ && Option.is_none !found ->
        found := Some ev
    | _ -> Queue.push ev keep
  done;
  Queue.transfer keep conn.events;
  match !found with
  | Some ev -> event_params ev
  | None ->
      (* Set a receive timeout and read until we find the event. *)
      let deadline = Unix.gettimeofday () +. timeout in
      let rec loop () =
        let remaining = deadline -. Unix.gettimeofday () in
        if remaining <= 0.0 then
          failwith
            (Printf.sprintf "timeout waiting for CDP event: %s" method_);
        let msg = Ws.recv conn.ws in
        let json = Yojson.Safe.from_string msg in
        match event_method json with
        | Some m when m = method_ -> event_params json
        | _ ->
            Queue.push json conn.events;
            loop ()
      in
      loop ()

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
