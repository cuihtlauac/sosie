(** Stratified random testing for GumTree matcher.

    Run with: [dune build @stratified]

    Tests structural invariants on trees of 10–1000 nodes across 7
    shape classes with 5 parameterized transformations. Uses Boltzmann
    sampling and random recursive trees for uniform/logarithmic-depth
    coverage, plus deterministic shapes (path, star, caterpillar, complete
    k-ary, lopsided, balanced binary, left comb) for stress testing.

    Stops at the first failure by default. Pass [--collect-all] to enumerate
    all failures:

    [dune exec test/test_stratified.exe -- --collect-all]

    Checked invariants:
    - Injectivity: no node in A maps to two nodes in B, and vice versa.
    - Symmetry: |match(A,B)| = |match(B,A)|.
    - Ancestor preservation: matched ancestor pairs preserve hierarchy.
    - Self-match completeness: match(A,A) matches every node to itself.
    - Performance: matching completes within 10x the expected O(n log n)
      bound (warning only, not a hard failure). *)

open Sosie
open Sosie_shared.Snapshot_types
open Test_tree_helpers

(* --- Deterministic shape constructors --- *)

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

let make_caterpillar_det n =
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

(* Complete k-ary tree of ~n nodes. Fills levels top-down. *)
let make_complete_kary k n =
  let rec go remaining =
    if remaining <= 1 then make_node ~tag:"SPAN" ()
    else
      let child_budget = remaining - 1 in
      let actual_k = min k child_budget in
      let per_child = child_budget / actual_k in
      let extra = child_budget mod actual_k in
      let children = List.init actual_k (fun i ->
        let sz = per_child + (if i < extra then 1 else 0) in
        go sz
      ) in
      make_node ~tag:"DIV" ~children ()
  in
  go n

(* Lopsided: root has one heavy child (subtree of n-k nodes) plus k-1 leaf
   siblings. Stresses dice coefficient edge cases. *)
let make_lopsided n =
  if n <= 1 then make_node ()
  else
    let n_leaves = min 4 (n - 2) in
    let heavy_size = n - 1 - n_leaves in
    let heavy = make_balanced_binary (max 1 heavy_size) in
    let leaves = List.init n_leaves (fun i ->
      make_node ~tag:tags.(i mod Array.length tags) ()
    ) in
    make_node ~tag:"DIV" ~children:(heavy :: leaves) ()

(* --- Random tag labeling --- *)

let randomize_tags rng (tree : node) : node =
  let rec go (nd : node) =
    let tag = tags.(Random.State.int rng (Array.length tags)) in
    let children = List.map go nd.children in
    make_node ~tag ~children ()
  in
  go tree

(* --- Caterpillar with random leaf tags --- *)

let make_caterpillar rng n =
  randomize_tags rng (make_caterpillar_det n)

(* --- Random recursive tree: sequential insertion, logarithmic depth --- *)

let make_random_recursive rng n =
  if n <= 1 then make_node ~tag:tags.(Random.State.int rng 3) ()
  else begin
    let children_of = Array.make n [] in
    for i = 1 to n - 1 do
      let p = Random.State.int rng i in
      children_of.(p) <- i :: children_of.(p)
    done;
    let rec build i =
      let tag = tags.(Random.State.int rng 3) in
      let kids = List.rev children_of.(i) in
      let children = List.map build kids in
      make_node ~tag ~children ()
    in
    build 0
  end

(* --- Boltzmann sampler for Catalan trees (Duchon et al., 2004) ---

   Spec: T = Z * Seq(T), singularity at x = 1/4, T(1/4) = 1/2.
   Children count ~ Geometric(1/2). Reject if total size outside tolerance. *)

let boltzmann_tree rng target_size =
  let tolerance = max 10 (target_size / 5) in
  let lo = target_size - tolerance and hi = target_size + tolerance in
  let rec try_sample () =
    let count = ref 0 in
    let too_big = ref false in
    let rec sample () =
      incr count;
      if !count > hi then begin too_big := true; make_node () end
      else
        let rec geom_children acc =
          (* Each child drawn with probability T(x) = 0.5 *)
          if Random.State.bool rng then
            geom_children (sample () :: acc)
          else
            List.rev acc
        in
        let children = geom_children [] in
        let tag = tags.(Random.State.int rng 3) in
        make_node ~tag ~children ()
    in
    let tree = sample () in
    let size = !count in
    if !too_big || size < lo || size > hi then try_sample ()
    else tree
  in
  try_sample ()

(* --- Tree size counter --- *)

let rec tree_size (nd : node) =
  1 + List.fold_left (fun acc c -> acc + tree_size c) 0 nd.children

(* --- Parameterized transformation operators ---

   Each operates at a random position selected by pre-order index.
   We use a single-pass O(n) counter + targeted rebuild to avoid
   materializing paths or arrays for every transformation. *)

(* Apply [f] to the node at pre-order index [target]. O(n) single pass. *)
let transform_at_preorder target f (root : node) =
  let counter = ref 0 in
  let rec go (nd : node) =
    let idx = !counter in
    incr counter;
    if idx = target then f nd
    else
      let children = List.map go nd.children in
      { nd with children }
  in
  go root

(* wrap: wrap the subtree at a random non-root position in a new node *)
let transform_wrap rng (root : node) : node =
  let n = tree_size root in
  if n <= 1 then root
  else
    let i = 1 + Random.State.int rng (n - 1) in
    transform_at_preorder i (fun nd ->
      make_node ~tag:"SECTION" ~children:[nd] ()
    ) root

(* reorder: permute children of a random node that has >= 2 children *)
let transform_reorder rng (root : node) : node =
  (* First pass: collect indices of nodes with >= 2 children *)
  let candidates = ref [] in
  let counter = ref 0 in
  let rec scan (nd : node) =
    let idx = !counter in
    incr counter;
    if List.length nd.children >= 2 then
      candidates := idx :: !candidates;
    List.iter scan nd.children
  in
  scan root;
  match !candidates with
  | [] -> root
  | cands ->
    let cands = Array.of_list cands in
    let target = cands.(Random.State.int rng (Array.length cands)) in
    transform_at_preorder target (fun nd ->
      let arr = Array.of_list nd.children in
      let n = Array.length arr in
      for i = n - 1 downto 1 do
        let j = Random.State.int rng (i + 1) in
        let tmp = arr.(i) in
        arr.(i) <- arr.(j);
        arr.(j) <- tmp
      done;
      { nd with children = Array.to_list arr }
    ) root

(* delete: remove a random non-root leaf *)
let transform_delete rng (root : node) : node =
  (* Collect indices of non-root leaves and their parent indices *)
  let leaves = ref [] in
  let counter = ref 0 in
  let rec scan parent_idx child_pos (nd : node) =
    let idx = !counter in
    incr counter;
    if nd.children = [] && parent_idx >= 0 then
      leaves := (parent_idx, child_pos) :: !leaves;
    List.iteri (fun i c -> scan idx i c) nd.children
  in
  scan (-1) (-1) root;
  match !leaves with
  | [] -> root
  | ls ->
    let ls = Array.of_list ls in
    let (parent_target, child_idx) = ls.(Random.State.int rng (Array.length ls)) in
    transform_at_preorder parent_target (fun nd ->
      { nd with children = List.filteri (fun i _ -> i <> child_idx) nd.children }
    ) root

(* insert: add a small random subtree at a random position *)
let transform_insert rng (root : node) : node =
  let n = tree_size root in
  let i = Random.State.int rng n in
  let new_child = make_node ~tag:tags.(Random.State.int rng 3)
    ~children:[make_node ~tag:tags.(Random.State.int rng 3) ()] () in
  transform_at_preorder i (fun nd ->
    let nc = List.length nd.children in
    let pos = if nc = 0 then 0 else Random.State.int rng (nc + 1) in
    let before = List.filteri (fun j _ -> j < pos) nd.children in
    let after = List.filteri (fun j _ -> j >= pos) nd.children in
    { nd with children = before @ [new_child] @ after }
  ) root

(* mutate_tag: change the tag of a random node *)
let transform_mutate_tag rng (root : node) : node =
  let n = tree_size root in
  let i = Random.State.int rng n in
  transform_at_preorder i (fun nd ->
    make_node ~tag:tags.(Random.State.int rng (Array.length tags))
      ~children:nd.children ()
  ) root

(* --- Performance timing --- *)

let time_match a b =
  let t0 = Unix.gettimeofday () in
  let m = Gumtree.match_trees a b in
  let t1 = Unix.gettimeofday () in
  (m, t1 -. t0)

(* Generous bound: 10x the baseline n*log(n) scaled from n=100.
   Returns None if OK, Some message if exceeded. *)
let check_performance_bound ~baseline_time ~baseline_size size elapsed =
  let expected_ratio =
    (float_of_int size *. log (float_of_int size)) /.
    (float_of_int baseline_size *. log (float_of_int baseline_size))
  in
  let bound = baseline_time *. expected_ratio *. 10.0 in
  if elapsed > bound then
    Some (Printf.sprintf "%.3fs exceeded bound %.3fs (10x scaled from baseline)" elapsed bound)
  else
    None

(* --- Main stratified random test runner ---

   Runs in incremental size tiers so progress is visible early and the
   suite can be killed after any tier. Stops after 10 minutes wall-clock. *)

let timeout_seconds = 600.0

let run_stratified_random () =
  let seed = 42 in
  let rng = Random.State.make [| seed |] in
  let n_random_samples = 10 in
  let t_start = Unix.gettimeofday () in

  (* Deterministic shape constructors: 1 tree per size *)
  let det_shapes : (string * (int -> node)) list = [
    ("path", make_path);
    ("star", make_star);
    ("caterpillar_det", make_caterpillar_det);
    ("balanced_binary", make_balanced_binary);
    ("left_comb", make_left_comb);
    ("complete_binary", make_complete_kary 2);
    ("complete_ternary", make_complete_kary 3);
    ("lopsided", make_lopsided);
  ] in

  (* Random shape constructors: n_random_samples trees per size *)
  let rng_shapes : (string * (int -> node)) list = [
    ("caterpillar_rnd", (fun n -> make_caterpillar rng n));
    ("boltzmann", (fun n -> boltzmann_tree rng n));
    ("random_recursive", (fun n -> make_random_recursive rng n));
  ] in

  let transformations : (string * (node -> node)) list = [
    ("wrap", transform_wrap rng);
    ("reorder", transform_reorder rng);
    ("delete", transform_delete rng);
    ("insert", transform_insert rng);
    ("mutate_tag", transform_mutate_tag rng);
  ] in

  let total_pairs = ref 0 in
  let perf_warnings = ref [] in

  (* Baseline timing: balanced binary at size 100 *)
  let baseline_tree = make_balanced_binary 100 in
  let (_, baseline_time) = time_match baseline_tree baseline_tree in
  let baseline_time = max baseline_time 0.001 in

  let timed_out () =
    Unix.gettimeofday () -. t_start > timeout_seconds
  in

  let test_tree shape_name size tree =
    if not (check_self_match_completeness tree) then
      record_failure "self_match_completeness" tree tree;

    List.iter (fun (xform_name, xform) ->
      let perturbed = xform tree in
      let (m_ab, elapsed) = time_match tree perturbed in
      incr total_pairs;

      if not (check_injectivity m_ab) then
        record_failure "injectivity" tree perturbed;
      if not (check_ancestor_preservation m_ab tree perturbed) then
        record_failure "ancestor_preservation" tree perturbed;

      let m_ba = Gumtree.match_trees perturbed tree in
      if matched_count m_ab <> matched_count m_ba then
        record_failure "symmetry" tree perturbed;

      let actual_size = tree_size tree + tree_size perturbed in
      (match check_performance_bound ~baseline_time ~baseline_size:200 actual_size elapsed with
       | None -> ()
       | Some msg ->
         perf_warnings :=
           Printf.sprintf "%s/%d/%s: %s" shape_name size xform_name msg
           :: !perf_warnings)
    ) transformations
  in

  (* Size tiers, run incrementally *)
  let tiers = [
    ("smoke",  [10; 20; 50]);
    ("small",  [100; 200]);
    ("medium", [500; 1000]);
  ] in

  let stopped_early = ref false in

  List.iter (fun (tier_name, sizes) ->
    if not !stopped_early then begin
      Printf.printf "  tier %s (sizes %s)...\n%!" tier_name
        (String.concat ", " (List.map string_of_int sizes));

      List.iter (fun size ->
        if not !stopped_early then begin
          List.iter (fun (shape_name, make_shape) ->
            if not !stopped_early then begin
              let tree = make_shape size in
              test_tree shape_name size tree;
              if timed_out () then stopped_early := true
            end
          ) det_shapes;

          List.iter (fun (shape_name, make_shape) ->
            if not !stopped_early then
              for _sample = 1 to n_random_samples do
                if not !stopped_early then begin
                  let tree = make_shape size in
                  test_tree shape_name size tree;
                  if timed_out () then stopped_early := true
                end
              done
          ) rng_shapes
        end
      ) sizes
    end
  ) tiers;

  let elapsed = Unix.gettimeofday () -. t_start in
  if !stopped_early then
    Printf.printf "Stopped after %.1fs (timeout %gs)\n%!" elapsed timeout_seconds;
  Printf.printf "Stratified random: %d pairs checked in %.1fs\n%!"
    !total_pairs elapsed;
  if !perf_warnings <> [] then begin
    Printf.printf "Performance warnings (%d):\n" (List.length !perf_warnings);
    List.iter (fun w -> Printf.printf "  WARN: %s\n" w) (List.rev !perf_warnings)
  end

(* --- Main --- *)

let () =
  run_and_report ~name:"stratified random tests" run_stratified_random
