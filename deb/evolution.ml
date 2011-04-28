(**************************************************************************************)
(*  Copyright (C) 2011 Pietro Abate                                                   *)
(*  Copyright (C) 2011 Mancoosi Project                                               *)
(*                                                                                    *)
(*  This library is free software: you can redistribute it and/or modify              *)
(*  it under the terms of the GNU Lesser General Public License as                    *)
(*  published by the Free Software Foundation, either version 3 of the                *)
(*  License, or (at your option) any later version.  A special linking                *)
(*  exception to the GNU Lesser General Public License applies to this                *)
(*  library, see the COPYING file for more information.                               *)
(**************************************************************************************)

open ExtLib
open Common

type range = [
    `Hi of string
  | `In of (string * string)
  | `Lo of string 
  | `Eq of string
]

let string_of_range = function
  |`Hi v -> Printf.sprintf "%s < ." v
  |`Lo v -> Printf.sprintf ". < %s" v
  |`Eq v -> Printf.sprintf "= %s" v
  |`In (v1,v2) -> Printf.sprintf "%s < . < %s" v1 v2
;;

(* returns a list of ranges w.r.t. the list of versions vl *)
(* the range is a [ ... [ kind of interval *)
let range ?(bottom=false) vl =
  let l = List.sort ~cmp:(fun v1 v2 -> Version.compare v2 v1) vl in
  let rec aux acc = function
    |(None,[]) -> acc
    |(None,a::t) -> aux ((`Hi a)::acc) (Some a,t)
    |(Some b,a::t) -> aux ((`In (a,b))::(`Eq b)::acc) (Some a,t)
    |(Some b,[]) when bottom = false -> (`Eq b)::acc 
    |(Some b,[]) -> (`Lo b)::(`Eq b)::acc 
  in
  aux [] (None,l)
;;

let discriminant ?(bottom=false) evalsel vl constraints =
  let eval_constr = Hashtbl.create 17 in
  let constr_eval = Hashtbl.create 17 in
  List.iter (fun target ->
    let eval = List.map (evalsel target) constraints in
    try
      let v_rep = Hashtbl.find eval_constr eval in
      let l = Hashtbl.find constr_eval v_rep in
      Hashtbl.replace constr_eval v_rep (target::l)
    with Not_found -> begin
      Hashtbl.add eval_constr eval target;
      Hashtbl.add constr_eval target []
    end
  ) (range ~bottom vl) ;
  (Hashtbl.fold (fun k v acc -> (k,v)::acc) constr_eval [])
;;

let add_unique h k v =
  try
    let vh = Hashtbl.find h k in
    if not (Hashtbl.mem vh v) then
      Hashtbl.add vh v ()
  with Not_found -> begin
    let vh = Hashtbl.create 17 in
    Hashtbl.add vh v ();
    Hashtbl.add h k vh
  end

(* collect dependency information *)
let conj_iter t l =
  List.iter (fun (name,sel) ->
    match CudfAdd.cudfop sel with
    |None -> add_unique t name None
    |Some(c,v) -> add_unique t name (Some(c,v))
  ) l
let cnf_iter t ll = List.iter (conj_iter t) ll

(** [constraints universe] returns a map between package names
    and an ordered list of constraints where the package name is
    mentioned *)
let constraints packagelist =
  let constraints_table = Hashtbl.create (List.length packagelist) in
  List.iter (fun pkg ->
    conj_iter constraints_table pkg.Packages.conflicts ;
    conj_iter constraints_table pkg.Packages.provides ;
    cnf_iter constraints_table pkg.Packages.depends
  ) packagelist
  ;
  let h = Hashtbl.create (List.length packagelist) in
  let elements hv =
    let cmp (_,v1) (_,v2) = Version.compare v2 v1 in
    List.sort ~cmp (
      Hashtbl.fold (fun k _ acc ->
        match k with
        |None -> acc 
        |Some k -> k::acc
      ) hv []
    )
  in
  Hashtbl.iter (fun n hv -> Hashtbl.add h n (elements hv)) constraints_table;
  h
;;

let all_constraints table pkgname =
  try (Hashtbl.find table pkgname)
  with Not_found -> []
;;

(* return a new target rebased accordingly to the epoch of the base version *)
let align version target =
  match Version.split version  with
  |("",_,_,_) -> target
  |(pe,_,_,_) ->
    let rebase v =
      let (_,u,r,b) = Version.split v in
      Version.concat (pe,u,r,b)
    in
    match target with
    |`Eq v -> `Eq (rebase v)
    |`Hi v -> `Hi (rebase v)
    |`Lo v -> `Lo (rebase v)
    |`In (v,w) -> `In (rebase v,rebase w)
;;

(* all versions mentioned in a list of constraints *)
let all_versions constr = Util.list_unique (List.map (snd) constr) ;;

let migrate packagelist target =
  List.map (fun pkg -> ((pkg,target),(align pkg.Packages.version target))) packagelist
;;

(*
let aa repository =
  (* to be optimized !!! *)
  let constraints_table = Debian.Evolution.constraints repository in
  let clusters = Debian.Debutil.cluster repository in
  Hashtbl.fold (fun (sn,sv) l acc0 ->
    List.fold_left (fun acc1 (version,cluster) ->
    let (versionlist, constr) =
      (* all binary versions in the cluster *)
      let clustervl = List.map (fun pkg -> pkg.Packages.version) cluster in
      List.fold_left (fun (vl,cl) pkg ->
        let pn = pkg.Packages.name in
        let pv = pkg.Packages.version in
        let constr = all_constraints constraints_table pn in
        let vl = clustervl@(all_versions constr) in
        let el = (extract_epochs vl) in
        let tvl = add_normalize vl in
        let versionlist = add_epochs el tvl in
        (versionlist @ vl, constr @ cl)
      ) ([],[]) cluster
    in
    (sn,version,cluster,List.unique versionlist,List.unique constr)::acc1
    ) acc0 l
  ) clusters []
;;
*)
