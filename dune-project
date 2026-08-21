(lang dune 3.0)

(name sosie)

(version 0.1.0)

(generate_opam_files true)

(license MIT)

(authors "Cuihtlauac Alvarado <cuihtlauac@tarides.com>")

(maintainers "Cuihtlauac Alvarado <cuihtlauac@tarides.com>")

(source
 (github cuihtlauac/sosie))

(homepage "https://github.com/cuihtlauac/sosie")

(bug_reports "https://github.com/cuihtlauac/sosie/issues")

(package
 (name sosie)
 (synopsis "DOM equivalence checker for UI-conservative HTML/CSS refactoring")
 (description
  "sosie answers whether an HTML/CSS refactoring changed the visual output. It captures the resolved layout and style tree of a page from a real browser using standard Web APIs (getBoundingClientRect, getComputedStyle) and compares two captures structurally. Unlike pixel diffing it is immune to subpixel/GPU/font-rendering noise; unlike CSS diffing it compares rendered effect rather than source. The design prioritises trustworthiness: missed regressions are fatal, spurious diffs are tolerable, and an explicit property whitelist is the trust boundary.")
 (depends
  (ocaml (>= 5.4))
  yojson
  digestif
  base64
  cmdliner
  js_of_ocaml
  js_of_ocaml-compiler
  js_of_ocaml-ppx
  (alcotest :with-test)
  (qcheck-core :with-test)
  (qcheck-alcotest :with-test)))
