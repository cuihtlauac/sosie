(** Configuration file parser for sosie.json.

    Parses a JSON config into normalization rules and comparison settings.
    Config file format follows the design doc's sosie.json schema. *)

type t = {
  normalize : Normalize.rule list;
  compare : Compare.config;
}
(** Parsed configuration. *)

val default : t
(** Empty normalize rules, default compare config. *)

val of_json : Yojson.Safe.t -> (t, string) result
(** Parse a JSON config value. Unknown fields are ignored; missing fields
    use defaults. *)

val load : string -> (t, string) result
(** [load path] reads and parses a JSON config file.
    @param path filesystem path to the config file
    @return the parsed config or an error message *)
