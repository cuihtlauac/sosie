(** High-level DOM snapshot capture via CDP.

    Orchestrates the full CDP conversation to capture a page snapshot:
    viewport configuration, navigation, page load waiting, extractor
    injection, and snapshot extraction. The JS extractor source is
    injected into the page and executed to produce the snapshot JSON.

    See the design doc section on CDP conversation flow. *)

val capture :
  Cdp.connection ->
  extractor_js:string ->
  url:string ->
  ?viewport:(int * int) ->
  ?color_scheme:[ `Light | `Dark ] ->
  unit ->
  Yojson.Safe.t
(** [capture conn ~extractor_js ~url ()] navigates to [url] and
    returns the snapshot JSON produced by the extractor.

    @param extractor_js The full source of the JSOO extractor
      (extractor.bc.js), which must export [sosieCapture].
    @param viewport Width and height in pixels (default: [(1920, 1080)]).
    @param color_scheme Emulated color scheme (default: [`Light]).
    @raise Failure if navigation fails, the page doesn't load within
      30 seconds, or the extractor returns an error. *)

val extract : Cdp.connection -> extractor_js:string -> Yojson.Safe.t
(** [extract conn ~extractor_js] injects the extractor into the
    already-loaded page and runs it. Does NOT navigate — the caller
    must ensure the page is loaded.

    @param extractor_js The full source of the JSOO extractor.
    @raise Failure if the extractor throws or returns no value. *)

val screenshot : Cdp.connection -> string
(** Take a PNG screenshot of the current page. Returns raw PNG bytes
    (decoded from the base64 response).
    @raise Failure if the CDP call fails or the response is malformed. *)
