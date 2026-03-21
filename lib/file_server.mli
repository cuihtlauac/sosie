(** Minimal static file server over Unix sockets.

    Fork-based: the server runs in a child process, the parent gets the port and
    proceeds. Same lifecycle pattern as {!Cdp_launcher.with_chromium}. *)

val with_server : root:string -> (int -> 'a) -> 'a
(** [with_server ~root f] forks a child process that serves static files from
    [root] on a free localhost port. Passes the port to [f]. Kills the child
    when [f] returns or raises.

    Supports GET requests only. Content-Type inferred from extension: [.html] ->
    [text/html], [.css] -> [text/css], [.js] -> [application/javascript], [.png]
    -> [image/png], [.woff]/[.woff2] -> [font/woff2], default
    [application/octet-stream].

    @raise Failure if the server cannot bind or fork. *)
