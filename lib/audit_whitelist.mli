(** Whitelist blind-spot detection via CSS property complement reset.

    Compares screenshots before and after resetting all non-whitelisted CSS
    properties to [initial]. If the screenshots differ, a visual property
    outside the whitelist affects the page — a blind spot.

    The browser property list is read from a [getComputedStyle] object
    (every longhand the engine exposes). Diff images are produced via
    ImageMagick [compare] when available, falling back to saving both
    PNGs. *)

val whitelist_css_names : string list
(** The 52 whitelisted CSS property names from {!Property_whitelist}. *)

val all_css_properties : Cdp.connection -> string list
(** Enumerate the browser's rendering-affecting CSS property names by
    reading a [getComputedStyle] object via [Runtime.evaluate]. Returns
    every longhand property the engine exposes.
    @raise Failure if the CDP call fails or the response is malformed. *)

val reset_stylesheet :
  whitelist:string list -> all_properties:string list -> string
(** [reset_stylesheet ~whitelist ~all_properties] generates a CSS string
    that resets every property in [all_properties] not in [whitelist] to
    [initial !important].

    @param whitelist CSS property names to keep (the sosie whitelist).
    @param all_properties all browser-supported property names.
    @return a CSS string like [* \{ prop: initial !important; ... \}],
      or an empty string if [whitelist] covers all properties. *)

val audit :
  Cdp.connection ->
  extractor_js:string ->
  url:string ->
  viewport:int * int ->
  color_scheme:[ `Light | `Dark ] ->
  output:string ->
  unit
(** Full audit workflow: navigate to [url], take a baseline screenshot,
    inject a reset stylesheet for non-whitelisted properties, take a
    second screenshot, and compare.

    If the screenshots are identical, prints "no blind spots" to stdout.
    If they differ, attempts to produce a diff image via ImageMagick
    [compare]. Falls back to saving [{output}-baseline.png] and
    [{output}-reset.png] if ImageMagick is absent.

    @param extractor_js passed to {!Capture.capture} for page load.
    @param url the page URL to audit.
    @param viewport width and height in pixels.
    @param color_scheme emulated color scheme.
    @param output path for the diff PNG output.
    @raise Failure if navigation or CDP calls fail. *)
