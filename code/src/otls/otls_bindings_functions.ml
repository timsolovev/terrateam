(* The ctypes stanza's [function_description] exists so dune emits a C
   stub archive for otls — that archive pulls [-ltls] into every
   consumer's final link. We declare a single libtls function so the
   generated C has a real undefined reference to libtls, which forces
   the linker to follow through. The real libtls bindings live in
   [otls_c_bindings.ml] and are resolved at runtime via
   ctypes.foreign/dlopen. *)
module Functions (F : Ctypes.FOREIGN) = struct
  open Ctypes

  let tls_init = F.(foreign "tls_init" (void @-> returning int))
end
