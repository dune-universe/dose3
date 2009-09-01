(***************************************************************************************)
(*  Copyright (C) 2009  Pietro Abate <pietro.abate@pps.jussieu.fr>                     *)
(*                                                                                     *)
(*  This library is free software: you can redistribute it and/or modify               *)
(*  it under the terms of the GNU Lesser General Public License as                     *)
(*  published by the Free Software Foundation, either version 3 of the                 *)
(*  License, or (at your option) any later version.  A special linking                 *)
(*  exception to the GNU Lesser General Public License applies to this                 *)
(*  library, see the COPYING file for more information.                                *)
(***************************************************************************************)

open ExtLib
open Common

type name = string
type version = string
type vpkg = (string * (string * string) option)
type veqpkg = (string * (string * string) option)

type package = {
  name : name ;
  version : version;
  depends : vpkg list list;
  conflicts : vpkg list;
  obsoletes : vpkg list;
  provides : veqpkg list;
}

let default_package = {
  name = "";
  version = "";
  depends = [];
  conflicts = [];
  obsoletes = [];
  provides = [];
}

module Set = Set.Make(struct type t = package let compare = compare end)

let input_raw_priv parse_packages files =
  let timer = Util.Timer.create "Rpm.Packages.input_raw" in
  Util.Timer.start timer;
  let s =
    List.fold_left (fun acc f ->
      let l = parse_packages (fun x -> x) f in
      List.fold_left (fun s x -> Set.add x s) acc l
    ) Set.empty files
  in
  Util.Timer.stop timer (Set.elements s)

module Hdlists = struct

  open Hdlists

  let parse_packages_fields par =
    try
      Some (
        {
          name = parse_name par;
          version = parse_version par;
          depends = (try depend_list par with Not_found -> []);
          conflicts = (try list_deps "conflict" par with Not_found -> []);
          obsoletes = (try list_deps "obsolete" par with Not_found -> []);
          provides = (try provide_list par with Not_found -> []);
        }
      )
    with Not_found -> None

  let parse_packages f filename =
    let t = _open_in filename in
    let parse_packages_rec = parse_822_iter parse_packages_fields in
    let l = parse_packages_rec f t in
    _close_in t ;
    l

  let input_raw files = input_raw_priv parse_packages files
end

module Synthesis = struct

  open ExtLib
  open Common

  let parse_op = function
    |"*" -> None
    |sel ->
        try Scanf.sscanf sel "%s %s" (fun op v ->
          match op with
          |"==" -> Some("=",v)
          |_ -> Some(op,v))
        with End_of_file -> (print_endline sel ; assert false)

  let parse_vpkg vpkg =
    try Scanf.sscanf vpkg "%[^[][%[^]]]" (fun n sel -> (n,parse_op sel))
    with End_of_file -> (vpkg,None)

  let parse_deps l = List.map parse_vpkg l

  let parse_info pkg = function
    |[nvra;epoch;size;group] ->
        let ra = String.rindex nvra '.' in
        let vr = String.rindex_from nvra (ra-1) '-' in
        let nv = String.rindex_from nvra (vr-1) '-' in
        let name = String.sub nvra 0 nv in
        let version = String.sub nvra (nv+1) (vr-nv-1) in
        let release = String.sub nvra (vr+1) (ra-vr-1) in
        (* let arch = String.sub nvra (ra+1) (String.length nvra-ra-1) in *)
        let version =
          if epoch <> "0" then Printf.sprintf "%s:%s-%s" epoch version release
          else Printf.sprintf "%s-%s" version release
        in
        { pkg with name = name ; version = version }
    |_ -> assert false

  exception Eof

  let rec parse_paragraph pkg ch =
    let parse_deps_ll l = List.map (fun x -> [x]) (parse_deps l) in
    let line =
      try IO.read_line ch
      with IO.No_more_input -> raise Eof | End_of_file -> assert false
    in
    try
      match Str.split (Str.regexp "@") line with
      |"provides"::l -> parse_paragraph {pkg with provides = parse_deps l} ch
      |"requires"::l -> parse_paragraph {pkg with depends = parse_deps_ll l} ch
      |"obsoletes"::l -> parse_paragraph { pkg with obsoletes = parse_deps l} ch
      |"conflicts"::l -> parse_paragraph {pkg with conflicts = parse_deps l} ch
      |"summary"::l -> parse_paragraph pkg ch
      |"filesize"::l -> parse_paragraph pkg ch
      |"suggests"::l -> parse_paragraph pkg ch
      |"info"::l -> parse_info pkg l
      |s::l -> ((Printf.eprintf "Unknown field %s\n%!" s) ; parse_paragraph pkg ch)
      |_ -> assert false
    with End_of_file -> assert false

  let rec parse_packages_rec acc ch =
    try
      let par = parse_paragraph default_package ch in
      parse_packages_rec (par::acc) ch
    with Eof -> acc

  let parse_packages f filename =
    let ch = Input.open_file filename in 
    let l = parse_packages_rec [] ch in
    Input.close_ch ch;
    l

  let input_raw files = input_raw_priv parse_packages files

end
