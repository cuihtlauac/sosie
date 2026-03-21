(** Visual normalization config overlay in a headed browser.

    Injects colored overlays into a live page to visualize which
    normalization rules affect which elements:
    - Yellow: [Mask_text] (shows replacement text)
    - Red semi-transparent: [Drop_subtree] (with "IGNORED" label)
    - Blue dashed border: [Drop_attributes]
    - Grid lines: [Round_bounds] (at quantum interval)

    Opens a headed Chromium window and blocks until the user presses
    Enter in the terminal. *)

val selector_to_css : Normalize.simple_selector -> string
(** Convert a sosie selector to a CSS selector string.
    E.g., [Tag "div"] becomes ["div"], [Id "main"] becomes ["#main"],
    [Class "active"] becomes [".active"], [Universal] becomes ["*"]. *)

val overlay_js : Normalize.rule list -> string
(** Generate JavaScript that draws visual overlays for each
    normalization rule. The JS uses [querySelectorAll] and
    inline styles to highlight affected elements.

    @param rules the normalization rules to visualize.
    @return a JavaScript source string (an IIFE). *)

val show :
  Cdp.connection ->
  extractor_js:string ->
  url:string ->
  viewport:int * int ->
  color_scheme:[ `Light | `Dark ] ->
  config:Config.t ->
  unit
(** Navigate to [url] in a headed Chromium, inject overlays, and block
    until the user presses Enter.

    @param extractor_js passed to {!Capture.capture} for page load.
    @param url the page URL to visualize.
    @param viewport width and height in pixels.
    @param color_scheme emulated color scheme.
    @param config the sosie configuration to visualize.
    @raise Failure if navigation or CDP calls fail. *)
