(** High-level DOM snapshot capture via CDP.

    See {!Capture} (the .mli) for the public interface documentation. *)

let extract conn ~extractor_js =
  (* Inject the JSOO extractor source. *)
  let _inject =
    Cdp.send conn "Runtime.evaluate"
      (`Assoc
        [
          ("expression", `String extractor_js);
          ("returnByValue", `Bool false);
        ])
  in
  (* Execute the capture function. *)
  let result =
    Cdp.send conn "Runtime.evaluate"
      (`Assoc
        [
          ("expression", `String "sosieCapture()");
          ("returnByValue", `Bool true);
          ("awaitPromise", `Bool false);
        ])
  in
  (* Extract the value from the Runtime.evaluate result envelope. *)
  match result with
  | `Assoc fields -> (
      match List.assoc_opt "exceptionDetails" fields with
      | Some details ->
          failwith
            (Printf.sprintf "extractor exception: %s"
               (Yojson.Safe.to_string details))
      | None -> (
          match List.assoc_opt "result" fields with
          | Some (`Assoc result_fields) -> (
              match List.assoc_opt "value" result_fields with
              | Some value -> value
              | None ->
                  failwith "extractor returned no value (returnByValue may have failed)")
          | Some other -> other
          | None -> failwith "extractor returned no result"))
  | other -> other

let capture conn ~extractor_js ~url ?(viewport = (1920, 1080))
    ?(color_scheme = `Light) () =
  let vw, vh = viewport in
  (* 1. Set viewport dimensions. *)
  let _metrics =
    Cdp.send conn "Emulation.setDeviceMetricsOverride"
      (`Assoc
        [
          ("width", `Int vw);
          ("height", `Int vh);
          ("deviceScaleFactor", `Int 1);
          ("mobile", `Bool false);
        ])
  in
  (* 2. Set emulated color scheme. *)
  let scheme_str = match color_scheme with `Light -> "light" | `Dark -> "dark" in
  let _media =
    Cdp.send conn "Emulation.setEmulatedMedia"
      (`Assoc
        [
          ( "features",
            `List [ `Assoc [ ("name", `String "prefers-color-scheme");
                             ("value", `String scheme_str) ] ] );
        ])
  in
  (* 3. Enable page events so we can wait for loadEventFired. *)
  let _page_enable = Cdp.send conn "Page.enable" (`Assoc []) in
  (* 4. Navigate to the target URL. *)
  let _nav =
    Cdp.send conn "Page.navigate" (`Assoc [ ("url", `String url) ])
  in
  (* 5. Wait for the page to finish loading. *)
  let _load = Cdp.wait_event conn "Page.loadEventFired" () in
  (* 6. Wait for web fonts to finish loading. *)
  let _fonts =
    Cdp.send conn "Runtime.evaluate"
      (`Assoc
        [
          ("expression", `String "document.fonts.ready");
          ("awaitPromise", `Bool true);
          ("returnByValue", `Bool false);
        ])
  in
  extract conn ~extractor_js

let screenshot conn =
  let result =
    Cdp.send conn "Page.captureScreenshot"
      (`Assoc [ ("format", `String "png") ])
  in
  match result with
  | `Assoc fields -> (
      match List.assoc_opt "data" fields with
      | Some (`String b64) -> Base64.decode_exn b64
      | _ -> failwith "Page.captureScreenshot: missing data field")
  | _ -> failwith "Page.captureScreenshot: unexpected response"
