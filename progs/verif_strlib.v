Require Import VST.floyd.proofauto.
Require Import VST.progs.strlib.
Require Import VST.progs.strings.
Instance CompSpecs : compspecs. make_compspecs prog. Defined.
Definition Vprog : varspecs. mk_varspecs prog. Defined.

Definition strchr_spec :=
 DECLARE _strchr
  WITH str : val, s : string, c : Z
  PRE  [ _str OF tptr tschar, _c OF tint ]
    PROP (repable_signed c; c <> 0)
    LOCAL (temp _str str; temp _c (Vint (Int.repr c)))
    SEP (cstring s str)
  POST [ tptr tschar ]
   EX i : Z, EX r : val,
    PROP (let ls := string_to_Z s in if in_dec Z_eq_dec c ls
      then Znth i ls 0 = c /\ sem_add_pi tschar str (Vint (Int.repr i)) = Some r
      else i = Zlength ls /\ r = Vint Int.zero)
    LOCAL (temp ret_temp r)
    SEP (cstring s str).

Definition strcat_spec :=
 DECLARE _strcat
  WITH dest : val, sd : string, n : Z, src : val, ss : string
  PRE  [ _dest OF tptr tschar, _src OF tptr tschar ]
    PROP (Zlength (string_to_Z sd) + Zlength (string_to_Z ss) < n)
    LOCAL (temp _dest dest; temp _src src)
    SEP (cstringn sd n dest; cstring ss src)
  POST [ tptr tschar ]
    PROP ()
    LOCAL (temp ret_temp dest)
    SEP (cstringn (append sd ss) n dest; cstring ss src).

Definition Gprog : funspecs :=
         ltac:(with_library prog [ strchr_spec; strcat_spec ]).

Lemma body_strchr: semax_body Vprog Gprog f_strchr strchr_spec.
Proof.
start_function.
forward.
unfold cstring.
set (ls := string_to_Z s).
Intros.
apply semax_pre with (P' := EX i : Z,
  PROP (0 <= i < Zlength ls + 1; Forall (fun d => d <> c) (sublist 0 i ls))
  LOCAL (temp _str str; temp _c (Vint (Int.repr c)); temp _i (Vint (Int.repr i)))
  SEP (data_at Tsh (tarray tschar (Zlength ls + 1))
          (map Vint (map Int.repr (ls ++ [0]))) str)).
{ Exists 0; rewrite sublist_nil; entailer!.
  pose proof (Zlength_nonneg ls); omega. }
eapply semax_loop.
- Intros i.
  forward.
  assert (Zlength (ls ++ [0]) = Zlength ls + 1) by (autorewrite with sublist; auto).
  forward.
  simpl.
  pose proof (repable_string_i s i) as Hi; fold ls in Hi.
  rewrite sign_ext_char by auto.
  match goal with |-semax _ (PROP () ?P) _ _ => forward_if (PROP (Znth i (ls ++ [0]) 0 <> c) P) end.
  { rewrite data_at_isptr; Intros.
    forward.
    Exists i.
    destruct str; try contradiction; simpl in *.
    Exists (Vptr b (Int.add i0 (Int.repr i))); unfold cstring; rewrite !map_app; entailer!.
    destruct (zlt i (Zlength ls)); autorewrite with sublist in *; simpl in *.
    - exploit repr_inj_signed; [| |eassumption|]; auto.
      intro; subst; destruct (in_dec _ _ _); auto.
      contradiction n; eapply Znth_In; subst ls; omega.
    - contradiction H0; apply repr_inj_signed; auto.
      replace (i - Zlength ls) with 0 in * by omega; auto. }
  { forward.
    entailer!. }
  Intros.
  match goal with |-semax _ (PROP () ?P) _ _ => forward_if (PROP (Znth i (ls ++ [0]) 0 <> 0) P) end.
  { rewrite data_at_isptr; Intros.
    forward.
    Exists i (Vint Int.zero); unfold cstring; rewrite !map_app; entailer!.
    destruct (zlt i (Zlength ls)); autorewrite with sublist in *; simpl in *.
    - exploit repr_inj_signed; [| |eassumption|]; auto.
      intro Hz; contradiction H1; rewrite <- Hz; eapply Znth_In; omega.
    - if_tac; [|subst ls; split; auto; omega].
      rewrite Forall_forall in H3; exploit H3; eauto; contradiction. }
  { forward.
    entailer!.
    congruence. }
  intros.
  unfold POSTCONDITION, abbreviate, overridePost, loop1_ret_assert.
  destruct (eq_dec ek EK_normal); [subst | apply drop_tc_environ].
  instantiate (1 := EX i : Z,
    PROP (0 <= i < Zlength ls; Forall (fun d => d <> c) (sublist 0 (i + 1) ls))
    LOCAL (temp _str str; temp _c (Vint (Int.repr c)); temp _i (Vint (Int.repr i)))
    SEP (data_at Tsh (tarray tschar (Zlength ls + 1))
            (map Vint (map Int.repr (ls ++ [0]))) str)).
  Intros; entailer!.
  Exists i; entailer!.
  destruct (eq_dec i (Zlength ls)).
  { subst; rewrite app_Znth2, Zminus_diag in * by omega; contradiction. }
  split; [omega|].
  erewrite sublist_split with (mid := i), sublist_len_1 by omega.
  rewrite Forall_app; split; auto; constructor; auto.
  autorewrite with sublist in H5; eauto.
- Intros i.
  forward.
  entailer!.
  Exists (i + 1); entailer!.
Qed.

Lemma body_strcat: semax_body Vprog Gprog f_strcat strcat_spec.
Proof.
start_function.
forward.
unfold cstringn, cstring.
set (ld := string_to_Z sd).
set (ls := string_to_Z ss).
Intros.
pose proof (Zlength_nonneg ld).
match goal with |-semax _ (PROP () (LOCALx [_; ?a; ?b] ?R)) _ _ =>
  apply semax_seq with (Q := PROP () (LOCALx [temp _i (Vint (Int.repr (Zlength ld))); a; b] R)); [|abbreviate_semax] end.
- apply semax_pre with (P' := EX i : Z,
    PROP (0 <= i < Zlength ld + 1)
    LOCAL (temp _i (Vint (Int.repr i)); temp _dest dest; temp _src src)
    SEP (data_at Tsh (tarray tschar n)
          (map Vint (map Int.repr (ld ++ [0])) ++
           list_repeat (Z.to_nat (n - (Zlength ld + 1))) Vundef) dest;
   data_at Tsh (tarray tschar (Zlength ls + 1))
     (map Vint (map Int.repr (ls ++ [0]))) src)).
  { Exists 0; entailer!. }
  eapply semax_loop.
  Intros i.
  forward.
  assert (Zlength (ld ++ [0]) = Zlength ld + 1) by (autorewrite with sublist; auto).
  pose proof (repable_string_i sd i) as Hi; fold ld in Hi.
  forward.
  { entailer!.
    (* local_facts should give us what we need *)
    autorewrite with sublist in *.
    pose proof (Zlength_nonneg (list_repeat (Z.to_nat (n - (Zlength ld + 1))) Vundef)).
    destruct (Z.max_spec 0 n) as [[? Hn] | [? Hn]]; rewrite Hn in *; omega. }
  { entailer!.
    autorewrite with sublist.
    simpl.
    rewrite sign_ext_char; auto.
    rewrite Int.signed_repr; auto.
    apply repable_char_int; auto. }
  autorewrite with sublist; simpl.
  rewrite sign_ext_char by auto.
  match goal with |-semax _ (PROP () ?P) _ _ => forward_if (PROP (Znth i (ld ++ [0]) 0 <> 0) P) end.
  + forward.
    entailer!.
    exploit repr_inj_signed; [| |eassumption|]; eauto.
    destruct (zlt i (Zlength ld)); autorewrite with sublist.
    { intro Hz; contradiction H0; rewrite <- Hz; eapply Znth_In; omega. }
    intro; do 2 apply f_equal; omega.
  + forward.
    entailer!.
    congruence.
  + intros.
    unfold POSTCONDITION, abbreviate, overridePost, loop1_ret_assert.
    destruct (eq_dec ek EK_normal); [subst | apply drop_tc_environ].
    instantiate (1 := EX i : Z,
      PROP (0 <= i < Zlength ld)
      LOCAL (temp _i (Vint (Int.repr i)); temp _dest dest; temp _src src)
      SEP (data_at Tsh (tarray tschar n)
            (map Vint (map Int.repr (ld ++ [0])) ++
             list_repeat (Z.to_nat (n - (Zlength ld + 1))) Vundef) dest;
           data_at Tsh (tarray tschar (Zlength ls + 1))
            (map Vint (map Int.repr (ls ++ [0]))) src)).
    Intros; entailer!.
    Exists i; entailer!.
    destruct (eq_dec i (Zlength ld)); [|omega].
    subst; rewrite app_Znth2, Zminus_diag in * by omega; contradiction.
  + Intros i; forward.
    unfold loop2_ret_assert; entailer!.
    Exists (i + 1); entailer!.
- forward.
  apply semax_pre with (P' := EX j : Z,
    PROP (0 <= j < Zlength ls + 1)
    LOCAL (temp _j (Vint (Int.repr j)); temp _i (Vint (Int.repr (Zlength ld)));
           temp _dest dest; temp _src src)
    SEP (data_at Tsh (tarray tschar n)
          (map Vint (map Int.repr (ld ++ sublist j 1 [0] ++ sublist 0 j ls)) ++
           list_repeat (Z.to_nat (n - (Zlength ld + j + Zlength (sublist j 1 [0])))) Vundef) dest;
         data_at Tsh (tarray tschar (Zlength ls + 1))
           (map Vint (map Int.repr (ls ++ [0]))) src)).
  { Exists 0; entailer!; auto.
    pose proof (Zlength_nonneg ls); omega. }
  eapply semax_loop.
  Intros j.
  forward.
  assert (Zlength (ls ++ [0]) = Zlength ls + 1) by (autorewrite with sublist; auto).
  pose proof (repable_string_i ss j) as Hj; fold ls in Hj.
  forward.
  forward.
  { entailer!.
    subst ls ld; omega. }
  simpl.
  rewrite sign_ext_char by auto.
  match goal with |-semax _ (PROP () ?P) _ _ => forward_if (PROP (Znth j (ls ++ [0]) 0 <> 0) P) end.
  + forward.
    unfold cstring, cstringn; entailer!.
    { rewrite string_to_Z_app, in_app in *; tauto. }
    exploit repr_inj_signed; [| |eassumption|]; auto.
    destruct (zlt j (Zlength ls)); autorewrite with sublist.
    { intro Hz; contradiction H1; rewrite <- Hz; eapply Znth_In; omega. }
    assert (j = Zlength ls) by omega; subst.
    rewrite (sublist_same 0) by auto; intros _.
    destruct (eq_dec (Zlength ls) 0).
    * apply Zlength_nil_inv in e; rewrite e; simpl.
      pose proof (Zlength_nonneg ld).
      rewrite upd_Znth_app1 by (autorewrite with sublist; omega).
      rewrite Z.add_0_r, !map_app.
      rewrite upd_Znth_app2 by (autorewrite with sublist; omega).
      simpl; autorewrite with sublist.
      rewrite upd_Znth0, sublist_nil, Znth_0_cons.
      autorewrite with sublist.
      destruct ss; [|subst ls; discriminate].
      simpl; rewrite append_empty; auto.
    * rewrite sublist_nil_gen by omega; simpl.
      pose proof (Zlength_nonneg (list_repeat (Z.to_nat (n - (Zlength ld + Zlength ls))) Vundef)).
      rewrite upd_Znth_app2 by (autorewrite with sublist; omega).
      rewrite string_to_Z_app; autorewrite with sublist.
      rewrite upd_Znth0, sublist_list_repeat; rewrite ?Zlength_list_repeat; subst ls ld; try omega.
      rewrite Znth_0_cons, !map_app, <- !app_assoc.
      apply derives_refl'; unfold data_at; simpl; do 6 f_equal; omega.
  + forward.
    entailer!.
    congruence.
  + intros.
    unfold POSTCONDITION, abbreviate, overridePost, loop1_ret_assert.
    destruct (eq_dec ek EK_normal); [subst | apply drop_tc_environ].
    instantiate (1 := EX j : Z,
      PROP (0 <= j < Zlength ls)
      LOCAL (temp _j (Vint (Int.repr j)); temp _i (Vint (Int.repr (Zlength ld)));
             temp _dest dest; temp _src src)
      SEP (data_at Tsh (tarray tschar n)
            (map Vint (map Int.repr (ld ++ sublist (j + 1) 1 [0] ++ sublist 0 (j + 1) ls)) ++
             list_repeat (Z.to_nat (n - (Zlength ld + (j + 1) + Zlength (sublist (j + 1) 1 [0])))) Vundef) dest;
           data_at Tsh (tarray tschar (Zlength ls + 1))
             (map Vint (map Int.repr (ls ++ [0]))) src)).
    Intros; entailer!.
    assert (j < Zlength ls) as Hj'.
    { destruct (eq_dec j (Zlength ls)); [|omega].
      subst; rewrite app_Znth2, Zminus_diag in * by omega; contradiction. }
    Exists j; entailer!.
    rewrite (sublist_nil_gen _ (j + 1)) by omega; simpl.
    destruct (eq_dec j 0).
    * subst; autorewrite with sublist.
      rewrite upd_Znth_app1 by (autorewrite with sublist; omega).
      rewrite !map_app, upd_Znth_app2 by (autorewrite with sublist; omega).
      autorewrite with sublist.
      rewrite upd_Znth0, sublist_nil.
      erewrite sublist_len_1 by omega.
      apply derives_refl.
    * rewrite sublist_nil_gen by omega.
      assert (1 <= n - (Zlength ld + j)).
      { clear - H Hj'; subst ls ld; omega. }
      simpl; rewrite upd_Znth_app2; autorewrite with sublist;
        rewrite ?Zlength_list_repeat; try omega.
      rewrite upd_Znth0, sublist_list_repeat; rewrite ?Zlength_list_repeat; try omega.
      erewrite (sublist_split 0 j (j + 1)), sublist_len_1 by omega.
      rewrite !map_app, <- !app_assoc; simpl.
      apply derives_refl'; unfold data_at; do 6 f_equal; omega.
  + Intros j; forward.
    unfold loop2_ret_assert; entailer!.
    Exists (j + 1); entailer!.
Qed.
