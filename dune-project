(lang dune 3.0)

(name sosie)

(version 0.1.0-dev)

(generate_opam_files true)

(license MIT)

(authors "Cuihtlauac Alvarado <cuihtlauac@tarides.com>")

(maintainers "Cuihtlauac Alvarado <cuihtlauac@tarides.com>")

(package
 (name sosie)
 (synopsis "DOM equivalence checker for UI-conservative HTML/CSS refactoring")
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
