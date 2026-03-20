(** Launch and manage headless Chromium instances for CDP.

    Provides utilities to locate a Chromium binary and launch it with
    remote debugging enabled, returning the WebSocket URL for CDP
    connections. *)

val find_chromium : unit -> string
(** [find_chromium ()] returns the path to a Chromium binary.
    Checks the [SOSIE_CHROMIUM_PATH] environment variable first, then
    common installation paths on Linux and macOS.
    @raise Failure if no Chromium binary is found. *)

val with_chromium : ?port:int -> ?headless:bool -> (string -> 'a) -> 'a
(** [with_chromium f] starts a headless Chromium instance, passes the
    page-level WebSocket debugger URL to [f], and kills the process
    when [f] returns or raises.

    @param port CDP remote debugging port (default: 0, meaning Chromium
      picks a free port).
    @param headless Run in headless mode (default: [true]).
    @raise Failure if Chromium cannot be started or the debugger URL
      cannot be obtained. *)
