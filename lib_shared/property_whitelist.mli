(** Canonical CSS property whitelist.

    Single source of truth for the CSS properties captured by sosie.
    Used by the js_of_ocaml extractor and the native snapshot parser.
    The list matches the DEFAULT_PROPERTIES array in the raw JS extractor.

    Border properties are grouped: [border-top-width], [border-top-style],
    [border-top-color] map to the [border_top : border] record field in
    {!Snapshot_types}. Shorthands that [getComputedStyle] does not reliably
    serialize (outline, text-emphasis, -webkit-text-stroke) are captured as
    individual longhands, so an empty computed value can never hide a real
    difference.

    SVG paint presentation properties (fill, stroke, stroke-width) are
    captured on every element: they are inherited with constant defaults on
    HTML content ([fill: rgb(0, 0, 0)], [stroke: none], [stroke-width: 1px]),
    so their presence adds effectively no spurious diffs while making SVG
    paint changes visible to the comparison. *)

type property = {
  css_name : string;  (** CSS property name, e.g. ["background-color"]. *)
  field : string;  (** OCaml record field name, e.g. ["background_color"]. *)
}
(** A single whitelisted CSS property with its CSS and OCaml names. *)

val properties : property list
(** The 52 whitelisted CSS properties in declaration order. *)

val css_names : string list
(** Just the CSS names, for passing to [getComputedStyle] iteration. *)
