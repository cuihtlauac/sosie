let version_is_non_empty () =
  Alcotest.(check bool)
    "version is non-empty" true
    (String.length Sosie.version > 0)

let () =
  Alcotest.run "sosie"
    [
      ( "version",
        [
          Alcotest.test_case "version_is_non_empty" `Quick version_is_non_empty;
        ] );
    ]
