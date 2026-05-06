(* Shim so the dune (ctypes ...) stanza finds a functor named [Types] in a
   local module. The upstream functor is named [Stubs]; we expose it under
   the name dune expects. *)
module Types = Otls_bindings.Stubs
