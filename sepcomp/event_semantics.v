Require Import compcert.lib.Coqlib.
Require Import compcert.lib.Maps.
Require Import compcert.lib.Integers.
Require Import compcert.common.Values.
Require Import compcert.common.Memory.
Require Import compcert.common.Events.
Require Import compcert.common.AST.
Require Import compcert.common.Globalenvs.

Require Import msl.Extensionality.
Require Import sepcomp.mem_lemmas.
Require Import sepcomp.semantics.
Require Import sepcomp.semantics_lemmas.

(** * Semantics annotated with Owens-style trace*)
Inductive mem_event :=
  Write : forall (b : block) (ofs : Z) (bytes : list memval), mem_event
| Read : forall (b:block) (ofs n:Z) (bytes: list memval), mem_event
| Alloc: forall (b:block)(lo hi:Z), mem_event
(*| Lock: drf_event
| Unlock: drf_event  -- these events are not generated by core steps*)
| Free: forall (l: list (block * Z * Z)), mem_event.

Fixpoint ev_elim (m:mem) (T: list mem_event) (m':mem):Prop :=
  match T with
   nil => m'=m
 | (Read b ofs n bytes :: R) => Mem.loadbytes m b ofs n = Some bytes /\ ev_elim m R m'
 | (Write b ofs bytes :: R) => exists m'', Mem.storebytes m b ofs bytes = Some m'' /\ ev_elim m'' R m'
 | (Alloc b lo hi :: R) => exists m'', Mem.alloc m lo hi = (m'',b) /\ ev_elim m'' R m'
 | (Free l :: R) => exists m'', Mem.free_list m l = Some m'' /\ ev_elim m'' R m'
  end.

Definition pmax (popt qopt: option permission): option permission :=
  match popt, qopt with
    _, None => popt
  | None, _ => qopt
  | Some p, Some q => if Mem.perm_order_dec p q then Some p else Some q
  end.

Lemma po_pmax_I p q1 q2:
  Mem.perm_order'' p q1 -> Mem.perm_order'' p q2 -> Mem.perm_order'' p (pmax q1 q2).
Proof.
  intros. destruct q1; destruct q2; simpl in *; trivial.
  destruct (Mem.perm_order_dec p0 p1); trivial.
Qed.

Fixpoint cur_perm (l: block * Z) (T: list mem_event): option permission :=
  match T with
      nil => None
    | (mu :: R) =>
          let popt := cur_perm l R in
          match mu, l with
            | (Read b ofs n bytes), (b',ofs') =>
                 pmax (if eq_block b b' && zle ofs ofs' && zlt ofs' (ofs+n)
                       then Some Readable else None) popt
            | (Write b ofs bytes), (b',ofs') =>
                 pmax (if eq_block b b' && zle ofs ofs' && zlt ofs' (ofs+ Zlength bytes)
                       then Some Writable else None) popt
            | (Alloc b lo hi), (b',ofs') =>  (*we don't add a constraint relating lo/hi/ofs*)
                 if eq_block b b' then None else popt
            | (Free l), (b',ofs') =>
                 List.fold_right (fun tr qopt => match tr with (b,lo,hi) =>
                                                   if eq_block b b' && zle lo ofs' && zlt ofs' hi
                                                   then Some Freeable else qopt
                                                end)
                                 popt l
          end
  end.

Lemma po_None popt: Mem.perm_order'' popt None.
Proof. destruct popt; simpl; trivial. Qed.

Lemma ev_perm b ofs: forall T m m', ev_elim m T m' ->
      Mem.perm_order'' ((Mem.mem_access m) !! b ofs Cur) (cur_perm (b,ofs) T).
Proof.
induction T; simpl; intros.
+ subst. apply po_None.
+ destruct a.
  - (*Store*)
     destruct H as [m'' [SB EV]]. specialize (IHT _ _ EV); clear EV.
     rewrite (Mem.storebytes_access _ _ _ _ _ SB) in *.
     eapply po_pmax_I; try eassumption.
     remember (eq_block b0 b && zle ofs0 ofs && zlt ofs (ofs0 + Zlength bytes)) as d.
     destruct d; try solve [apply po_None].
     destruct (eq_block b0 b); simpl in *; try discriminate.
     destruct (zle ofs0 ofs); simpl in *; try discriminate.
     destruct (zlt ofs (ofs0 + Zlength bytes)); simpl in *; try discriminate.
     rewrite Zlength_correct in *.
     apply Mem.storebytes_range_perm in SB.
     exploit (SB ofs); try omega.
     intros; subst; assumption.
  - (*Load*)
     destruct H as [LB EV]. specialize (IHT _ _ EV); clear EV.
     eapply po_pmax_I; try eassumption.
     remember (eq_block b0 b && zle ofs0 ofs && zlt ofs (ofs0 + n)) as d.
     destruct d; try solve [apply po_None].
     destruct (eq_block b0 b); simpl in *; try discriminate.
     destruct (zle ofs0 ofs); simpl in *; try discriminate.
     destruct (zlt ofs (ofs0 + n)); simpl in *; try discriminate.
     apply Mem.loadbytes_range_perm in LB.
     exploit (LB ofs); try omega.
     intros; subst; assumption.
  - (*Alloc*)
     destruct H as [m'' [ALLOC EV]]. specialize (IHT _ _ EV); clear EV.
     destruct (eq_block b0 b); subst; try solve [apply po_None].
     eapply po_trans; try eassumption.
     remember ((Mem.mem_access m'') !! b ofs Cur) as d.
     destruct d; try solve [apply po_None].
     symmetry in Heqd.
     apply (Mem.perm_alloc_4 _ _ _ _ _ ALLOC b ofs Cur p).
     * unfold Mem.perm; rewrite Heqd. destruct p; simpl; constructor.
     * intros N; subst; elim n; trivial.
  - (*Free*)
     destruct H as [m'' [FR EV]]. specialize (IHT _ _ EV); clear EV.
     generalize dependent m.
     induction l; simpl; intros.
     * inv FR. assumption.
     * destruct a as [[bb lo] hi].
       remember (Mem.free m bb lo hi) as p.
       destruct p; inv FR; symmetry in Heqp. specialize (IHl _ H0).
       remember (eq_block bb b && zle lo ofs && zlt ofs hi) as d.
       destruct d.
       { clear - Heqp Heqd. apply Mem.free_range_perm in Heqp.
         destruct (eq_block bb b); simpl in Heqd; inv Heqd.
         exploit (Heqp ofs); clear Heqp; trivial.
         destruct (zle lo ofs); try discriminate.
         destruct (zlt ofs hi); try discriminate. omega. }
       { eapply po_trans; try eassumption. clear - Heqp.
         remember ((Mem.mem_access m0) !! b ofs Cur) as perm2.
         destruct perm2; try solve [apply po_None].
         exploit (Mem.perm_free_3 _ _ _ _ _ Heqp); unfold Mem.perm.
            rewrite <- Heqperm2. apply perm_refl.
         simpl; trivial. }
Qed.

Lemma ev_elim_app: forall T1 m1 m2 (EV1:ev_elim m1 T1 m2) T2 m3  (EV2: ev_elim m2 T2 m3), ev_elim m1 (T1++T2) m3.
Proof.
  induction T1; simpl; intros; subst; trivial.
  destruct a.
+ destruct EV1 as [mm [SB EV]]. specialize (IHT1 _ _ EV _ _ EV2).
  exists mm; split; trivial.
+ destruct EV1 as [LB EV]. specialize (IHT1 _ _ EV _ _ EV2).
  split; trivial.
+ destruct EV1 as [mm [AL EV]]. specialize (IHT1 _ _ EV _ _ EV2).
  exists mm; split; trivial.
+ destruct EV1 as [mm [FL EV]]. specialize (IHT1 _ _ EV _ _ EV2).
  exists mm; split; trivial.
Qed.

Lemma ev_elim_split: forall T1 T2 m1 m3 (EV1:ev_elim m1 (T1++T2) m3),
      exists m2, ev_elim m1 T1 m2 /\ ev_elim m2 T2 m3.
Proof.
  induction T1; simpl; intros.
+ exists m1; split; trivial.
+ destruct a.
  - destruct EV1 as [mm [SB EV]]. destruct (IHT1 _ _ _ EV) as [m2 [EV1 EV2]].
    exists m2; split; trivial. exists mm; split; trivial.
  - destruct EV1 as [LB EV]. destruct (IHT1 _ _ _ EV) as [m2 [EV1 EV2]].
    exists m2; split; trivial. split; trivial.
  - destruct EV1 as [mm [AL EV]]. destruct (IHT1 _ _ _ EV) as [m2 [EV1 EV2]].
    exists m2; split; trivial. exists mm; split; trivial.
  - destruct EV1 as [mm [SB EV]]. destruct (IHT1 _ _ _ EV) as [m2 [EV1 EV2]].
    exists m2; split; trivial. exists mm; split; trivial.
Qed.

(** Similar to effect semantics, event semantics augment memory semantics with suitable effects, in the form
    of a set of memory access traces associated with each internal
    step of the semantics. *)

Record EvSem {G C} :=
  { (** [sem] is a memory semantics. *)
    msem :> MemSem G C

    (** The step relation of the new semantics. *)
  ; ev_step: G -> C -> mem -> list mem_event -> C -> mem -> Prop

    (** The next four fields axiomatize [drfstep] and its relation to the
        underlying step relation of [msem]. *)
  ; ev_step_ax1: forall g c m T c' m',
       ev_step g c m T c' m' ->
            corestep msem g c m c' m'
  ; ev_step_ax2: forall g c m c' m',
       corestep msem g c m c' m' ->
       exists T, ev_step g c m T c' m'
  ; ev_step_fun: forall g c m T' c' m' T'' c'' m'',
       ev_step g c m T' c' m' -> ev_step g c m T'' c'' m'' -> T'=T''
(*  ; ev_step_elim: forall g c m T c' m',
       ev_step g c m T c' m' -> ev_elim m T m'*)
  ; ev_step_elim: forall g c m T c' m' (STEP: ev_step g c m T c' m'),
       ev_elim m T m' /\
       (forall mm mm', ev_elim mm T mm' -> exists cc', ev_step g c mm T cc' mm')
  }.

Lemma Ev_sem_cur_perm {G C} (R: @EvSem G C) g c m T c' m' b ofs (D: ev_step R g c m T c' m'):
      Mem.perm_order'' ((Mem.mem_access m) !! b ofs Cur) (cur_perm (b,ofs) T).
Proof. eapply ev_perm. eapply ev_step_elim; eassumption. Qed.

Implicit Arguments EvSem [].

Require Import List.
Import ListNotations.

Definition in_free_list (b : block) ofs xs :=
  exists x, List.In x xs /\
       let '(b', lo, hi) := x in
       b = b' /\
       (lo <= ofs < hi)%Z.


Fixpoint in_free_list_trace (b : block) ofs es :=
  match es with
  | Free l :: es =>
    in_free_list b ofs l \/ in_free_list_trace b ofs es
  | _ :: es =>
    in_free_list_trace b ofs es
  | nil =>
    False
  end.

(*not needed later - not sure it's useful*)
Lemma EFLT_char es: forall b ofs, in_free_list_trace b ofs es <->
                             exists l lo hi, In (Free l) es /\ In ((b, lo), hi) l /\ lo <= ofs < hi.
Proof. induction es; simpl.
       + split; intros; try contradiction. destruct H as [? [? [? [? ?]]]]. contradiction.
       + intros.
       - destruct a.
         * destruct (IHes b ofs).
           split; intros.
           ++ destruct (H H1) as [? [? [? [? ?]]]]. eexists; eexists; eexists. split. right. apply H2. apply H3.
           ++ destruct H1 as [? [? [? [? ?]]]].
              destruct H1. discriminate. apply H0.  eexists; eexists; eexists. split. eassumption. apply H2.
         * destruct (IHes b ofs).
           split; intros.
           ++ destruct (H H1) as [? [? [? [? ?]]]]. eexists; eexists; eexists. split. right. apply H2. apply H3.
           ++ destruct H1 as [? [? [? [? ?]]]].
              destruct H1. discriminate. apply H0.  eexists; eexists; eexists. split. eassumption. apply H2.
         * destruct (IHes b ofs).
           split; intros.
           ++ destruct (H H1) as [? [? [? [? ?]]]]. eexists; eexists; eexists. split. right. apply H2. apply H3.
           ++ destruct H1 as [? [? [? [? ?]]]].
              destruct H1. discriminate. apply H0.  eexists; eexists; eexists. split. eassumption. apply H2.
         * destruct (IHes b ofs).
           split; intros.
           ++ destruct H1. destruct H1 as [[[? ?] ?] [? [? ?]]]; subst b0. exists l, z, z0. split; eauto.
              destruct (H H1) as [? [? [? [? ?]]]]. eexists; eexists; eexists. split. right. apply H2. apply H3.
           ++ destruct H1 as [? [? [? [? [? ?]]]]].
              destruct H1. inv H1. left. red. exists ((b,x0),x1). split; trivial. split; trivial.
              right. apply H0. exists x, x0 , x1. split; trivial. split; trivial.
Qed.

Lemma freelist_mem_access_1 b ofs p: forall l m (ACC:(Mem.mem_access m) !! b ofs Cur = Some p)
                                       m1 (FL: Mem.free_list m1 l = Some m), (Mem.mem_access m1) !! b ofs Cur = Some p.
Proof. induction l; simpl; intros. inv FL; trivial.
       destruct a. destruct p0.
       case_eq (Mem.free m1 b0 z0 z); intros; rewrite H in FL; try discriminate.
       eapply free_access_inv; eauto.
Qed.

Lemma freelist_access_2 b ofs: forall l  (FL: in_free_list b ofs l)
                                 m m' (FR : Mem.free_list m l = Some m'),
    (Mem.mem_access m') !! b ofs Cur = None /\ Mem.valid_block m' b.
Proof. intros l FL. destruct FL as [[[? ?] ?] [? [? ?]]]; subst b0.
       induction l; simpl; intros.
       - inv H.
       - destruct H.
         * subst. case_eq (Mem.free m b z z0); intros; rewrite H in FR; try discriminate.
           clear IHl. case_eq ((Mem.mem_access m') !! b ofs Cur); intros; trivial.
           ++ exploit freelist_mem_access_1. eassumption. eassumption. intros XX.
              exfalso. apply Mem.free_result in H. subst m0. simpl in XX.
              rewrite PMap.gss in XX. case_eq (zle z ofs && zlt ofs z0); intros; rewrite H in *; try discriminate.
              destruct (zle z ofs); try omega; simpl  in *. destruct ( zlt ofs z0); try omega. inv H.
           ++ split; trivial. eapply freelist_forward; eauto.
              exploit Mem.free_range_perm. eassumption. eassumption. intros.
              eapply Mem.valid_block_free_1; try eassumption. eapply Mem.perm_valid_block; eauto.
         * destruct a. destruct p.
           case_eq (Mem.free m b0 z2 z1); intros; rewrite H0 in FR; try discriminate. eauto.
Qed.

Lemma freelist_access_3 b ofs: forall l m (ACC: (Mem.mem_access m) !! b ofs Cur = None)
                                 (VB: Mem.valid_block m b) m' (FL: Mem.free_list m l = Some m'),
    (Mem.mem_access m') !! b ofs Cur = None.
Proof. induction l; simpl; intros.
       + inv FL; trivial.
       + destruct a as [[? ?] ?].
         case_eq (Mem.free m b0 z z0); intros; rewrite H in FL; try discriminate.
         eapply (IHl m0); trivial.
       - destruct (eq_block b0 b); subst. apply Mem.free_result in H. subst. simpl. rewrite PMap.gss, ACC. destruct (zle z ofs && zlt ofs z0); trivial.
         apply Mem.free_result in H. subst. simpl. rewrite PMap.gso; eauto.
       - eapply Mem.valid_block_free_1; eauto.
Qed.

Lemma ev_elim_accessNone b ofs: forall ev m' m'' (EV:ev_elim m'' ev m')
                                  (ACC: (Mem.mem_access m'') !! b ofs Cur = None)
                                  (VB: Mem.valid_block m'' b), (Mem.mem_access m') !! b ofs Cur = None.
Proof.  induction ev; simpl; intros. subst; trivial.
        destruct a.
        - destruct EV as [? [? EV]]. exploit Mem.storebytes_valid_block_1; eauto. intros.
          apply Mem.storebytes_access in H. rewrite <- H in *; clear H.
          apply (IHev _ _ EV ACC H0).
        - destruct EV as [? EV]. eauto.
        - destruct EV as [? [? EV]].
          apply (IHev _ _ EV); clear IHev EV.
          + Transparent Mem.alloc.
            unfold Mem.alloc in H. Opaque Mem.alloc.  inv H. simpl. rewrite PMap.gso; trivial. unfold Mem.valid_block in VB. xomega.
          + eapply Mem.valid_block_alloc; eauto.
        - destruct EV as [? [? EV]]. apply (IHev _ _ EV); clear IHev.
          2: eapply freelist_forward; eauto.
          clear EV ev m'.
          eapply freelist_access_3; eassumption.
Qed.

Lemma ev_elim_valid_block: forall ev m m' (EV: ev_elim m ev m') b
                             (VB : Mem.valid_block m b), Mem.valid_block m' b.
Proof. induction ev; simpl; intros; subst; trivial.
       destruct a.
       + destruct EV as [? [? EV]]. exploit Mem.storebytes_valid_block_1. apply H. eassumption. eauto.
       + destruct EV as [? EV]. eauto.
       + destruct EV as [? [? EV]]. exploit Mem.valid_block_alloc. apply H. eassumption. eauto.
       + destruct EV as [? [? EV]]. exploit freelist_forward; eauto. intros [? _]. eauto.
Qed.


(** If (b, ofs) is in the list of freed addresses then the
         permission was Freeable and became None or it was not allocated*)
Lemma ev_elim_free_1 b ofs:
  forall ev m m',
    ev_elim m ev m' ->
    in_free_list_trace b ofs ev ->
    (Mem.perm m b ofs Cur Freeable \/
     ~ Mem.valid_block m b) /\
    (Mem.mem_access m') !! b ofs Cur = None /\
    Mem.valid_block m' b /\
    exists e, List.In e ev /\
         match e with
         | Free _ => True
         | _ => False
         end.
Proof.
  induction ev; simpl; intros; try contradiction.
  destruct a.
  + destruct H as [m'' [ST EV]].
    specialize (Mem.storebytes_access _ _ _ _ _ ST); intros ACCESS.
    destruct (eq_block b0 b); subst.
  - destruct (IHev _ _ EV H0) as [IHa [IHb [IHc [e [E HE]]]]]; clear IHev.
    split. { destruct IHa. left. eapply Mem.perm_storebytes_2; eauto.
             right. intros N. apply H. eapply Mem.storebytes_valid_block_1; eauto. }
           split; trivial.
    split; trivial.
    exists e. split; trivial. right; trivial.
  - destruct (IHev _ _ EV H0) as [IHa [IHb [IHc [e [E HE]]]]]; clear IHev.
    split. { destruct IHa. left. eapply Mem.perm_storebytes_2; eassumption.
             right; intros N. apply H. eapply Mem.storebytes_valid_block_1; eauto. }
           split. trivial.
    split; trivial. exists e. split; trivial. right; trivial.
    + destruct H.
      destruct (IHev _ _ H1 H0) as [IHa [IHb [IHc [e [E HE]]]]]; clear IHev.
      split; trivial.
      split; trivial.
      split; trivial.
      exists e. split; trivial. right; trivial.
    + destruct H as [m'' [ALLOC EV]].
      destruct (IHev _ _ EV H0) as [IHa [IHb [IHc [e [E HE]]]]]; clear IHev.
      destruct (eq_block b0 b); subst.
  - split. right. eapply Mem.fresh_block_alloc. eauto.
    split; trivial.
    split; trivial.
    exists e.
    split; trivial. right; trivial.
  - split. { destruct IHa. left. eapply Mem.perm_alloc_4; eauto.
             right; intros N. apply H. eapply Mem.valid_block_alloc; eauto. }
           split; trivial.
    split; trivial.
    exists e. split; trivial. right; trivial.
    + destruct H as [m'' [FR EV]].
      destruct H0.
  - clear IHev.
    split. { destruct (valid_block_dec m b). 2: right; trivial. left.
             clear EV m'. generalize dependent m''. generalize dependent m.
             destruct H as [[[bb lo] hi] [X [? Y]]]; subst bb.
             induction l; simpl in *; intros. contradiction.
             destruct X; subst.
             + case_eq (Mem.free m b lo hi); intros; rewrite H in FR; try discriminate.
               eapply Mem.free_range_perm; eassumption.
             + destruct a. destruct p.
               case_eq (Mem.free m b0 z0 z); intros; rewrite H0 in FR; try discriminate.
               eapply Mem.perm_free_3. eassumption.
               eapply IHl; try eassumption.
               eapply Mem.valid_block_free_1; eauto. }
           split. { exploit freelist_access_2. eassumption. eassumption.
                    intros [ACC VB].  clear FR m l H.
                    eapply ev_elim_accessNone; eauto. }
                  split. { exploit freelist_access_2; eauto. intros [ACC VB].
                           eapply ev_elim_valid_block; eauto. }
                         exists (Free l). intuition.
  - destruct (IHev _ _ EV H) as [IHa [IHb [IHc [e [E HE]]]]]; clear IHev.
    split. { destruct IHa. left. eapply perm_freelist; eauto.
             right; intros N. apply H0. eapply freelist_forward; eauto. }
           split; trivial.
    split; trivial.
    exists e. split; trivial. right; trivial.
Qed.

Lemma perm_order_pp_refl p: Mem.perm_order'' p p.
Proof. unfold Mem.perm_order''. destruct p; trivial. apply perm_refl. Qed.

Lemma in_free_list_dec b ofs xs: {in_free_list b ofs xs} + {~in_free_list b ofs xs}.
Proof. unfold in_free_list.
       induction xs; simpl. right. intros N. destruct N as [[[? ?] ?] [? _]]. trivial.
       destruct IHxs.
       + left. destruct e as [? [? ?]]. exists x. split; eauto.
       + destruct a as [[? ?] ?].
         destruct (eq_block b0 b); subst.
       - destruct (zle z ofs).
         * destruct (zlt ofs z0). -- left. exists (b, z, z0). split; eauto.
           -- right. intros [[[? ?] ?] [? [? ?]]]. subst b0.
              destruct H. inv H. omega. apply n; clear n.
              exists (b, z1, z2). split; eauto.
         * right. intros [[[? ?] ?] [? [? ?]]]. subst b0.
           destruct H. inv H. omega. apply n; clear n.
           exists (b, z1, z2). split; eauto.
       - right. intros [[[? ?] ?] [? [? ?]]]. subst b1.
         destruct H. inv H. congruence.
         apply n; clear n. exists (b, z1, z2). split; eauto.
Qed.

Lemma in_free_list_trace_dec b ofs: forall es, {in_free_list_trace b ofs es} + {~in_free_list_trace b ofs es}.
Proof.
  induction es; simpl. right; intros N; trivial.
  destruct IHes.
  + destruct a; try solve [left; eauto].
  + destruct a; try solve [right; eauto].
    destruct (in_free_list_dec b ofs l). left; left; trivial.
    right; intros N. destruct N; contradiction.
Qed.

Lemma freelist_access_1 b ofs: forall l,
    ~ in_free_list b ofs l ->
    forall m m' : mem, Mem.free_list m l = Some m' -> (Mem.mem_access m') !! b ofs Cur = (Mem.mem_access m) !! b ofs Cur.
Proof.
  induction l; simpl; intros. inv H0. trivial.
  destruct a as [[? ?] ?].
  remember (Mem.free m b0 z z0) as q; destruct q; try discriminate. symmetry in Heqq.
  assert (~ in_free_list b ofs l). { intros N. elim H. destruct N as [? [? ?]]. exists x. split; eauto. right; trivial. }
                                   rewrite (IHl H1 _ _ H0). clear IHl H0.
  Transparent Mem.free. unfold Mem.free in Heqq.
  remember (Mem.range_perm_dec m b0 z z0 Cur Freeable).
  destruct s; inv Heqq; clear Heqs. simpl.
  rewrite PMap.gsspec. destruct (peq b b0); subst; trivial.
  destruct (zle z ofs); simpl; trivial.
  destruct (zlt ofs z0); simpl; trivial.
  elim H. unfold in_free_list. exists (b0, z, z0). split; eauto. left; trivial.
Qed.

(** If (b, ofs) is not in the list of freed locations then its permissions
cannot decrease*)
Lemma ev_elim_free_2 b ofs:
  forall ev m m' (EV: ev_elim m ev m')
    (T: ~ in_free_list_trace b ofs ev),
    Mem.perm_order'' ((Mem.mem_access m') !! b ofs Cur)
                     ((Mem.mem_access m) !! b ofs Cur).
Proof.
  induction ev; simpl; intros.
  + subst. apply perm_order_pp_refl.
  + destruct a.
  - destruct EV  as [m'' [ST EV]].
    apply Mem.storebytes_access in ST. rewrite <- ST. apply (IHev _ _ EV T).
  - destruct EV  as [LD EV].
    apply (IHev _ _ EV T).
  - destruct EV  as [m'' [ALLOC EV]].
    eapply po_trans. apply (IHev _ _ EV T). clear IHev.
    unfold Mem.perm_order''. remember ((Mem.mem_access m'') !! b ofs Cur) as q.
    symmetry in Heqq; destruct q.
    * exploit Mem.perm_alloc_inv. eassumption. unfold Mem.perm. rewrite Heqq. simpl. apply perm_refl.
      destruct (eq_block b b0); simpl; intros; subst.
      ++ rewrite Mem.nextblock_noaccess; trivial. intros N.
         eapply Mem.fresh_block_alloc; eassumption.
      ++ Transparent Mem.alloc. unfold Mem.alloc in ALLOC. inv ALLOC. simpl in *. clear EV.
         Opaque Mem.alloc.
         remember ((Mem.mem_access m) !! b ofs Cur) as r. destruct r; trivial. symmetry in Heqr.
         rewrite PMap.gso in Heqq; trivial. rewrite Heqq in Heqr. inv Heqr. apply perm_refl.
    * erewrite alloc_access_inv_None; eauto.
  - destruct EV  as [m'' [FR EV]]. specialize (IHev _ _ EV).
    destruct (in_free_list_dec b ofs l).
    * elim T. left; trivial.
    * destruct (in_free_list_trace_dec b ofs ev).
      elim T. right; trivial.
      eapply po_trans. apply IHev; trivial.
      erewrite freelist_access_1; eauto. apply perm_order_pp_refl.
Qed.

Lemma free_list_cases:
  forall l m m' b ofs
    (Hfree: Mem.free_list m l = Some m'),
    ((Mem.mem_access m) !! b ofs Cur = Some Freeable /\
     (Mem.mem_access m') !! b ofs Cur = None) \/
    ((Mem.mem_access m) !! b ofs Cur =
     (Mem.mem_access m') !! b ofs Cur).
Proof.
  induction l; simpl; intros. inv Hfree. right; trivial.
  destruct a as [[bb lo] hi].
  remember (Mem.free m bb lo hi) as q; symmetry in Heqq. destruct q; inv Hfree.
  specialize (IHl _ _ b ofs H0); clear H0.
  Transparent Mem.free. unfold Mem.free in Heqq. Opaque Mem.free.
  remember (Mem.range_perm_dec m bb lo hi Cur Freeable). destruct s; try discriminate. inv Heqq. clear Heqs.
  simpl in *.
  rewrite PMap.gsspec in *.
  destruct (peq b bb); subst; trivial.
  destruct IHl.
  + destruct H.
    rewrite H0; clear H0.
    destruct (zle lo ofs); try discriminate; simpl in *.
  - destruct (zlt ofs hi); try discriminate; simpl in *. rewrite H. left; split; trivial.
  - rewrite H. left; split; trivial.
    + destruct (zle lo ofs); simpl in *; try solve [right; trivial].
      destruct (zlt ofs hi); simpl in *; try solve [right; trivial].
      rewrite <- H; clear H.
      assert (A: lo <= ofs < hi) by omega.
      specialize (r _ A). unfold Mem.perm, Mem.perm_order' in r.
      remember ((Mem.mem_access m) !! bb ofs Cur) as q. destruct q; try contradiction.
      left; split; trivial. destruct p; simpl in *; trivial; inv r.
Qed.