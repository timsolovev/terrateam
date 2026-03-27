module List = ListLabels
module Sys_stdlib = Sys
module Unix = UnixLabels

module Fd_map = CCMap.Make (struct
  type t = Unix.file_descr

  let compare = compare
end)

module Native = struct
  type t = Unix.file_descr
end

external unsafe_int_of_file_descr : Unix.file_descr -> int = "%identity"

let sec_ns = Mtime.Span.(to_float_ns s)

(* El is short for Event Loop *)
module El = struct
  type t = {
    loop : Luv.Loop.t;
    mutable curr_time : float;
    mutable mono_time : Mtime.span;
    check : Luv.Check.t;
    thread_pool : (Unix.file_descr * Unix.file_descr) Abb_domain_pool.t;
  }

  type t_ = t

  module Future = Abb_fut.Make (struct
    type t = t_
  end)

  let create ?thread_pool_size () =
    let pool_size =
      CCInt.max 2 (CCOption.get_or ~default:(Domain.recommended_domain_count ()) thread_pool_size)
    in
    let loop = Luv.Loop.init () |> Result.get_ok in
    let check = Luv.Check.init ~loop () |> Result.get_ok in
    let t =
      {
        loop;
        curr_time = Unix.gettimeofday ();
        mono_time = Mtime_clock.elapsed ();
        check;
        thread_pool = Abb_domain_pool.create ~capacity:pool_size ~wait:Unix.pipe;
      }
    in
    ignore
      (Luv.Check.start t.check (fun () ->
           t.curr_time <- Unix.gettimeofday ();
           t.mono_time <- Mtime_clock.elapsed ())
      |> Result.get_ok);
    t

  let destroy t =
    Abb_domain_pool.destroy t.thread_pool;
    ignore (Luv.Check.stop t.check);
    Luv.Handle.close t.check CCFun.id;
    ignore (Luv.Loop.close t.loop)
end

module Future = El.Future

module Scheduler = struct
  type t = El.t Abb_fut.State.t

  let create ?thread_pool_size ?exec_duration:_ () =
    Abb_fut.State.create (El.create ?thread_pool_size ())

  let destroy t = El.destroy (Abb_fut.State.state t)

  let run t f =
    ignore Sys.(signal sigpipe Signal_ignore);
    let ret = f () in
    let t = Future.run_with_state ret t in
    match Future.state ret with
    | (`Det _ | `Aborted | `Exn _) as r -> (t, r)
    | `Undet -> (
        let stopper =
          let open Future.Infix_monad in
          ret
          >>= fun _ ->
          Future.with_state (fun s ->
              let el = Abb_fut.State.state s in
              Luv.Loop.stop el.El.loop;
              (s, Future.return ()))
        in
        let t = Future.run_with_state stopper t in
        let el = Abb_fut.State.state t in
        ignore (Luv.Loop.run ~loop:el.El.loop ());
        match Future.state ret with
        | (`Det _ | `Aborted | `Exn _) as r -> (t, r)
        | `Undet -> assert false)

  let run_with_state ?thread_pool_size ?exec_duration:_ f =
    let t = create ?thread_pool_size () in
    let t, r = run t f in
    destroy t;
    r
end

module Sys = struct
  let sleep duration =
    assert (duration >= 0.0);
    Future.with_state (fun s ->
        let el = Abb_fut.State.state s in
        let timer = Luv.Timer.init ~loop:el.El.loop () |> Result.get_ok in
        let ms = max 1 (int_of_float (duration *. 1000.0)) in
        let p =
          Future.Promise.create
            ~abort:(fun () ->
              ignore (Luv.Timer.stop timer);
              Luv.Handle.close timer CCFun.id;
              Future.return ())
            ()
        in
        ignore
          (Luv.Timer.start timer ms (fun () ->
               ignore (Future.run_with_state (Future.Promise.set p ()) s);
               Luv.Handle.close timer CCFun.id)
          |> Result.get_ok);
        (s, Future.Promise.future p))

  let time () =
    Future.with_state (fun s ->
        let el = Abb_fut.State.state s in
        (s, Future.return el.El.curr_time))

  let monotonic () =
    Future.with_state (fun s ->
        let el = Abb_fut.State.state s in
        (s, Future.return Mtime.Span.(to_float_ns el.El.mono_time /. sec_ns)))
end

module Thread = struct
  let run f =
    Future.with_state (fun s ->
        let el = Abb_fut.State.state s in
        let ret = ref None in
        let aborted = ref false in
        let trigger (_, trigger_fd) res =
          ret := Some res;
          (try ignore (Unix.write trigger_fd ~buf:(Bytes.of_string "0") ~pos:0 ~len:1)
           with Unix.Unix_error _ -> ());
          Unix.close trigger_fd
        in
        let wait, _write_end = Abb_domain_pool.enqueue el.El.thread_pool ~f ~trigger in
        let poll =
          Luv.Poll.init ~loop:el.El.loop (unsafe_int_of_file_descr wait) |> Result.get_ok
        in
        let abort () =
          Future.with_state (fun s ->
              let el = Abb_fut.State.state s in
              let timer = Luv.Timer.init ~loop:el.El.loop () |> Result.get_ok in
              ignore
                (Luv.Timer.start timer 0 (fun () ->
                     aborted := true;
                     ignore (Luv.Poll.stop poll);
                     Luv.Handle.close poll (fun () -> try Unix.close wait with _ -> ());
                     Luv.Handle.close timer CCFun.id)
                |> Result.get_ok);
              (s, Future.return ()))
        in
        let p = Future.Promise.create ~abort () in
        Luv.Poll.start poll [ `READABLE ] (fun _result ->
            ignore (Luv.Poll.stop poll);
            let fut =
              match !ret with
              | Some (Ok v) -> Future.Promise.set p v
              | Some (Error exn) -> Future.Promise.set_exn p exn
              | None when !aborted -> Future.return ()
              | None -> assert false
            in
            ignore (Future.run_with_state fut s);
            Luv.Handle.close poll (fun () -> try Unix.close wait with _ -> ()));
        (s, Future.Promise.future p))
end

let safe_call f = try Ok (f ()) with e -> Error (`Unexpected e)

(* The filesystem calls are implemented through a thread call because there is
   no guarantee that they will not block, for example on an NFS system. *)
module File = struct
  type t = Unix.file_descr

  let to_native t = t
  let of_native t = t
  let stdin = Unix.stdin
  let stdout = Unix.stdout
  let stderr = Unix.stderr

  let mode_of_flags flags =
    List.map
      ~f:
        Abb_intf.File.Flag.(
          function
          | Read_only -> Unix.O_RDONLY
          | Write_only -> Unix.O_WRONLY
          | Create _ -> Unix.O_CREAT
          | Read_write -> Unix.O_RDWR
          | Append -> Unix.O_APPEND
          | Truncate -> Unix.O_TRUNC
          | Exclusive -> Unix.O_EXCL)
      flags

  let perm_of_flags flags =
    let creates =
      List.filter
        ~f:
          Abb_intf.File.Flag.(
            function
            | Create _ -> true
            | _ -> false)
        flags
    in
    match creates with
    | [ Abb_intf.File.Flag.Create perm ] -> perm
    | _ -> 0

  let open_file ~flags path =
    try
      let t =
        Unix.openfile
          path
          ~mode:(Unix.O_CLOEXEC :: Unix.O_NONBLOCK :: mode_of_flags flags)
          ~perm:(perm_of_flags flags)
      in
      Future.return (Ok t)
    with
    | Unix.Unix_error (err, _, _) as exn ->
        let open Unix in
        Future.return
          (Error
             (match err with
             | ENOTDIR -> `E_not_dir
             | ENAMETOOLONG -> `E_name_too_long
             | ENOENT -> `E_no_entity
             | EACCES -> `E_access
             | EROFS | EPERM -> `E_permission
             | ELOOP -> `E_loop
             | ENFILE | EMFILE -> `E_file_table_full
             | ENOSPC -> `E_no_space
             | EIO -> `E_io
             | EEXIST -> `E_exists
             | EINVAL -> `E_invalid
             | _ -> `Unexpected exn))
    | exn -> Future.return (Error (`Unexpected exn))

  let read t ~buf ~pos ~len =
    try Future.return (Ok (Unix.read t ~buf ~pos ~len)) with
    | Unix.Unix_error (Unix.EAGAIN, _, _) | Unix.Unix_error (Unix.EWOULDBLOCK, _, _) ->
        Future.with_state (fun s ->
            let el = Abb_fut.State.state s in
            let poll =
              Luv.Poll.init ~loop:el.El.loop (unsafe_int_of_file_descr t) |> Result.get_ok
            in
            let p =
              Future.Promise.create
                ~abort:(fun () ->
                  ignore (Luv.Poll.stop poll);
                  Luv.Handle.close poll CCFun.id;
                  Future.return ())
                ()
            in
            Luv.Poll.start poll [ `READABLE ] (fun _result ->
                ignore (Luv.Poll.stop poll);
                Luv.Handle.close poll CCFun.id;
                ignore
                  (Future.run_with_state
                     (Future.Promise.set
                        p
                        (try Ok (Unix.read t ~buf ~pos ~len) with
                        | Unix.Unix_error (err, _, _) as exn ->
                            let open Unix in
                            Error
                              (match err with
                              | EBADF -> `E_bad_file
                              | EIO -> `E_io
                              | EINVAL -> `E_invalid
                              | EISDIR -> `E_is_dir
                              | _ -> `Unexpected exn)
                        | exn -> Error (`Unexpected exn)))
                     s));
            (s, Future.Promise.future p))
    | Unix.Unix_error (err, _, _) as exn ->
        let open Unix in
        Future.return
          (Error
             (match err with
             | EBADF -> `E_bad_file
             | EIO -> `E_io
             | EINVAL -> `E_invalid
             | EISDIR -> `E_is_dir
             | _ -> `Unexpected exn))
    | exn -> Future.return (Error (`Unexpected exn))

  let pread t ~offset ~buf ~pos ~len =
    try
      let n = Unix.lseek t offset ~mode:Unix.SEEK_SET in
      assert (n = offset);
      read t ~buf ~pos ~len
    with
    | Unix.Unix_error (Unix.ENXIO, _, _) -> Future.return (Error `E_nxio)
    | exn -> Future.return (Error (`Unexpected exn))

  let write' ~buf ~pos ~len t =
    try Future.return (Ok (Unix.write t ~buf ~pos ~len)) with
    | Unix.Unix_error (Unix.EAGAIN, _, _) | Unix.Unix_error (Unix.EWOULDBLOCK, _, _) ->
        Future.with_state (fun s ->
            let el = Abb_fut.State.state s in
            let poll =
              Luv.Poll.init ~loop:el.El.loop (unsafe_int_of_file_descr t) |> Result.get_ok
            in
            let p =
              Future.Promise.create
                ~abort:(fun () ->
                  ignore (Luv.Poll.stop poll);
                  Luv.Handle.close poll CCFun.id;
                  Future.return ())
                ()
            in
            Luv.Poll.start poll [ `WRITABLE ] (fun _result ->
                ignore (Luv.Poll.stop poll);
                Luv.Handle.close poll CCFun.id;
                ignore
                  (Future.run_with_state
                     (Future.Promise.set
                        p
                        (try Ok (Unix.write t ~buf ~pos ~len) with
                        | Unix.Unix_error (err, _, _) as exn ->
                            let open Unix in
                            Error
                              (match err with
                              | EBADF -> `E_bad_file
                              | EPIPE -> `E_pipe
                              | EINVAL -> `E_invalid
                              | ENOSPC -> `E_no_space
                              | EIO -> `E_io
                              | EROFS -> `E_permission
                              | _ -> `Unexpected exn)
                        | exn -> Error (`Unexpected exn)))
                     s));
            (s, Future.Promise.future p))
    | Unix.Unix_error (err, _, _) as exn ->
        let open Unix in
        Future.return
          (Error
             (match err with
             | EBADF -> `E_bad_file
             | EPIPE -> `E_pipe
             | EINVAL -> `E_invalid
             | ENOSPC -> `E_no_space
             | EIO -> `E_io
             | EROFS -> `E_permission
             | _ -> `Unexpected exn))
    | exn -> Future.return (Error (`Unexpected exn))

  let rec write_buf t buf =
    let open Future.Infix_monad in
    write'
      t
      ~buf:buf.Abb_intf.Write_buf.buf
      ~pos:buf.Abb_intf.Write_buf.pos
      ~len:buf.Abb_intf.Write_buf.len
    >>= function
    | Ok n when n < buf.Abb_intf.Write_buf.len -> (
        let buf = Abb_intf.Write_buf.{ buf with pos = buf.pos + n; len = buf.len - n } in
        write_buf t buf
        >>= function
        | Ok n' -> Future.return (Ok (n + n'))
        | Error _ as err -> Future.return err)
    | Ok n -> Future.return (Ok n)
    | Error _ as err -> Future.return err

  let write_bufs t bufs =
    let rec write_bufs' t = function
      | [] -> Future.return (Ok 0)
      | b :: bs -> (
          let open Future.Infix_monad in
          write_buf t b
          >>= function
          | Ok n -> (
              write_bufs' t bs
              >>= function
              | Ok n' -> Future.return (Ok (n + n'))
              | Error _ as err -> Future.return err)
          | Error _ as err -> Future.return err)
    in
    write_bufs' t bufs

  let write t bufs = write_bufs t bufs

  let pwrite t ~offset bufs =
    try
      let n = Unix.lseek t offset ~mode:Unix.SEEK_SET in
      assert (n = offset);
      write_bufs t bufs
    with
    | Unix.Unix_error (Unix.ENXIO, _, _) -> Future.return (Error `E_nxio)
    | exn -> Future.return (Error (`Unexpected exn))

  let lseek' t ~offset = function
    | Abb_intf.File.Seek.Cur ->
        ignore (Unix.lseek t offset ~mode:Unix.SEEK_CUR);
        Ok ()
    | Abb_intf.File.Seek.Set ->
        ignore (Unix.lseek t offset ~mode:Unix.SEEK_SET);
        Ok ()
    | Abb_intf.File.Seek.End ->
        ignore (Unix.lseek t offset ~mode:Unix.SEEK_END);
        Ok ()

  let lseek t ~offset seek =
    try lseek' t ~offset seek with
    | Unix.Unix_error (err, _, _) as exn ->
        let open Unix in
        Error
          (match err with
          | EBADF -> `E_bad_file
          | ENXIO -> `E_nxio
          | EINVAL -> `E_invalid
          | _ -> `Unexpected exn)
    | exn -> Error (`Unexpected exn)

  let close t =
    Future.with_state (fun s ->
        let el = Abb_fut.State.state s in
        let timer = Luv.Timer.init ~loop:el.El.loop () |> Result.get_ok in
        ignore
          (Luv.Timer.start timer 0 (fun () ->
               Luv.Handle.close timer (fun () -> try Unix.close t with _ -> ()))
          |> Result.get_ok);
        (s, Future.return (Ok ())))

  let unlink path =
    try Future.return (Ok (Unix.unlink path)) with
    | Unix.Unix_error (err, _, _) as exn ->
        let open Unix in
        Future.return
          (Error
             (match err with
             | ENOTDIR -> `E_not_dir
             | EISDIR -> `E_is_dir
             | ENAMETOOLONG -> `E_name_too_long
             | ENOENT -> `E_no_entity
             | EACCES -> `E_access
             | ELOOP -> `E_loop
             | EPERM -> `E_permission
             | EIO -> `E_io
             | ENOSPC -> `E_no_space
             | _ -> `Unexpected exn))
    | exn -> Future.return (Error (`Unexpected exn))

  let mkdir path perm =
    Thread.run (fun () ->
        try Ok (Unix.mkdir ~perm path) with
        | Unix.Unix_error (err, _, _) as exn ->
            let open Unix in
            Error
              (match err with
              | ENOTDIR -> `E_not_dir
              | EISDIR -> `E_is_dir
              | ENAMETOOLONG -> `E_name_too_long
              | ENOENT -> `E_no_entity
              | EACCES -> `E_access
              | ELOOP -> `E_loop
              | EPERM -> `E_permission
              | EIO -> `E_io
              | ENOSPC -> `E_no_space
              | EEXIST -> `E_exists
              | _ -> `Unexpected exn)
        | exn -> Error (`Unexpected exn))

  let rmdir path =
    Thread.run (fun () ->
        try Ok (Unix.rmdir path) with
        | Unix.Unix_error (err, _, _) as exn ->
            let open Unix in
            Error
              (match err with
              | ENOTDIR -> `E_not_dir
              | ENAMETOOLONG -> `E_name_too_long
              | ENOENT -> `E_no_entity
              | ENOTEMPTY -> `E_not_empty
              | EACCES -> `E_access
              | ELOOP -> `E_loop
              | EPERM -> `E_permission
              | EINVAL -> `E_invalid
              | EBUSY -> `E_busy
              | EIO -> `E_io
              | EEXIST -> `E_exists
              | _ -> `Unexpected exn)
        | exn -> Error (`Unexpected exn))

  let readdir path =
    Thread.run (fun () -> safe_call (fun () -> Array.to_list (Sys_stdlib.readdir path)))

  let of_unix_stat stat =
    let of_file_kind = function
      | Unix.S_REG -> Abb_intf.File.File_kind.Regular
      | Unix.S_DIR -> Abb_intf.File.File_kind.Directory
      | Unix.S_CHR -> Abb_intf.File.File_kind.Char
      | Unix.S_BLK -> Abb_intf.File.File_kind.Block
      | Unix.S_LNK -> Abb_intf.File.File_kind.Symlink
      | Unix.S_FIFO -> Abb_intf.File.File_kind.Fifo
      | Unix.S_SOCK -> Abb_intf.File.File_kind.Socket
    in
    Abb_intf.File.Stat.
      {
        dev = stat.Unix.st_dev;
        inode = stat.Unix.st_ino;
        kind = of_file_kind stat.Unix.st_kind;
        perm = stat.Unix.st_perm;
        num_links = stat.Unix.st_nlink;
        uid = stat.Unix.st_uid;
        gid = stat.Unix.st_gid;
        rdev = stat.Unix.st_rdev;
        size = stat.Unix.st_size;
        atime = stat.Unix.st_atime;
        mtime = stat.Unix.st_mtime;
        ctime = stat.Unix.st_ctime;
      }

  let stat path =
    Thread.run (fun () ->
        try Ok (of_unix_stat (Unix.stat path)) with
        | Unix.Unix_error (err, _, _) as exn ->
            let open Unix in
            Error
              (match err with
              | EACCES -> `E_access
              | EIO -> `E_io
              | ELOOP -> `E_loop
              | ENAMETOOLONG -> `E_name_too_long
              | ENOENT -> `E_no_entity
              | ENOTDIR -> `E_not_dir
              | _ -> `Unexpected exn)
        | exn -> Error (`Unexpected exn))

  let fstat t =
    Thread.run (fun () ->
        try Ok (of_unix_stat (Unix.fstat t)) with
        | Unix.Unix_error (err, _, _) as exn ->
            let open Unix in
            Error
              (match err with
              | EBADF -> `E_bad_file
              | EINVAL -> `E_invalid
              | EACCES -> `E_access
              | EIO -> `E_io
              | ELOOP -> `E_loop
              | ENAMETOOLONG -> `E_name_too_long
              | ENOENT -> `E_no_entity
              | ENOTDIR -> `E_not_dir
              | _ -> `Unexpected exn)
        | exn -> Error (`Unexpected exn))

  let lstat path =
    Thread.run (fun () ->
        try Ok (of_unix_stat (Unix.lstat path)) with
        | Unix.Unix_error (err, _, _) as exn ->
            let open Unix in
            Error
              (match err with
              | EACCES -> `E_access
              | EIO -> `E_io
              | ELOOP -> `E_loop
              | ENAMETOOLONG -> `E_name_too_long
              | ENOENT -> `E_no_entity
              | ENOTDIR -> `E_not_dir
              | _ -> `Unexpected exn)
        | exn -> Error (`Unexpected exn))

  let rename ~src ~dst =
    Thread.run (fun () ->
        try Ok (Unix.rename ~src ~dst) with
        | Unix.Unix_error (err, _, _) as exn ->
            let open Unix in
            Error
              (match err with
              | ENAMETOOLONG -> `E_name_too_long
              | ENOENT -> `E_no_entity
              | EACCES -> `E_access
              | EPERM | EROFS -> `E_permission
              | ELOOP -> `E_loop
              | ENOTDIR -> `E_not_dir
              | EISDIR -> `E_is_dir
              | ENOSPC -> `E_no_space
              | EIO -> `E_io
              | EINVAL -> `E_invalid
              | ENOTEMPTY -> `E_not_empty
              | _ -> `Unexpected exn)
        | exn -> Error (`Unexpected exn))

  let truncate path len =
    Thread.run (fun () ->
        try Ok (Unix.truncate path ~len:(Int64.to_int len)) with
        | Unix.Unix_error (err, _, _) as exn ->
            let open Unix in
            Error
              (match err with
              | ENOTDIR -> `E_not_dir
              | ENAMETOOLONG -> `E_name_too_long
              | ENOENT -> `E_no_entity
              | EACCES -> `E_access
              | ELOOP -> `E_loop
              | EROFS | EPERM -> `E_permission
              | EISDIR -> `E_is_dir
              | EINVAL -> `E_invalid
              | EIO -> `E_io
              | _ -> `Unexpected exn)
        | exn -> Error (`Unexpected exn))

  let ftruncate t len =
    Thread.run (fun () ->
        try Ok (Unix.ftruncate t ~len:(Int64.to_int len)) with
        | Unix.Unix_error (err, _, _) as exn ->
            let open Unix in
            Error
              (match err with
              | EBADF -> `E_bad_file
              | ENOTDIR -> `E_not_dir
              | ENAMETOOLONG -> `E_name_too_long
              | ENOENT -> `E_no_entity
              | EACCES -> `E_access
              | ELOOP -> `E_loop
              | EROFS | EPERM -> `E_permission
              | EISDIR -> `E_is_dir
              | EINVAL -> `E_invalid
              | EIO -> `E_io
              | _ -> `Unexpected exn)
        | exn -> Error (`Unexpected exn))

  let chmod path mode =
    Thread.run (fun () ->
        try Ok (Unix.chmod path ~perm:mode) with
        | Unix.Unix_error (err, _, _) as exn ->
            let open Unix in
            Error
              (match err with
              | ENOTDIR -> `E_not_dir
              | ENAMETOOLONG -> `E_name_too_long
              | ENOENT -> `E_no_entity
              | EACCES -> `E_access
              | ELOOP -> `E_loop
              | EROFS | EPERM -> `E_permission
              | EIO -> `E_io
              | _ -> `Unexpected exn)
        | exn -> Error (`Unexpected exn))

  let fchmod t mode =
    Thread.run (fun () ->
        try Ok (Unix.fchmod t ~perm:mode) with
        | Unix.Unix_error (err, _, _) as exn ->
            let open Unix in
            Error
              (match err with
              | EBADF -> `E_bad_file
              | EINVAL -> `E_invalid
              | ENOTDIR -> `E_not_dir
              | ENAMETOOLONG -> `E_name_too_long
              | ENOENT -> `E_no_entity
              | EACCES -> `E_access
              | ELOOP -> `E_loop
              | EROFS | EPERM -> `E_permission
              | EIO -> `E_io
              | _ -> `Unexpected exn)
        | exn -> Error (`Unexpected exn))

  let symlink ~src ~dst =
    Thread.run (fun () ->
        try Ok (Unix.symlink ~to_dir:false ~src ~dst) with
        | Unix.Unix_error (err, _, _) as exn ->
            let open Unix in
            Error
              (match err with
              | ENOTDIR -> `E_not_dir
              | ENAMETOOLONG -> `E_name_too_long
              | ENOENT -> `E_no_entity
              | EACCES -> `E_access
              | ELOOP -> `E_loop
              | EEXIST -> `E_exists
              | EROFS | EPERM -> `E_permission
              | EIO -> `E_io
              | ENOSPC -> `E_no_space
              | _ -> `Unexpected exn)
        | exn -> Error (`Unexpected exn))

  let link ~src ~dst =
    Thread.run (fun () ->
        try Ok (Unix.link ~follow:true ~src ~dst) with
        | Unix.Unix_error (err, _, _) as exn ->
            let open Unix in
            Error
              (match err with
              | ENOTDIR -> `E_not_dir
              | ENAMETOOLONG -> `E_name_too_long
              | ENOENT -> `E_no_entity
              | EOPNOTSUPP -> `E_op_not_supported
              | EACCES -> `E_access
              | ELOOP -> `E_loop
              | EEXIST -> `E_exists
              | EROFS | EPERM -> `E_permission
              | EIO -> `E_io
              | ENOSPC -> `E_no_space
              | _ -> `Unexpected exn)
        | exn -> Error (`Unexpected exn))

  let chown path ~uid ~gid =
    Thread.run (fun () ->
        try Ok (Unix.chown path ~uid ~gid) with
        | Unix.Unix_error (err, _, _) as exn ->
            let open Unix in
            Error
              (match err with
              | ENOTDIR -> `E_not_dir
              | ENAMETOOLONG -> `E_name_too_long
              | ENOENT -> `E_no_entity
              | EACCES -> `E_access
              | ELOOP -> `E_loop
              | EROFS | EPERM -> `E_permission
              | EIO -> `E_io
              | _ -> `Unexpected exn)
        | exn -> Error (`Unexpected exn))

  let fchown t ~uid ~gid =
    Thread.run (fun () ->
        try Ok (Unix.fchown t ~uid ~gid) with
        | Unix.Unix_error (err, _, _) as exn ->
            let open Unix in
            Error
              (match err with
              | EBADF -> `E_bad_file
              | ENOTDIR -> `E_not_dir
              | ENAMETOOLONG -> `E_name_too_long
              | ENOENT -> `E_no_entity
              | EACCES -> `E_access
              | ELOOP -> `E_loop
              | EROFS | EPERM -> `E_permission
              | EIO -> `E_io
              | _ -> `Unexpected exn)
        | exn -> Error (`Unexpected exn))
end

module Socket = struct
  type tcp
  type udp
  type _ t = Unix.file_descr

  let unix_of_domain = function
    | Abb_intf.Socket.Domain.Unix -> Unix.PF_UNIX
    | Abb_intf.Socket.Domain.Inet4 -> Unix.PF_INET
    | Abb_intf.Socket.Domain.Inet6 -> Unix.PF_INET6

  let domain_of_unix = function
    | Unix.PF_UNIX -> Abb_intf.Socket.Domain.Unix
    | Unix.PF_INET -> Abb_intf.Socket.Domain.Inet4
    | Unix.PF_INET6 -> Abb_intf.Socket.Domain.Inet6

  let socket_type_of_unix = function
    | Unix.SOCK_STREAM -> Abb_intf.Socket.Socket_type.Stream
    | Unix.SOCK_DGRAM -> Abb_intf.Socket.Socket_type.Dgram
    | Unix.SOCK_RAW -> Abb_intf.Socket.Socket_type.Raw
    | Unix.SOCK_SEQPACKET -> Abb_intf.Socket.Socket_type.Seqpacket

  let unix_of_socket_type = function
    | Abb_intf.Socket.Socket_type.Stream -> Unix.SOCK_STREAM
    | Abb_intf.Socket.Socket_type.Dgram -> Unix.SOCK_DGRAM
    | Abb_intf.Socket.Socket_type.Raw -> Unix.SOCK_RAW
    | Abb_intf.Socket.Socket_type.Seqpacket -> Unix.SOCK_SEQPACKET

  let addrinfo_of_unix_addrinfo ai =
    let family = domain_of_unix ai.Unix.ai_family in
    let sock_type = socket_type_of_unix ai.Unix.ai_socktype in
    let addr =
      match ai.Unix.ai_addr with
      | Unix.ADDR_UNIX s -> Abb_intf.Socket.Sockaddr.Unix s
      | Unix.ADDR_INET (a, p) -> Abb_intf.Socket.Sockaddr.(Inet { addr = a; port = p })
    in
    Abb_intf.Socket.Addrinfo.
      { family; sock_type; protocol = ai.Unix.ai_protocol; addr; canon_name = ai.Unix.ai_canonname }

  let unix_sockaddr_of_sockaddr = function
    | Abb_intf.Socket.Sockaddr.Unix s -> Unix.ADDR_UNIX s
    | Abb_intf.Socket.Sockaddr.Inet inet ->
        Abb_intf.Socket.Sockaddr.(Unix.ADDR_INET (inet.addr, inet.port))

  let sockaddr_of_unix_sockaddr = function
    | Unix.ADDR_UNIX s -> Abb_intf.Socket.Sockaddr.Unix s
    | Unix.ADDR_INET (addr, port) -> Abb_intf.Socket.Sockaddr.(Inet { addr; port })

  let getaddrinfo_options_of_hints hints =
    List.map
      ~f:
        Abb_intf.Socket.Addrinfo_hints.(
          function
          | Family domain -> Unix.AI_FAMILY (unix_of_domain domain)
          | Socket_type socktype -> Unix.AI_SOCKTYPE (unix_of_socket_type socktype)
          | Protocol p -> Unix.AI_PROTOCOL p
          | Numeric_host -> Unix.AI_NUMERICHOST
          | Canon_name -> Unix.AI_CANONNAME
          | Passive -> Unix.AI_PASSIVE)
      hints

  let getaddrinfo ?hints query =
    Thread.run (fun () ->
        safe_call (fun () ->
            let hints =
              match hints with
              | Some h -> h
              | None -> []
            in
            let ai =
              match query with
              | Abb_intf.Socket.Addrinfo_query.Host h ->
                  Unix.getaddrinfo h "" (getaddrinfo_options_of_hints hints)
              | Abb_intf.Socket.Addrinfo_query.Service s ->
                  Unix.getaddrinfo "" s (getaddrinfo_options_of_hints hints)
              | Abb_intf.Socket.Addrinfo_query.Host_service (h, s) ->
                  Unix.getaddrinfo h s (getaddrinfo_options_of_hints hints)
            in
            List.map ~f:addrinfo_of_unix_addrinfo ai))

  let getsockname t =
    match Unix.getsockname t with
    | Unix.ADDR_UNIX str -> Abb_intf.Socket.Sockaddr.Unix str
    | Unix.ADDR_INET (addr, port) -> Abb_intf.Socket.Sockaddr.(Inet { addr; port })

  let getpeername t =
    match Unix.getpeername t with
    | Unix.ADDR_UNIX str -> Abb_intf.Socket.Sockaddr.Unix str
    | Unix.ADDR_INET (addr, port) -> Abb_intf.Socket.Sockaddr.(Inet { addr; port })

  let recvfrom t ~buf ~pos ~len =
    Future.with_state (fun s ->
        let el = Abb_fut.State.state s in
        let poll = Luv.Poll.init ~loop:el.El.loop (unsafe_int_of_file_descr t) |> Result.get_ok in
        let p =
          Future.Promise.create
            ~abort:(fun () ->
              ignore (Luv.Poll.stop poll);
              Luv.Handle.close poll CCFun.id;
              Future.return ())
            ()
        in
        Luv.Poll.start poll [ `READABLE ] (fun _result ->
            ignore (Luv.Poll.stop poll);
            Luv.Handle.close poll CCFun.id;
            ignore
              (Future.run_with_state
                 (Future.Promise.set
                    p
                    (try
                       let n, addr = Unix.recvfrom t ~buf ~pos ~len ~mode:[] in
                       Ok (n, sockaddr_of_unix_sockaddr addr)
                     with
                    | Unix.Unix_error (err, _, _) as exn ->
                        let open Unix in
                        Error
                          (match err with
                          | EBADF -> `E_bad_file
                          | ECONNRESET -> `E_connection_reset
                          | _ -> `Unexpected exn)
                    | exn -> Error (`Unexpected exn)))
                 s));
        (s, Future.Promise.future p))

  let sendto t ~bufs sockaddr =
    let p =
      Future.Promise.create
        ~abort:(fun () ->
          Future.with_state (fun s ->
              (* We don't track the poll handle here so we can't stop it on abort.
                 The poll callback will detect the aborted promise and no-op. *)
              (s, Future.return ())))
        ()
    in
    let addr = unix_sockaddr_of_sockaddr sockaddr in
    let rec send' ~total ~pos = function
      | [] -> Future.Promise.set p (Ok total)
      | wb :: bufs as all_bufs ->
          Future.with_state (fun s ->
              let el = Abb_fut.State.state s in
              let poll =
                Luv.Poll.init ~loop:el.El.loop (unsafe_int_of_file_descr t) |> Result.get_ok
              in
              Luv.Poll.start poll [ `WRITABLE ] (fun _result ->
                  ignore (Luv.Poll.stop poll);
                  Luv.Handle.close poll CCFun.id;
                  ignore
                    (try
                       let len = wb.Abb_intf.Write_buf.len - pos in
                       let n =
                         Unix.sendto t ~buf:wb.Abb_intf.Write_buf.buf ~pos ~len ~mode:[] ~addr
                       in
                       let total = total + n in
                       match n with
                       | n when n = len -> Future.run_with_state (send' ~total ~pos:0 bufs) s
                       | n -> Future.run_with_state (send' ~total ~pos:(pos + n) all_bufs) s
                     with
                    | Unix.Unix_error (err, _, _) as exn ->
                        let open Unix in
                        Future.run_with_state
                          (Future.Promise.set
                             p
                             (Error
                                (match err with
                                | EBADF -> `E_bad_file
                                | EACCES -> `E_access
                                | ENOBUFS -> `E_no_buffers
                                | EHOSTUNREACH -> `E_host_unreachable
                                | EHOSTDOWN -> `E_host_down
                                | ECONNREFUSED -> `E_connection_refused
                                | _ -> `Unexpected exn)))
                          s
                    | exn ->
                        Future.run_with_state (Future.Promise.set p (Error (`Unexpected exn))) s));
              (s, Future.return ()))
    in
    let open Future.Infix_monad in
    send' ~total:0 ~pos:0 bufs >>= fun () -> Future.Promise.future p

  let close t =
    Future.with_state (fun s ->
        let el = Abb_fut.State.state s in
        let timer = Luv.Timer.init ~loop:el.El.loop () |> Result.get_ok in
        ignore
          (Luv.Timer.start timer 0 (fun () ->
               Luv.Handle.close timer (fun () -> try Unix.close t with _ -> ()))
          |> Result.get_ok);
        (s, Future.return (Ok ())))

  let listen t ~backlog =
    try
      Unix.listen t ~max:backlog;
      Ok ()
    with
    | Unix.Unix_error (err, _, _) as exn ->
        let open Unix in
        Error
          (match err with
          | EBADF -> `E_bad_file
          | EDESTADDRREQ -> `E_dest_address_required
          | EINVAL -> `E_invalid
          | EOPNOTSUPP -> `E_op_not_supported
          | _ -> `Unexpected exn)
    | exn -> Error (`Unexpected exn)

  let accept t =
    try
      let fd, _ = Unix.accept ~cloexec:true t in
      Unix.set_nonblock fd;
      Future.return (Ok fd)
    with
    | Unix.Unix_error (Unix.EAGAIN, _, _) | Unix.Unix_error (Unix.EWOULDBLOCK, _, _) ->
        Future.with_state (fun s ->
            let el = Abb_fut.State.state s in
            let poll =
              Luv.Poll.init ~loop:el.El.loop (unsafe_int_of_file_descr t) |> Result.get_ok
            in
            let p =
              Future.Promise.create
                ~abort:(fun () ->
                  ignore (Luv.Poll.stop poll);
                  Luv.Handle.close poll CCFun.id;
                  Future.return ())
                ()
            in
            Luv.Poll.start poll [ `READABLE ] (fun _result ->
                ignore (Luv.Poll.stop poll);
                Luv.Handle.close poll CCFun.id;
                ignore
                  (Future.run_with_state
                     (Future.Promise.set
                        p
                        (try
                           let fd, _ = Unix.accept ~cloexec:true t in
                           Unix.set_nonblock fd;
                           Ok fd
                         with
                        | Unix.Unix_error (err, _, _) as exn ->
                            let open Unix in
                            Error
                              (match err with
                              | EBADF -> `E_bad_file
                              | EMFILE | ENFILE -> `E_file_table_full
                              | EINVAL -> `E_invalid
                              | ECONNABORTED -> `E_connection_aborted
                              | _ -> `Unexpected exn)
                        | exn -> Error (`Unexpected exn)))
                     s));
            (s, Future.Promise.future p))
    | Unix.Unix_error (err, _, _) as exn ->
        let open Unix in
        Future.return
          (Error
             (match err with
             | ENOTSOCK | EBADF -> `E_bad_file
             | _ -> `Unexpected exn))
    | exn -> Future.return (Error (`Unexpected exn))

  let create_sock ~kind ~domain =
    try
      let t = Unix.socket ~cloexec:true ~domain:(unix_of_domain domain) ~kind ~protocol:0 in
      Unix.set_nonblock t;
      Ok t
    with
    | Unix.Unix_error (err, _, _) as exn ->
        let open Unix in
        Error
          (match err with
          | EACCES -> `E_access
          | EAFNOSUPPORT -> `E_address_family_not_supported
          | EMFILE | ENFILE -> `E_file_table_full
          | ENOBUFS -> `E_no_buffers
          | EPERM -> `E_permission
          | EPROTONOSUPPORT -> `E_protocol_not_supported
          | EPROTOTYPE -> `E_protocol_type
          | _ -> `Unexpected exn)
    | exn -> Error (`Unexpected exn)

  let readable t =
    Future.with_state (fun s ->
        let el = Abb_fut.State.state s in
        let poll = Luv.Poll.init ~loop:el.El.loop (unsafe_int_of_file_descr t) |> Result.get_ok in
        let p =
          Future.Promise.create
            ~abort:(fun () ->
              ignore (Luv.Poll.stop poll);
              Luv.Handle.close poll CCFun.id;
              Future.return ())
            ()
        in
        Luv.Poll.start poll [ `READABLE ] (fun _result ->
            ignore (Luv.Poll.stop poll);
            Luv.Handle.close poll CCFun.id;
            ignore (Future.run_with_state (Future.Promise.set p ()) s));
        (s, Future.Promise.future p))

  let writable t =
    Future.with_state (fun s ->
        let el = Abb_fut.State.state s in
        let poll = Luv.Poll.init ~loop:el.El.loop (unsafe_int_of_file_descr t) |> Result.get_ok in
        let p =
          Future.Promise.create
            ~abort:(fun () ->
              ignore (Luv.Poll.stop poll);
              Luv.Handle.close poll CCFun.id;
              Future.return ())
            ()
        in
        Luv.Poll.start poll [ `WRITABLE ] (fun _result ->
            ignore (Luv.Poll.stop poll);
            Luv.Handle.close poll CCFun.id;
            ignore (Future.run_with_state (Future.Promise.set p ()) s));
        (s, Future.Promise.future p))

  module Tcp = struct
    let to_native t = t
    let of_native t = t
    let create = create_sock ~kind:Unix.SOCK_STREAM

    let bind t addr =
      try
        Unix.setsockopt t Unix.SO_REUSEADDR true;
        let sa = unix_sockaddr_of_sockaddr addr in
        Unix.bind t ~addr:sa;
        Ok ()
      with
      | Unix.Unix_error (err, _, _) as exn ->
          let open Unix in
          Error
            (match err with
            | ENOTSOCK | EBADF -> `E_bad_file
            | EAGAIN -> `E_again
            | EINVAL -> `E_invalid
            | EADDRNOTAVAIL -> `E_address_not_available
            | EADDRINUSE -> `E_address_in_use
            | EAFNOSUPPORT -> `E_address_family_not_supported
            | EACCES -> `E_access
            | ENOTDIR -> `E_not_dir
            | EROFS | EPERM -> `E_permission
            | ENAMETOOLONG -> `E_name_too_long
            | ENOENT -> `E_no_entity
            | ELOOP -> `E_loop
            | EIO -> `E_io
            | EISDIR -> `E_is_dir
            | _ -> `Unexpected exn)
      | exn -> Error (`Unexpected exn)

    let connect t addr =
      let sa = unix_sockaddr_of_sockaddr addr in
      try
        Unix.connect t ~addr:sa;
        Future.return (Ok ())
      with
      | Unix.Unix_error (Unix.EINPROGRESS, _, _) ->
          Future.with_state (fun s ->
              let el = Abb_fut.State.state s in
              let poll =
                Luv.Poll.init ~loop:el.El.loop (unsafe_int_of_file_descr t) |> Result.get_ok
              in
              let p =
                Future.Promise.create
                  ~abort:(fun () ->
                    ignore (Luv.Poll.stop poll);
                    Luv.Handle.close poll CCFun.id;
                    Future.return ())
                  ()
              in
              Luv.Poll.start poll [ `WRITABLE ] (fun _result ->
                  ignore (Luv.Poll.stop poll);
                  Luv.Handle.close poll CCFun.id;
                  ignore (Future.run_with_state (Future.Promise.set p (Ok ())) s));
              (s, Future.Promise.future p))
      | Unix.Unix_error (err, _, _) as exn ->
          let open Unix in
          Future.return
            (Error
               (match err with
               | EBADF -> `E_bad_file
               | EINVAL -> `E_invalid
               | EADDRNOTAVAIL -> `E_address_not_available
               | EAFNOSUPPORT -> `E_address_family_not_supported
               | EISCONN -> `E_is_connected
               | ECONNREFUSED -> `E_connection_refused
               | ECONNRESET -> `E_connection_reset
               | ENETUNREACH -> `E_network_unreachable
               | EHOSTUNREACH -> `E_host_unreachable
               | EADDRINUSE -> `E_address_in_use
               | EACCES -> `E_access
               | _ -> `Unexpected exn))
      | exn -> Future.return (Error (`Unexpected exn))

    let recv t ~buf ~pos ~len =
      Future.with_state (fun s ->
          let el = Abb_fut.State.state s in
          let poll = Luv.Poll.init ~loop:el.El.loop (unsafe_int_of_file_descr t) |> Result.get_ok in
          let p =
            Future.Promise.create
              ~abort:(fun () ->
                ignore (Luv.Poll.stop poll);
                Luv.Handle.close poll CCFun.id;
                Future.return ())
              ()
          in
          Luv.Poll.start poll [ `READABLE ] (fun _result ->
              ignore (Luv.Poll.stop poll);
              Luv.Handle.close poll CCFun.id;
              ignore
                (Future.run_with_state
                   (Future.Promise.set
                      p
                      (try Ok (Unix.recv t ~buf ~pos ~len ~mode:[]) with
                      | Unix.Unix_error (err, _, _) as exn ->
                          let open Unix in
                          Error
                            (match err with
                            | ENOTSOCK | EBADF -> `E_bad_file
                            | ECONNRESET -> `E_connection_reset
                            | ENOTCONN -> `E_not_connected
                            | _ -> `Unexpected exn)
                      | exn -> Error (`Unexpected exn)))
                   s));
          (s, Future.Promise.future p))

    let send t ~bufs =
      let p =
        Future.Promise.create
          ~abort:(fun () ->
            Future.with_state (fun s ->
                (* We don't track the poll handle here so we can't stop it on abort.
                   The poll callback will detect the aborted promise and no-op. *)
                (s, Future.return ())))
          ()
      in
      let rec send' ~total ~pos = function
        | [] -> Future.Promise.set p (Ok total)
        | wb :: bufs as all_bufs ->
            Future.with_state (fun s ->
                let el = Abb_fut.State.state s in
                let poll =
                  Luv.Poll.init ~loop:el.El.loop (unsafe_int_of_file_descr t) |> Result.get_ok
                in
                Luv.Poll.start poll [ `WRITABLE ] (fun _result ->
                    ignore (Luv.Poll.stop poll);
                    Luv.Handle.close poll CCFun.id;
                    ignore
                      (try
                         let len = wb.Abb_intf.Write_buf.len - pos in
                         let n = Unix.send t ~buf:wb.Abb_intf.Write_buf.buf ~pos ~len ~mode:[] in
                         let total = total + n in
                         match n with
                         | n when n = len -> Future.run_with_state (send' ~total ~pos:0 bufs) s
                         | n -> Future.run_with_state (send' ~total ~pos:(pos + n) all_bufs) s
                       with
                      | Unix.Unix_error (err, _, _) as exn ->
                          let open Unix in
                          Future.run_with_state
                            (Future.Promise.set
                               p
                               (Error
                                  (match err with
                                  | ENOTSOCK | EBADF -> `E_bad_file
                                  | EACCES -> `E_access
                                  | ENOBUFS -> `E_no_buffers
                                  | EHOSTUNREACH -> `E_host_unreachable
                                  | EHOSTDOWN -> `E_host_down
                                  | EPIPE -> `E_pipe
                                  | _ -> `Unexpected exn)))
                            s
                      | exn ->
                          Future.run_with_state (Future.Promise.set p (Error (`Unexpected exn))) s));
                (s, Future.return ()))
      in
      let open Future.Infix_monad in
      send' ~total:0 ~pos:0 bufs >>= fun () -> Future.Promise.future p

    let nodelay t enabled =
      try
        Unix.setsockopt t Unix.TCP_NODELAY enabled;
        Ok ()
      with
      | Unix.Unix_error (err, _, _) as exn ->
          let open Unix in
          Error
            (match err with
            | ENOTSOCK | EBADF -> `E_bad_file
            | _ -> `Unexpected exn)
      | exn -> Error (`Unexpected exn)
  end

  module Udp = struct
    let to_native t = t
    let of_native t = t
    let create = create_sock ~kind:Unix.SOCK_DGRAM
    let bind = Tcp.bind
  end
end

module Process = struct
  module Pid = struct
    type t = int
    type native = int

    let of_native n = n
    let to_native t = t
  end

  type t = {
    pid : Pid.t;
    exit_code : Abb_intf.Process.Exit_code.t Future.t;
  }

  let int_of_signal = function
    | Abb_intf.Process.Signal.SIGABRT -> Sys_stdlib.sigabrt
    | Abb_intf.Process.Signal.SIGFPE -> Sys_stdlib.sigfpe
    | Abb_intf.Process.Signal.SIGHUP -> Sys_stdlib.sighup
    | Abb_intf.Process.Signal.SIGILL -> Sys_stdlib.sigill
    | Abb_intf.Process.Signal.SIGINT -> Sys_stdlib.sigint
    | Abb_intf.Process.Signal.SIGKILL -> Sys_stdlib.sigkill
    | Abb_intf.Process.Signal.SIGSEGV -> Sys_stdlib.sigsegv
    | Abb_intf.Process.Signal.SIGTERM -> Sys_stdlib.sigterm
    | Abb_intf.Process.Signal.Num s -> s

  let signal_of_int n =
    if n = Sys_stdlib.sigabrt then Abb_intf.Process.Signal.SIGABRT
    else if n = Sys_stdlib.sigfpe then Abb_intf.Process.Signal.SIGFPE
    else if n = Sys_stdlib.sighup then Abb_intf.Process.Signal.SIGHUP
    else if n = Sys_stdlib.sigill then Abb_intf.Process.Signal.SIGILL
    else if n = Sys_stdlib.sigint then Abb_intf.Process.Signal.SIGINT
    else if n = Sys_stdlib.sigkill then Abb_intf.Process.Signal.SIGKILL
    else if n = Sys_stdlib.sigsegv then Abb_intf.Process.Signal.SIGSEGV
    else if n = Sys_stdlib.sigterm then Abb_intf.Process.Signal.SIGTERM
    else Abb_intf.Process.Signal.Num n

  let wait_on_pid pid =
    Thread.run (fun () ->
        let pid', signal = Unix.waitpid ~mode:[] pid in
        assert (pid = pid');
        match signal with
        | Unix.WEXITED code -> Abb_intf.Process.Exit_code.Exited code
        | Unix.WSIGNALED code -> Abb_intf.Process.Exit_code.Signaled (signal_of_int code)
        | Unix.WSTOPPED code -> Abb_intf.Process.Exit_code.Stopped (signal_of_int code))

  let spawn ~stdin ~stdout ~stderr init_args =
    try
      let pid =
        let module P = Abb_intf.Process in
        match init_args.P.env with
        | Some env ->
            let env =
              CCArray.of_list @@ CCList.map (fun (k, v) -> CCString.concat "=" [ k; v ]) env
            in
            Unix.create_process_env
              ~prog:init_args.P.exec_name
              ~args:(CCArray.of_list init_args.P.args)
              ~env
              ~stdin
              ~stdout
              ~stderr
        | None ->
            Unix.create_process
              ~prog:init_args.P.exec_name
              ~args:(CCArray.of_list init_args.P.args)
              ~stdin
              ~stdout
              ~stderr
      in
      Ok { pid; exit_code = wait_on_pid pid }
    with
    | Unix.Unix_error (err, _, _) as exn ->
        let open Unix in
        Error
          (match err with
          | EAGAIN -> `E_again
          | ENOMEM -> `E_no_memory
          | _ -> `Unexpected exn)
    | exn -> Error (`Unexpected exn)

  let pid t = t.pid
  let wait t = t.exit_code

  let exit_code t =
    match Future.state t.exit_code with
    | `Det exit_code -> Some exit_code
    | `Undet | `Aborted | `Exn _ -> None

  let signal_pid ~pid signal = Unix.kill ~pid ~signal:(int_of_signal signal)
  let signal t signal = signal_pid ~pid:t.pid signal
end
