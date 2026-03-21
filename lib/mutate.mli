(** Mutation testing for snapshot sensitivity measurement.

    Mutates CSS properties in typed snapshot trees and measures whether
    sosie's comparison pipeline detects each mutation. The mutation score
    (killed / non-equivalent) quantifies sensitivity.

    Mutation operators follow the design doc (lines 1095–1105):
    numeric perturbation, color replacement, reset-to-default, sibling
    swap, keyword change, and visibility toggle. *)

open Sosie_shared.Snapshot_types

(** {2 Mutation operators} *)

type operator =
  | Perturb_numeric
  | Replace_color
  | Reset_to_default
  | Swap_siblings
  | Change_keyword
  | Toggle_visibility

val operator_to_string : operator -> string
(** Human-readable name for an operator. *)

(** {2 Mutations} *)

type mutation = {
  node_index : int;
  (** Pre-order index of the target node in the snapshot tree. *)
  property : string;
  (** CSS property name (e.g., ["font-size"], ["color"]). *)
  operator : operator;
  original : css_value;
  (** Original value at [node_index]/[property]. *)
  mutated : css_value;
  (** Replacement value. Always differs from [original]. *)
}

(** {2 Enumeration and application} *)

val enumerate_mutations : snapshot -> mutation list
(** [enumerate_mutations snap] walks the tree in pre-order and returns
    all applicable (node, property, operator) combinations with concrete
    original and mutated values. Never produces identity mutations
    (where [original = mutated]).

    @return list of mutations in pre-order × property × operator order *)

val apply_mutation : snapshot -> mutation -> snapshot
(** [apply_mutation snap m] returns a new snapshot with the value at
    [m.node_index]/[m.property] replaced by [m.mutated]. All other
    nodes and properties are unchanged.

    @raise Invalid_argument if [m.node_index] is out of range or
      [m.property] is not a recognized property name. *)

(** {2 Sampling} *)

val sample : Random.State.t -> int -> mutation list -> mutation list
(** [sample rng n mutations] picks [n] mutations uniformly at random
    without replacement. Returns all if [n >= List.length mutations]. *)

(** {2 Harness} *)

type outcome =
  | Equivalent  (** Mutation is pixel-identical to baseline — not a bug. *)
  | Killed      (** Mutation detected by comparison — good. *)
  | Survived    (** Mutation NOT detected — false negative. *)

type result = {
  mutation : mutation;
  outcome : outcome;
}

val run :
  Cdp.connection ->
  extractor_js:string ->
  config:Config.t ->
  viewport:(int * int) ->
  snapshot ->
  mutations:mutation list ->
  on_progress:(int -> int -> unit) ->
  result list
(** [run conn ~extractor_js ~config ~viewport snap ~mutations ~on_progress]
    executes each mutation against a browser baseline:

    1. Render baseline HTML, capture baseline snapshot and screenshot.
    2. For each mutation: render mutant, screenshot; if pixel-identical
       mark [Equivalent]; otherwise capture+normalize+compare.
    3. [on_progress i total] is called after processing mutation [i].

    @return one {!result} per mutation, in the same order as [mutations]. *)

(** {2 Reporting} *)

val report : root:node -> result list -> string
(** [report ~root results] formats a human-readable mutation score summary.
    Shows total/equivalent/killed/survived counts, per-property breakdown,
    and lists surviving mutants with XPath paths.

    @param root the snapshot root, used for XPath rendering. *)
