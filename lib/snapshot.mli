(** Snapshot parsing and serialization.

    Converts between the JS extractor's JSON output and typed
    {!Snapshot_types.snapshot} values. All CSS values are stored as
    [Str] — typed parsing (Px, Num, Color) is deferred to normalization.

    The round-trip property [of_json (to_json s) = s] holds for all
    well-formed snapshots. *)

type t = Sosie_shared.Snapshot_types.snapshot

val of_json : Yojson.Safe.t -> t
(** Parse the JS extractor's JSON output into a typed snapshot.
    @raise Failure on malformed input. *)

val to_json : t -> Yojson.Safe.t
(** Serialize a snapshot to JSON (same format as the extractor output). *)

val pp : Format.formatter -> t -> unit
(** Pretty-print a snapshot for debugging. *)
