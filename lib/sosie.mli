(** sosie — DOM equivalence checker for UI-conservative HTML/CSS refactoring.

    This is the top-level module of the sosie library. It captures resolved
    layout and style trees from a browser and compares them structurally to
    detect visual regressions introduced by HTML/CSS refactoring. *)

val version : string
(** The sosie version string. *)
