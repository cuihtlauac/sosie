(** Launch and manage headless Chromium instances for CDP.

    Provides utilities to locate a Chromium binary and launch it with
    remote debugging enabled, returning the WebSocket URL for CDP
    connections. The Chromium process lifecycle is tied to an Eio switch:
    when the switch is released, the process is killed. *)

val find_chromium : unit -> string
(** [find_chromium ()] returns the path to a Chromium binary.
    Checks the [SOSIE_CHROMIUM_PATH] environment variable first, then
    common installation paths on Linux and macOS.
    @raise Failure if no Chromium binary is found. *)

val launch :
  sw:Eio.Switch.t ->
  proc_mgr:_ Eio.Process.mgr ->
  net:Eio_unix.Net.t ->
  clock:_ Eio.Time.clock ->
  ?port:int ->
  ?headless:bool ->
  unit ->
  string
(** [launch ~sw ~proc_mgr ~net ~clock ()] starts a headless Chromium
    instance and returns the WebSocket debugger URL from the
    [/json/version] endpoint.

    The Chromium process is killed when [sw] is released.

    @param clock Eio clock for retry sleeps while waiting for Chromium's
      HTTP endpoint to become available.
    @param port CDP remote debugging port (default: 0, meaning Chromium
      picks a free port).
    @param headless Run in headless mode (default: [true]).
    @raise Failure if Chromium cannot be started or the debugger URL
      cannot be obtained. *)
