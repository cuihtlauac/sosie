(** Bounded exhaustive and stratified random testing for GumTree matcher.

    Run with: [dune build @exhaustive]

    Stops at the first failure by default, printing the failing tree pair
    as copy-pasteable OCaml source. Pass [--collect-all] to enumerate all
    failures (slower — runs every pair even after a failure):

    [dune exec test/test_exhaustive.exe -- --collect-all]

    Enumerates all ordered labeled trees up to size 5 with 3 tags (DIV, SPAN,
    SECTION) and checks structural invariants on every pair. Also runs
    stratified random tests on larger trees of specific shapes.

    Checked invariants (all must hold on every pair):
    - Injectivity: no node in A maps to two nodes in B, and vice versa.
    - Symmetry: |match(A,B)| = |match(B,A)|.
    - Ancestor preservation: matched ancestor pairs preserve hierarchy.
    - Self-match completeness: match(A,A) matches every node to itself. *)

open Sosie
open Sosie_shared.Snapshot_types

(* --- Node construction helpers --- *)

let default_border : border =
  { width = Px 0.0; style = Str "none"; color = Color 0x000000FF }

let default_styles : visual_properties =
  { display = Str "block"; visibility = Str "visible"; opacity = Num 1.0;
    color = Color 0x000000FF; background_color = Color 0x00000000;
    font_family = Str "serif"; font_size = Px 16.0; font_weight = Num 400.0;
    line_height = Px 20.0; text_align = Str "start";
    text_decoration = Str "none";
    border_top = default_border; border_right = default_border;
    border_bottom = default_border; border_left = default_border;
    border_radius = Px 0.0; box_shadow = Str "none";
    overflow_x = Str "visible"; overflow_y = Str "visible";
    z_index = Str "auto"; cursor = Str "auto" }

let make_node ?(tag = "DIV") ?(children = []) () : node =
  { tag; attributes = [];
    bounds = { x = 0.0; y = 0.0; w = 100.0; h = 50.0 };
    styles = default_styles; text = None; paint_order = 0; children }

let tags = [| "DIV"; "SPAN"; "SECTION" |]

(* --- Tree enumeration --- *)

(* Enumerate all compositions of [n] into [k] positive parts *)
let rec compositions n k =
  if k = 0 then (if n = 0 then [[]] else [])
  else if k = 1 then [[n]]
  else
    let acc = ref [] in
    for i = 1 to n - k + 1 do
      List.iter (fun rest -> acc := (i :: rest) :: !acc)
        (compositions (n - i) (k - 1))
    done;
    List.rev !acc

(* Enumerate all ordered trees of exactly [n] nodes.
   Returns list of child-lists for each tree shape. *)
let rec enum_shapes n : node list list =
  if n = 1 then [[]]
  else
    let acc = ref [] in
    for k = 1 to n - 1 do
      let comps = compositions (n - 1) k in
      List.iter (fun sizes ->
        let child_shape_lists = List.map enum_shapes sizes in
        let combos = List.fold_left (fun acc shapes ->
          List.concat_map (fun prefix ->
            List.map (fun children ->
              prefix @ [make_node ~children ()]
            ) shapes
          ) acc
        ) [[]] child_shape_lists in
        acc := combos @ !acc
      ) comps
    done;
    List.rev !acc

(* Label a tree shape with all possible tag assignments *)
let label_tree shape n_tags =
  let rec count (nd : node) = 1 + List.fold_left (fun a c -> a + count c) 0 nd.children in
  let n = count shape in
  let total = int_of_float (float_of_int n_tags ** float_of_int n) in
  let results = ref [] in
  for combo = 0 to total - 1 do
    let tag_indices = Array.make n 0 in
    let v = ref combo in
    for i = n - 1 downto 0 do
      tag_indices.(i) <- !v mod n_tags;
      v := !v / n_tags
    done;
    let idx = ref 0 in
    let rec apply (nd : node) =
      let tag = tags.(tag_indices.(!idx)) in
      incr idx;
      let children = List.map apply nd.children in
      make_node ~tag ~children ()
    in
    results := apply shape :: !results
  done;
  List.rev !results

let all_trees s n_tags =
  let shapes = enum_shapes s in
  List.concat_map (fun children ->
    let shape = make_node ~children () in
    label_tree shape n_tags
  ) shapes

(* --- Tree serialization (OCaml source for unit tests) --- *)

let rec pp_tree buf indent (nd : node) =
  let pad = String.make indent ' ' in
  match nd.children with
  | [] ->
    Buffer.add_string buf (Printf.sprintf "%smake_node ~tag:%S ()" pad nd.tag)
  | children ->
    Buffer.add_string buf (Printf.sprintf "%smake_node ~tag:%S ~children:[\n" pad nd.tag);
    List.iteri (fun i c ->
      pp_tree buf (indent + 2) c;
      if i < List.length children - 1 then Buffer.add_string buf ";\n"
      else Buffer.add_string buf "\n"
    ) children;
    Buffer.add_string buf (Printf.sprintf "%s] ()" pad)

let tree_to_string nd =
  let buf = Buffer.create 256 in
  pp_tree buf 4 nd;
  Buffer.contents buf

(* --- Property checking --- *)

let check_injectivity m =
  let seen = Hashtbl.create 16 in
  let ok = ref true in
  for i = 0 to Gumtree.size_a m - 1 do
    match Gumtree.partner_of_a m i with
    | None -> ()
    | Some b_id ->
      if Hashtbl.mem seen b_id then ok := false
      else Hashtbl.replace seen b_id ()
  done;
  !ok

let check_self_match_completeness a =
  let m = Gumtree.match_trees a a in
  let n = Gumtree.size_a m in
  let ok = ref true in
  for i = 0 to n - 1 do
    (match Gumtree.partner_of_a m i with
     | Some j when j = i -> ()
     | _ -> ok := false)
  done;
  !ok

let matched_count m =
  let c = ref 0 in
  for i = 0 to Gumtree.size_a m - 1 do
    if Gumtree.is_matched_a m i then incr c
  done;
  !c

let build_parent_map root =
  let tbl = Hashtbl.create 64 in
  let next = ref 0 in
  let rec go parent (n : node) =
    let id = !next in
    incr next;
    Hashtbl.replace tbl id parent;
    List.iter (go (Some id)) n.children
  in
  go None root;
  (tbl, !next)

let is_ancestor parent_map x y =
  let rec go cur =
    if cur = x then true
    else match Hashtbl.find parent_map cur with
      | None -> false
      | Some p -> go p
  in
  x <> y && go y

let check_ancestor_preservation m a b =
  let (pmap_a, n_a) = build_parent_map a in
  let (pmap_b, _) = build_parent_map b in
  let pairs = ref [] in
  for i = 0 to n_a - 1 do
    match Gumtree.partner_of_a m i with
    | Some j -> pairs := (i, j) :: !pairs
    | None -> ()
  done;
  let pairs = !pairs in
  List.for_all (fun (x, x') ->
    List.for_all (fun (y, y') ->
      if is_ancestor pmap_a x y then is_ancestor pmap_b x' y'
      else true
    ) pairs
  ) pairs

(* --- Failure collection with witnesses --- *)

let collect_all = Array.exists (fun s -> s = "--collect-all") Sys.argv

type witness_set = {
  mutable count : int;
  mutable examples : (node * node) list;
}

let max_witnesses = 3

let witnesses : (string, witness_set) Hashtbl.t = Hashtbl.create 8

exception Fail_fast of string * node * node

let record_failure prop a b =
  let ws = match Hashtbl.find_opt witnesses prop with
    | Some ws -> ws
    | None ->
      let ws = { count = 0; examples = [] } in
      Hashtbl.replace witnesses prop ws; ws
  in
  ws.count <- ws.count + 1;
  if List.length ws.examples < max_witnesses then
    ws.examples <- (a, b) :: ws.examples;
  if not collect_all then
    raise (Fail_fast (prop, a, b))

let dump_witnesses () =
  let props = Hashtbl.fold (fun k v acc -> (k, v) :: acc) witnesses [] in
  let props = List.sort (fun (a, _) (b, _) -> String.compare a b) props in
  List.iter (fun (prop, ws) ->
    Printf.printf "\n=== %s: %d failures, showing %d witnesses ===\n"
      prop ws.count (List.length ws.examples);
    List.iteri (fun i (a, b) ->
      Printf.printf "\n-- witness %d --\n  let a =\n%s\n  let b =\n%s\n"
        (i + 1) (tree_to_string a) (tree_to_string b)
    ) ws.examples
  ) props

let total_failure_count () =
  Hashtbl.fold (fun _ ws acc -> acc + ws.count) witnesses 0

(* --- Bounded exhaustive tests --- *)

let run_bounded_exhaustive () =
  let n_tags = 3 in
  let max_size = 5 in
  let total_pairs = ref 0 in
  let trees_by_size = Array.init (max_size + 1) (fun s ->
    if s = 0 then [] else all_trees s n_tags
  ) in
  for sa = 1 to max_size do
    for sb = 1 to max_size do
      let trees_a = trees_by_size.(sa) in
      let trees_b = trees_by_size.(sb) in
      List.iter (fun a ->
        List.iter (fun b ->
          incr total_pairs;
          let m = Gumtree.match_trees a b in
          if not (check_injectivity m) then
            record_failure "injectivity" a b;
          let m_ba = Gumtree.match_trees b a in
          if matched_count m <> matched_count m_ba then
            record_failure "symmetry" a b;
          if not (check_ancestor_preservation m a b) then
            record_failure "ancestor_preservation" a b;
        ) trees_b
      ) trees_a
    done
  done;
  for s = 1 to max_size do
    List.iter (fun a ->
      if not (check_self_match_completeness a) then
        record_failure "self_match_completeness" a a
    ) trees_by_size.(s)
  done;
  Printf.printf "Bounded exhaustive: %d pairs checked\n%!" !total_pairs

(* --- Stratified random tests --- *)

let make_path n =
  let rec go depth =
    if depth = 0 then make_node ()
    else make_node ~children:[go (depth - 1)] ()
  in
  go (n - 1)

let make_star n =
  let children = List.init (n - 1) (fun i ->
    make_node ~tag:tags.(i mod Array.length tags) ()
  ) in
  make_node ~children ()

let make_caterpillar n =
  let spine_len = n / 2 in
  let rec go depth =
    if depth = 0 then make_node ~tag:"SPAN" ()
    else
      let leaf = make_node ~tag:"SECTION" () in
      make_node ~tag:"DIV" ~children:[go (depth - 1); leaf] ()
  in
  go (spine_len - 1)

let make_balanced_binary n =
  let rec go remaining =
    if remaining <= 1 then make_node ~tag:"SPAN" ()
    else
      let left_size = (remaining - 1) / 2 in
      let right_size = remaining - 1 - left_size in
      let children =
        (if left_size > 0 then [go left_size] else []) @
        (if right_size > 0 then [go right_size] else [])
      in
      make_node ~tag:"DIV" ~children ()
  in
  go n

let make_left_comb n =
  let rec go remaining =
    if remaining <= 1 then make_node ~tag:"SPAN" ()
    else
      let subtree = go (remaining - 2) in
      let leaf = make_node ~tag:"SECTION" () in
      make_node ~tag:"DIV" ~children:[subtree; leaf] ()
  in
  go n

let perturb_swap (nd : node) : node =
  match nd.children with
  | a :: b :: rest -> { nd with children = b :: a :: rest }
  | _ -> nd

let perturb_wrap (nd : node) : node =
  match nd.children with
  | c :: rest ->
    let wrapper = make_node ~tag:"SECTION" ~children:[c] () in
    { nd with children = wrapper :: rest }
  | [] -> nd

let perturb_remove_leaf (nd : node) : node =
  match List.rev nd.children with
  | last :: _ when last.children = [] ->
    { nd with children = List.filteri (fun i _ ->
        i < List.length nd.children - 1) nd.children }
  | _ -> nd

let run_stratified_random () =
  let shapes = [
    ("path", make_path);
    ("star", make_star);
    ("caterpillar", make_caterpillar);
    ("balanced_binary", make_balanced_binary);
    ("left_comb", make_left_comb);
  ] in
  let sizes = [50; 100; 200] in
  let perturbations = [
    ("swap", perturb_swap);
    ("wrap", perturb_wrap);
    ("remove_leaf", perturb_remove_leaf);
  ] in
  List.iter (fun (_shape_name, make_shape) ->
    List.iter (fun size ->
      let tree = make_shape size in
      if not (check_self_match_completeness tree) then
        record_failure "self_match_completeness" tree tree;
      List.iter (fun (_pert_name, perturb) ->
        let perturbed = perturb tree in
        let m = Gumtree.match_trees tree perturbed in
        if not (check_injectivity m) then
          record_failure "injectivity" tree perturbed;
        if not (check_ancestor_preservation m tree perturbed) then
          record_failure "ancestor_preservation" tree perturbed
      ) perturbations
    ) sizes
  ) shapes;
  Printf.printf "Stratified random: %d shapes x %d sizes x %d perturbations\n%!"
    (List.length shapes) (List.length sizes) (List.length perturbations)

(* --- Main --- *)

let () =
  if collect_all then
    Printf.printf "Mode: --collect-all (enumerate all failures)\n%!"
  else
    Printf.printf "Mode: fail-fast (stop at first failure; use --collect-all to enumerate)\n%!";
  begin try
    Printf.printf "Running bounded exhaustive tests (all tree pairs up to size 5, 3 tags)...\n%!";
    run_bounded_exhaustive ();
    Printf.printf "Running stratified random tests...\n%!";
    run_stratified_random ()
  with Fail_fast (prop, a, b) ->
    Printf.printf "\nFAILED: %s\n  let a =\n%s\n  let b =\n%s\n"
      prop (tree_to_string a) (tree_to_string b);
    exit 1
  end;
  let n = total_failure_count () in
  if n = 0 then
    Printf.printf "All exhaustive and stratified tests passed.\n%!"
  else begin
    Printf.printf "\n%d total failures.\n" n;
    dump_witnesses ();
    exit 1
  end
