(******************************************************************************)
(*  This file is part of the Dose library http://www.irill.org/software/dose  *)
(*                                                                            *)
(*  Copyright (C) 2009-2012 Pietro Abate <pietro.abate@pps.jussieu.fr>        *)
(*                                                                            *)
(*  This library is free software: you can redistribute it and/or modify      *)
(*  it under the terms of the GNU Lesser General Public License as            *)
(*  published by the Free Software Foundation, either version 3 of the        *)
(*  License, or (at your option) any later version.  A special linking        *)
(*  exception to the GNU Lesser General Public License applies to this        *)
(*  library, see the COPYING file for more information.                       *)
(*                                                                            *)
(*  Work developed with the support of the Mancoosi Project                   *)
(*  http://www.mancoosi.org                                                   *)
(*                                                                            *)
(******************************************************************************)

open ExtLib
open Common
open Algo
open Doseparse

module Options = struct
  open OptParse
  open OptParser
  let description = "Compute the list broken packages in a repository"
  let options = OptParser.make ~description
  include StdOptions.MakeOptions(struct let options = options end)

  let coinst = StdDebian.vpkglist_option ();;

  include StdOptions.DistcheckOptions
  StdOptions.DistcheckOptions.add_options options ;;
  StdOptions.DistcheckOptions.add_option options ~long_name:"coinst" ~help:"Check if these packages are coinstallable" coinst;;

  include StdOptions.InputOptions
  let default = "dot"::(StdOptions.InputOptions.default_options) in
  StdOptions.InputOptions.add_options ~default options ;;

  include StdOptions.OutputOptions;;
  StdOptions.OutputOptions.add_options options ;;

  include StdOptions.DistribOptions;;
  let default = List.remove StdOptions.DistribOptions.default_options "deb-host-arch" in
  StdOptions.DistribOptions.add_options ~default options ;;

  let group = add_group options "Cv Specific Options" in
  add options ~group ~long_name:"cv-int" ~help:"" int_versions;

end

include Util.Logging(struct let label = __FILE__ end) ;;

let timer = Util.Timer.create "Solver" 

(* implicit prefix of resources derived from name of executable *)
(* (input_format * add_format ?) *)
let guess_format t l =
  match Filename.basename(Sys.argv.(0)) with
  |"debcheck"|"dose-debcheck" -> (`Deb, true)
  |"eclipsecheck"|"dose-eclipsecheck" -> (`Eclipse, true)
  |"rpmcheck"|"dose-rpmcheck" -> (`Synthesis,true)
  |_ when OptParse.Opt.is_set t -> 
      (Url.scheme_of_string (OptParse.Opt.get t),true)
  |_ -> (Input.guess_format [l], false)
;;

let main () =
  let posargs = OptParse.OptParser.parse_argv Options.options in
  let inputlist = posargs@(OptParse.Opt.get Options.foreground) in
  let (input_type,implicit) = guess_format Options.inputtype inputlist in

  StdDebug.enable_debug (OptParse.Opt.get Options.verbose);
  StdDebug.enable_timers (OptParse.Opt.get Options.timers) ["Solver";"Load"];
  StdDebug.enable_bars (OptParse.Opt.get Options.progress)
    ["Depsolver_int.univcheck";"Depsolver_int.init_solver"] ;
  StdDebug.all_quiet (OptParse.Opt.get Options.quiet);

  let options = Options.set_options input_type in
  let (fg,bg) = Options.parse_cmdline (input_type,implicit) posargs in

  let (preamble,pkgll,_,from_cudf,to_cudf) = StdLoaders.load_list ~options [fg;bg] in
  let (fg_pkglist, bg_pkglist) = match pkgll with [fg;bg] -> (fg,bg) | _ -> assert false in
  let fg_pkglist = 
    if OptParse.Opt.get Options.latest then CudfAdd.latest fg_pkglist
    else fg_pkglist
  in
  let universe = 
    let s = CudfAdd.to_set (fg_pkglist @ bg_pkglist) in
    Cudf.load_universe (CudfAdd.Cudf_set.elements s) 
  in
  let universe_size = Cudf.universe_size universe in

  if OptParse.Opt.is_set Options.checkonly && 
    OptParse.Opt.is_set Options.coinst then
      fatal "--checkonly and --coinst cannot be specified together";

  let checklist = 
    if OptParse.Opt.is_set Options.checkonly then begin
      info "--checkonly specified, consider all packages as background packages";
      let co = OptParse.Opt.get Options.checkonly in
      match
        List.flatten (
          List.filter_map (fun ((n,a),c) ->
            try
              let (name,filter) = Debian.Debutil.debvpkg to_cudf ((n,a),c) in
              Some(Cudf.lookup_packages ~filter universe name)
            with Not_found -> None
          ) co
        )
      with 
      |[] ->
        fatal "Cannot find any package corresponding to the selector %s" 
        (Debian.Printer.string_of_vpkglist co)
      |l -> l
    end else []
  in

  let coinstlist = 
    if OptParse.Opt.is_set Options.coinst then begin
      info "--coinst specified, consider all packages as background packages";
      let co = OptParse.Opt.get Options.coinst in
      match
        List.filter_map (fun ((n,a),c) ->
          try
            let (name,filter) = Debian.Debutil.debvpkg to_cudf ((n,a),c) in
            Some(Cudf.lookup_packages ~filter universe name)
          with Not_found -> None
        ) co
      with 
      |[] ->
        fatal "Cannot find any package corresponding to the selector %s" 
        (Debian.Printer.string_of_vpkglist co)
      |l -> l
    end else []
  in
  let pp = CudfAdd.pp from_cudf in

  info "Solving..." ;
  let failure = OptParse.Opt.get Options.failure in
  let success = OptParse.Opt.get Options.success in
  let explain = OptParse.Opt.get Options.explain in
  let minimal = OptParse.Opt.get Options.minimal in
  let summary = OptParse.Opt.get Options.summary in
  let fmt =
    if OptParse.Opt.is_set Options.outfile then
      let f =
        let s = OptParse.Opt.get Options.outfile in
        if OptParse.Opt.is_set Options.outdir then
          let d = OptParse.Opt.get Options.outdir in
          Filename.concat d s
        else
            s
      in
      let oc = open_out f in
      Format.formatter_of_out_channel oc
    else
      Format.std_formatter
  in
  let results = Diagnostic.default_result universe_size in

  Diagnostic.pp_out_version fmt;

  if failure || success then Format.fprintf fmt "@[<v 1>report:@,";
  let callback d =
    if summary then Diagnostic.collect results d ;
    let _ = 
      IFDEF HASOCAMLGRAPH THEN
      if not(Diagnostic.is_solution d) && (OptParse.Opt.get Options.dot) then
        let dir = OptParse.Opt.opt Options.outdir in
        Diagnostic.print_dot ~addmissing:explain ?dir d
      ELSE
      ()
      ENDIF
    in
    let pp =
      if input_type = `Cudf then 
        fun pkg -> pp ~decode:(fun x -> x) pkg 
      else fun pkg -> pp pkg
    in
    Diagnostic.fprintf ~pp ~failure ~success ~explain ~minimal fmt d
  in
  Util.Timer.start timer;

  if (OptParse.Opt.is_set Options.coinst) && (List.length coinstlist) > 0 then begin
    let rl = Depsolver.edos_coinstall_prod universe coinstlist in
    let nbt = List.length (List.filter (fun r -> not (Diagnostic.is_solution r)) rl) in
    let number_checks = List.length rl in 
    ignore(Util.Timer.stop timer ());
    List.iter callback rl;
    if failure || success then Format.fprintf fmt "@]@.";
    Format.fprintf fmt "total-packages: %d@." universe_size;
    Format.fprintf fmt "total-tuples: %d@." number_checks;
    Format.fprintf fmt "broken-tuples: %d@." nbt;
    nbt
  end else begin 
    let global_constraints = not(OptParse.Opt.get Options.deb_ignore_essential) in
    let nbp =
      if (OptParse.Opt.is_set Options.checkonly) && (List.length checklist) = 0 then 0
      else if OptParse.Opt.is_set Options.checkonly then 
        Depsolver.listcheck ~global_constraints ~callback universe checklist
      else if bg_pkglist = [] then
          Depsolver.univcheck ~global_constraints ~callback universe 
      else
        Depsolver.listcheck ~global_constraints ~callback universe fg_pkglist
    in
    ignore(Util.Timer.stop timer ());
    
    if failure || success then Format.fprintf fmt "@]@.";
    
    let fn = List.length fg_pkglist in
    let bn = List.length bg_pkglist in
    
    let nb,nf = 
      let cl = List.length checklist in
      if cl != 0 then ((fn + bn) - cl,cl) else (bn,fn)
    in
    
    if nb > 0 then begin
      Format.fprintf fmt "background-packages: %d@." nb;
      Format.fprintf fmt "foreground-packages: %d@." nf
    end;

    Format.fprintf fmt "total-packages: %d@." universe_size;
    Format.fprintf fmt "broken-packages: %d@." nbp;
    if summary then 
      Format.fprintf fmt "@[%a@]@." (Diagnostic.pp_summary ~explain ~pp ()) results;
    nbp
  end
;;

StdUtils.if_application
~alternatives:[
  "debcheck";"dose-debcheck"; "dose-distcheck";
  "eclipsecheck";"dose-eclipsecheck";
  "rpmcheck";"dose-rpmcheck"]
__FILE__ main ;;

