(lang dune 3.0)

(name sosie)

(version 0.1.0-dev)

(generate_opam_files true)

(package
 (name sosie)
 (synopsis "DOM equivalence checker for UI-conservative HTML/CSS refactoring")
 (depends
  (ocaml (>= 5.4))
  yojson
  eio
  eio_main
  httpun-ws-eio
  base64
  cmdliner
  js_of_ocaml
  js_of_ocaml-compiler
  js_of_ocaml-ppx
  (alcotest :with-test)
  (qcheck-core :with-test)
  (qcheck-alcotest :with-test)))
