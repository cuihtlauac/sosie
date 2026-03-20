(** Longest common subsequence via standard DP. *)

type 'a edit =
  | Keep of 'a * 'a
  | Insert of 'a
  | Delete of 'a

let diff ~eq xs ys =
  let xa = Array.of_list xs in
  let ya = Array.of_list ys in
  let n = Array.length xa in
  let m = Array.length ya in
  if n = 0 then List.map (fun y -> Insert y) ys
  else if m = 0 then List.map (fun x -> Delete x) xs
  else begin
    (* DP table: dp.(i).(j) = LCS length of xa[0..i-1] and ya[0..j-1] *)
    let dp = Array.init (n + 1) (fun _ -> Array.make (m + 1) 0) in
    for i = 1 to n do
      for j = 1 to m do
        if eq xa.(i - 1) ya.(j - 1) then
          dp.(i).(j) <- dp.(i - 1).(j - 1) + 1
        else
          dp.(i).(j) <- max dp.(i - 1).(j) dp.(i).(j - 1)
      done
    done;
    (* Backtrack to produce edit script *)
    let rec backtrack i j acc =
      if i = 0 && j = 0 then acc
      else if i > 0 && j > 0 && eq xa.(i - 1) ya.(j - 1) then
        backtrack (i - 1) (j - 1) (Keep (xa.(i - 1), ya.(j - 1)) :: acc)
      else if j > 0 && (i = 0 || dp.(i).(j - 1) >= dp.(i - 1).(j)) then
        backtrack i (j - 1) (Insert ya.(j - 1) :: acc)
      else
        backtrack (i - 1) j (Delete xa.(i - 1) :: acc)
    in
    backtrack n m []
  end
