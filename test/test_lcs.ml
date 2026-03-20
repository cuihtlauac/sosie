(** Unit tests for the LCS diff module. *)

open Sosie

let eq = Int.equal

let edit_to_string = function
  | Lcs.Keep (a, b) -> Printf.sprintf "Keep(%d,%d)" a b
  | Lcs.Insert a -> Printf.sprintf "Insert(%d)" a
  | Lcs.Delete a -> Printf.sprintf "Delete(%d)" a

let check_edits name expected actual =
  let to_s l = "[" ^ String.concat "; " (List.map edit_to_string l) ^ "]" in
  Alcotest.(check string) name (to_s expected) (to_s actual)

(* --- Unit tests --- *)

let empty_sequences () =
  check_edits "both empty" [] (Lcs.diff ~eq [] [])

let empty_left () =
  check_edits "empty left"
    [Lcs.Insert 1; Lcs.Insert 2]
    (Lcs.diff ~eq [] [1; 2])

let empty_right () =
  check_edits "empty right"
    [Lcs.Delete 1; Lcs.Delete 2]
    (Lcs.diff ~eq [1; 2] [])

let identical_sequences () =
  check_edits "identical"
    [Lcs.Keep (1, 1); Lcs.Keep (2, 2); Lcs.Keep (3, 3)]
    (Lcs.diff ~eq [1; 2; 3] [1; 2; 3])

let completely_different () =
  check_edits "different"
    [Lcs.Delete 1; Lcs.Delete 2; Lcs.Insert 3; Lcs.Insert 4]
    (Lcs.diff ~eq [1; 2] [3; 4])

let single_insertion () =
  check_edits "insert middle"
    [Lcs.Keep (1, 1); Lcs.Insert 5; Lcs.Keep (2, 2)]
    (Lcs.diff ~eq [1; 2] [1; 5; 2])

let single_deletion () =
  check_edits "delete middle"
    [Lcs.Keep (1, 1); Lcs.Delete 5; Lcs.Keep (2, 2)]
    (Lcs.diff ~eq [1; 5; 2] [1; 2])

let interleaved () =
  check_edits "interleaved"
    [Lcs.Keep (1, 1); Lcs.Delete 2; Lcs.Keep (3, 3); Lcs.Insert 4]
    (Lcs.diff ~eq [1; 2; 3] [1; 3; 4])

let prefix_insertion () =
  check_edits "prefix insert"
    [Lcs.Insert 0; Lcs.Keep (1, 1); Lcs.Keep (2, 2)]
    (Lcs.diff ~eq [1; 2] [0; 1; 2])

let suffix_deletion () =
  check_edits "suffix delete"
    [Lcs.Keep (1, 1); Lcs.Keep (2, 2); Lcs.Delete 3]
    (Lcs.diff ~eq [1; 2; 3] [1; 2])

let single_element_both () =
  check_edits "single match"
    [Lcs.Keep (1, 1)]
    (Lcs.diff ~eq [1] [1])

let single_element_mismatch () =
  check_edits "single mismatch"
    [Lcs.Delete 1; Lcs.Insert 2]
    (Lcs.diff ~eq [1] [2])

(* --- Test registration --- *)

let () =
  Alcotest.run "lcs" [
    "diff", [
      Alcotest.test_case "empty sequences" `Quick empty_sequences;
      Alcotest.test_case "empty left" `Quick empty_left;
      Alcotest.test_case "empty right" `Quick empty_right;
      Alcotest.test_case "identical sequences" `Quick identical_sequences;
      Alcotest.test_case "completely different" `Quick completely_different;
      Alcotest.test_case "single insertion" `Quick single_insertion;
      Alcotest.test_case "single deletion" `Quick single_deletion;
      Alcotest.test_case "interleaved" `Quick interleaved;
      Alcotest.test_case "prefix insertion" `Quick prefix_insertion;
      Alcotest.test_case "suffix deletion" `Quick suffix_deletion;
      Alcotest.test_case "single element match" `Quick single_element_both;
      Alcotest.test_case "single element mismatch" `Quick single_element_mismatch;
    ];
  ]
