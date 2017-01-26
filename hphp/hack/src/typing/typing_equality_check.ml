(**
 * Copyright (c) 2015, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the "hack" directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 *
 *)

open Typing_defs

module Env = Typing_env
module TDef = Typing_tdef
module N = Nast
module TAccess = Typing_taccess
module Phase = Typing_phase

(*****************************************************************************)
(* Check if a comparison is trivially true or false *)
(*****************************************************************************)

let trivial_result_str bop =
  match bop with
    | Ast.EQeqeq -> "false"
    | Ast.Diff2 -> "true"
    | _ -> assert false

let trivial_comparison_error p bop (r1, ty1) (r2, ty2) trail1 trail2 =
  let trivial_result = trivial_result_str bop in
  let tys1 = Typing_print.error ty1 in
  let tys2 = Typing_print.error ty2 in
  Errors.trivial_strict_eq p trivial_result
    (Reason.to_string ("This is " ^ tys1) r1)
    (Reason.to_string ("This is " ^ tys2) r2)
    trail1 trail2

let eq_incompatible_types p (r1, ty1) (r2, ty2) =
  let tys1 = Typing_print.error ty1 in
  let tys2 = Typing_print.error ty2 in
  Errors.eq_incompatible_types p
    (Reason.to_string ("This is " ^ tys1) r1)
    (Reason.to_string ("This is " ^ tys2) r2)

let rec assert_nontrivial p bop env ty1 ty2 =
  let ety_env = Phase.env_with_self env in
  let _, ty1 = Env.expand_type env ty1 in
  let _, ety1, trail1 = TDef.force_expand_typedef ~ety_env env ty1 in
  let _, ty2 = Env.expand_type env ty2 in
  let _, ety2, trail2 = TDef.force_expand_typedef ~ety_env env ty2 in
  match ty1, ty2 with
  (* Disallow `===` on distinct abstract enum types. *)
  (* Future: consider putting this in typed lint not type checking *)
  | (_, Tabstract (AKenum e1, None)), (_, Tabstract (AKenum e2, None)) ->
    if e1=e2 then ()
    else eq_incompatible_types p ety1 ety2
  | _ ->
  match ety1, ety2 with
  | (_, Tprim N.Tnum),               (_, Tprim (N.Tint | N.Tfloat))
  | (_, Tprim (N.Tint | N.Tfloat)),  (_, Tprim N.Tnum) -> ()
  | (_, Tprim N.Tarraykey),          (_, Tprim (N.Tint | N.Tstring))
  | (_, Tprim (N.Tint | N.Tstring)), (_, Tprim N.Tarraykey) -> ()
  | (r, Tprim N.Tnoreturn), _
  | _, (r, Tprim N.Tnoreturn) ->
      Errors.noreturn_usage p (Reason.to_string ("This always throws or exits") r)
  | (r, Tprim N.Tvoid), _
  | _, (r, Tprim N.Tvoid) ->
      (* Ideally we shouldn't hit this case, but well... *)
      Errors.void_usage p (Reason.to_string ("This is void") r)
  | (_, Tprim a), (_, Tprim b) when a <> b ->
      trivial_comparison_error p bop ty1 ty2 trail1 trail2
  | (_, Toption ty1), (_, Tprim _ as ty2)
  | (_, Tprim _ as ty1), (_, Toption ty2) ->
      assert_nontrivial p bop env ty1 ty2
  | (_, (Terr | Tany | Tmixed | Tarraykind _ | Tprim _ | Toption _
    | Tvar _ | Tfun _ | Tabstract (_, _) | Tclass (_, _) | Ttuple _
    | Tanon (_, _) | Tunresolved _ | Tobject | Tshape _)
    ), _ -> ()

let assert_nullable p bop env ty =
  let _, ty = Env.expand_type env ty in
  match ty with
  | r, Tarraykind _ ->
    let trivial_result = trivial_result_str bop in
    let ty_str = Typing_print.error (snd ty) in
    let msgl = Reason.to_string ("This is "^ty_str^" and cannot be null") r in
    Errors.trivial_strict_not_nullable_compare_null p trivial_result msgl
  | _, _ ->
    ()
