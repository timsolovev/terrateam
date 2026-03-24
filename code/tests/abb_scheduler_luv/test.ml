module Test = Abb_test.Make (Abb_scheduler_luv)

let () = Test.run_tests ()
