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

(** Debian Specific Ipr to Cudf conversion routines *)

(** abstract data type holding the conversion tables 
 * for the debcudf translation. *)
type tables

(** initialize the version conversion tables *)
val init_tables : Packages.package list -> tables

(** return the cudf version associated to a tuple (name,version) *)
val get_version : tables -> Format822.name * Format822.version -> int

(** convert the a package in the ipr format to cudf. The resulting
    cudf package will be obtained by:
   - Version and package name normalization.
   - Adding self conflicts.
   - Virtual package normalization.
   - Adding priority information.
   - Mapping APT request.
*)
val tocudf : tables -> ?inst:bool -> Packages.package -> Cudf.package

(** convert a debian dependency list in a cudf constraints formula *)
val lltocudf : tables -> Format822.vpkg list list -> Cudf_types.vpkgformula

(** convert a debian conflict list in a cudf constraints list *)
val ltocudf  : tables -> Format822.vpkg list -> Cudf_types.vpkglist

(** declare the Cudf preamble used by cudf. Namely, Debcudf add a property named
 * Number of type string containing the original debian version *)
val preamble : Cudf.preamble

(** load a Cudf universe. *)
val load_universe : Packages.package list -> Cudf.universe
