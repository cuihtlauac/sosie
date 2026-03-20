(** GumTree-style three-phase tree matcher. *)

open Sosie_shared.Snapshot_types

type node_id = int

(* --- Annotated tree: pre-order indexed with structural hash --- *)

type annotated = {
  id : node_id;
  node : node;
  hash : int;
  size : int;  (* subtree size including self *)
  parent : node_id option;
  children_ids : node_id list;
}

let annotate root =
  let tbl = Hashtbl.create 64 in
  let next_id = ref 0 in
  let rec go parent n =
    let id = !next_id in
    incr next_id;
    (* Annotate children first for bottom-up hash *)
    let child_annots = List.map (go (Some id)) n.children in
    let child_hashes = List.map (fun c -> (Hashtbl.find tbl c).hash) child_annots in
    let hash = Hashtbl.hash (n.tag, child_hashes) in
    let size = 1 + List.fold_left (fun acc c -> acc + (Hashtbl.find tbl c).size) 0 child_annots in
    let ann = { id; node = n; hash; size; parent; children_ids = child_annots } in
    Hashtbl.replace tbl id ann;
    id
  in
  let root_id = go None root in
  (tbl, root_id, !next_id)

(* --- Matching structure --- *)

type matching = {
  a_to_b : (node_id, node_id) Hashtbl.t;
  b_to_a : (node_id, node_id) Hashtbl.t;
  n_a : int;
  n_b : int;
}

let make_matching n_a n_b =
  { a_to_b = Hashtbl.create (min n_a n_b);
    b_to_a = Hashtbl.create (min n_a n_b);
    n_a; n_b }

let add_match m a_id b_id =
  if not (Hashtbl.mem m.a_to_b a_id) && not (Hashtbl.mem m.b_to_a b_id) then begin
    Hashtbl.replace m.a_to_b a_id b_id;
    Hashtbl.replace m.b_to_a b_id a_id
  end

let is_matched_a m id = Hashtbl.mem m.a_to_b id
let is_matched_b m id = Hashtbl.mem m.b_to_a id
let partner_of_a m id = Hashtbl.find_opt m.a_to_b id
let partner_of_b m id = Hashtbl.find_opt m.b_to_a id
let size_a m = m.n_a
let size_b m = m.n_b

(* --- Helpers --- *)

(* Build hash -> node_id list multimap *)
let build_hash_map tbl n =
  let hmap = Hashtbl.create n in
  for id = 0 to n - 1 do
    let ann = Hashtbl.find tbl id in
    let existing = try Hashtbl.find hmap ann.hash with Not_found -> [] in
    Hashtbl.replace hmap ann.hash (id :: existing)
  done;
  hmap

(* Collect all descendant ids (excluding self) *)
let descendants tbl id =
  let acc = ref [] in
  let rec go nid =
    let ann = Hashtbl.find tbl nid in
    List.iter (fun cid -> acc := cid :: !acc; go cid) ann.children_ids
  in
  go id;
  !acc

(* --- Phase 1: Hash matching --- *)

let phase1 m tbl_a tbl_b n_a n_b =
  let hmap_a = build_hash_map tbl_a n_a in
  let hmap_b = build_hash_map tbl_b n_b in
  (* Process from leaves up: sort by subtree size ascending *)
  let all_hashes = Hashtbl.create 64 in
  Hashtbl.iter (fun h _ ->
    if not (Hashtbl.mem all_hashes h) then Hashtbl.replace all_hashes h ()
  ) hmap_a;
  let hash_list = Hashtbl.fold (fun h () acc -> h :: acc) all_hashes [] in
  List.iter (fun h ->
    let a_nodes = try Hashtbl.find hmap_a h with Not_found -> [] in
    let b_nodes = try Hashtbl.find hmap_b h with Not_found -> [] in
    match a_nodes, b_nodes with
    | [a_id], [b_id] ->
      (* Unique hash in both trees: match and recurse into children *)
      let ann_a = Hashtbl.find tbl_a a_id in
      let ann_b = Hashtbl.find tbl_b b_id in
      if String.equal ann_a.node.tag ann_b.node.tag then begin
        add_match m a_id b_id;
        (* Recursively match children by position *)
        let rec match_children ca cb =
          match ca, cb with
          | [], _ | _, [] -> ()
          | a :: arest, b :: brest ->
            add_match m a b;
            let aa = Hashtbl.find tbl_a a in
            let ab = Hashtbl.find tbl_b b in
            match_children aa.children_ids ab.children_ids;
            match_children arest brest
        in
        match_children ann_a.children_ids ann_b.children_ids
      end
    | a_nodes, b_nodes when List.length a_nodes > 0 && List.length b_nodes > 0 ->
      (* Ambiguous: prefer candidates whose parent is already matched *)
      let unmatched_a = List.filter (fun id -> not (is_matched_a m id)) a_nodes in
      let unmatched_b = List.filter (fun id -> not (is_matched_b m id)) b_nodes in
      List.iter (fun a_id ->
        let ann_a = Hashtbl.find tbl_a a_id in
        let best = ref None in
        let best_score = ref (-1) in
        List.iter (fun b_id ->
          if not (is_matched_b m b_id) then begin
            let ann_b = Hashtbl.find tbl_b b_id in
            if String.equal ann_a.node.tag ann_b.node.tag then begin
              let score =
                (* Parent already matched to each other? *)
                (match ann_a.parent, ann_b.parent with
                 | Some pa, Some pb ->
                   (match partner_of_a m pa with
                    | Some pb' when pb' = pb -> 10
                    | _ -> 0)
                 | _ -> 0)
                +
                (* Same sibling index bonus *)
                (let idx_a = match ann_a.parent with
                   | None -> 0
                   | Some pa ->
                     let p = Hashtbl.find tbl_a pa in
                     let rec find_idx i = function
                       | [] -> 0
                       | c :: _ when c = a_id -> i
                       | _ :: rest -> find_idx (i + 1) rest
                     in
                     find_idx 0 p.children_ids
                 in
                 let idx_b = match ann_b.parent with
                   | None -> 0
                   | Some pb ->
                     let p = Hashtbl.find tbl_b pb in
                     let rec find_idx i = function
                       | [] -> 0
                       | c :: _ when c = b_id -> i
                       | _ :: rest -> find_idx (i + 1) rest
                     in
                     find_idx 0 p.children_ids
                 in
                 if idx_a = idx_b then 1 else 0)
              in
              if score > !best_score then begin
                best := Some b_id;
                best_score := score
              end
            end
          end
        ) unmatched_b;
        match !best with
        | Some b_id -> add_match m a_id b_id
        | None -> ()
      ) unmatched_a
    | _ -> ()
  ) hash_list

(* --- Phase 2: Container matching (dice coefficient) --- *)

let phase2 m tbl_a tbl_b n_a n_b =
  (* For each unmatched node in A, find best unmatched partner in B *)
  let dice a_id b_id =
    let desc_a = descendants tbl_a a_id in
    let desc_b = descendants tbl_b b_id in
    let size_a = List.length desc_a + 1 in
    let size_b = List.length desc_b + 1 in
    (* Count matched descendants of a_id that map to descendants of b_id *)
    let b_desc_set = Hashtbl.create (List.length desc_b) in
    List.iter (fun d -> Hashtbl.replace b_desc_set d ()) desc_b;
    Hashtbl.replace b_desc_set b_id ();
    let common = ref 0 in
    List.iter (fun d ->
      match partner_of_a m d with
      | Some pb when Hashtbl.mem b_desc_set pb -> incr common
      | _ -> ()
    ) desc_a;
    (* Also check if a_id itself maps to b_id *)
    (match partner_of_a m a_id with
     | Some pb when Hashtbl.mem b_desc_set pb -> incr common
     | _ -> ());
    let c = float_of_int !common in
    2.0 *. c /. float_of_int (size_a + size_b)
  in
  for a_id = 0 to n_a - 1 do
    if not (is_matched_a m a_id) then begin
      let ann_a = Hashtbl.find tbl_a a_id in
      let best = ref None in
      let best_dice = ref 0.0 in
      for b_id = 0 to n_b - 1 do
        if not (is_matched_b m b_id) then begin
          let ann_b = Hashtbl.find tbl_b b_id in
          if String.equal ann_a.node.tag ann_b.node.tag then begin
            let d = dice a_id b_id in
            if d > !best_dice then begin
              best := Some b_id;
              best_dice := d
            end
          end
        end
      done;
      match !best with
      | Some b_id when !best_dice > 0.5 -> add_match m a_id b_id
      | _ -> ()
    end
  done

(* --- Phase 3: Children alignment (LCS) --- *)

let phase3 m tbl_a tbl_b =
  (* For each matched pair, align their children using LCS *)
  Hashtbl.iter (fun a_id b_id ->
    let ann_a = Hashtbl.find tbl_a a_id in
    let ann_b = Hashtbl.find tbl_b b_id in
    let ca = ann_a.children_ids in
    let cb = ann_b.children_ids in
    (* LCS keyed on match-partner identity: two children "equal" if they
       are already matched to each other *)
    let eq ai bi = partner_of_a m ai = Some bi in
    let edits = Lcs.diff ~eq ca cb in
    (* For Keep entries where children weren't matched, try matching now *)
    List.iter (fun edit ->
      match edit with
      | Lcs.Keep (ai, bi) ->
        if not (is_matched_a m ai) then begin
          let aa = Hashtbl.find tbl_a ai in
          let ab = Hashtbl.find tbl_b bi in
          if String.equal aa.node.tag ab.node.tag then
            add_match m ai bi
        end
      | Lcs.Insert _ | Lcs.Delete _ -> ()
    ) edits
  ) m.a_to_b

(* --- Post-processing: symmetrization and ancestor repair --- *)

(* Run the three-phase matcher on a single direction. *)
let match_directed tbl_a root_a n_a tbl_b root_b n_b =
  let m = make_matching n_a n_b in
  let ra = Hashtbl.find tbl_a root_a in
  let rb = Hashtbl.find tbl_b root_b in
  if String.equal ra.node.tag rb.node.tag then
    add_match m root_a root_b;
  phase1 m tbl_a tbl_b n_a n_b;
  phase2 m tbl_a tbl_b n_a n_b;
  phase3 m tbl_a tbl_b;
  m

(* Intersect two matchings: keep only pairs (a, b) present in m_ab
   AND (b, a) present in m_ba (i.e., both directions agree). *)
let intersect m_ab m_ba n_a n_b =
  let m = make_matching n_a n_b in
  for a_id = 0 to n_a - 1 do
    match Hashtbl.find_opt m_ab.a_to_b a_id with
    | Some b_id ->
      (* Check the reverse matching agrees *)
      (match Hashtbl.find_opt m_ba.a_to_b b_id with
       | Some a_id' when a_id' = a_id -> add_match m a_id b_id
       | _ -> ())
    | None -> ()
  done;
  m

(* Compute pre/post-order numbering for O(1) ancestry queries.
   is_ancestor x y = true iff x is a proper ancestor of y. *)
let make_ancestry tbl n =
  let pre = Array.make n 0 in
  let post = Array.make n 0 in
  let pre_c = ref 0 in
  let post_c = ref 0 in
  let root = ref 0 in
  for id = 0 to n - 1 do
    if (Hashtbl.find tbl id).parent = None then root := id
  done;
  let rec number id =
    let ann = Hashtbl.find tbl id in
    pre.(id) <- !pre_c; incr pre_c;
    List.iter number ann.children_ids;
    post.(id) <- !post_c; incr post_c
  in
  number !root;
  fun x y -> x <> y && pre.(x) <= pre.(y) && post.(x) >= post.(y)

(* Remove matched pairs that violate ancestor preservation in one direction.
   For each pair (a, b): if any matched ancestor of [a] in [tbl_src] has
   a partner that is NOT an ancestor of [b] in the other tree, remove the pair.
   Processes leaves first so removals don't cascade upward. *)
let repair_one_direction m tbl_src is_ancestor_dst src_to_dst dst_to_src =
  let pairs = ref [] in
  Hashtbl.iter (fun src_id dst_id ->
    let ann = Hashtbl.find tbl_src src_id in
    pairs := (ann.size, src_id, dst_id) :: !pairs
  ) src_to_dst;
  let pairs = List.sort (fun (s1, _, _) (s2, _, _) -> compare s1 s2) !pairs in
  List.iter (fun (_size, src_id, dst_id) ->
    if Hashtbl.mem src_to_dst src_id then begin
      let violates = ref false in
      let cur = ref (Hashtbl.find tbl_src src_id).parent in
      while !cur <> None && not !violates do
        let anc = match !cur with Some id -> id | None -> assert false in
        (match Hashtbl.find_opt src_to_dst anc with
         | Some anc_dst ->
           if not (is_ancestor_dst anc_dst dst_id) then
             violates := true
         | None -> ());
        cur := (Hashtbl.find tbl_src anc).parent
      done;
      if !violates then begin
        Hashtbl.remove src_to_dst src_id;
        Hashtbl.remove dst_to_src dst_id;
        ignore m (* keep m reachable for clarity *)
      end
    end
  ) pairs

(* Remove pairs violating ancestor preservation in either direction.
   A valid matching must preserve ancestry both ways: if x ancestor of y
   in A and both matched, then partner(x) ancestor of partner(y) in B,
   AND vice versa. *)
let repair_ancestors m tbl_a tbl_b n_a n_b =
  let is_ancestor_b = make_ancestry tbl_b n_b in
  let is_ancestor_a = make_ancestry tbl_a n_a in
  (* Forward: check A ancestors map to B ancestors *)
  repair_one_direction m tbl_a is_ancestor_b m.a_to_b m.b_to_a;
  (* Reverse: check B ancestors map to A ancestors *)
  repair_one_direction m tbl_b is_ancestor_a m.b_to_a m.a_to_b

(* --- Main entry point --- *)

let match_trees a b =
  let (tbl_a, root_a, n_a) = annotate a in
  let (tbl_b, root_b, n_b) = annotate b in
  (* Step A: run matching in both directions and intersect *)
  let m_ab = match_directed tbl_a root_a n_a tbl_b root_b n_b in
  let m_ba = match_directed tbl_b root_b n_b tbl_a root_a n_a in
  let m = intersect m_ab m_ba n_a n_b in
  (* Step B: remove pairs that violate ancestor preservation (both ways) *)
  repair_ancestors m tbl_a tbl_b n_a n_b;
  m
