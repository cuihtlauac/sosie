(** Blocking WebSocket client over Unix sockets.

    Minimal RFC 6455 implementation for CDP communication. Connects via
    TCP, performs the HTTP upgrade handshake, and provides blocking
    text-frame send/receive. Only supports the client role (masks
    outgoing frames, expects unmasked incoming frames).

    This is intentionally simple: no TLS, no extensions, no
    per-message compression. sosie only needs a local WebSocket
    connection to Chromium's CDP endpoint. *)

type t
(** An open WebSocket connection. *)

val connect : string -> t
(** [connect url] TCP-connects to the host:port in [url] and performs
    the HTTP upgrade handshake.
    @param url A [ws://host:port/path] URL.
    @raise Failure on connection or handshake error. *)

val send_text : t -> string -> unit
(** [send_text t msg] sends [msg] as a masked text frame. *)

val recv : t -> string
(** [recv t] reads the next complete data message (text or binary).
    Handles continuation frames and responds to Ping with Pong.
    Blocks until a data message arrives.
    @raise Failure on connection close or protocol error. *)

val close : t -> unit
(** [close t] sends a close frame and closes the socket. Idempotent. *)

(** {2 Low-level (exposed for testing)} *)

val write_frame : out_channel -> bool -> int -> string -> unit
(** [write_frame oc masked opcode payload] writes a single WebSocket
    frame. [masked] controls whether a 4-byte mask is applied.
    @param opcode 0x1 for text, 0x2 for binary, 0x8 for close,
      0x9 for ping, 0xA for pong. *)

val read_frame : in_channel -> int * string
(** [read_frame ic] reads a single WebSocket frame and returns
    [(opcode, payload)]. Reassembles continuation frames into a
    single message. Server-to-client frames are expected unmasked. *)
