(** Unit tests for snapshot parsing and serialization. *)

open Sosie

let default_styles_json =
  `Assoc [
    ("display", `String "block");
    ("visibility", `String "visible");
    ("opacity", `String "1");
    ("color", `String "rgb(0, 0, 0)");
    ("background-color", `String "rgba(0, 0, 0, 0)");
    ("font-family", `String "serif");
    ("font-size", `String "16px");
    ("font-weight", `String "400");
    ("line-height", `String "normal");
    ("text-align", `String "start");
    ("text-decoration", `String "none");
    ("border-top-width", `String "0px");
    ("border-top-style", `String "none");
    ("border-top-color", `String "rgb(0, 0, 0)");
    ("border-right-width", `String "0px");
    ("border-right-style", `String "none");
    ("border-right-color", `String "rgb(0, 0, 0)");
    ("border-bottom-width", `String "0px");
    ("border-bottom-style", `String "none");
    ("border-bottom-color", `String "rgb(0, 0, 0)");
    ("border-left-width", `String "0px");
    ("border-left-style", `String "none");
    ("border-left-color", `String "rgb(0, 0, 0)");
    ("border-radius", `String "0px");
    ("box-shadow", `String "none");
    ("overflow-x", `String "visible");
    ("overflow-y", `String "visible");
    ("z-index", `String "auto");
    ("cursor", `String "auto");
  ]

let make_node_json ?(tag = "DIV") ?(attributes = `List [])
    ?(bounds = `Assoc [ ("x", `Float 0.0); ("y", `Float 0.0);
                         ("w", `Float 800.0); ("h", `Float 600.0) ])
    ?(styles = default_styles_json) ?(text = `Null) ?(paint_order = `Int 0)
    ?(children = `List []) () =
  `Assoc [
    ("tag", `String tag);
    ("attributes", attributes);
    ("bounds", bounds);
    ("styles", styles);
    ("text", text);
    ("paintOrder", paint_order);
    ("children", children);
  ]

let make_snapshot_json ?(version = `Int 1)
    ?(url = `String "https://example.com")
    ?(viewport = `List [ `Int 1920; `Int 1080 ])
    ?(color_scheme = `String "light") ?(root = make_node_json ()) () =
  `Assoc [
    ("version", version);
    ("url", url);
    ("viewport", viewport);
    ("colorScheme", color_scheme);
    ("root", root);
  ]

(* -- Round-trip tests ---------------------------------------------------- *)

let round_trip_minimal_snapshot () =
  let json = make_snapshot_json () in
  let s = Snapshot.of_json json in
  let json' = Snapshot.to_json s in
  let s' = Snapshot.of_json json' in
  Alcotest.(check int) "version" s.version s'.version;
  Alcotest.(check string) "url" s.url s'.url;
  let vw, vh = s.viewport and vw', vh' = s'.viewport in
  Alcotest.(check int) "vw" vw vw';
  Alcotest.(check int) "vh" vh vh';
  Alcotest.(check bool) "scheme" true (s.color_scheme = s'.color_scheme);
  Alcotest.(check string) "root tag" s.root.tag s'.root.tag

let round_trip_json_equality () =
  let json = make_snapshot_json () in
  let json' = Snapshot.to_json (Snapshot.of_json json) in
  Alcotest.(check string) "json round-trip"
    (Yojson.Safe.to_string json) (Yojson.Safe.to_string json')

let round_trip_with_children () =
  let child = make_node_json ~tag:"#text" ~text:(`String "hello")
      ~paint_order:(`Int 1) () in
  let parent = make_node_json ~tag:"P" ~children:(`List [ child ]) () in
  let json = make_snapshot_json ~root:parent () in
  let json' = Snapshot.to_json (Snapshot.of_json json) in
  Alcotest.(check string) "json round-trip with children"
    (Yojson.Safe.to_string json) (Yojson.Safe.to_string json')

let round_trip_dark_scheme () =
  let json = make_snapshot_json ~color_scheme:(`String "dark") () in
  let s = Snapshot.of_json json in
  Alcotest.(check bool) "dark" true (s.color_scheme = `Dark);
  let json' = Snapshot.to_json s in
  Alcotest.(check string) "json round-trip dark"
    (Yojson.Safe.to_string json) (Yojson.Safe.to_string json')

let round_trip_with_attributes () =
  let node = make_node_json
      ~attributes:(`List [ `List [ `String "class"; `String "main" ];
                           `List [ `String "id"; `String "root" ] ]) () in
  let json = make_snapshot_json ~root:node () in
  let json' = Snapshot.to_json (Snapshot.of_json json) in
  Alcotest.(check string) "json round-trip attributes"
    (Yojson.Safe.to_string json) (Yojson.Safe.to_string json')

let round_trip_all_29_properties () =
  (* Verify all 29 CSS properties survive the round-trip *)
  let json = make_snapshot_json () in
  let s = Snapshot.of_json json in
  let open Snapshot_types in
  let vp = s.root.styles in
  (* Spot-check a few fields *)
  Alcotest.(check string) "display" "block"
    (match vp.display with Str s -> s | _ -> "?");
  Alcotest.(check string) "border-top-width" "0px"
    (match vp.border_top.width with Str s -> s | _ -> "?");
  Alcotest.(check string) "cursor" "auto"
    (match vp.cursor with Str s -> s | _ -> "?");
  (* Full round-trip *)
  let json' = Snapshot.to_json s in
  Alcotest.(check string) "json round-trip all props"
    (Yojson.Safe.to_string json) (Yojson.Safe.to_string json')

(* -- Parsing edge cases -------------------------------------------------- *)

let text_null_parsed_as_none () =
  let json = make_snapshot_json () in
  let s = Snapshot.of_json json in
  Alcotest.(check (option string)) "text is None" None s.root.text

let text_string_parsed_as_some () =
  let node = make_node_json ~text:(`String "hello") () in
  let json = make_snapshot_json ~root:node () in
  let s = Snapshot.of_json json in
  Alcotest.(check (option string)) "text is Some" (Some "hello") s.root.text

let empty_children_array () =
  let json = make_snapshot_json () in
  let s = Snapshot.of_json json in
  Alcotest.(check int) "no children" 0 (List.length s.root.children)

let empty_attributes_list () =
  let json = make_snapshot_json () in
  let s = Snapshot.of_json json in
  Alcotest.(check int) "no attrs" 0 (List.length s.root.attributes)

let text_node_tag () =
  let node = make_node_json ~tag:"#text" ~text:(`String "world") () in
  let json = make_snapshot_json ~root:node () in
  let s = Snapshot.of_json json in
  Alcotest.(check string) "tag" "#text" s.root.tag

(* -- Error cases --------------------------------------------------------- *)

let parse_error msg f () =
  match f () with
  | _ -> Alcotest.fail ("expected Failure, got success: " ^ msg)
  | exception Failure _ -> ()

let missing_version () =
  parse_error "missing version" (fun () ->
      Snapshot.of_json (`Assoc [
        ("url", `String "x");
        ("viewport", `List [ `Int 1; `Int 1 ]);
        ("colorScheme", `String "light");
        ("root", make_node_json ());
      ])) ()

let wrong_version () =
  parse_error "wrong version" (fun () ->
      Snapshot.of_json (make_snapshot_json ~version:(`Int 99) ())) ()

let missing_root () =
  parse_error "missing root" (fun () ->
      Snapshot.of_json (`Assoc [
        ("version", `Int 1);
        ("url", `String "x");
        ("viewport", `List [ `Int 1; `Int 1 ]);
        ("colorScheme", `String "light");
      ])) ()

let malformed_viewport_not_array () =
  parse_error "viewport not array" (fun () ->
      Snapshot.of_json (make_snapshot_json ~viewport:(`String "bad") ())) ()

let malformed_viewport_wrong_length () =
  parse_error "viewport wrong length" (fun () ->
      Snapshot.of_json (make_snapshot_json ~viewport:(`List [ `Int 1 ]) ())) ()

let malformed_bounds () =
  let node = make_node_json
      ~bounds:(`Assoc [ ("x", `Float 0.0) ]) () in
  parse_error "malformed bounds" (fun () ->
      Snapshot.of_json (make_snapshot_json ~root:node ())) ()

let non_object_styles () =
  let node = make_node_json ~styles:(`String "bad") () in
  parse_error "non-object styles" (fun () ->
      Snapshot.of_json (make_snapshot_json ~root:node ())) ()

(* -- Format fidelity ----------------------------------------------------- *)

let to_json_matches_known_good () =
  let json = make_snapshot_json () in
  let expected = Yojson.Safe.to_string json in
  let actual = Yojson.Safe.to_string (Snapshot.to_json (Snapshot.of_json json)) in
  Alcotest.(check string) "matches known-good" expected actual

(* -- Pretty-printer ------------------------------------------------------ *)

let pp_produces_output () =
  let json = make_snapshot_json () in
  let s = Snapshot.of_json json in
  let buf = Buffer.create 256 in
  let fmt = Format.formatter_of_buffer buf in
  Snapshot.pp fmt s;
  Format.pp_print_flush fmt ();
  let output = Buffer.contents buf in
  Alcotest.(check bool) "non-empty output" true (String.length output > 0);
  Alcotest.(check bool) "contains version"
    true (String.starts_with ~prefix:"snapshot v1" output)

(* -- Test runner --------------------------------------------------------- *)

let () =
  Alcotest.run "snapshot"
    [
      ( "round-trip",
        [
          Alcotest.test_case "minimal snapshot" `Quick round_trip_minimal_snapshot;
          Alcotest.test_case "json equality" `Quick round_trip_json_equality;
          Alcotest.test_case "with children" `Quick round_trip_with_children;
          Alcotest.test_case "dark color scheme" `Quick round_trip_dark_scheme;
          Alcotest.test_case "with attributes" `Quick round_trip_with_attributes;
          Alcotest.test_case "all 29 CSS properties" `Quick
            round_trip_all_29_properties;
        ] );
      ( "parsing-edge-cases",
        [
          Alcotest.test_case "text null -> None" `Quick text_null_parsed_as_none;
          Alcotest.test_case "text string -> Some" `Quick text_string_parsed_as_some;
          Alcotest.test_case "empty children" `Quick empty_children_array;
          Alcotest.test_case "empty attributes" `Quick empty_attributes_list;
          Alcotest.test_case "#text tag" `Quick text_node_tag;
        ] );
      ( "error-cases",
        [
          Alcotest.test_case "missing version" `Quick missing_version;
          Alcotest.test_case "wrong version" `Quick wrong_version;
          Alcotest.test_case "missing root" `Quick missing_root;
          Alcotest.test_case "malformed viewport (not array)" `Quick
            malformed_viewport_not_array;
          Alcotest.test_case "malformed viewport (wrong length)" `Quick
            malformed_viewport_wrong_length;
          Alcotest.test_case "malformed bounds" `Quick malformed_bounds;
          Alcotest.test_case "non-object styles" `Quick non_object_styles;
        ] );
      ( "format-fidelity",
        [
          Alcotest.test_case "to_json matches known-good" `Quick
            to_json_matches_known_good;
        ] );
      ( "pretty-printer",
        [
          Alcotest.test_case "produces non-empty output" `Quick pp_produces_output;
        ] );
    ]
