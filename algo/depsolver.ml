(**************************************************************************************)
(*  Copyright (C) 2009 Pietro Abate <pietro.abate@pps.jussieu.fr>                     *)
(*  Copyright (C) 2009 Mancoosi Project                                               *)
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
open CudfAdd

#define __label __FILE__
let label =  __label ;;
include Util.Logging(struct let label = label end) ;;

type solver = Depsolver_int.solver

(** 
 * @param check if the universe is consistent *)
let load ?(check=true) universe =
  let is_consistent check universe =
    if check then Cudf_checker.is_consistent universe
    else (true,None)
  in
  match is_consistent check universe with
  |true,None -> Depsolver_int.init_solver_univ universe 
  |false,Some(r) -> 
      fatal "%s"
      (Cudf_checker.explain_reason (r :> Cudf_checker.bad_solution_reason)) ;
  |_,_ -> assert false

let reason map universe =
  let from_sat = CudfAdd.inttovar universe in
  let globalid = Cudf.universe_size universe in
  List.filter_map (function
    |Diagnostic_int.Dependency(i,vl,il) when i = globalid -> None
    |Diagnostic_int.Missing(i,vl) when i = globalid -> 
        fatal "the package encoding global constraints can't be missing"
    |Diagnostic_int.Conflict(i,j,vpkg) when i = globalid || j = globalid -> 
        fatal "the package encoding global constraints can't be in conflict"

    |Diagnostic_int.Dependency(i,vl,il) -> Some (
        Diagnostic.Dependency(from_sat (map#inttovar i),vl,List.map (fun i -> from_sat (map#inttovar i)) il)
    )
    |Diagnostic_int.Missing(i,vl) -> Some (
        Diagnostic.Missing(from_sat (map#inttovar i),vl)
    )
    |Diagnostic_int.Conflict(i,j,vpkg) -> Some (
        Diagnostic.Conflict(from_sat (map#inttovar i),from_sat (map#inttovar j),vpkg)
    )
  )

let result map universe result = 
  let from_sat = CudfAdd.inttovar universe in
  let globalid = Cudf.universe_size universe in
  match result with
  |Diagnostic_int.Success f_int ->
      Diagnostic.Success (fun ?(all=false) () ->
        List.filter_map (function 
          |i when i = globalid -> None
          |i -> Some ({(from_sat i) with Cudf.installed = true})
        ) (f_int ~all ())
      )
  |Diagnostic_int.Failure f -> Diagnostic.Failure (fun () ->
      reason map universe (f ()))
;;

let request universe result = 
  List.map (CudfAdd.inttovar universe) (snd result)
;;

(* XXX here the threatment of result and request is not uniform.
 * On one hand indexes in result must be processed with map#inttovar 
 * as they represent indexes associated with the solver.
 * On the other hand the indexes in result represent cudf uid and
 * therefore do not need to be processed.
 * Ideally the compiler should make sure that we use the correct indexes
 * but we should annotate everything making packing/unpackaing handling
 * a bit too heavy *)
let diagnosis map universe res req =
  let result = result map universe res in
  let request = request universe req in
  { Diagnostic.result = result ; request = request }

(** [univcheck ?callback universe] check all packages in the
    universe for installability 

    @return the number of packages that cannot be installed
*)
let univcheck ?(global_constraints=true) ?callback universe =
  let aux ?callback univ =
    let timer = Util.Timer.create "Algo.Depsolver.univcheck" in
    Util.Timer.start timer;
    let solver = Depsolver_int.init_solver_univ univ in
    let failed = ref 0 in
    (* This is size + 1 because we encode the global constraint of the
     * universe as a package that must be tested like any other *)
    let size = (Cudf.universe_size univ) + 1 in
    let tested = Array.make size false in
    Util.Progress.set_total Depsolver_int.progressbar_univcheck size ;
    let check = Depsolver_int.pkgcheck global_constraints callback solver tested in
    (* we do not test the last package that encodes the global constraints
     * on the universe as it is tested all the time with all other packages. *)
    for id = 0 to size - 2 do if not(check id) then incr failed done;
    Util.Timer.stop timer !failed
  in
  let map = new Depsolver_int.identity in
  match callback with
  |None -> aux universe
  |Some f ->
      let callback_int (res,req) = f (diagnosis map universe res req) in
      aux ~callback:callback_int universe
;;

(** [listcheck ?callback universe pkglist] check if a subset of packages 
    un the universe are installable.

    @param pkglist list of packages to be checked
    @return the number of packages that cannot be installed
*)
let listcheck ?(global_constraints=true) ?callback universe pkglist =
  let aux ?callback univ idlist =
    let solver = Depsolver_int.init_solver_univ univ in
    let timer = Util.Timer.create "Algo.Depsolver.listcheck" in
    Util.Timer.start timer;
    let failed = ref 0 in
    let size = (Cudf.universe_size univ) + 1 in
    let tested = Array.make size false in
    Util.Progress.set_total Depsolver_int.progressbar_univcheck size ;
    let check = Depsolver_int.pkgcheck global_constraints callback solver tested in
    List.iter (function id when id = size -> () |id -> if not(check id) then incr failed) idlist ;
    Util.Timer.stop timer !failed
  in
  let idlist = List.map (CudfAdd.vartoint universe) pkglist in
  let map = new Depsolver_int.identity in
  match callback with
  |None -> aux universe idlist
  |Some f ->
      let callback_int (res,req) = f (diagnosis map universe res req) in
      aux ~callback:callback_int universe idlist
;;

let edos_install_cache global_constraints univ cudfpool pkglist =
  let idlist = List.map (CudfAdd.vartoint univ) pkglist in
  let globalid = Cudf.universe_size univ in
  let closure = Depsolver_int.dependency_closure_cache cudfpool (globalid::idlist) in
  let solver = Depsolver_int.init_solver_closure cudfpool closure in
  let req = if global_constraints then (Some globalid,idlist) else (None,idlist) in
  let res = Depsolver_int.solve solver req in
  diagnosis solver.Depsolver_int.map univ res req
;;

let edos_install ?(global_constraints=false) univ pkg =
  let cudfpool = Depsolver_int.init_pool_univ ~global_constraints univ in
  edos_install_cache global_constraints univ cudfpool [pkg]

let edos_coinstall ?(global_constraints=false) univ pkglist =
  let cudfpool = Depsolver_int.init_pool_univ ~global_constraints univ in
  edos_install_cache global_constraints univ cudfpool pkglist
;;

let edos_coinstall_prod ?(global_constraints=false) univ ll =
  let cudfpool = Depsolver_int.init_pool_univ ~global_constraints univ in
  let return a = [a] in
  let bind m f = List.flatten (List.map f m) in
  let rec permutation = function
    |[] -> return []
    |h::t ->
        bind (permutation t) (fun t1 ->
          List.map (fun h1 -> h1 :: t1) h
        )
  in
  List.map (edos_install_cache global_constraints univ cudfpool) (permutation ll)
;;

let trim ?(global_constraints=true) universe =
  let trimmed_pkgs = ref [] in
  let callback d =
    if Diagnostic.is_solution d then
      match d.Diagnostic.request with
      |[p] -> trimmed_pkgs := p::!trimmed_pkgs
      |_ -> assert false
  in
  ignore (univcheck ~global_constraints ~callback universe);
  Cudf.load_universe !trimmed_pkgs
;;

let trimlist ?(global_constraints=true) universe pkglist =
  let trimmed_pkgs = ref [] in
  let callback d =
    if Diagnostic.is_solution d then
      match d.Diagnostic.request with
      |[p] -> trimmed_pkgs := p::!trimmed_pkgs
      |_ -> assert false
  in
  ignore (listcheck ~global_constraints ~callback universe pkglist);
  !trimmed_pkgs
;;

let find_broken ?(global_constraints=true) universe =
  let broken_pkgs = ref [] in
  let callback d =
    if not (Diagnostic.is_solution d) then
      match d.Diagnostic.request with
      |[p] -> broken_pkgs := p::!broken_pkgs
      |_ -> assert false
  in
  ignore (univcheck ~global_constraints ~callback universe);
  !broken_pkgs
;;

let callback_aux acc d =
  match d.Diagnostic.request with
  |[p] when (Diagnostic.is_solution d) -> 
      acc := p::!acc
  |[p] ->
      warning "Package %s is not installable" (CudfAdd.string_of_package p)
  |_ -> ()
;;

let find_installable ?(global_constraints=true) universe =
  let acc = ref [] in
  let callback = callback_aux acc in
  ignore (univcheck ~global_constraints ~callback universe);
  !acc
;;

let find_listinstallable ?(global_constraints=true) universe pkglist =
  let acc = ref [] in
  let callback = callback_aux acc in
  ignore (listcheck ~global_constraints ~callback universe pkglist);
  !acc
;;

let find_listbroken ?(global_constraints=true) universe pkglist =
  let broken_pkgs = ref [] in
  let callback d =
    if not (Diagnostic.is_solution d) then
      match d.Diagnostic.request with
      |[p] -> broken_pkgs := p::!broken_pkgs
      |_ -> assert false
  in
  ignore (listcheck ~global_constraints ~callback universe pkglist);
  !broken_pkgs
;;

let dependency_closure ?maxdepth ?conjunctive ?(global_constraints=false) univ pkglist =
  Depsolver_int.dependency_closure ?maxdepth ?conjunctive ~global_constraints univ pkglist

let reverse_dependencies univ =
  let rev = Depsolver_int.reverse_dependencies univ in
  let h = Cudf_hashtbl.create (Array.length rev) in
  Array.iteri (fun i l ->
    Cudf_hashtbl.add h 
      (CudfAdd.inttovar univ i) 
      (List.map (CudfAdd.inttovar univ) l)
  ) rev ;
  h

let reverse_dependency_closure ?maxdepth univ pkglist =
  let idlist = List.map (CudfAdd.vartoint univ) pkglist in
  let reverse = Depsolver_int.reverse_dependencies univ in
  let closure = Depsolver_int.reverse_dependency_closure ?maxdepth reverse idlist in
  List.map (CudfAdd.inttovar univ) closure

type enc = Cnf | Dimacs

let output_clauses ?(global_constraints=true) ?(enc=Cnf) univ =
  let solver = Depsolver_int.init_solver_univ ~global_constraints ~buffer:true univ in
  let clauses = Depsolver_int.S.dump solver.Depsolver_int.constraints in
  let size = Cudf.universe_size univ in
  let buff = Buffer.create size in
  let globalid = size in
  let to_cnf dump =
    let str (v, p) =
      if (abs v) != globalid then
        let pkg = (CudfAdd.inttovar univ) (abs v) in
        let pol = if p then "" else "!" in
        Printf.sprintf "%s%s-%d" pol pkg.Cudf.package pkg.Cudf.version
      else ""
    in
    List.iter (fun l ->
      List.iter (fun var -> Printf.bprintf buff " %s" (str var)) l;
      Printf.bprintf buff "\n"
    ) dump
  in
  let to_dimacs dump =
    let str (v, p) =
      if v != globalid then
        if p then Printf.sprintf "%d" v else Printf.sprintf "-%d" v 
      else ""
    in
    let varnum = Cudf.universe_size univ in
    let closenum = (List.length clauses) in
    Printf.bprintf buff "p cnf %d %d\n" varnum closenum;
    List.iter (fun l ->
      List.iter (fun var -> Printf.bprintf buff " %s" (str var)) l;
      Printf.bprintf buff " 0\n"
    ) dump
  in
  if enc = Cnf then to_cnf clauses ;
  if enc = Dimacs then to_dimacs clauses;
  Buffer.contents buff
;;

type solver_result =
  |Sat of (Cudf.preamble option * Cudf.universe)
  |Unsat of Diagnostic.diagnosis option
  |Error of string

(* add a version constraint to ensure name is upgraded *)
let upgrade_constr universe name = 
  match Cudf.get_installed universe name with
  | [] -> name,None
  |[p] -> name,Some(`Geq,p.Cudf.version)
  | pl ->
      let p = List.hd(List.sort ~cmp:Cudf.(>%) pl) 
      in (name,Some(`Geq,p.Cudf.version))

let check_request_using ?call_solver ?callback ?criteria ?(explain=false) (pre,universe,request) =
  let intSolver ?(explain=false) universe request =

    let deps = 
      let k =
        Cudf.fold_packages (fun acc pkg ->
          if pkg.Cudf.installed then
            match pkg.Cudf.keep with
            |`Keep_package -> (pkg.Cudf.package,None)::acc
            |`Keep_version -> (pkg.Cudf.package,Some(`Eq,pkg.Cudf.version))::acc
            |_ -> acc
          else acc
        ) [] universe
      in
      let il = request.Cudf.install in
      (* we preserve the user defined constraints, while adding the upgrade constraint *)
      let ulc = List.filter (function (_,Some _) -> true | _ -> false) request.Cudf.upgrade in
      let ulnc = List.map (fun (name,_) -> upgrade_constr universe name) request.Cudf.upgrade in
      let l = il @ ulc @ ulnc in
      debug "request consistency (keep %d) (install %d) (upgrade %d) (remove %d) (# %d)"
      (List.length k) (List.length request.Cudf.install) 
      (List.length request.Cudf.upgrade)
      (List.length request.Cudf.remove)
      (Cudf.universe_size universe);
      List.fold_left (fun acc j -> [j]::acc) (List.map (fun j -> [j]) l) k
    in
    let dummy = {
      Cudf.default_package with
      Cudf.package = "dose-dummy-request";
      version = 1;
      depends = deps;
      conflicts = request.Cudf.remove}
    in
    (* XXX it should be possible to add a package to a cudf document ! *)
    let pkglist = Cudf.get_packages universe in
    let universe = Cudf.load_universe (dummy::pkglist) in
    edos_install universe dummy
  in
  match call_solver with
  | None ->
    let d = intSolver universe request in
    if Diagnostic.is_solution d then
      let is = Diagnostic.get_installationset d in
      Sat (Some pre,Cudf.load_universe is)
    else
      if explain then Unsat (Some d) else Unsat None
  | Some call_solver ->
    try Sat(call_solver (pre,universe,request)) with
    |CudfSolver.Unsat when not explain -> Unsat None
    |CudfSolver.Unsat when explain -> Unsat (Some (intSolver ~explain universe request))
    |CudfSolver.Error s -> Error s
;;

(** check if a cudf request is satisfiable. we do not care about
 * universe consistency . We try to install a dummy package *)
let check_request ?cmd ?callback ?criteria ?explain cudf =
  let call_solver =
    match cmd with
    | Some cmd ->
        let criteria = Option.default "-removed,-new" criteria in
        Some (CudfSolver.execsolver cmd criteria)
    | None -> None
  in
  check_request_using ?call_solver ?callback ?explain cudf
;;

type depclean_t =
  (Cudf.package *
    (Cudf_types.vpkglist * Cudf_types.vpkg * Cudf.package list) list *
    (Cudf_types.vpkg * Cudf.package list) list
  )

(** Depclean. Detect useless dependencies and/or conflicts 
    to missing or broken packages *)
let depclean ?(global_constraints=true) ?(callback=(fun _ -> ())) univ pkglist =
  let cudfpool = Depsolver_int.init_pool_univ ~global_constraints univ in
  let is_broken =
    let cache = Hashtbl.create (Cudf.universe_size univ) in
    fun pkg -> 
      try Hashtbl.find cache pkg with 
      |Not_found ->
        let r = edos_install_cache global_constraints univ cudfpool [pkg] in
        let res = not(Diagnostic.is_solution r) in
        Hashtbl.add cache pkg res;
        res
  in
  let enum_conf univ pkg =
    List.map (fun vpkg ->
      match CudfAdd.who_provides univ vpkg with
      |[] -> (vpkg,[])
      |l -> (vpkg,l)
    ) pkg.Cudf.conflicts
  in
  (* for each vpkglist in the depends field create a new vpkgformula
     where for each vpkg, only one one possible alternative is considered.
     We will use this revised vpkgformula to check if the selected alternative
     is a valid dependency *)
  let enum_deps univ pkg =
    let rec aux before acc = function
      |vpkglist :: after ->
          let l =
            List.map (fun vpkg ->
              match CudfAdd.who_provides univ vpkg with
              |[] -> (vpkglist,vpkg,[],[])
              |l -> (vpkglist,vpkg,before@[[vpkg]]@after,l)
            ) vpkglist
          in
          aux (before@[vpkglist]) (l::acc) after
      |[] -> List.flatten acc
    in aux [] [] pkg.Cudf.depends
  in
  (* if a package is in conflict with another package that is broken or missing,
     then the conflict can be removed *)
  let test_conflict l = 
    List.fold_left (fun acc -> function
      |(vpkg,[]) -> (vpkg,[])::acc
      |(vpkg,l) -> acc 
      (* if the conflict is with a broken package, 
         it is still a valid conflict *)
      (*
          List.fold_left (fun acc pkg ->
            if is_broken pkg then (vpkg,[pkg])::acc else acc
          ) acc l
          *)
    ) [] l 
  in
  (* if a package p depends on a package that make p uninstallable, then it 
     can be removed. If p depends on a missing package, the dependency can
     be equally removed *)
  let test_depends univ cudfpool pkg l =
    let pool = Depsolver_int.strip_cudf_pool cudfpool in
    List.fold_left (fun acc -> function
      |(vpkglist,vpkg,_,[]) -> (vpkglist,vpkg,[])::acc
      |(vpkglist,vpkg,depends,l) ->
        let pkgid = Cudf.uid_by_package univ pkg in
        let (pkgdeps,pkgconf) = pool.(pkgid) in
        let dll =
          List.map (fun vpkgs ->
            (vpkgs, CudfAdd.resolve_vpkgs_int univ vpkgs)
          ) depends
        in
        let _ = pool.(pkgid) <- (dll,pkgconf) in
        let res = edos_install_cache global_constraints univ cudfpool [pkg] in
        let _ = pool.(pkgid) <- (pkgdeps,pkgconf) in
        if not(Diagnostic.is_solution res) then (vpkglist,vpkg,l)::acc else acc
    ) [] l
  in
  List.filter_map (fun pkg ->
    if not(is_broken pkg) then begin
      let resdep = test_depends univ cudfpool pkg (enum_deps univ pkg) in
      let resconf = test_conflict (enum_conf univ pkg) in
      match resdep,resconf with
      |[],[] -> None
      |_,_ -> (callback(pkg,resdep,resconf) ; Some(pkg,resdep,resconf))
    end else None
  ) pkglist
;;
