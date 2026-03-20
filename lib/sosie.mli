(** sosie — DOM equivalence checker for UI-conservative HTML/CSS refactoring.

    This is the top-level module of the sosie library. It captures resolved
    layout and style trees from a browser and compares them structurally to
    detect visual regressions introduced by HTML/CSS refactoring. *)

val version : string
(** The sosie version string. *)

module Snapshot_types = Sosie_shared.Snapshot_types
(** Resolved layout+style tree types shared with the JSOO extractor. *)

module Property_whitelist = Sosie_shared.Property_whitelist
(** Canonical CSS property whitelist. *)

module Ws = Ws
(** Blocking WebSocket client over Unix sockets. *)

module Cdp = Cdp
(** Chrome DevTools Protocol bridge. *)

module Cdp_launcher = Cdp_launcher
(** Chromium process launcher. *)

module Capture = Capture
(** High-level DOM snapshot capture via CDP. *)

module Snapshot = Snapshot
(** Snapshot parsing and serialization. *)

module Snapshot_gen = Snapshot_gen
(** Snapshot round-trip generator: snapshot to HTML. *)

module Extractor_js_source : sig
  val source : string
end
(** Build-time embedded JSOO extractor source. *)
