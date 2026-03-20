(** Unit tests for WebSocket frame serialization and parsing.

    Tests the low-level frame I/O exposed by {!Ws} for testing. *)

open Sosie

(** Write a frame to a buffer and read it back via in_channel/out_channel
    by using temporary pipes. *)
(* Write a frame in a background thread to avoid pipe buffer deadlock
   on large payloads, then read it back on the main thread. *)
let roundtrip_frame ~masked opcode payload =
  let r, w = Unix.pipe () in
  let oc = Unix.out_channel_of_descr w in
  let ic = Unix.in_channel_of_descr r in
  let _writer = Thread.create (fun () ->
    Ws.write_frame oc masked opcode payload;
    close_out oc) ()
  in
  let op, data = Ws.read_frame ic in
  close_in ic;
  (op, data)

(* -- Frame round-trip tests ----------------------------------------------- *)

let unmasked_text_frame_roundtrips () =
  let op, data = roundtrip_frame ~masked:false 0x1 "hello" in
  Alcotest.(check int) "opcode" 0x1 op;
  Alcotest.(check string) "payload" "hello" data

let masked_text_frame_roundtrips () =
  let op, data = roundtrip_frame ~masked:true 0x1 "hello" in
  Alcotest.(check int) "opcode" 0x1 op;
  Alcotest.(check string) "payload" "hello" data

let empty_payload_roundtrips () =
  let op, data = roundtrip_frame ~masked:false 0x1 "" in
  Alcotest.(check int) "opcode" 0x1 op;
  Alcotest.(check string) "payload" "" data

let binary_frame_roundtrips () =
  let payload = String.init 256 (fun i -> Char.chr (i land 0xFF)) in
  let op, data = roundtrip_frame ~masked:true 0x2 payload in
  Alcotest.(check int) "opcode" 0x2 op;
  Alcotest.(check string) "payload" payload data

let medium_payload_roundtrips () =
  (* 126..65535 byte payload uses 2-byte extended length. *)
  let payload = String.make 300 'x' in
  let op, data = roundtrip_frame ~masked:true 0x1 payload in
  Alcotest.(check int) "opcode" 0x1 op;
  Alcotest.(check int) "length" 300 (String.length data);
  Alcotest.(check string) "payload" payload data

let large_payload_roundtrips () =
  (* >65535 byte payload uses 8-byte extended length. *)
  let payload = String.make 70000 'y' in
  let op, data = roundtrip_frame ~masked:false 0x1 payload in
  Alcotest.(check int) "opcode" 0x1 op;
  Alcotest.(check int) "length" 70000 (String.length data);
  Alcotest.(check string) "payload" payload data

let close_frame_roundtrips () =
  let op, data = roundtrip_frame ~masked:true 0x8 "" in
  Alcotest.(check int) "opcode" 0x8 op;
  Alcotest.(check string) "payload" "" data

let ping_frame_roundtrips () =
  let op, data = roundtrip_frame ~masked:false 0x9 "ping" in
  Alcotest.(check int) "opcode" 0x9 op;
  Alcotest.(check string) "payload" "ping" data

let pong_frame_roundtrips () =
  let op, data = roundtrip_frame ~masked:false 0xA "pong" in
  Alcotest.(check int) "opcode" 0xA op;
  Alcotest.(check string) "payload" "pong" data

let masked_large_payload_roundtrips () =
  let payload = String.make 70000 'z' in
  let op, data = roundtrip_frame ~masked:true 0x2 payload in
  Alcotest.(check int) "opcode" 0x2 op;
  Alcotest.(check string) "payload" payload data

(* -- Test runner --------------------------------------------------------- *)

let () =
  Alcotest.run "ws"
    [
      ( "frame_roundtrip",
        [
          Alcotest.test_case "unmasked_text" `Quick
            unmasked_text_frame_roundtrips;
          Alcotest.test_case "masked_text" `Quick
            masked_text_frame_roundtrips;
          Alcotest.test_case "empty_payload" `Quick
            empty_payload_roundtrips;
          Alcotest.test_case "binary_frame" `Quick
            binary_frame_roundtrips;
          Alcotest.test_case "medium_payload_126_to_65535" `Quick
            medium_payload_roundtrips;
          Alcotest.test_case "large_payload_over_65535" `Quick
            large_payload_roundtrips;
          Alcotest.test_case "close_frame" `Quick
            close_frame_roundtrips;
          Alcotest.test_case "ping_frame" `Quick
            ping_frame_roundtrips;
          Alcotest.test_case "pong_frame" `Quick
            pong_frame_roundtrips;
          Alcotest.test_case "masked_large_payload" `Quick
            masked_large_payload_roundtrips;
        ] );
    ]
