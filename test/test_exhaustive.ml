(** Bounded exhaustive testing for GumTree matcher.

    Run with: [dune build @exhaustive]

    Stops at the first failure by default, printing the failing tree pair
    as copy-pasteable OCaml source. Pass [--collect-all] to enumerate all
    failures (slower — runs every pair even after a failure):

    [dune exec test/test_exhaustive.exe -- --collect-all]

    Enumerates all ordered labeled trees up to size 5 with 3 tags (DIV, SPAN,
    SECTION) and checks structural invariants on every pair.

    Checked invariants (all must hold on every pair):
    - Injectivity: no node in A maps to two nodes in B, and vice versa.
    - Symmetry: |match(A,B)| = |match(B,A)|.
    - Ancestor preservation: matched ancestor pairs preserve hierarchy.
    - Self-match completeness: match(A,A) matches every node to itself. *)

open Sosie
open Test_tree_helpers

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

(* --- Main --- *)

let () =
  run_and_report ~name:"bounded exhaustive tests (all tree pairs up to size 5, 3 tags)"
    run_bounded_exhaustive
