(** Canonical CSS property whitelist.

    Single source of truth for the CSS properties captured by sosie.
    Used by the js_of_ocaml extractor and the native snapshot parser.
    The list matches the DEFAULT_PROPERTIES array in the raw JS extractor.

    Border properties are grouped: [border-top-width], [border-top-style],
    [border-top-color] map to the [border_top : border] record field in
    {!Snapshot_types}. *)

type property = {
  css_name : string;  (** CSS property name, e.g. ["background-color"]. *)
  field : string;  (** OCaml record field name, e.g. ["background_color"]. *)
}
(** A single whitelisted CSS property with its CSS and OCaml names. *)

val properties : property list
(** The 29 whitelisted CSS properties in declaration order. *)

val css_names : string list
(** Just the CSS names, for passing to [getComputedStyle] iteration. *)
