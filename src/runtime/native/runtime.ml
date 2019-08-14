(* This file is part of Bisect_ppx, released under the MIT license. See
   LICENSE.md for details, or visit
   https://github.com/aantron/bisect_ppx/blob/master/LICENSE.md. *)



type message =
  | Unable_to_create_file
  | Unable_to_write_file
  | String of string

let string_of_message = function
  | Unable_to_create_file ->
      " *** Bisect runtime was unable to create file."
  | Unable_to_write_file ->
      " *** Bisect runtime was unable to write file."
  | String s ->
      " *** " ^ s

let full_path fname =
  if Filename.is_implicit fname then
    Filename.concat Filename.current_dir_name fname
  else
    fname

let env_to_fname env default = try Sys.getenv env with Not_found -> default

let verbose =
  lazy begin
    let fname = env_to_fname "BISECT_SILENT" "bisect.log" in
    match (String.uppercase [@ocaml.warning "-3"]) fname with
    | "YES" | "ON" -> fun _ -> ()
    | "ERR"        -> fun msg -> prerr_endline (string_of_message msg)
    | _uc_fname    ->
        let oc_l = lazy (
          (* A weird race condition is caused if we use this invocation instead
            let oc = open_out_gen [Open_append] 0o244 (full_path fname) in
            Note that verbose is called only during [at_exit]. *)
          let oc = open_out_bin (full_path fname) in
          at_exit (fun () -> close_out_noerr oc);
          oc)
        in
        fun msg ->
          Printf.fprintf (Lazy.force oc_l) "%s\n" (string_of_message msg)
  end

let verbose message =
  (Lazy.force verbose) message

let () =
  Random.self_init ()

let file_channel () =
  let base_name = full_path (env_to_fname "BISECT_FILE" "bisect") in
  let rec create_file () =
    let numeric_suffix = abs (Random.int 1000000000) in
    let filename =
      Printf.sprintf "%s%09d.out" base_name numeric_suffix in
    try
      let fd = Unix.(openfile filename [O_WRONLY; O_CREAT; O_EXCL] 0o644) in
      let channel = Unix.out_channel_of_descr fd in
      Some channel
    with
    | Unix.Unix_error (Unix.EEXIST, _, _) -> create_file ()
    | Unix.Unix_error (code, _, _) ->
      let detail = Printf.sprintf "%s: %s" (Unix.error_message code) filename in
      verbose Unable_to_create_file;
      verbose (String detail);
      None
  in
  create_file ()

let dump_counters_exn =
  Bisect_common.write_runtime_data

let reset_counters () =
  Hashtbl.iter (fun _ (point_state, _) ->
      match Array.length point_state with
      | 0 -> ()
      | n -> Array.(fill point_state 0 (n - 1) 0)
    ) (Lazy.force Bisect_common.table)

let dump () =
  match file_channel () with
  | None -> ()
  | Some channel ->
      (try
        dump_counters_exn channel
      with _ ->
        verbose Unable_to_write_file);
      close_out_noerr channel

let register_dump : unit Lazy.t =
  lazy (at_exit dump)

let register_file file ~point_count ~point_definitions =
  let () = Lazy.force register_dump in
  Bisect_common.register_file file ~point_count ~point_definitions
