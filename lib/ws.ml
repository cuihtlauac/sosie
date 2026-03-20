(** Blocking WebSocket client over Unix sockets.

    See {!Ws} (the .mli) for the public interface documentation. *)

type t = {
  ic : in_channel;
  oc : out_channel;
  mutable closed : bool;
}

(* -- URL parsing ---------------------------------------------------------- *)

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

(* -- WebSocket handshake (RFC 6455 Section 4) ----------------------------- *)

(** The magic GUID concatenated with the client nonce, then SHA-1'd and
    base64'd, to produce the expected Sec-WebSocket-Accept value. *)
let ws_magic = "258EAFA5-E914-47DA-95CA-5AB9DC11B85A"

let expected_accept nonce =
  let hash = Digestif.SHA1.digest_string (nonce ^ ws_magic) in
  Base64.encode_exn (Digestif.SHA1.to_raw_string hash)

let handshake ic oc host resource =
  let nonce_bytes = Bytes.create 16 in
  for i = 0 to 15 do
    Bytes.set_uint8 nonce_bytes i (Random.int 256)
  done;
  let nonce = Base64.encode_exn (Bytes.to_string nonce_bytes) in
  Printf.fprintf oc
    "GET %s HTTP/1.1\r\n\
     Host: %s\r\n\
     Upgrade: websocket\r\n\
     Connection: Upgrade\r\n\
     Sec-WebSocket-Key: %s\r\n\
     Sec-WebSocket-Version: 13\r\n\
     \r\n"
    resource host nonce;
  flush oc;
  (* Read status line. *)
  let status_line = input_line ic in
  if not (String.starts_with ~prefix:"HTTP/1.1 101" status_line) then
    failwith ("WebSocket handshake failed: " ^ String.trim status_line);
  (* Read headers until blank line. *)
  let accept = ref "" in
  let rec read_headers () =
    let line = String.trim (input_line ic) in
    if line = "" then ()
    else begin
      let lower = String.lowercase_ascii line in
      if String.starts_with ~prefix:"sec-websocket-accept:" lower then begin
        let v = String.sub line 22 (String.length line - 22) in
        accept := String.trim v
      end;
      read_headers ()
    end
  in
  read_headers ();
  let expected = expected_accept nonce in
  if !accept <> expected then
    failwith
      (Printf.sprintf "WebSocket accept mismatch: got %S, expected %S"
         !accept expected)

(* -- Frame I/O (RFC 6455 Section 5) --------------------------------------- *)

let write_frame oc masked opcode payload =
  let len = String.length payload in
  let b0 = 0x80 lor (opcode land 0x0F) in (* FIN=1 *)
  let mask_bit = if masked then 0x80 else 0 in
  output_byte oc b0;
  if len < 126 then
    output_byte oc (mask_bit lor len)
  else if len < 65536 then begin
    output_byte oc (mask_bit lor 126);
    output_byte oc ((len lsr 8) land 0xFF);
    output_byte oc (len land 0xFF)
  end else begin
    output_byte oc (mask_bit lor 127);
    (* 8-byte extended length, big-endian. *)
    for i = 7 downto 0 do
      output_byte oc ((len lsr (i * 8)) land 0xFF)
    done
  end;
  if masked then begin
    let mask = Bytes.create 4 in
    for i = 0 to 3 do
      Bytes.set_uint8 mask i (Random.int 256)
    done;
    output_bytes oc mask;
    let out = Bytes.of_string payload in
    for i = 0 to len - 1 do
      let b = Char.code (Bytes.get out i) in
      let m = Bytes.get_uint8 mask (i mod 4) in
      Bytes.set_uint8 out i (b lxor m)
    done;
    output_bytes oc out
  end else
    output_string oc payload;
  flush oc

let read_exact ic n =
  let buf = Bytes.create n in
  really_input ic buf 0 n;
  buf

let read_frame ic =
  let hdr = read_exact ic 2 in
  let b0 = Bytes.get_uint8 hdr 0 in
  let b1 = Bytes.get_uint8 hdr 1 in
  let fin = b0 land 0x80 <> 0 in
  let opcode = b0 land 0x0F in
  let has_mask = b1 land 0x80 <> 0 in
  let len0 = b1 land 0x7F in
  let len =
    if len0 < 126 then len0
    else if len0 = 126 then begin
      let ext = read_exact ic 2 in
      (Bytes.get_uint8 ext 0 lsl 8) lor Bytes.get_uint8 ext 1
    end else begin
      (* 8-byte extended length. *)
      let ext = read_exact ic 8 in
      let len = ref 0 in
      for i = 0 to 7 do
        len := (!len lsl 8) lor Bytes.get_uint8 ext i
      done;
      !len
    end
  in
  let mask_key =
    if has_mask then Some (read_exact ic 4) else None
  in
  let payload = read_exact ic len in
  (match mask_key with
   | Some mask ->
       for i = 0 to len - 1 do
         let b = Bytes.get_uint8 payload i in
         let m = Bytes.get_uint8 mask (i mod 4) in
         Bytes.set_uint8 payload i (b lxor m)
       done
   | None -> ());
  if fin then
    (opcode, Bytes.to_string payload)
  else begin
    (* Continuation frames: accumulate until FIN. *)
    let buf = Buffer.create (len * 2) in
    Buffer.add_bytes buf payload;
    let rec loop () =
      let cont_hdr = read_exact ic 2 in
      let cb0 = Bytes.get_uint8 cont_hdr 0 in
      let cb1 = Bytes.get_uint8 cont_hdr 1 in
      let cont_fin = cb0 land 0x80 <> 0 in
      let cont_mask = cb1 land 0x80 <> 0 in
      let clen0 = cb1 land 0x7F in
      let clen =
        if clen0 < 126 then clen0
        else if clen0 = 126 then begin
          let ext = read_exact ic 2 in
          (Bytes.get_uint8 ext 0 lsl 8) lor Bytes.get_uint8 ext 1
        end else begin
          let ext = read_exact ic 8 in
          let l = ref 0 in
          for i = 0 to 7 do
            l := (!l lsl 8) lor Bytes.get_uint8 ext i
          done;
          !l
        end
      in
      let cmask_key =
        if cont_mask then Some (read_exact ic 4) else None
      in
      let cpayload = read_exact ic clen in
      (match cmask_key with
       | Some mask ->
           for i = 0 to clen - 1 do
             let b = Bytes.get_uint8 cpayload i in
             let m = Bytes.get_uint8 mask (i mod 4) in
             Bytes.set_uint8 cpayload i (b lxor m)
           done
       | None -> ());
      Buffer.add_bytes buf cpayload;
      if cont_fin then ()
      else loop ()
    in
    loop ();
    (opcode, Buffer.contents buf)
  end

(* -- Public API ----------------------------------------------------------- *)

let connect url =
  let host, port, resource = parse_ws_url url in
  let addr =
    Unix.ADDR_INET
      ((Unix.gethostbyname host).Unix.h_addr_list.(0), port)
  in
  let ic, oc = Unix.open_connection addr in
  handshake ic oc host resource;
  { ic; oc; closed = false }

let send_text t msg =
  if t.closed then failwith "WebSocket: send on closed connection";
  write_frame t.oc true 0x1 msg

let rec recv t =
  if t.closed then failwith "WebSocket: recv on closed connection";
  let opcode, payload = read_frame t.ic in
  match opcode with
  | 0x1 | 0x2 -> payload           (* text or binary *)
  | 0x9 ->                          (* ping -> pong *)
      write_frame t.oc true 0xA payload;
      recv t
  | 0x8 ->                          (* close *)
      t.closed <- true;
      (try write_frame t.oc true 0x8 "" with _ -> ());
      failwith "WebSocket: connection closed by server"
  | _ -> recv t                     (* ignore unknown opcodes *)

let close t =
  if not t.closed then begin
    t.closed <- true;
    (try write_frame t.oc true 0x8 "" with _ -> ());
    (try close_in_noerr t.ic; close_out_noerr t.oc with _ -> ())
  end
