(** Chrome DevTools Protocol bridge.

    Connects to a Chromium instance via CDP over WebSocket and provides
    a typed interface for sending commands and receiving responses.

    The CDP protocol is JSON-RPC-like over WebSocket: each request has an
    [id], [method], and [params]; responses echo the [id] with either
    [result] or [error]. Events have [method] and [params] but no [id].

    See {{: https://chromedevtools.github.io/devtools-protocol/ }
    Chrome DevTools Protocol documentation}. *)

type connection
(** An active CDP WebSocket connection. *)

val connect : sw:Eio.Switch.t -> net:Eio_unix.Net.t -> string -> connection
(** [connect ~sw ~net url] connects to the CDP WebSocket endpoint at [url].
    The connection is closed when [sw] is released.
    @param url The WebSocket debugger URL
      (e.g. ["ws://127.0.0.1:9222/devtools/page/..."]).
    @raise Failure if the connection cannot be established or the
      WebSocket handshake fails. *)

val send : connection -> string -> Yojson.Safe.t -> Yojson.Safe.t
(** [send conn method_ params] sends a CDP command and waits for the
    response. Returns the ["result"] field from the response.
    @param method_ The CDP method name (e.g. ["Runtime.evaluate"]).
    @param params The parameters as JSON.
    @raise Failure if the CDP response contains an error. *)

val close : connection -> unit
(** Close the WebSocket connection. *)

val evaluate_js : connection -> string -> Yojson.Safe.t
(** [evaluate_js conn expr] evaluates a JavaScript expression via
    [Runtime.evaluate] and returns the result value.
    Convenience wrapper around {!send}.
    @raise Failure if evaluation fails or the result contains an
      exception. *)

(** {2 Low-level serialization (exposed for testing)} *)

val make_request : int -> string -> Yojson.Safe.t -> Yojson.Safe.t
(** [make_request id method_ params] builds a CDP JSON-RPC request
    object with the given [id], [method], and [params]. *)

val parse_response :
  Yojson.Safe.t -> (Yojson.Safe.t, Yojson.Safe.t) result
(** [parse_response json] extracts the ["result"] or ["error"] from a
    CDP response. Returns [Ok result] on success, [Error err] if the
    response contains an error or is malformed. *)

val response_id : Yojson.Safe.t -> int option
(** [response_id json] extracts the ["id"] field from a CDP message.
    Returns [None] for events (which have no ["id"]). *)

val is_event : Yojson.Safe.t -> bool
(** [is_event json] returns [true] if the JSON message is a CDP event
    (has ["method"] but no ["id"]). *)
