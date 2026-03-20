open Sosie

(* -- make_request tests -------------------------------------------------- *)

let request_has_correct_fields () =
  let req = Cdp.make_request 1 "Runtime.evaluate" (`Assoc [ ("expr", `String "1+1") ]) in
  match req with
  | `Assoc fields ->
      Alcotest.(check int) "id" 1
        (match List.assoc "id" fields with `Int n -> n | _ -> -1);
      Alcotest.(check string) "method" "Runtime.evaluate"
        (match List.assoc "method" fields with `String s -> s | _ -> "");
      Alcotest.(check bool) "params present" true
        (List.mem_assoc "params" fields)
  | _ -> Alcotest.fail "expected JSON object"

let request_with_empty_params () =
  let req = Cdp.make_request 42 "Browser.getVersion" (`Assoc []) in
  let json_str = Yojson.Safe.to_string req in
  (* Verify round-trip through JSON serialization. *)
  Alcotest.(check bool) "serializes to non-empty string" true
    (String.length json_str > 0);
  let reparsed = Yojson.Safe.from_string json_str in
  match Cdp.response_id reparsed with
  | Some 42 -> ()
  | _ -> Alcotest.fail "round-trip id mismatch"

let request_ids_are_independent () =
  let r1 = Cdp.make_request 1 "A" `Null in
  let r2 = Cdp.make_request 2 "B" `Null in
  let r3 = Cdp.make_request 3 "C" `Null in
  let ids = List.filter_map Cdp.response_id [ r1; r2; r3 ] in
  Alcotest.(check (list int)) "ids" [ 1; 2; 3 ] ids

(* -- parse_response tests ------------------------------------------------ *)

let parse_success_response () =
  let json =
    Yojson.Safe.from_string
      {|{"id":1,"result":{"value":42}}|}
  in
  match Cdp.parse_response json with
  | Ok (`Assoc fields) ->
      Alcotest.(check bool) "has value" true (List.mem_assoc "value" fields)
  | Ok _ -> Alcotest.fail "expected object result"
  | Error _ -> Alcotest.fail "expected Ok"

let parse_error_response () =
  let json =
    Yojson.Safe.from_string
      {|{"id":1,"error":{"code":-32601,"message":"method not found"}}|}
  in
  match Cdp.parse_response json with
  | Error (`Assoc fields) ->
      Alcotest.(check bool) "has code" true (List.mem_assoc "code" fields)
  | Error _ -> Alcotest.fail "expected object error"
  | Ok _ -> Alcotest.fail "expected Error"

let parse_malformed_response () =
  let json = `String "not an object" in
  match Cdp.parse_response json with
  | Error _ -> ()
  | Ok _ -> Alcotest.fail "expected Error for malformed response"

let parse_response_without_result_or_error () =
  let json = Yojson.Safe.from_string {|{"id":1}|} in
  match Cdp.parse_response json with
  | Error _ -> ()
  | Ok _ -> Alcotest.fail "expected Error for missing result/error"

(* -- response_id tests --------------------------------------------------- *)

let response_id_present () =
  let json = Yojson.Safe.from_string {|{"id":7,"result":{}}|} in
  Alcotest.(check (option int)) "id" (Some 7) (Cdp.response_id json)

let response_id_absent () =
  let json = Yojson.Safe.from_string {|{"method":"Page.loadEventFired","params":{}}|} in
  Alcotest.(check (option int)) "no id" None (Cdp.response_id json)

let response_id_non_integer () =
  let json = Yojson.Safe.from_string {|{"id":"not_an_int","result":{}}|} in
  Alcotest.(check (option int)) "non-int id" None (Cdp.response_id json)

let response_id_non_object () =
  Alcotest.(check (option int)) "non-object" None (Cdp.response_id `Null)

(* -- is_event tests ------------------------------------------------------ *)

let event_detected () =
  let json =
    Yojson.Safe.from_string
      {|{"method":"Page.loadEventFired","params":{}}|}
  in
  Alcotest.(check bool) "is event" true (Cdp.is_event json)

let response_not_event () =
  let json =
    Yojson.Safe.from_string {|{"id":1,"method":"Runtime.evaluate","params":{}}|}
  in
  Alcotest.(check bool) "response is not event" false (Cdp.is_event json)

let non_object_not_event () =
  Alcotest.(check bool) "null is not event" false (Cdp.is_event `Null)

let no_method_not_event () =
  let json = Yojson.Safe.from_string {|{"params":{}}|} in
  Alcotest.(check bool) "no method" false (Cdp.is_event json)

(* -- Test runner --------------------------------------------------------- *)

let () =
  Alcotest.run "cdp"
    [
      ( "make_request",
        [
          Alcotest.test_case "request_has_correct_fields" `Quick
            request_has_correct_fields;
          Alcotest.test_case "request_with_empty_params" `Quick
            request_with_empty_params;
          Alcotest.test_case "request_ids_are_independent" `Quick
            request_ids_are_independent;
        ] );
      ( "parse_response",
        [
          Alcotest.test_case "parse_success_response" `Quick
            parse_success_response;
          Alcotest.test_case "parse_error_response" `Quick
            parse_error_response;
          Alcotest.test_case "parse_malformed_response" `Quick
            parse_malformed_response;
          Alcotest.test_case "parse_response_without_result_or_error" `Quick
            parse_response_without_result_or_error;
        ] );
      ( "response_id",
        [
          Alcotest.test_case "response_id_present" `Quick response_id_present;
          Alcotest.test_case "response_id_absent" `Quick response_id_absent;
          Alcotest.test_case "response_id_non_integer" `Quick
            response_id_non_integer;
          Alcotest.test_case "response_id_non_object" `Quick
            response_id_non_object;
        ] );
      ( "is_event",
        [
          Alcotest.test_case "event_detected" `Quick event_detected;
          Alcotest.test_case "response_not_event" `Quick response_not_event;
          Alcotest.test_case "non_object_not_event" `Quick non_object_not_event;
          Alcotest.test_case "no_method_not_event" `Quick no_method_not_event;
        ] );
    ]
