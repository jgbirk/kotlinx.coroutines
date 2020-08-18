Require Import SegmentQueue.lib.util.getAndSet.
From iris.heap_lang Require Import proofmode notation lang.

Section impl.

Variable segment_size : positive.

Definition new_segment : val :=
  λ: "id" "prev", ref ((("id", ref #0), AllocN #(Zpos segment_size) NONE),
                       (ref "prev", ref NONE)).

Definition segment_id : val :=
  λ: "seg", Fst (Fst (Fst !"seg")).

Definition segment_cancelled : val :=
  λ: "seg", Snd (Fst (Fst !"seg")).

Definition segment_prev : val :=
  λ: "seg", Fst (Snd !"seg").

Definition segment_next : val :=
  λ: "seg", Snd (Snd !"seg").

Definition segment_data_at : val :=
  λ: "seg" "idx", Snd (Fst !"seg") +ₗ "idx".

Definition copy_segment_ref : val :=
  λ: "v", "v".

Definition segment_is_removed : val :=
  λ: "seg", ! (segment_cancelled "seg") = #(Zpos segment_size).

Definition from_some : val :=
  λ: "v", match: "v" with NONE => ! #0 | SOME "v'" => "v'" end.

Definition segment_move_next_to_right : val :=
  rec: "loop" "seg" "next" := let: "curNext" := ! (segment_next "seg") in
                              if: (segment_id (from_some "next") ≤
                                   segment_id (from_some "curNext")) ||
                                  CAS (segment_next "seg") "curNext" "next"
                              then #() else "loop" "seg" "next".

Definition segment_move_prev_to_left : val :=
  rec: "loop" "seg" "prev" := let: "curPrev" := ! (segment_prev "seg") in
                              if: ("curPrev" = NONE) ||
                                  (((("prev" = NONE) = #false) &&
                                  (segment_id (from_some "curPrev") ≤
                                             segment_id (from_some "prev"))) ||
                                  CAS (segment_prev "seg") "curPrev" "prev")
                              then #() else "loop" "seg" "prev".

Definition segment_remove_first_loop : val :=
  rec: "loop" "prev" "next" :=
              if: !"prev" = NONEV
                then #() else
              let: "seg" := from_some ! "prev" in
              segment_move_next_to_right "seg" ! "next" ;;
              if: segment_is_removed "seg" = #false
                then #() else
              "prev" <- !(segment_prev "seg") ;;
              "loop" "prev" "next".

Definition segment_remove_second_loop : val :=
  rec: "loop" "prev" "next" :=
      let: "seg" := (from_some ! "next") in
      if: (segment_is_removed "seg" = #false) ||
          (!(segment_next "seg") = NONE)
      then #() else
      "next" <- !(segment_next "seg") ;;
      segment_move_prev_to_left (from_some ! "next") ! "prev" ;;
      "loop" "prev" "next".

Definition segment_remove : val :=
  λ: "seg", let: "prev" := ref !(segment_prev "seg") in
            let: "next" := ref !(segment_next "seg") in
            if: !"next" = NONEV
              then NONE else
            segment_remove_first_loop "prev" "next" ;;
            segment_move_prev_to_left (from_some ! "next") ! "prev" ;;
            segment_remove_second_loop "prev" "next" ;;
            SOME (!"prev", from_some !"next").

Definition segment_cutoff : val :=
  λ: "seg", (segment_prev "seg") <- NONE.

Definition segment_cancel_single_cell : val :=
  λ: "seg", FAA (segment_cancelled "seg") #1.

Definition segment_cancell_cell: val :=
  λ: "seg", if: (FAA (segment_cancelled "seg") #1) + #1 = #(Zpos segment_size)
            then segment_remove "seg"
            else #().

Definition cell_ref_loc : val :=
  λ: "c", let: "seg" := Fst "c" in
          let: "idx" := Snd "c" in
          segment_data_at "seg" "idx".

Definition cell_ref_cutoff : val :=
  λ: "c", segment_cutoff (Fst "c").

Definition new_infinite_array : val :=
  λ: <>, new_segment #O NONE.

Definition array_tail : val :=
  λ: "arr", "arr".

Definition move_tail_forward : val :=
  rec: "loop" "arr" "tail" := let: "curTail" := !(array_tail "arr") in
                              if: segment_id "tail" ≤ segment_id "curTail"
                              then #() else
                                if: CAS (array_tail "arr") "curTail" "tail"
                                then #() else "loop" "arr" "tail".

Definition find_segment : val :=
  rec: "loop" "cur" "fid" :=
    if: "fid" ≤ segment_id "cur" then "cur" else
      let: "next" := ref !(segment_next "cur") in
      (if: ! "next" = NONE then
         let: "newTail" := new_segment (#1%nat + segment_id "cur") (SOME "cur") in
         if: CAS (segment_next "cur") NONE (SOME "newTail") then
           (if: segment_is_removed "cur" then segment_remove "cur" else #()) ;;
           "next" <- SOME "newTail"
         else
           "next" <- !(segment_next "cur")
       else #()) ;;
      "loop" (from_some ! "next") "fid".

End impl.

From iris.algebra Require Import cmra auth list agree csum excl gset frac.
Require Import SegmentQueue.util.everything.

Section proof.

Notation cell_algebra := (optionUR (csumR (agreeR unitO) fracR)).

Notation segment_locations_algebra :=
  (optionUR (agreeR (prodO (prodO locO (prodO locO locO))
                           (prodO locO locO)))).

Notation segment_algebra := (prodUR segment_locations_algebra
                                    (listUR cell_algebra)).

Notation algebra := (authUR (listUR segment_algebra)).

Context `{heapG Σ}.

Variable segment_size: positive.

Record infinite_array_parameters :=
  InfiniteArrayParameters {
    p_cell_is_done: nat -> iProp Σ;
    p_cell_is_done_persistent: forall n, Persistent (p_cell_is_done n);
    p_cell_invariant: gname -> nat -> loc -> iProp Σ;
    p_cell_invariant_persistent: forall γ n ℓ, Persistent (p_cell_invariant γ n ℓ);
  }.

Class iArrayG Σ := IArrayG { iarray_inG :> inG Σ algebra }.
Definition iArrayΣ : gFunctors := #[GFunctor algebra].
Instance subG_iArrayΣ : subG iArrayΣ Σ -> iArrayG Σ.
Proof. solve_inG. Qed.
Context `{iArrayG Σ}.

Notation iProp := (iProp Σ).
Variable (N: namespace).

Variable array_parameters : infinite_array_parameters.

Let cell_is_done:= p_cell_is_done array_parameters.
Let cell_is_done_persistent := p_cell_is_done_persistent array_parameters.
Let cell_invariant:= p_cell_invariant array_parameters.
Let cell_invariant_persistent:= p_cell_invariant_persistent array_parameters.
Existing Instance cell_is_done_persistent.
Existing Instance cell_invariant_persistent.

Section ias_cell_info.

Definition ias_cell_info' (id_seg id_cell: nat) (c: cell_algebra):
  listUR segment_algebra := {[ id_seg := (ε, {[ id_cell := c ]}) ]}.

Theorem ias_cell_info'_op ns nc s s':
  ias_cell_info' ns nc (s ⋅ s') ≡
  ias_cell_info' ns nc s ⋅ ias_cell_info' ns nc s'.
Proof. by rewrite list_singletonM_op -pair_op list_singletonM_op. Qed.

Global Instance ias_cell_info'_core_id (ids idc: nat) (c: cell_algebra):
  CoreId c -> CoreId (ias_cell_info' ids idc c).
Proof. apply _. Qed.

Theorem ias_cell_info'_valid (ns nc: nat) (s: cell_algebra):
  ✓ (ias_cell_info' ns nc s) <-> ✓ s.
Proof.
  rewrite list_singletonM_valid pair_valid list_singletonM_valid.
  split; by [done|case].
Qed.

Definition ias_cell_info_view {A: Type} f id: A :=
  let ns := (id `div` Pos.to_nat segment_size)%nat in
  let nc := (id `mod` Pos.to_nat segment_size)%nat in
  f ns nc.

Theorem ias_cell_info_view_eq {A: Type} ns nc n (f: nat -> nat -> A):
  (nc < Pos.to_nat segment_size)%nat ->
  n = (nc + ns * Pos.to_nat segment_size)%nat ->
  f ns nc = ias_cell_info_view f n.
Proof.
  move=> HLt ->. rewrite /ias_cell_info_view.
  congr f.
  - rewrite Nat.div_add; last lia. by rewrite Nat.div_small.
  - rewrite Nat.mod_add; last lia. by rewrite Nat.mod_small.
Qed.

End ias_cell_info.

Definition segment_exists γ id := own γ (◯ ({[ id := ε ]})).

Global Instance segment_exists_persistent γ id: Persistent (segment_exists γ id).
Proof. apply _. Qed.

Theorem segment_exists_from_segment_info γ id p:
  own γ (◯ {[ id := p ]}) -∗
      own γ (◯ {[ id := p ]}) ∗ segment_exists γ id.
Proof.
  rewrite /segment_exists -own_op -auth_frag_op list_singletonM_op.
  by rewrite ucmra_unit_right_id.
Qed.

Section locations.

Definition segment_locations γ id ℓs: iProp :=
  own γ (◯ {[id := (Some (to_agree ℓs), nil)]}).

Global Instance segment_locations_persistent γ id ℓs:
  Persistent (segment_locations γ id ℓs).
Proof. apply _. Qed.

Theorem segment_locations_agree γ id ℓs ℓs':
  segment_locations γ id ℓs -∗ segment_locations γ id ℓs' -∗ ⌜ℓs = ℓs'⌝.
Proof.
  iIntros "HLoc1 HLoc2".
  iDestruct (own_valid_2 with "HLoc1 HLoc2") as %HValid.
  iPureIntro.
  move: HValid.
  rewrite auth_frag_valid list_singletonM_op list_singletonM_valid.
  repeat case; simpl; intros.
  by apply agree_op_invL'.
Qed.

Definition segment_location γ id ℓ : iProp :=
  (∃ dℓ cℓ pℓ nℓ, segment_locations γ id (ℓ, (dℓ, cℓ), (pℓ, nℓ)))%I.
Definition segment_data_location γ id dℓ: iProp :=
  (∃ ℓ cℓ pℓ nℓ, segment_locations γ id (ℓ, (dℓ, cℓ), (pℓ, nℓ)))%I.
Definition segment_canc_location γ id cℓ: iProp :=
  (∃ ℓ dℓ pℓ nℓ, segment_locations γ id (ℓ, (dℓ, cℓ), (pℓ, nℓ)))%I.
Definition segment_prev_location γ id pℓ: iProp :=
  (∃ ℓ dℓ cℓ nℓ, segment_locations γ id (ℓ, (dℓ, cℓ), (pℓ, nℓ)))%I.
Definition segment_next_location γ id nℓ: iProp :=
  (∃ ℓ dℓ cℓ pℓ, segment_locations γ id (ℓ, (dℓ, cℓ), (pℓ, nℓ)))%I.

Theorem segment_location_agree γ id ℓ ℓ':
  segment_location γ id ℓ -∗ segment_location γ id ℓ' -∗ ⌜ℓ = ℓ'⌝.
Proof. iIntros "HLoc1 HLoc2".
  iDestruct "HLoc1" as (? ? ? ?) "HLoc1". iDestruct "HLoc2" as (? ? ? ?) "HLoc2".
  iDestruct (segment_locations_agree with "HLoc1 HLoc2") as %HH; iPureIntro.
  revert HH. by intros [=].
Qed.

Theorem segment_data_location_agree γ id ℓ ℓ':
  segment_data_location γ id ℓ -∗ segment_data_location γ id ℓ' -∗ ⌜ℓ = ℓ'⌝.
Proof. iIntros "HLoc1 HLoc2".
  iDestruct "HLoc1" as (? ? ? ?) "HLoc1". iDestruct "HLoc2" as (? ? ? ?) "HLoc2".
  iDestruct (segment_locations_agree with "HLoc1 HLoc2") as %HH; iPureIntro.
  revert HH. by intros [=].
Qed.

Theorem segment_canc_location_agree γ id ℓ ℓ':
  segment_canc_location γ id ℓ -∗ segment_canc_location γ id ℓ' -∗ ⌜ℓ = ℓ'⌝.
Proof. iIntros "HLoc1 HLoc2".
  iDestruct "HLoc1" as (? ? ? ?) "HLoc1". iDestruct "HLoc2" as (? ? ? ?) "HLoc2".
  iDestruct (segment_locations_agree with "HLoc1 HLoc2") as %HH; iPureIntro.
  revert HH. by intros [=].
Qed.

Theorem segment_prev_location_agree γ id ℓ ℓ':
  segment_prev_location γ id ℓ -∗ segment_prev_location γ id ℓ' -∗ ⌜ℓ = ℓ'⌝.
Proof. iIntros "HLoc1 HLoc2".
  iDestruct "HLoc1" as (? ? ? ?) "HLoc1". iDestruct "HLoc2" as (? ? ? ?) "HLoc2".
  iDestruct (segment_locations_agree with "HLoc1 HLoc2") as %HH; iPureIntro.
  revert HH. by intros [=].
Qed.

Theorem segment_next_location_agree γ id ℓ ℓ':
  segment_next_location γ id ℓ -∗ segment_next_location γ id ℓ' -∗ ⌜ℓ = ℓ'⌝.
Proof. iIntros "HLoc1 HLoc2".
  iDestruct "HLoc1" as (? ? ? ?) "HLoc1". iDestruct "HLoc2" as (? ? ? ?) "HLoc2".
  iDestruct (segment_locations_agree with "HLoc1 HLoc2") as %HH; iPureIntro.
  revert HH. by intros [=].
Qed.

Definition segments_mapto γ (locs: list loc): iProp :=
  ([∗ list] id ↦ ℓ ∈ locs, segment_location γ id ℓ)%I.

Global Instance segments_mapto_persistent γ locs:
  Persistent (segments_mapto γ locs).
Proof. apply _. Qed.

End locations.

Hint Extern 1 => match goal with | [ |- context [segment_location]]
                                  => unfold segment_location end : core.
Hint Extern 1 => match goal with | [ |- context [segment_data_location]]
                                  => unfold segment_data_location end : core.
Hint Extern 1 => match goal with | [ |- context [segment_canc_location]]
                                  => unfold segment_canc_location end : core.
Hint Extern 1 => match goal with | [ |- context [segment_prev_location]]
                                  => unfold segment_prev_location end : core.
Hint Extern 1 => match goal with | [ |- context [segment_next_location]]
                                  => unfold segment_next_location end : core.

Section array_mapsto.

Definition array_mapsto' γ ns nc ℓ: iProp :=
  (∃ (dℓ: loc), ⌜ℓ = dℓ +ₗ Z.of_nat nc⌝ ∧ segment_data_location γ ns dℓ)%I.

Global Instance array_mapsto'_persistent γ ns nc ℓ:
  Persistent (array_mapsto' γ ns nc ℓ).
Proof. apply _. Qed.

Definition array_mapsto γ (id: nat) (ℓ: loc): iProp :=
  ias_cell_info_view (fun ns nc => array_mapsto' γ ns nc ℓ) id.

Theorem array_mapsto'_agree γ (ns nc: nat) (ℓ ℓ': loc):
  array_mapsto' γ ns nc ℓ -∗ array_mapsto' γ ns nc ℓ' -∗ ⌜ℓ = ℓ'⌝.
Proof.
  rewrite /array_mapsto'.
  iIntros "Ham Ham'".
  iDestruct "Ham" as (dℓ) "[% Ham]".
  iDestruct "Ham'" as (dℓ') "[% Ham']".
  iDestruct (segment_data_location_agree with "Ham Ham'") as %Hv.
  by subst.
Qed.

Theorem array_mapsto_agree γ n (ℓ ℓ': loc):
  array_mapsto γ n ℓ -∗ array_mapsto γ n ℓ' -∗ ⌜ℓ = ℓ'⌝.
Proof. apply array_mapsto'_agree. Qed.

Global Instance array_mapsto_persistent γ ns nc ℓ: Persistent (array_mapsto' γ ns nc ℓ).
Proof. apply _. Qed.

Global Instance array_mapsto_timeless γ ns nc ℓ: Timeless (array_mapsto' γ ns nc ℓ).
Proof. apply _. Qed.

End array_mapsto.

Section cancellation.

Definition cell_is_cancelled' γ (ns nc: nat): iProp :=
  own γ (◯ (ias_cell_info' ns nc (Some (Cinl (to_agree tt))))).
Definition cell_is_cancelled γ := ias_cell_info_view (cell_is_cancelled' γ).

Global Instance cell_is_cancelled_timeless γ j:
  Timeless (cell_is_cancelled γ j).
Proof. apply _. Qed.

Global Instance cell_is_cancelled'_persistent γ ns nc:
  Persistent (cell_is_cancelled' γ ns nc).
Proof. apply _. Qed.

Definition cells_are_cancelled γ id (cells: vec bool (Pos.to_nat segment_size)) :=
  ([∗ list] i ↦ v ∈ vec_to_list cells,
   if (v: bool) then cell_is_cancelled' γ id i else True)%I.

Global Instance cells_are_cancelled_timeless γ id cells:
  Timeless (cells_are_cancelled γ id cells).
Proof. apply big_sepL_timeless. destruct x; apply _. Qed.

Definition segment_is_cancelled γ id :=
  cells_are_cancelled γ id (Vector.const true _).

Global Instance segment_is_cancelled_timeless γ j:
  Timeless (segment_is_cancelled γ j).
Proof. apply big_sepL_timeless. destruct x; apply _. Qed.

Global Instance cells_are_cancelled_persistent γ id cells:
  Persistent (cells_are_cancelled γ id cells).
Proof.
  rewrite /cells_are_cancelled. apply big_sepL_persistent.
  intros ? x. destruct x; apply _.
Qed.

Definition cell_cancellation_handle' γ (ns nc: nat): iProp :=
  own γ (◯ (ias_cell_info' ns nc (Some (Cinr (3/4)%Qp)))).

Theorem cell_cancellation_handle'_exclusive γ (ns nc: nat):
  cell_cancellation_handle' γ ns nc -∗ cell_cancellation_handle' γ ns nc -∗ False.
Proof.
  iIntros "HCh1 HCh2".
  iDestruct (own_valid_2 with "HCh1 HCh2") as %HContra.
  iPureIntro.
  revert HContra.
  rewrite auth_frag_valid -ias_cell_info'_op ias_cell_info'_valid.
  by case.
Qed.

Theorem cell_cancellation_handle'_not_cancelled γ (ns nc: nat):
  cell_cancellation_handle' γ ns nc -∗ cell_is_cancelled' γ ns nc -∗ False.
Proof.
  iIntros "HC1 HC2". iDestruct (own_valid_2 with "HC1 HC2") as %HH.
  exfalso. move: HH.
  rewrite auth_frag_valid /= -ias_cell_info'_op ias_cell_info'_valid. case.
Qed.

Definition cell_cancellation_handle γ :=
  ias_cell_info_view (cell_cancellation_handle' γ).

End cancellation.

Definition is_valid_prev γ (id: nat) (pl: val): iProp :=
  (⌜pl = NONEV⌝ ∧
   ([∗ list] j ∈ seq 0 (id * Pos.to_nat segment_size),
    cell_is_cancelled γ j ∨ cell_is_done j) ∨
   ∃ (pid: nat) (prevℓ: loc),
     ⌜pid < id⌝ ∧ ⌜pl = SOMEV #prevℓ⌝ ∧
     segment_location γ pid prevℓ ∗
     [∗ list] j ∈ seq (S pid) (id - S pid), segment_is_cancelled γ j)%I.

Global Instance is_valid_prev_persistent γ id pl:
  Persistent (is_valid_prev γ id pl).
Proof. apply _. Qed.

Definition is_valid_next γ (id: nat) (nl: val): iProp :=
  (∃ (nid: nat) (nextℓ: loc),
      ⌜id < nid⌝ ∧ ⌜nl = SOMEV #nextℓ⌝ ∧
      segment_location γ nid nextℓ ∗
      [∗ list] j ∈ seq (S id) (nid - S id), segment_is_cancelled γ j)%I.

Global Instance is_valid_next_persistent γ id pl:
  Persistent (is_valid_prev γ id pl).
Proof. apply _. Qed.

Definition segment_invariant γ id: iProp :=
  (∃ (dℓ: loc), segment_data_location γ id dℓ ∗
  ([∗ list] i ∈ seq 0 (Pos.to_nat segment_size),
   cell_invariant γ (id*Pos.to_nat segment_size+i)%nat
                  (dℓ +ₗ Z.of_nat i)))%I.

Definition is_segment' γ (id cancelled: nat) (ℓ dℓ cℓ pℓ nℓ: loc)
           (pl nl: val): iProp :=
  (((pℓ ↦ pl ∗ nℓ ↦ nl)
      ∗ ℓ ↦ (((#id, #cℓ), #dℓ), (#pℓ, #nℓ))
      ∗ cℓ ↦ #cancelled) ∗ is_valid_prev γ id pl)%I.

Definition cell_cancellation_parts γ (id: nat)
           (cells: vec bool (Pos.to_nat segment_size)) :=
  ([∗ list] cid ↦ was_cancelled ∈ vec_to_list cells,
   if (was_cancelled: bool) then True
   else own γ (◯ (ias_cell_info' id cid (Some (Cinr (1/4)%Qp)))))%I.

Definition is_segment γ (id: nat) (ℓ: loc) (pl nl: val) : iProp :=
  (∃ dℓ cℓ pℓ nℓ cancelled,
      is_segment' γ id cancelled ℓ dℓ cℓ pℓ nℓ pl nl
                  ∗ segment_locations γ id (ℓ, (dℓ, cℓ), (pℓ, nℓ)) ∗
      segment_invariant γ id ∗
      (∃ (cells: vec bool (Pos.to_nat segment_size)),
          ⌜cancelled = length (List.filter (fun i => i) (vec_to_list cells))⌝ ∗
          cells_are_cancelled γ id cells ∗ cell_cancellation_parts γ id cells))%I.

Definition can_not_be_tail γ id := own γ (◯ {[ S id := ε ]}).

Definition is_normal_segment γ (ℓ: loc) (id: nat): iProp :=
  (∃ pl nl, is_segment γ id ℓ pl nl ∗ is_valid_next γ id nl)%I.

Definition is_tail_segment γ (ℓ: loc) (id: nat): iProp :=
  (∃ pl, is_segment γ id ℓ pl NONEV)%I.

Definition is_infinite_array γ : iProp :=
  (∃ segments, ([∗ list] i ↦ ℓ ∈ segments, is_normal_segment γ ℓ i)
                 ∗ (∃ ℓ, is_tail_segment γ ℓ (length segments))
                 ∗ (∃ segments', ⌜S (length segments) = length segments'⌝ ∧
                                 own γ (● segments')))%I.

Ltac iDestructHIsSeg :=
  iDestruct "HIsSeg" as (dℓ cℓ pℓ nℓ cancelled)
                          "[HIsSeg [>#HLocs [#HCells HCanc]]]";
  iDestruct "HIsSeg" as "[[[Hpℓ Hnℓ] [Hℓ Hcℓ]] #HValidPrev]";
  iDestruct "HCanc" as (cancelled_cells) "[>-> [>#HCanc HCancParts]]".

Ltac iCloseHIsSeg := iMod ("HClose" with "[-]") as "HΦ";
  first by (rewrite /is_segment /is_segment'; eauto 20 with iFrame).

Theorem segment_id_spec γ id (ℓ: loc):
  ⊢ <<< ∀ pl nl, ▷ is_segment γ id ℓ pl nl >>>
    segment_id #ℓ @ ⊤
  <<< is_segment γ id ℓ pl nl, RET #id >>>.
Proof.
  iIntros (Φ) "AU". wp_lam.
  wp_bind (!_)%E. iMod "AU" as (pl nl) "[HIsSeg [_ HClose]]".
  iDestructHIsSeg.
  wp_load.
  iCloseHIsSeg.
  iModIntro.
  by wp_pures.
Qed.

Theorem segment_prev_spec γ id (ℓ: loc):
  ⊢ <<< ∀ pl nl, ▷ is_segment γ id ℓ pl nl >>>
    segment_prev #ℓ @ ⊤
    <<< ∃ (pℓ: loc),
          is_segment γ id ℓ pl nl ∗ segment_prev_location γ id pℓ, RET #pℓ >>>.
Proof.
  iIntros (Φ) "AU". wp_lam.
  wp_bind (!_)%E. iMod "AU" as (pl nl) "[HIsSeg [_ HClose]]".
  iDestructHIsSeg.
  wp_load.
  iCloseHIsSeg.
  by iModIntro; wp_pures; auto.
Qed.

Theorem segment_prev_read_spec γ id (ℓ pℓ: loc):
  ⊢ segment_prev_location γ id pℓ -∗
  <<< ∀ pl nl, ▷ is_segment γ id ℓ pl nl >>>
    ! #pℓ @ ⊤
  <<< is_segment γ id ℓ pl nl ∗ is_valid_prev γ id pl, RET pl >>>.
Proof.
  iIntros "#HIsPrevLoc". iIntros (Φ) "AU".
  iMod "AU" as (pl nl) "[HIsSeg [_ HClose]]".
  rename pℓ into pℓ'. iDestructHIsSeg.
  iAssert (segment_prev_location γ id pℓ) as "#HPrevLoc"; first by eauto 6.
  iDestruct (segment_prev_location_agree with "HIsPrevLoc HPrevLoc") as %->.
  wp_load.
  iCloseHIsSeg.
  iModIntro.
  by wp_pures.
Qed.

Theorem segment_prev_write_spec γ id (ℓ pℓ: loc) (pl: val):
  ⊢ segment_prev_location γ id pℓ -∗ is_valid_prev γ id pl -∗
  <<< ∀ pl' nl, ▷ is_segment γ id ℓ pl' nl >>>
  #pℓ <- pl @ ⊤
  <<< is_segment γ id ℓ pl nl, RET #() >>>.
Proof.
  iIntros "#HIsPrevLoc #HIsValidPrev". iIntros (Φ) "AU".
  iMod "AU" as (pl' nl) "[HIsSeg [_ HClose]]".
  rename pℓ into pℓ'. iDestructHIsSeg.
  iAssert (segment_prev_location γ id pℓ) as "#HPrevLoc"; first by eauto 6.
  iDestruct (segment_prev_location_agree with "HIsPrevLoc HPrevLoc") as %->.
  wp_store.
  iCloseHIsSeg.
  by iModIntro.
Qed.

Theorem segment_next_spec γ id (ℓ: loc):
  ⊢ <<< ∀ pl nl, ▷ is_segment γ id ℓ pl nl >>>
    segment_next #ℓ @ ⊤
  <<< ∃ (nℓ: loc),
        is_segment γ id ℓ pl nl ∗ segment_next_location γ id nℓ, RET #nℓ >>>.
Proof.
  iIntros (Φ) "AU". wp_lam.
  wp_bind (!_)%E. iMod "AU" as (pl nl) "[HIsSeg [_ HClose]]".
  iDestructHIsSeg.
  wp_load.
  iCloseHIsSeg.
  iModIntro.
  by wp_pures.
Qed.

Theorem segment_next_read_spec γ id (ℓ nℓ: loc):
  ⊢ segment_next_location γ id nℓ -∗
  <<< ∀ pl nl, ▷ is_segment γ id ℓ pl nl >>>
    ! #nℓ @ ⊤
  <<< is_segment γ id ℓ pl nl, RET nl >>>.
Proof.
  iIntros "#HIsNextLoc".
  iIntros (Φ) "AU". iMod "AU" as (pl nl) "[HIsSeg [_ HClose]]".
  rename nℓ into nℓ'. iDestructHIsSeg.
  iAssert (segment_next_location γ id nℓ) as "#HNextLoc"; first by eauto 6.
  iDestruct (segment_next_location_agree with "HIsNextLoc HNextLoc") as %->.
  wp_load.
  iCloseHIsSeg.
  iModIntro.
  by wp_pures.
Qed.

Theorem segment_next_write_spec γ id (ℓ nℓ: loc) (nl: val):
  ⊢ segment_next_location γ id nℓ -∗
  <<< ∀ pl nl', ▷ is_segment γ id ℓ pl nl' >>>
    #nℓ <- nl @ ⊤
  <<< is_segment γ id ℓ pl nl, RET #() >>>.
Proof.
  iIntros "#HIsNextLoc".
  iIntros (Φ) "AU". iMod "AU" as (pl nl') "[HIsSeg [_ HClose]]".
  rename nℓ into nℓ'. iDestructHIsSeg.
  iAssert (segment_next_location γ id nℓ) as "#HNextLoc"; first by eauto 6.
  iDestruct (segment_next_location_agree with "HIsNextLoc HNextLoc") as %->.
  wp_store.
  iCloseHIsSeg.
  by iModIntro.
Qed.

Theorem segment_canc_spec γ id (ℓ: loc):
  ⊢ <<< ∀ pl nl, ▷ is_segment γ id ℓ pl nl >>>
    segment_cancelled #ℓ @ ⊤
    <<< ∃ (cℓ: loc),
          is_segment γ id ℓ pl nl ∗ segment_canc_location γ id cℓ, RET #cℓ >>>.
Proof.
  iIntros (Φ) "AU". wp_lam.
  wp_bind (!_)%E. iMod "AU" as (pl nl) "[HIsSeg [_ HClose]]".
  iDestructHIsSeg.
  wp_load.
  iCloseHIsSeg.
  iModIntro.
  by wp_pures.
Qed.

Theorem segment_canc_read_spec γ id (ℓ cℓ: loc):
  ⊢ segment_canc_location γ id cℓ -∗
  <<< ∀ pl nl, ▷ is_segment γ id ℓ pl nl >>>
    ! #cℓ @ ⊤
  <<< ∃ (cancelled: nat), is_segment γ id ℓ pl nl ∗
      (∃ cells,
          cells_are_cancelled γ id cells
          ∗ ⌜cancelled = length (List.filter (fun i => i) (vec_to_list cells))⌝),
      RET #cancelled >>>.
Proof.
  iIntros "#HIsCancLoc".
  iIntros (Φ) "AU". iMod "AU" as (pl nl) "[HIsSeg [_ HClose]]".
  rename cℓ into cℓ'. iDestructHIsSeg.
  iAssert (segment_canc_location γ id cℓ) as "#HCancLoc"; first by eauto 6.
  iDestruct (segment_canc_location_agree with "HIsCancLoc HCancLoc") as %->.
  wp_load.
  iCloseHIsSeg.
  iModIntro.
  by wp_pures.
Qed.

Lemma segment_info_to_cell_info' l γ id:
  forall k, own γ (◯ {[ id := (ε, replicate k ε ++ l) ]}) ≡
  (([∗ list] i ↦ e ∈ l, own γ (◯ ias_cell_info' id (k+i)%nat e)) ∗
  own γ (◯ {[ id := (ε, replicate (k + length l)%nat ε) ]}))%I.
Proof.
  induction l; simpl; intros.
  { by rewrite -plus_n_O app_nil_r bi.emp_sep. }
  rewrite -plus_n_O -plus_n_Sm.
  assert (
      own γ (◯ {[ id := (ε, replicate k ε ++ a :: l) ]}) ≡
      (own γ (◯ {[ id := (ε, replicate (S k) ε ++ l) ]}) ∗
       own γ (◯ ias_cell_info' id k a))%I) as ->.
  {
    rewrite -own_op -auth_frag_op list_singletonM_op -pair_op ucmra_unit_left_id.
    assert (((replicate (S k) ε ++ l) ⋅ (replicate k ε ++ [a])) ≡
            replicate k ε ++ a :: l) as ->.
    { apply list_equiv_lookup.
      induction k; case; simpl; try done.
      by rewrite ucmra_unit_left_id.
      intros n. rewrite list_lookup_op.
      by destruct (l !! n). }
    done.
  }
  rewrite IHl.
  rewrite bi.sep_comm bi.sep_assoc.
  assert (([∗ list] i ↦ e ∈ l, own γ (◯ ias_cell_info' id (S k + i)%nat e))%I ≡
          ([∗ list] i ↦ e ∈ l, own γ (◯ ias_cell_info' id (k + S i)%nat e))%I) as ->.
  2: done.
  apply big_sepL_proper.
  intros.
  by rewrite -plus_n_Sm.
Qed.

Theorem segment_canc_incr_spec γ id cid (ℓ cℓ: loc):
  (cid < Pos.to_nat segment_size)%nat ->
  ⊢ segment_canc_location γ id cℓ -∗
  <<< ∀ pl nl segments, ▷ is_segment γ id ℓ pl nl ∗
                              cell_cancellation_handle' γ id cid ∗
                              own γ (● segments) >>>
    FAA #cℓ #1 @ ⊤
  <<< ∃ (cancelled: nat),
        is_segment γ id ℓ pl nl ∗
    (∃ cells,
          cells_are_cancelled γ id cells
          ∗ ⌜S cancelled = length (List.filter (fun i => i) (vec_to_list cells))⌝) ∗
    (∃ segments', ⌜length segments' = length segments⌝ ∧ own γ (● segments')),
    RET #cancelled >>>.
Proof.
  iIntros (HCid) "#HIsCancLoc". iIntros (Φ) "AU".
  iMod "AU" as (pl nl segments) "[[HIsSeg [HCancHandle HAuth]] [_ HClose]]".
  rename cℓ into cℓ'. iDestructHIsSeg.
  iAssert (segment_canc_location γ id cℓ) as "#HCancLoc"; first by eauto 6.
  iDestruct (segment_canc_location_agree with "HIsCancLoc HCancLoc") as %->.
  rewrite /cell_cancellation_handle'.
  destruct (list_lookup cid cancelled_cells) as [[|]|] eqn:HWasNotCancelled.
  3: {
    apply lookup_ge_None in HWasNotCancelled.
    rewrite vec_to_list_length in HWasNotCancelled.
    exfalso; lia.
  }
  1: {
    rewrite /cells_are_cancelled.
    iAssert (▷ cell_is_cancelled' γ id cid)%I as ">HCidCanc". {
      iApply bi.later_mono. iIntros "HCanc".
      2: by iApply "HCanc".
      iDestruct big_sepL_lookup as "HH".
      2: done.
      2: iSpecialize ("HH" with "HCanc").
      apply _. done.
    }
    rewrite /cell_is_cancelled'.
    iDestruct (own_valid_2 with "HCancHandle HCidCanc") as %HContra.
    exfalso. move: HContra. rewrite -auth_frag_op -ias_cell_info'_op -Some_op.
    rewrite auth_frag_valid ias_cell_info'_valid. by case.
  }
  remember (VectorDef.replace_order cancelled_cells HCid true) as cancelled_cells'.
  iAssert (▷ (own γ (◯ ias_cell_info' id cid (Some (Cinr (1 / 4)%Qp)))
          ∗ cell_cancellation_parts γ id cancelled_cells'))%I
          with "[HCancParts]" as "[>HCancMain HCancParts']".
  { rewrite /cell_cancellation_parts.
    subst.
    rewrite VectorDef_replace_order_list_alter.
    iDestruct (big_sepL_list_alter) as "HOwnFr".
    { unfold lookup. apply HWasNotCancelled. }
    iSpecialize ("HOwnFr" with "HCancParts").
    by iApply "HOwnFr".
  }
  iCombine "HCancMain" "HCancHandle" as "HCancPermit".
  rewrite -ias_cell_info'_op -Some_op -Cinr_op.
  replace ((1/4) ⋅ (3/4))%Qp with 1%Qp
    by (symmetry; apply Qp_quarter_three_quarter).
  iMod (own_update_2 with "HAuth HCancPermit") as "[HAuth HSeg]".
  { apply auth_update.
    apply (let update_list := alter (fun _ => Some (Cinl (to_agree ()))) cid in
           let auth_fn x := (x.1, update_list x.2) in
           let frag_fn x := (x.1, update_list x.2)
           in list_alter_local_update id auth_fn frag_fn).
    rewrite list_lookup_singletonM.
    simpl.
    unfold lookup.
    destruct (list_lookup id segments); simpl.
    2: by apply None_local_update.
    apply option_local_update.
    apply prod_local_update_2; simpl.
    apply list_alter_local_update.
    rewrite lookup_app_r replicate_length. 2: lia.
    rewrite -minus_diag_reverse; simpl.
    remember (_ !! _) as K.
    destruct K as [u'|].
    2: by apply None_local_update.
    apply option_local_update.
    apply transitivity with (y := (None, None)).
    - apply delete_option_local_update.
      apply Cinr_exclusive.
      by apply frac_full_exclusive.
    - apply alloc_option_local_update.
      done.
  }
  rewrite /ias_cell_info' list_alter_singletonM.
  simpl.
  rewrite list_alter_singletonM.
  iAssert (cell_is_cancelled' γ id cid) with "HSeg" as "#HSeg'".
  iClear "HSeg".
  iAssert (cells_are_cancelled γ id cancelled_cells')%I as "HCancLoc'".
  { rewrite /cells_are_cancelled.
    subst. rewrite VectorDef_replace_order_list_alter.
    iDestruct (big_sepL_list_alter (fun _ => true)) as "HOwnFr".
    by apply HWasNotCancelled.
    iSpecialize ("HOwnFr" with "HCanc HSeg'").
    iDestruct "HOwnFr" as "[_ HOwnFr]". done.
  }
  iRevert "HCancLoc'".
  iIntros "#HCancLoc'".
  wp_faa.
  assert (length (List.filter (fun i => i) cancelled_cells) + 1 =
          Z.of_nat (length (List.filter (fun i => i) cancelled_cells')))%Z as Hlen.
  { subst. rewrite VectorDef_replace_order_list_alter.
    remember (vec_to_list cancelled_cells) as K.
    rewrite Z.add_comm. replace 1%Z with (Z.of_nat (S O)) by auto.
    rewrite -Nat2Z.inj_add. simpl. apply inj_eq.
    move: HWasNotCancelled. clear.
    generalize dependent cid.
    unfold alter.
    induction K; simpl.
    - discriminate.
    - destruct cid.
      { intros [= ->]. simpl. lia. }
      { intros. destruct a; simpl; auto. }
  }
  rewrite Hlen.
  iMod ("HClose" $! (length (List.filter (fun i => i) (vec_to_list cancelled_cells)))%nat
          with "[-]") as "HΦ".
  2: by iModIntro.
  iSplitR "HAuth".
  {
    rewrite /is_segment /is_segment'.
    eauto 20 with iFrame.
  }
  {
    iSplitR.
    2: {
      iExists _. iFrame.
      iPureIntro. by rewrite alter_length.
    }
    iExists _.
    iSplitL.
    iApply "HCancLoc'".
    iPureIntro.
    lia.
  }
Qed.

Theorem segment_data_at_spec γ id (ℓ: loc) (ix: nat):
  ⊢ ⌜(ix < Pos.to_nat segment_size)%nat⌝ -∗
  <<< ∀ pl nl, ▷ is_segment γ id ℓ pl nl >>>
    segment_data_at #ℓ #ix @ ⊤
  <<< ∃ (v: loc), is_segment γ id ℓ pl nl
                             ∗ array_mapsto' γ id ix v
                             ∗ cell_invariant γ
                             (id * Pos.to_nat segment_size + ix)%nat v,
  RET #v >>>.
Proof.
  iIntros "%". iIntros (Φ) "AU". wp_lam. wp_pures.
  wp_bind (!_)%E. iMod "AU" as (pl nl) "[HIsSeg [_ HClose]]".
  iDestructHIsSeg.
  wp_load.
  iSpecialize ("HClose" $! (dℓ +ₗ ix)).
  iMod ("HClose" with "[-]") as "HΦ".
  { rewrite /is_segment /is_segment'.
    iAssert (cell_invariant γ (id * Pos.to_nat segment_size + ix)%nat
                            (dℓ +ₗ ix)) as "#HCellInv".
    { iDestruct "HCells" as (dℓ') "[#HDataLoc HCells]".
      iAssert (segment_data_location γ id dℓ) as "#HDataLoc'"; first by eauto 6.
      iDestruct (segment_data_location_agree with "HDataLoc HDataLoc'") as %->.
      iApply (big_sepL_elem_of with "HCells").
      apply elem_of_list_In. apply in_seq. lia. }
    rewrite /array_mapsto'.
    by eauto 30 with iFrame.
  }
  iModIntro.
  by wp_pures.
Qed.

Theorem new_segment_spec γ (id: nat) pl :
  {{{ is_valid_prev γ id pl }}}
    (new_segment segment_size) #id pl
  {{{ (ℓ dℓ cℓ pℓ nℓ: loc), RET #ℓ;
      is_segment' γ id O ℓ dℓ cℓ pℓ nℓ pl NONEV }}}.
Proof.
  iIntros (Φ) "#HValidPrev HPost". wp_lam. wp_pures.
  wp_bind ((_, _))%E.
  wp_bind (ref _)%E. wp_alloc nℓ as "Hnℓ".
  wp_bind (ref _)%E. wp_alloc pℓ as "Hpℓ".
  wp_pures.
  wp_bind (AllocN _ _)%E. wp_alloc dℓ as "Hdℓ"; first done.
  wp_bind (ref _)%E. wp_alloc cℓ as "Hcℓ".
  wp_pures.
  wp_alloc ℓ as "Hℓ".
  iApply "HPost".
  rewrite /is_segment' /segment_invariant.
  iSplitL "Hpℓ Hnℓ Hℓ Hcℓ".
  { iSplitR "Hℓ Hcℓ"; iFrame. }
  done.
Qed.

Lemma segment_by_location' γ id hid:
  ⊢ ⌜(id ≤ hid)%nat⌝ -∗ segment_exists γ hid -∗ is_infinite_array γ -∗
  (∃ ℓ, (is_normal_segment γ ℓ id ∗ (is_normal_segment γ ℓ id -∗ is_infinite_array γ)) ∨
   (is_tail_segment γ ℓ id ∗ (is_tail_segment γ ℓ id -∗ is_infinite_array γ))).
Proof.
  iIntros (HLt) "#HSegExists HInfArr".
  iDestruct "HInfArr" as (segments) "[HNormSegs [HTailSeg HAuth]]".
  iDestruct "HAuth" as (segments') "[% HAuth]".
  destruct (le_lt_dec (length segments) id).
  { inversion l; subst.
    2: {
      iDestruct (own_valid_2 with "HAuth HSegExists")
        as %[HValid _]%auth_both_valid.
      exfalso. revert HValid. rewrite list_lookup_included.
      intro HValid. specialize (HValid hid).
      rewrite list_lookup_singletonM in HValid.
      assert (length segments' <= hid)%nat as HIsNil by lia.
      apply lookup_ge_None in HIsNil. rewrite HIsNil in HValid.
      apply option_included in HValid.
      destruct HValid as [[=]|[a [b [_ [[=] _]]]]].
    }
    iDestruct "HTailSeg" as (ℓ pl) "HIsSeg".
    iExists _. iRight.
    iSplitL "HIsSeg"; first by rewrite /is_tail_segment; eauto with iFrame.
    iIntros "HTailSeg". rewrite /is_infinite_array.
    iExists segments. iFrame. iSplitR "HAuth"; eauto 10 with iFrame.
  }
  apply lookup_lt_is_Some_2 in l. destruct l as [ℓ Hℓ].
  iDestruct (big_sepL_lookup_acc with "[HNormSegs]") as "[HIsSeg HRestSegs]".
  by apply Hℓ.
  by iApply "HNormSegs".
  simpl. iExists ℓ. iLeft. iFrame "HIsSeg".
  iIntros "HNormSeg". rewrite /is_infinite_array.
  iExists segments. iFrame "HTailSeg". iSplitR "HAuth".
  by iApply "HRestSegs".
  by eauto 10 with iFrame.
Qed.

Lemma segment_exists_from_location γ id ℓ:
  segment_location γ id ℓ -∗ segment_exists γ id.
Proof.
  iIntros "HSegLoc".
  iDestruct "HSegLoc" as (? ? ? ?) "HSegLocs". rewrite /segment_locations.
  iDestruct (segment_exists_from_segment_info with "HSegLocs") as "[_ $]".
Qed.

Lemma segment_location_from_segment γ id ℓ pl nl:
  is_segment γ id ℓ pl nl -∗ segment_location γ id ℓ.
Proof.
  iIntros "HIsSeg". rewrite /segment_location.
  iDestruct "HIsSeg" as (? ? ? ? ?) "(_ & HLocs & _)"; eauto.
Qed.

Lemma segment_by_location γ id ℓ:
  segment_location γ id ℓ -∗ is_infinite_array γ -∗
  ((is_normal_segment γ ℓ id ∗ (is_normal_segment γ ℓ id -∗ is_infinite_array γ)) ∨
   (is_tail_segment γ ℓ id ∗ (is_tail_segment γ ℓ id -∗ is_infinite_array γ))).
Proof.
  iIntros "#HSegLoc HInfArr".
  iDestruct (segment_exists_from_location with "HSegLoc") as "#HSegExists".
  iDestruct (segment_by_location' with "[% //] HSegExists HInfArr") as (ℓ') "HH".
  iAssert (segment_location γ id ℓ') as "#HSegLoc'".
  {
    iDestruct "HH" as "[[HNormSeg _]|[HTailSeg _]]".
    1: iDestruct "HNormSeg" as (? ?) "[HIsSeg _]".
    2: iDestruct "HTailSeg" as (?) "HIsSeg".
    all: iApply segment_location_from_segment; done.
  }
  iDestruct (segment_location_agree with "HSegLoc' HSegLoc") as %->.
  done.
Qed.

Lemma is_segment_by_location_prev' γ id hid:
  ⌜(id <= hid)%nat⌝ -∗ segment_exists γ hid -∗ is_infinite_array γ -∗
  ∃ ℓ nl, (∃ pl, is_segment γ id ℓ pl nl) ∗
                      (∀ pl, is_segment γ id ℓ pl nl -∗ is_infinite_array γ).
Proof.
  iIntros (HLt) "#HSegLoc HInfArr".
  iDestruct (segment_by_location' with "[% //] HSegLoc HInfArr")
    as (ℓ) "[[HNorm HRest]|[HTail HRest]]".
  1: iDestruct "HNorm" as (pl nl) "[HIsSeg #HValNext]".
  2: iDestruct "HTail" as (pl) "HIsSeg".
  all: iExists ℓ, _; iSplitL "HIsSeg"; try (iExists _; eauto).
  all: iIntros (?) "HSeg"; iApply "HRest".
  { rewrite /is_normal_segment. eauto 10 with iFrame. }
  { rewrite /is_tail_segment. eauto 10 with iFrame. }
Qed.

Lemma is_segment_by_location_prev γ id ℓ:
  segment_location γ id ℓ -∗ is_infinite_array γ -∗
  ∃ nl, (∃ pl, is_segment γ id ℓ pl nl) ∗
                      (∀ pl, is_segment γ id ℓ pl nl -∗ is_infinite_array γ).
Proof.
  iIntros "#HSegLoc HInfArr".
  iDestruct (segment_exists_from_location with "HSegLoc") as "#HSegExists".
  iDestruct (is_segment_by_location_prev' with "[% //] HSegExists HInfArr")
    as (ℓ') "HH".
  iAssert (segment_location γ id ℓ') as "#HSegLoc'".
  { iDestruct ("HH") as (?) "[HH _]". iDestruct "HH" as (?) "HIsSeg".
    iApply (segment_location_from_segment with "HIsSeg"). }
  iDestruct (segment_location_agree with "HSegLoc HSegLoc'") as %->.
  done.
Qed.

Lemma is_segment_by_location γ id ℓ:
  segment_location γ id ℓ -∗ is_infinite_array γ -∗
  ∃ pl nl, is_segment γ id ℓ pl nl ∗
                      (is_segment γ id ℓ pl nl -∗ is_infinite_array γ).
Proof.
  iIntros "#HSegLoc HInfArr".
  iDestruct (is_segment_by_location_prev with "HSegLoc HInfArr")
    as (nl) "[HIsSeg HArrRestore]".
  iDestruct "HIsSeg" as (pl) "HIsSeg".
  iExists _, _; iFrame. iApply "HArrRestore".
Qed.

Lemma segment_location_id_agree: forall γ ℓ id id',
  is_infinite_array γ -∗
                    segment_location γ id ℓ -∗
                    segment_location γ id' ℓ -∗ ⌜id = id'⌝.
Proof.
  assert (forall γ ℓ id id', (id' < id)%nat ->
            is_infinite_array γ -∗
                              segment_location γ id ℓ -∗
                              segment_location γ id' ℓ -∗ False) as HPf.
  {
    iIntros (γ ℓ id id' HLt) "HInfArr #HSegLoc1 #HSegLoc2".
    iDestruct "HInfArr" as (segments) "[HNormSegs [HTailSeg HAuth]]".
    iDestruct "HAuth" as (segments') "[% HAuth]".
    iAssert ((∃ ℓ', is_normal_segment γ ℓ' id')
               ∗ ∃ ℓ' pl nl, is_segment γ id ℓ' pl nl)%I
      with "[-]" as "[H1 H2]".
    {
      iAssert (⌜(id < length segments')%nat⌝)%I with "[-]" as %HLt'.
      {
        iDestruct (segment_exists_from_location with "HSegLoc1") as "HEx".
        iDestruct (own_valid_2 with "HAuth HEx")
          as %[HValid _]%auth_both_valid.
        iPureIntro. revert HValid. rewrite list_lookup_included.
        intro HValid. specialize (HValid id).
        rewrite list_lookup_singletonM in HValid.
        apply option_included in HValid.
        destruct HValid as [[=]|[a [b [_ [HHH _]]]]].
        apply lookup_lt_is_Some_1. by eexists _.
      }
      replace segments with (take id segments ++ drop id segments).
      2: by apply take_drop.
      rewrite big_opL_app. iDestruct "HNormSegs" as "[HNormSegsLt HNormSegsGt]".
      rewrite app_length.
      assert (id <= length segments) as HLt'' by lia.
      assert ((id' < length (take id segments))%nat) as HLt'''.
      by rewrite take_length_le; lia.
      replace (length (take id segments)) with id.
      2: by rewrite take_length_le; lia.
      apply lookup_lt_is_Some in HLt'''. destruct HLt''' as [x HLt'''].
      iSplitL "HNormSegsLt".
      by iDestruct (big_sepL_lookup with "HNormSegsLt") as "HH"; eauto.
      inversion HLt'.
      {
        assert (id = length segments) as -> by lia.
        rewrite drop_length Nat.sub_diag -plus_n_O.
        iDestruct "HTailSeg" as (? ?) "HIsSeg".
        iExists _, _, _. done.
      }
      assert (id < length segments) as HLt_ by lia.
      assert (is_Some (drop id segments !! O)) as [x' HH].
      { apply lookup_lt_is_Some. rewrite drop_length. lia. }
      iDestruct (big_sepL_lookup _ _ _ _ HH with "HNormSegsGt") as "HH".
      rewrite -plus_n_O. iDestruct "HH" as (? ?) "[HH _]".
      eauto.
    }
    iDestruct "H1" as (ℓ' ? ?) "[H1 _]". iDestruct "H2" as (ℓ'' ? ?) "H2".

    iDestruct "H1" as (? ? ? ? ?) "(H11 & H12 & _)".
    iDestruct "H2" as (? ? ? ? ?) "(H21 & H22 & _)".

    iDestruct "HSegLoc1" as (? ? ? ?) "HSegLoc1".
    iDestruct "HSegLoc2" as (? ? ? ?) "HSegLoc2".

    iDestruct (segment_locations_agree with "HSegLoc1 H22") as %[=].
    iDestruct (segment_locations_agree with "HSegLoc2 H12") as %[=].
    subst.

    iDestruct "H11" as "((_ & Hℓ' & _) & _)".
    iDestruct "H21" as "((_ & Hℓ'2 & _) & _)".
    iDestruct (mapsto_combine with "Hℓ' Hℓ'2") as "[HH _]".
    iDestruct (mapsto_valid with "HH") as %[].
    by compute.
  }
  iIntros (? ? id id') "HInfArr #HSegLoc1 #HSegLoc2".
  destruct (decide (id <= id')%nat).
  inversion l; subst.
  done.
  iDestruct (HPf with "HInfArr HSegLoc2 HSegLoc1") as %[]; lia.
  iDestruct (HPf with "HInfArr HSegLoc1 HSegLoc2") as %[]; lia.
Qed.

Definition cell_init (E: coPset) : iProp :=
  (□ (∀ γ id ℓ, cell_cancellation_handle γ id -∗ ℓ ↦ NONEV
                                         ={E}=∗ cell_invariant γ id ℓ))%I.

Theorem move_head_forward_spec γ id (ℓ: loc):
  ([∗ list] j ∈ seq 0 (id * Pos.to_nat segment_size),
    (cell_is_cancelled γ j ∨ cell_is_done j))%I -∗
  <<< ∀ pl nl, ▷ is_segment γ id ℓ pl nl >>>
    segment_cutoff #ℓ @ ⊤
  <<< is_segment γ id ℓ (InjLV #()) nl, RET #() >>>.
Proof.
  iIntros "#HDone". iIntros (Φ) "AU". wp_lam.
  rewrite /segment_prev. wp_pures.
  wp_bind (! #ℓ)%E.
  iMod "AU" as (pl nl) "[HIsSeg [HClose _]]".
  iDestructHIsSeg. wp_load. iCloseHIsSeg.
  iModIntro. wp_pures.
  iMod "HΦ" as (pl' nl') "[HIsSeg [_ HClose]]".
  iDestruct "HIsSeg" as (dℓ' cℓ' pℓ' nℓ' cancelled_cells')
                          "[HIsSeg [>#HLocs' HCanc']]".
  iDestruct "HIsSeg" as "[[[HH HH'''] HH''] HHVP]".
  iDestruct (segment_locations_agree with "HLocs HLocs'") as %HH.
  revert HH. intros [=]. subst. wp_store.
  iMod ("HClose" with "[-]") as "HPost".
  { rewrite /is_segment /is_segment' /is_valid_prev.
    eauto 20 with iFrame. }
  done.
Qed.

Lemma normal_segment_by_location γ id ℓ:
  segment_location γ id ℓ -∗ can_not_be_tail γ id -∗ is_infinite_array γ -∗
  (is_normal_segment γ ℓ id ∗ (is_normal_segment γ ℓ id -∗ is_infinite_array γ)).
Proof.
  iIntros "#HSegLoc #HNotTail HInfArr".
  iDestruct "HInfArr" as (segments) "[HNormSegs [HTail HAuth]]".
  iDestruct "HAuth" as (segments') "[% HAuth]".
  destruct (le_lt_dec (length segments) id).
  {
    iDestruct (own_valid_2 with "HAuth HNotTail") as %HContra.
    exfalso. move: HContra.
    rewrite auth_both_valid; case. rewrite list_lookup_included.
    intros HContra _. specialize (HContra (S id)). revert HContra.
    rewrite list_lookup_singletonM.
    assert (length segments' <= S id)%nat as HIsNil by lia.
    apply lookup_ge_None in HIsNil. rewrite HIsNil.
    rewrite option_included. intros HValid.
    destruct HValid as [[=]|[a [b [_ [[=] _]]]]].
  }
  apply lookup_lt_is_Some_2 in l. destruct l as [x Hx].
  iDestruct (big_sepL_lookup_acc with "[HNormSegs]") as "[HIsSeg HRestSegs]".
  by apply Hx. done. simpl. destruct (decide (ℓ = x)); subst.
  2: {
    iDestruct "HIsSeg" as (pl nl) "[HIsSeg #HValNext]".
    iDestruct "HIsSeg" as (? ? ? ? ?) "[_ [HLocs _]]".
    iAssert (segment_location γ id x) as "#HLoc";
      first by eauto 6.
    iDestruct (segment_location_agree with "HSegLoc HLoc") as %->.
    contradiction.
  }
  iFrame.
  iIntros "HNormSeg". rewrite /is_infinite_array.
  iSpecialize ("HRestSegs" with "HNormSeg").
  eauto 10 with iFrame.
Qed.

Theorem can_not_be_tail_if_has_next γ id nl:
  is_valid_next γ id nl -∗ can_not_be_tail γ id.
Proof.
  iIntros "HValidNext".
  iDestruct "HValidNext" as (nid nℓ) "(% & -> & #SegLoc & _)".
  assert (id < nid)%nat as HLt by lia.
  revert HLt. clear. intros ?.
  iDestruct "SegLoc" as (? ? ? ?) "SegLoc".
  rewrite /segment_locations. remember (_, _) as K.
  rewrite /can_not_be_tail.
  clear HeqK.
  iAssert ({[ nid := K ]} ≡ list_singletonM nid K ⋅ {[ (S id) := ε ]})%I as %->.
  { iPureIntro. rewrite /singletonM. apply list_equiv_lookup.
    intros i. rewrite list_lookup_op. generalize dependent i.
    generalize dependent id.
    induction nid as [|nid']; intros; first by lia.
    simpl. destruct i; first done; simpl.
    destruct id; simpl. 2: by apply IHnid'; lia.
    destruct nid'; simpl; destruct i; simpl; try done.
    - by rewrite -Some_op ucmra_unit_right_id.
    - by destruct ((replicate nid' _ ++ _) !! _).
  }
  rewrite auth_frag_op own_op.
  iDestruct "SegLoc" as "[_ $]".
Qed.

Theorem segment_move_next_to_right_spec γ id (ℓ: loc) mnl:
  segment_location γ id ℓ -∗
  is_valid_next γ id mnl -∗
  <<< ▷ is_infinite_array γ >>>
    segment_move_next_to_right #ℓ mnl @ ⊤
  <<< ▷ is_infinite_array γ, RET #() >>>.
Proof.
  iIntros "#HSegLoc #HValidNewNext". iIntros (Φ) "AU". wp_lam.
  rewrite /from_some. wp_pures.
  iDestruct (can_not_be_tail_if_has_next with "HValidNewNext") as "#HNotTail".
  iLöb as "IH".

  awp_apply segment_next_spec. iApply (aacc_aupd_abort with "AU"); first done.
  iIntros "HInfArr".
  iDestruct (normal_segment_by_location with "HSegLoc HNotTail HInfArr")
    as "[HNormSeg HArrRestore]".
  iDestruct "HNormSeg" as (? ?) "(HIsSeg & #HValidNext)".
  iAaccIntro with "HIsSeg".
  { iIntros "HIsSeg !>". iSplitL. 2: by eauto. iApply "HArrRestore".
    rewrite /is_normal_segment. iExists _, _.
    iFrame "HIsSeg HValidNext HNotTail". }
  iIntros (nℓ) "[HIsSeg #HNextLoc] !>".
  iSplitL.
  { rewrite /is_normal_segment. iApply "HArrRestore".
    iExists _, _. iFrame "HIsSeg HValidNext HNotTail". }
  iClear "HValidNext".
  iIntros "AU !>".

  awp_apply segment_next_read_spec; first done.
  iApply (aacc_aupd_abort with "AU"); first done.
  iIntros "HInfArr".
  iDestruct (normal_segment_by_location with "HSegLoc HNotTail HInfArr")
    as "[HNormSeg HArrRestore]".
  iDestruct "HNormSeg" as (? ?) "(HIsSeg & #HValidNext)".
  iAaccIntro with "HIsSeg".
  { iIntros "HIsSeg !>". iSplitL. 2: by eauto.
    iApply "HArrRestore". rewrite /is_normal_segment. iExists _, _.
    iFrame "HIsSeg HValidNext HNotTail". }
  iIntros "HIsSeg !>". iSplitL.
  { iApply "HArrRestore". rewrite /is_normal_segment. iExists _, _.
    iFrame "HIsSeg HValidNext HNotTail". }
  iIntros "AU !>".
  iDestruct "HValidNext" as (nid nextℓ) "(_ & >-> & >#HNextSegLoc & _)".

  wp_pures.

  awp_apply segment_id_spec. iApply (aacc_aupd_abort with "AU"); first done.
  iIntros "HInfArr".
  iDestruct (is_segment_by_location with "HNextSegLoc HInfArr")
    as (? ?) "[HIsSeg HArrRestore]".
  iAaccIntro with "HIsSeg"; iIntros "HIsSeg !>".
  { iSplitL; by [iApply "HArrRestore"|eauto]. }
  iSplitL; first by iApply "HArrRestore". iIntros "AU !>".

  iDestruct "HValidNewNext" as (nnid ?) "(% & -> & #HNewNextSegLoc & HNewCanc)".
  wp_pures.

  awp_apply segment_id_spec. iApply (aacc_aupd_abort with "AU"); first done.
  iIntros "HInfArr".
  iDestruct (is_segment_by_location with "HNewNextSegLoc HInfArr")
    as (? ?) "[HIsSeg HArrRestore]".
  iAaccIntro with "HIsSeg"; iIntros "HIsSeg !>".
  { iSplitL; by [iApply "HArrRestore"|eauto]. }
  iSplitL; first by iApply "HArrRestore". iIntros "AU".

  destruct (bool_decide (nnid <= nid)%Z) eqn:E.
  iMod "AU" as "[HInfArr [_ HClose]]"; iMod ("HClose" with "HInfArr") as "HΦ".
  all: iModIntro; wp_pures; rewrite E; wp_pures.
  1: done.

  awp_apply segment_next_spec. iApply (aacc_aupd_abort with "AU"); first done.
  iIntros "HInfArr".
  iDestruct (normal_segment_by_location with "HSegLoc HNotTail HInfArr")
    as "[HNormSeg HArrRestore]".
  iDestruct "HNormSeg" as (? ?) "(HIsSeg & #HValidNext)".
  iAaccIntro with "HIsSeg".
  { iIntros "HIsSeg !>". iSplitL. 2: by eauto. iApply "HArrRestore".
    rewrite /is_normal_segment. iExists _, _.
    iFrame "HIsSeg HValidNext HNotTail". }
  iIntros (?) "[HIsSeg #HNextLoc'] !>".
  iSplitL.
  { rewrite /is_normal_segment. iApply "HArrRestore".
    iExists _, _. iFrame "HIsSeg HValidNext HNotTail". }
  iClear "HValidNext".
  iIntros "AU !>".

  iDestruct (segment_next_location_agree with "HNextLoc' HNextLoc") as %->.
  iClear "HNextLoc'".
  wp_bind (CmpXchg _ _ _). iMod "AU" as "[HInfArr HClose]".
  iDestruct (normal_segment_by_location with "HSegLoc HNotTail HInfArr")
    as "[HIsNormSeg HArrRestore]".
  iDestruct "HIsNormSeg" as (spl snl) "(HIsSeg & #HValidNext)".
  iDestruct "HIsSeg" as (? ? ? nℓ' ?) "(HIsSeg' & >#HLocs & HCancS)".
  iAssert (segment_next_location γ id nℓ') as "#HNextLoc'";
    first by eauto 6 with iFrame.
  iDestruct (segment_next_location_agree with "HNextLoc' HNextLoc") as %->.
  iClear "HNextLoc'".
  iDestruct "HIsSeg'" as "([[HMem'' Hnl] HMem'] & HCells)".
  destruct (decide (snl = InjRV #nextℓ)); subst.
  {
    wp_cmpxchg_suc. iDestruct "HClose" as "[_ HClose]".
    iMod ("HClose" with "[-]") as "HΦ".
    2: by iModIntro; wp_pures.
    iApply "HArrRestore".
    rewrite /is_normal_segment /is_segment /is_segment'.
    iExists spl, (InjRV _). iSplitL.
    by eauto 10 with iFrame.
    rewrite /is_valid_next. eauto 10 with iFrame.
  }
  {
    wp_cmpxchg_fail. iDestruct "HClose" as "[HClose _]".
    iMod ("HClose" with "[-]") as "AU".
    { iApply "HArrRestore".
      rewrite /is_normal_segment /is_segment /is_segment'.
      by eauto 20 with iFrame. }
    iModIntro. wp_pures. wp_lam. wp_pures.
    iApply "IH". done.
  }
Qed.

Theorem segment_move_prev_to_left_spec γ id (ℓ: loc) mpl:
  segment_location γ id ℓ -∗
  is_valid_prev γ id mpl -∗
  <<< ▷ is_infinite_array γ >>>
    segment_move_prev_to_left #ℓ mpl @ ⊤
  <<< ▷ is_infinite_array γ, RET #() >>>.
Proof.
  iIntros "#HSegLoc #HNewValidPrev". iIntros (Φ) "AU". wp_lam. wp_pures.
  rewrite /from_some. iLöb as "IH".

  awp_apply segment_prev_spec; iApply (aacc_aupd_abort with "AU"); first done.
  iIntros "HInfArr".
  iDestruct (is_segment_by_location with "HSegLoc HInfArr")
    as (? ?) "[HIsSeg HArrRestore]".
  iAaccIntro with "HIsSeg".
  { iIntros "HIsSeg !>". iSplitL; by [iApply "HArrRestore"|eauto]. }
  iIntros (?) "[HIsSeg #HPrevLoc] !>". iSplitL; first by iApply "HArrRestore".
  iIntros "AU !>".

  awp_apply segment_prev_read_spec; first done.
  iApply (aacc_aupd with "AU"); first done.
  iIntros "HInfArr".
  iDestruct (is_segment_by_location with "HSegLoc HInfArr")
    as (? ?) "[HIsSeg HArrRestore]".
  iAaccIntro with "HIsSeg".
  { iIntros "HIsSeg !>"; iSplitL; by [iApply "HArrRestore"|eauto]. }
  iIntros "[HIsSeg #HValidPrev] !>".

  iDestruct "HValidPrev" as "[[-> HCanc]|#HValidPrev]".
  { iRight. iSplitL. by iApply "HArrRestore". iIntros "HΦ !>". by wp_pures. }
  iDestruct "HValidPrev" as (opid opℓ) "(% & -> & #HPrevSegLoc & HNewCanc)".

  iLeft. iSplitL. by iApply "HArrRestore". iIntros "AU !>". wp_pures.
  iDestruct "HNewValidPrev" as "[[-> HNewCanc']|#HNewValidPrev']".
  2: iDestruct "HNewValidPrev'"
    as (npid nprevℓ) "(% & -> & #HNPrevSegLoc & HNewCanc')".
  all: wp_pures.
  {
    awp_apply segment_prev_spec; iApply (aacc_aupd_abort with "AU"); first done.
    iIntros "HInfArr".
    iDestruct (is_segment_by_location with "HSegLoc HInfArr")
      as (? ?) "[HIsSeg HArrRestore]".
    iAaccIntro with "HIsSeg".
    { iIntros "HIsSeg !>"; iSplitL; by [iApply "HArrRestore"|eauto]. }
    iIntros (pℓ') "[HIsSeg #HPrevLoc'] !>".
    iSplitL; first by iApply "HArrRestore". iIntros "AU !>".

    iDestruct (segment_prev_location_agree with "HPrevLoc' HPrevLoc") as %->.
    iClear "HPrevLoc'".

    wp_bind (CmpXchg _ _ _). iMod "AU" as "[HInfArr HClose]".
    iDestruct (is_segment_by_location_prev with "HSegLoc HInfArr")
      as (?) "[HIsSeg HArrRestore]".
    iDestruct "HIsSeg" as (spl) "HIsSeg".

    iDestructHIsSeg.
    iAssert (segment_prev_location γ id pℓ) as "#HPrevLoc'";
      first by eauto 6 with iFrame.
    iDestruct (segment_prev_location_agree with "HPrevLoc HPrevLoc'") as %->.
    iClear "HPrevLoc'".
    destruct (decide (spl = InjRV #opℓ)); subst.
    { wp_cmpxchg_suc. iDestruct "HClose" as "[_ HClose]".
      iMod ("HClose" with "[-]") as "HΦ".
      2: by iModIntro; wp_pures.
      iApply "HArrRestore".
      rewrite /is_segment /is_segment' /is_valid_prev.
      iExists dℓ, cℓ, pℓ, nℓ, _.
      iSplitR "HCancParts". 2: iSplitR; eauto 10 with iFrame.
      eauto 10 with iFrame.
    }
    { wp_cmpxchg_fail. iDestruct "HClose" as "[HClose _]".
      iMod ("HClose" with "[-]") as "AU".
      { iApply "HArrRestore".
        rewrite /is_segment /is_segment' /is_valid_prev.
        iExists dℓ, cℓ, pℓ, nℓ, _. eauto 10 with iFrame. }
      iModIntro. wp_pures. wp_lam. wp_pures.
      by iApply "IH".
    }
  }
  {
    awp_apply segment_id_spec. iApply (aacc_aupd_abort with "AU"); first done.
    iIntros "HInfArr".
    iDestruct (is_segment_by_location with "HNPrevSegLoc HInfArr")
      as (? ?) "[HIsSeg HArrRestore]".
    iAaccIntro with "HIsSeg"; iIntros "HIsSeg !>".
    { iSplitL; by [iApply "HArrRestore"|eauto]. }
    iSplitL; first by iApply "HArrRestore". iIntros "AU !>". wp_pures.

    awp_apply segment_id_spec. iApply (aacc_aupd with "AU"); first done.
    iIntros "HInfArr".
    iDestruct (is_segment_by_location with "HPrevSegLoc HInfArr")
      as (? ?) "[HIsSeg HArrRestore]".
    iAaccIntro with "HIsSeg"; iIntros "HIsSeg !>".
    { iSplitL; by [iApply "HArrRestore"|eauto]. }
    iAssert (▷ is_infinite_array γ)%I with "[-]" as "HInfArr".
    { by iApply "HArrRestore". }
    iFrame "HInfArr".

    destruct (bool_decide (opid <= npid)%Z) eqn:E.
    { iRight. iIntros "HΦ !>". wp_pures. rewrite E. by wp_pures. }
    { iLeft. iIntros "AU !>". wp_pures. rewrite E. wp_pures.

  (* Mostly copy-pasted from above. *)
    awp_apply segment_prev_spec; iApply (aacc_aupd_abort with "AU"); first done.
    iIntros "HInfArr".
    iDestruct (is_segment_by_location with "HSegLoc HInfArr")
      as (? ?) "[HIsSeg HArrRestore]".
    iAaccIntro with "HIsSeg".
    { iIntros "HIsSeg !>"; iSplitL; by [iApply "HArrRestore"|eauto]. }
    iIntros (pℓ') "[HIsSeg #HPrevLoc'] !>".
    iSplitL; first by iApply "HArrRestore". iIntros "AU !>".

    iDestruct (segment_prev_location_agree with "HPrevLoc' HPrevLoc") as %->.
    iClear "HPrevLoc'".

    wp_bind (CmpXchg _ _ _). iMod "AU" as "[HInfArr HClose]".
    iDestruct (is_segment_by_location_prev with "HSegLoc HInfArr")
      as (?) "[HIsSeg HArrRestore]".
    iDestruct "HIsSeg" as (spl) "HIsSeg".

    iDestructHIsSeg.
    iAssert (segment_prev_location γ id pℓ) as "#HPrevLoc'";
      first by eauto 6 with iFrame.
    iDestruct (segment_prev_location_agree with "HPrevLoc HPrevLoc'") as %->.
    iClear "HPrevLoc'".
    destruct (decide (spl = InjRV #opℓ)); subst.
    { wp_cmpxchg_suc. iDestruct "HClose" as "[_ HClose]".
      iMod ("HClose" with "[-]") as "HΦ".
      2: by iModIntro; wp_pures.
      iApply "HArrRestore".
      rewrite /is_segment /is_segment' /is_valid_prev.
      iExists dℓ, cℓ, pℓ, nℓ, _.
      iSplitR "HCancParts". 2: iSplitR; eauto 10 with iFrame.
      iFrame. iRight. iClear "IH HValidPrev".
      iExists npid, _. eauto 10 with iFrame.
    }
    { wp_cmpxchg_fail. iDestruct "HClose" as "[HClose _]".
      iMod ("HClose" with "[-]") as "AU".
      { iApply "HArrRestore".
        rewrite /is_segment /is_segment' /is_valid_prev.
        iExists dℓ, cℓ, pℓ, nℓ, _. eauto 10 with iFrame. }
      iModIntro. wp_pures. wp_lam. wp_pures.
      by iApply "IH".
    } }
  }
Qed.

Lemma segment_cancelled__cells_cancelled γ id:
  segment_is_cancelled γ id -∗
  [∗ list] id ∈ seq (id * Pos.to_nat segment_size)%nat (Pos.to_nat segment_size),
                       cell_is_cancelled γ id.
Proof.
  rewrite /segment_is_cancelled /cells_are_cancelled.
  iIntros "#HOld".
  iAssert ([∗ list] i ↦ v ∈ Vector.const true (Pos.to_nat segment_size),
           cell_is_cancelled' γ id i)%I with "[HOld]" as "#HOld'".
  {
    iApply big_sepL_mono. 2: done.
    iIntros (k y HEl). replace y with true. done.
    revert HEl. rewrite -vlookup_lookup'.
    case. intros ?. clear. remember (nat_to_fin x) as m. clear.
    by induction m.
  }
  rewrite big_sepL_forall.
  rewrite big_sepL_forall.
  iIntros (k x) "%".
  assert (k < Pos.to_nat segment_size)%nat as HKLt. {
    remember (seq _ _) as K. replace (Pos.to_nat segment_size) with (length K).
    apply lookup_lt_is_Some_1; by eauto.
    subst. by rewrite seq_length.
  }
  rewrite /cell_is_cancelled -(ias_cell_info_view_eq id k); try assumption.
  { iApply "HOld'". iPureIntro.
    rewrite -vlookup_lookup'. exists HKLt. done. }
  rewrite Nat.add_comm. rewrite -(@seq_nth (Pos.to_nat segment_size) _ _ O).
  2: by eauto.
  symmetry. apply nth_lookup_Some with (d := O).
  done.
Qed.

Definition RemoveInv γ nlℓ plℓ :=
  (∃ nℓ nid, segment_location γ nid nℓ ∗ nlℓ ↦ SOMEV #nℓ ∗
                              (∃ pl, plℓ ↦ pl ∗ is_valid_prev γ nid pl))%I.

Theorem segment_is_removed_spec γ id (ℓ: loc):
  ⊢ <<< ∀ pl nl, ▷ is_segment γ id ℓ pl nl >>>
    (segment_is_removed segment_size) #ℓ @ ⊤
  <<< ∃ (v: bool), ▷ is_segment γ id ℓ pl nl ∗
      (⌜v = false⌝ ∨ ⌜v = true⌝ ∧ segment_is_cancelled γ id), RET #v >>>.
Proof.
  iIntros (Φ) "AU". wp_lam. awp_apply segment_canc_spec.
  iApply (aacc_aupd_abort with "AU"); first done.
  iIntros (? ?) "HIsSeg". iAaccIntro with "HIsSeg".
  { iIntros "$ !>". by eauto. }
  iIntros (cℓ) "[$ #HCancLoc] !> AU !>".

  awp_apply segment_canc_read_spec; first done.
  iApply (aacc_aupd_commit with "AU"); first done.
  iIntros (? ?) "HIsSeg". iAaccIntro with "HIsSeg".
  { iIntros "$ !>". by eauto. }
  iIntros (cancelled) "[$ #HCells] !>".
  destruct (decide (cancelled = Pos.to_nat segment_size)); subst.
  2: {
    iExists false. iSplit; first by iLeft. iIntros "HΦ !>". wp_pures.
    rewrite bool_decide_eq_false_2; first by eauto.
    intros [=]; lia.
  }
  { iExists true. iSplit.
    2: iIntros "HΦ !>"; wp_pures; by rewrite positive_nat_Z bool_decide_eq_true_2.
    iRight. rewrite /segment_is_cancelled.
    iDestruct "HCells" as (cells) "[HCancelled %]".
    replace cells with (Vector.const true (Pos.to_nat segment_size)).
    1: by auto.
    by erewrite <-filter_induces_vector.
  }
Qed.

Lemma segments_cancelled__cells_cancelled γ n m:
  ([∗ list] id ∈ seq n m, segment_is_cancelled γ id) -∗
   [∗ list] id ∈ seq (n * Pos.to_nat segment_size)%nat
   (m * Pos.to_nat segment_size)%nat,
  cell_is_cancelled γ id.
Proof.
  iIntros "#HSegCanc".
  iDestruct (big_sepL_mono with "HSegCanc") as "HSegCanc'".
  { intros ? ? _. simpl. iApply segment_cancelled__cells_cancelled. }
  by rewrite /= -big_sepL_bind seq_bind.
Qed.

Lemma move_cutoff id nid γ:
  (id < nid)%nat ->
  ([∗ list] j ∈ seq 0 (id * Pos.to_nat segment_size),
    cell_is_cancelled γ j ∨ cell_is_done j) -∗
  segment_is_cancelled γ id -∗
  ([∗ list] j ∈ seq (S id) (nid - S id), segment_is_cancelled γ j) -∗
  [∗ list] j ∈ seq 0 (nid * Pos.to_nat segment_size),
    cell_is_cancelled γ j ∨ cell_is_done j.
Proof.
  iIntros (HLt) "HLow HC HHigh".
  iAssert ([∗ list] j ∈ seq id (nid - id), segment_is_cancelled γ j)%I
    with "[HC HHigh]" as "HHigh".
  { replace (nid - id)%nat with (S (nid - S id)) by lia.
    simpl. iFrame. }
  rewrite -(seq_app (id * Pos.to_nat segment_size) _ (nid * _)).
  2: apply mult_le_compat_r; lia.
  rewrite big_sepL_app -Nat.mul_sub_distr_r /=. iFrame "HLow".
  iDestruct (segments_cancelled__cells_cancelled with "HHigh") as "HHigh".
  iApply big_sepL_mono. 2: done. iIntros; by iLeft.
Qed.

Lemma merge_cancelled_segments pid id nid γ:
  (pid < id)%nat -> (id < nid)%nat ->
  ([∗ list] j ∈ seq (S pid) (id - S pid), segment_is_cancelled γ j) -∗
  segment_is_cancelled γ id -∗
  ([∗ list] j ∈ seq (S id) (nid - S id), segment_is_cancelled γ j) -∗
  [∗ list] j ∈ seq (S pid) (nid - S pid), segment_is_cancelled γ j.
Proof.
  iIntros (HLt HLt') "HLow HC HHigh".
  iAssert ([∗ list] j ∈ seq id (nid - id), segment_is_cancelled γ j)%I
    with "[HC HHigh]" as "HHigh".
  { replace (nid - id)%nat with (S (nid - S id)) by lia.
    simpl. iFrame. }
  rewrite -(seq_app (id - S pid) _ (nid - S pid)). 2: lia. rewrite big_opL_app.
  replace (S pid + (id - S pid))%nat with id by lia.
  replace (nid - S pid - (id - S pid))%nat with (nid - id)%nat by lia.
  iFrame.
Qed.

Theorem remove_first_loop_spec γ (plℓ nlℓ: loc):
  RemoveInv γ nlℓ plℓ -∗
  <<< ▷ is_infinite_array γ >>>
    (segment_remove_first_loop segment_size) #plℓ #nlℓ @ ⊤
  <<< ▷ is_infinite_array γ ∗ RemoveInv γ nlℓ plℓ, RET #() >>>.
Proof.
  iIntros "RemoveInv". iIntros (Φ) "AU". wp_lam. wp_pures.
  iLöb as "IH". wp_bind (! _)%E.
  iDestruct "RemoveInv" as (? nid) "(#HNextSegLoc & Hnlℓ & Hplℓ)".
  iDestruct "Hplℓ" as (?) "[Hplℓ [[-> #HCanc]|HVplℓ]]".
  { iMod "AU" as "[HInfArr [_ HClose]]".
    wp_load.
    iMod ("HClose" with "[-]") as "HΦ".
    { iFrame "HInfArr". rewrite /RemoveInv /is_valid_prev.
      iExists _, _. iFrame "Hnlℓ HNextSegLoc".
      iExists _. iFrame "Hplℓ". iLeft. iSplit; done. }
    iModIntro.
    by wp_pures. }
  iDestruct "HVplℓ" as (pid ?) "(% & -> & #HPrevSegLoc & #HSegCanc)".
  wp_load. wp_pures. rewrite /from_some. wp_load. wp_pures. wp_load.

  awp_apply segment_move_next_to_right_spec; first done.
  { iExists _, _. eauto with iFrame. }
  iApply (aacc_aupd_abort with "AU"); first done.
  iIntros "HInfArr". iAaccIntro with "HInfArr"; iIntros "$ !>".
  { eauto with iFrame. }
  iIntros "AU !>". wp_pures.

  awp_apply segment_is_removed_spec. iApply (aacc_aupd with "AU"); first done.
  iIntros "HInfArr".
  iDestruct (is_segment_by_location with "HPrevSegLoc HInfArr")
    as (? ?) "[HIsSeg HArrRestore]".
  iAaccIntro with "HIsSeg".
  { iIntros "HIsSeg !>". iDestruct ("HArrRestore" with "HIsSeg") as "$".
    by eauto with iFrame. }
  iIntros (b) "[HIsSeg HCanc] !>".
  iDestruct ("HArrRestore" with "HIsSeg") as "$".
  iDestruct "HCanc" as "[->|[-> #HSegCanc']]".
  { iRight. iSplitL.
    { rewrite /RemoveInv. iExists _, _. iFrame "HNextSegLoc Hnlℓ".
      iExists _. iFrame "Hplℓ". rewrite /is_valid_prev.
      iRight. iClear "IH". iExists _, _.
      eauto with iFrame.
    }
    iIntros "HΦ !>". by wp_pures. }
  iLeft. iIntros "AU !>". wp_pures.

  awp_apply segment_prev_spec. iApply (aacc_aupd_abort with "AU"); first done.
  iIntros "HInfArr".
  iDestruct (is_segment_by_location with "HPrevSegLoc HInfArr")
    as (? ?) "[HIsSeg HArrRestore]".
  iAaccIntro with "HIsSeg".
  { iIntros "HIsSeg !>". iDestruct ("HArrRestore" with "HIsSeg") as "$".
    by eauto with iFrame. }
  iIntros (cℓ) "[HIsSeg #HPrevLoc] !>".
  iDestruct (bi.later_wand with "HArrRestore HIsSeg") as "$".
  iIntros "AU !>".

  awp_apply segment_prev_read_spec; first done.
  iApply (aacc_aupd_abort with "AU"); first done.
  iIntros "HInfArr".
  iDestruct (is_segment_by_location with "HPrevSegLoc HInfArr")
    as (? ?) "[HIsSeg HArrRestore]".
  iAaccIntro with "HIsSeg".
  { iIntros "HIsSeg !>". iDestruct ("HArrRestore" with "HIsSeg") as "$".
    by eauto with iFrame. }
  iIntros "[HIsSeg #HValidPrev] !>".
  iDestruct (bi.later_wand with "HArrRestore HIsSeg") as "$".
  iIntros "AU !>".
  wp_store. wp_lam. wp_pures.
  iApply ("IH" with "[-AU]"). 2: by auto.

  iClear "IH". rewrite /RemoveInv.
  iExists _, _. iFrame "HNextSegLoc Hnlℓ". iExists _. iFrame "Hplℓ".

  iDestruct "HValidPrev" as "[[-> #HOldCanc]|HValidPrev]".
  { iLeft; iSplit; first done.
    iApply move_cutoff; try done. }
  { iRight. iDestruct "HValidPrev"
      as (pid' prevℓ') "(% & -> & #HNewPrevSegLoc & #HNewPrevCanc)".
    iExists pid', prevℓ'. repeat iSplit; try done.
    iPureIntro; lia.

    iApply (merge_cancelled_segments pid' pid nid); try done; lia.
  }
Qed.

Theorem remove_second_loop_spec γ (plℓ nlℓ: loc):
  RemoveInv γ nlℓ plℓ -∗
  <<< ▷ is_infinite_array γ >>>
    (segment_remove_second_loop segment_size) #plℓ #nlℓ @ ⊤
  <<< ▷ is_infinite_array γ ∗ RemoveInv γ nlℓ plℓ, RET #() >>>.
Proof.
  iIntros "RemoveInv". iIntros (Φ) "AU". wp_lam. wp_pures.
  rewrite /from_some. iLöb as "IH". wp_bind (! _)%E.
  iDestruct "RemoveInv" as (? nid) "(#HNextSegLoc & Hnlℓ & Hplℓ)".
  iDestruct "Hplℓ" as (pl) "[Hplℓ #HValidPrev]".
  wp_load. wp_pures.

  awp_apply segment_is_removed_spec.
  iApply (aacc_aupd with "AU"); first done.
  iIntros "HInfArr".
  iDestruct (is_segment_by_location with "HNextSegLoc HInfArr")
    as (? ?) "[HIsSeg HArrRestore]".
  iAaccIntro with "HIsSeg".
  { iIntros "HIsSeg". iDestruct ("HArrRestore" with "HIsSeg") as "$".
    by eauto with iFrame. }
  iIntros (?) "[HIsSeg HIsRemoved] !>".
  iDestruct (bi.later_wand with "HArrRestore HIsSeg") as "$".

  iDestruct "HIsRemoved" as "[->|[-> #HSegCanc]]".
  { iRight. iSplitL.
    2: by iIntros "HΦ"; iModIntro; wp_pures.
    iExists _, _. iFrame "HNextSegLoc Hnlℓ".
    iExists _. iFrame "Hplℓ HValidPrev". }
  iLeft. iIntros "AU !>". wp_pures.

  awp_apply segment_next_spec. iApply (aacc_aupd_abort with "AU"); first done.
  iIntros "HInfArr".
  iDestruct (is_segment_by_location with "HNextSegLoc HInfArr")
    as (? ?) "[HIsSeg HArrRestore]".
  iAaccIntro with "HIsSeg".
  { iIntros "HIsSeg". iDestruct ("HArrRestore" with "HIsSeg") as "$".
    by eauto with iFrame. }
  iIntros (?) "[HIsSeg #HNextLoc] !>".
  iDestruct (bi.later_wand with "HArrRestore HIsSeg") as "$".
  iIntros "AU !>".

  awp_apply segment_next_read_spec; first done.
  iApply (aacc_aupd with "AU"); first done.
  iIntros "HInfArr".
  iDestruct (segment_by_location with "HNextSegLoc HInfArr")
    as "[[HH HArrRestore]|[HH HArrRestore]]".
  2: {
    iDestruct "HH" as (?) "HIsSeg".
    iAaccIntro with "HIsSeg".
    { iIntros "HIsSeg !>". iSplitL "HArrRestore HIsSeg". 2: by eauto with iFrame.
      iApply "HArrRestore". iExists _. iFrame "HIsSeg". }
    iIntros "HIsSeg !>". iRight. iSplitL.
    2: by iIntros "HΦ !>"; wp_pures.
    iSplitL "HArrRestore HIsSeg".
    { iApply "HArrRestore". iExists _. by iAssumption. }
    rewrite /RemoveInv. iExists _, _. iFrame "Hnlℓ HNextSegLoc".
    iExists _. iFrame "Hplℓ HValidPrev".
  }
  iDestruct "HH" as (? ?) "(HIsSeg & #HValidNext)".
  iAaccIntro with "HIsSeg".
  { iIntros "HIsSeg !>". iSplitR "Hnlℓ Hplℓ". 2: by eauto with iFrame.
    iApply "HArrRestore". iExists _, _. by iFrame. }
  iIntros "HIsSeg !>". iLeft. iSplitR "Hnlℓ Hplℓ".
  { iApply "HArrRestore". iExists _, _. by iFrame. }
  iIntros "AU !>". wp_pures.

  iDestruct (can_not_be_tail_if_has_next with "HValidNext") as "#HNotTail".
  iDestruct "HValidNext" as (? ?) "(% & -> & _)".
  wp_pures.

  awp_apply segment_next_spec. iApply (aacc_aupd_abort with "AU"); first done.
  iIntros "HInfArr".
  iDestruct (is_segment_by_location with "HNextSegLoc HInfArr")
    as (? ?) "[HIsSeg HArrRestore]".
  iAaccIntro with "HIsSeg".
  { iIntros "HIsSeg !>". iSplitR "Hnlℓ Hplℓ". 2: by eauto with iFrame.
    iDestruct ("HArrRestore" with "HIsSeg") as "$". }
  iIntros (?) "[HIsSeg HNextLoc'] !>".
  iDestruct (bi.later_wand with "HArrRestore HIsSeg") as "$".
  iDestruct (segment_next_location_agree with "HNextLoc' HNextLoc") as %->.
  iClear "HNextLoc'".
  iIntros "AU !>".

  awp_apply segment_next_read_spec; first by iAssumption.
  iApply (aacc_aupd_abort with "AU"); first done.
  iIntros "HInfArr".
  iDestruct (normal_segment_by_location with "HNextSegLoc HNotTail HInfArr")
    as "[HNormSeg HArrRestore]".
  iDestruct "HNormSeg" as (? ?) "[HIsSeg >#HValidNext]".
  iAaccIntro with "HIsSeg".
  all: iIntros "HIsSeg !>"; iSplitR "Hnlℓ Hplℓ"; first by
    iApply "HArrRestore"; iExists _, _; by iFrame.
  by eauto with iFrame.
  iIntros "AU !>".

  wp_store. wp_load. wp_load.

  iDestruct "HValidNext" as (nid' ?) "(% & -> & #HNewNextSegLoc & #HNewSegCanc)".
  wp_pures.

  iAssert (is_valid_prev γ nid' pl) as "#HNewValidPrev".
  { iDestruct "HValidPrev" as "[[-> HCanc]|HValidPrev]".
    { iLeft; iSplitR; first done. iApply move_cutoff; done. }
    { iDestruct "HValidPrev" as (pid prevℓ) "(% & -> & #HSegLoc & #HPrevCanc)".
      iRight; iExists pid, prevℓ; repeat iSplit; try done. iPureIntro; lia.
      iApply merge_cancelled_segments; try done; lia. }
  }

  awp_apply segment_move_prev_to_left_spec; try done.
  iApply (aacc_aupd_abort with "AU"); first done.
  iIntros "HInfArr". iAaccIntro with "HInfArr"; iIntros "$ !> AU !>".
  by iFrame.

  wp_pures. wp_lam. wp_pures. iApply ("IH" with "[-AU]"); try done. iClear "IH".
  rewrite /RemoveInv.
  iExists _, _. iFrame "Hnlℓ HNewNextSegLoc". iExists _; by iFrame.
Qed.

Theorem remove_segment_spec γ id (ℓ: loc):
  segment_is_cancelled γ id -∗
  segment_location γ id ℓ -∗
  <<< ▷ is_infinite_array γ >>>
    (segment_remove segment_size) #ℓ @ ⊤
  <<< ∃ v, ▷ is_infinite_array γ ∗ (⌜v = NONEV⌝ ∨
                                    ∃ p nℓ nid, segment_location γ nid nℓ ∗
                                                ⌜v = SOMEV (p, #nℓ)⌝ ∗
                                                is_valid_prev γ nid p),
    RET v >>>.
Proof.
  iIntros "#HSegCanc #HSegLoc". iIntros (Φ) "AU". wp_lam.

  awp_apply segment_prev_spec. iApply (aacc_aupd_abort with "AU"); first done.
  iIntros "HInfArr".
  iDestruct (is_segment_by_location with "HSegLoc HInfArr")
    as (? ?) "[HIsSeg HArrRestore]".
  iAaccIntro with "HIsSeg".
  { iIntros "HIsSeg". iSpecialize ("HArrRestore" with "HIsSeg").
    by eauto with iFrame. }
  iIntros (?) "[HIsSeg #HPrevLoc]".
  iDestruct (bi.later_wand with "HArrRestore HIsSeg") as "$".
  iIntros "!> AU !>".

  awp_apply segment_prev_read_spec; first done.
  iApply (aacc_aupd_abort with "AU"); first done.
  iIntros "HInfArr".
  iDestruct (is_segment_by_location with "HSegLoc HInfArr")
    as (? ?) "[HIsSeg HArrRestore]".
  iAaccIntro with "HIsSeg".
  { iIntros "HIsSeg". iDestruct ("HArrRestore" with "HIsSeg") as "$". by eauto. }
  iIntros "[HIsSeg #HValidPrev]".
  iDestruct (bi.later_wand with "HArrRestore HIsSeg") as "$".
  iIntros "!> AU !>".

  wp_alloc plℓ as "Hplℓ". wp_pures.

  awp_apply segment_next_spec. iApply (aacc_aupd_abort with "AU"); first done.
  iIntros "HInfArr".
  iDestruct (is_segment_by_location with "HSegLoc HInfArr")
    as (? ?) "[HIsSeg HArrRestore]".
  iAaccIntro with "HIsSeg".
  { iIntros "HIsSeg". iDestruct ("HArrRestore" with "HIsSeg") as "$".
    by eauto with iFrame. }
  iIntros (?) "[HIsSeg #HNextLoc]".
  iDestruct (bi.later_wand with "HArrRestore HIsSeg") as "$".
  iIntros "!> AU !>".

  awp_apply segment_next_read_spec without "Hplℓ"; first done.
  iApply (aacc_aupd with "AU"); first done.
  iIntros "HInfArr".
  iDestruct (segment_by_location with "HSegLoc HInfArr")
    as "[[HIsNSeg HArrRestore]|[HIsTSeg HArrRestore]]".
  2: {
    iDestruct "HIsTSeg" as (?) "HIsSeg".
    iAaccIntro with "HIsSeg". all: iIntros "HIsSeg !>".
    { iSplitL. 2: by eauto. iApply "HArrRestore". iExists _. iFrame. }
    iRight. iExists _. iSplitL. iSplitL.
    { iApply "HArrRestore". iExists _. iFrame. }
    { iLeft; done. }
    iIntros "HΦ !> Hplℓ". wp_bind (ref _)%E. wp_alloc nlℓ as "Hnlℓ". wp_pures.
    wp_load. wp_pures. done.
  }

  iDestruct "HIsNSeg" as (? ?) "(HIsSeg & #HValidNext)".
  iAaccIntro with "HIsSeg"; iIntros "HIsSeg !>".
  { iSplitL. 2: by eauto. iApply "HArrRestore".
    iExists _, _. iFrame "HIsSeg HValidNext HNotTail". }
  iLeft. iSplitL.
  { iApply "HArrRestore". iExists _, _. iFrame "HIsSeg HValidNext HNotTail". }
  iIntros "AU".
  iIntros "!> Hplℓ".
  wp_alloc nlℓ as "Hnlℓ".

  iAssert (RemoveInv γ nlℓ plℓ) with "[Hplℓ Hnlℓ]" as "RemoveInv".
  { iDestruct "HValidNext"
      as (nid nextℓ) "(% & -> & #HNextSegLoc & HNextSegCanc)".
    iExists nextℓ, nid. iFrame "HNextSegLoc". iFrame.
    iDestruct "HValidPrev" as "[(-> & #HPrevCanc)|HH]".
    { iExists (InjLV #()). iFrame. iLeft. iSplitL; first done.
      iApply move_cutoff; done. }
    {
      iDestruct "HH" as (pid prevℓ) "(% & -> & #HPrevSegLoc & #HPrevSegCanc)".
      iExists _. iFrame. iRight. iExists _, _. iFrame "HPrevSegLoc".
      iSplitR. by iPureIntro; lia. iSplitR; first done.
      iApply merge_cancelled_segments; try done; lia. }
  }
  wp_pures.
  iClear "HSegCanc HSegLoc HPrevLoc HValidPrev HNextLoc HValidNext".
  revert cell_invariant_persistent cell_is_done_persistent; clear; intros ? ?.
  wp_bind (! _)%E. iDestruct "RemoveInv" as (nℓ nid) "(#HSegLoc & Hnlℓ & Hplℓ)".
  wp_load.
  iAssert (RemoveInv γ nlℓ plℓ) with "[Hnlℓ Hplℓ]" as "RemoveInv".
  1: by rewrite /RemoveInv; eauto with iFrame.
  wp_pures. iClear "HSegLoc".
  revert cell_invariant_persistent cell_is_done_persistent; clear; intros ? ?.

  awp_apply (remove_first_loop_spec with "RemoveInv").
  iApply (aacc_aupd_abort with "AU"); first done.
  iIntros "HInfArr". iAaccIntro with "HInfArr".
  iIntros "$"; by eauto with iFrame.
  iIntros "[$ RemoveInv] !> AU !>". wp_pures.

  iDestruct "RemoveInv" as (? ?) "(#HSegLoc & Hnlℓ & Hplℓ)".
  iDestruct "Hplℓ" as (?) "[Hplℓ #HValidPrev]".
  wp_load. wp_load. rewrite /from_some. wp_pures.

  awp_apply (segment_move_prev_to_left_spec); try done.
  iApply (aacc_aupd_abort with "AU"); first done. iIntros "HInfArr".
  iAaccIntro with "HInfArr"; iIntros "$"; first by eauto with iFrame.
  iIntros "!> AU !>". wp_pures.

  iAssert (RemoveInv γ nlℓ plℓ) with "[Hnlℓ Hplℓ]" as "RemoveInv".
  { iExists _, _. iFrame "HSegLoc Hnlℓ". iExists _. by iFrame. }
  iClear "HSegLoc HValidPrev".

  awp_apply (remove_second_loop_spec with "RemoveInv").
  iApply (aacc_aupd_commit with "AU"); first done.
  iIntros "HInfArr". iAaccIntro with "HInfArr".
  iIntros "$"; by eauto with iFrame.
  iIntros "[$ RemoveInv] !>".

  iDestruct "RemoveInv" as (? ?) "(#HSegLoc & Hnlℓ & Hplℓ)".
  iDestruct "Hplℓ" as (p) "[Hplℓ #HValidPrev]".

  iExists _. iSplitR.
  2: iIntros "HΦ !>"; wp_pures; wp_load; wp_pures; wp_load; wp_pures; done.
  iRight. iExists _, _, _. iFrame "HSegLoc HValidPrev". done.
Qed.

Theorem segment_cancel_cell_spec γ id ix s:
  (ix < Pos.to_nat segment_size)%nat ->
  segment_location γ id s -∗
  cell_cancellation_handle' γ id ix -∗
  <<< ▷ is_infinite_array γ >>>
  segment_cancell_cell segment_size #s @ ⊤
  <<< ∃ v, ▷ is_infinite_array γ, RET v >>>.
Proof.
  iIntros (HLt) "#HSegLoc HCancHandle". iIntros (Φ) "AU".
  wp_lam.

  awp_apply segment_canc_spec without "HCancHandle".
  iApply (aacc_aupd_abort with "AU"); first done.
  iIntros "HInfArr".
  iDestruct (is_segment_by_location with "HSegLoc HInfArr")
    as (? ?) "[HIsSeg HInfArrRestore]".
  iAaccIntro with "HIsSeg".
  {
    iIntros "HIsSeg".
    iDestruct ("HInfArrRestore" with "HIsSeg") as "$".
    iIntros "!> $ !> //".
  }
  iIntros (cℓ) "[HIsSeg #HCancLoc] !>".
  iDestruct (bi.later_wand with "HInfArrRestore HIsSeg") as "$".
  iIntros "AU !> HCancHandle".

  awp_apply segment_canc_incr_spec.
  eassumption.
  done.
  iApply (aacc_aupd with "AU"); first done.
  iIntros "HInfArr".

  iAssert (▷ (∃ pl nl ss, own γ (● ss) ∗ is_segment γ id s pl nl ∗
        (∀ pl' ss', ⌜length ss' = length ss⌝ -∗ own γ (● ss') -∗
                          (is_segment γ id s pl' nl) -∗
                          is_infinite_array γ)))%I with "[HInfArr]"
    as (? ? ?) "(>HAuth & HIsSeg & HInfArrRestore)".
  {
    iDestruct "HInfArr" as (segments) "[HNormSegs [HTailSeg HAuth]]".
    iDestruct "HAuth" as (segments') "[>% >HAuth]".
    destruct (le_lt_dec (length segments) id).
    { inversion l; subst.
      2: {
        iDestruct "HSegLoc" as (? ? ? ?) "HSegLoc".
        iDestruct (own_valid_2 with "HAuth HSegLoc")
          as %[HValid _]%auth_both_valid.
        exfalso. revert HValid. rewrite list_lookup_included.
        intro HValid. specialize (HValid (S m)).
        rewrite list_lookup_singletonM in HValid.
        assert (length segments' <= (S m))%nat as HIsNil by lia.
        apply lookup_ge_None in HIsNil. rewrite HIsNil in HValid.
        apply option_included in HValid.
        destruct HValid as [[=]|[a [b [_ [[=] _]]]]].
      }
      iDestruct "HTailSeg" as (ℓ ?) "HIsSeg".
      iExists _, _, _. iFrame "HAuth".
      iSplitL "HIsSeg".
      {
        iDestruct (segment_location_from_segment with "HIsSeg") as "#>HSegLoc'".
        iDestruct (segment_location_agree with "HSegLoc HSegLoc'") as %->.
        iFrame.
      }
      iIntros (pl' ss' HLen) "!> HAuth HIsSeg".
      iExists segments. iFrame "HNormSegs".
      iSplitL "HIsSeg"; first by iExists _, _.
      iExists _. iFrame "HAuth". iPureIntro. lia.
    }
    apply lookup_lt_is_Some_2 in l. destruct l as [ℓ Hℓ].
    iDestruct (big_sepL_lookup_acc with "HNormSegs") as "[HIsSeg HRestSegs]".
    done.
    iDestruct "HIsSeg" as (? ?) "[HIsSeg HValNext]".
    iExists _, _, _. iFrame "HAuth".
    iDestruct (segment_location_from_segment with "HIsSeg") as "#>HSegLoc'".
    iDestruct (segment_location_agree with "HSegLoc HSegLoc'") as %->.
    iFrame "HIsSeg".

    iIntros (pl' ss' HLen) "!> HAuth HIsSeg".
    iExists segments. iFrame "HTailSeg". iSplitR "HAuth".
    by iApply "HRestSegs"; iExists _, _; iFrame.
    iExists _. iFrame. iPureIntro. lia.
  }

  iAssert (_ ∗ _ ∗ _)%I with "[HIsSeg HCancHandle HAuth]" as "HAacc".
  {
    iSplitL "HIsSeg"; first by iApply "HIsSeg".
    iSplitL "HCancHandle"; first by iApply "HCancHandle".
    by iApply "HAuth".
  }

  iAaccIntro with "HAacc".
  {
    iIntros "(HIsSeg & $ & HAuth)".
    iDestruct ("HInfArrRestore" with "[] [HAuth] HIsSeg") as "$"; try done.
    iIntros "!> $ !> //".
  }

  iIntros (v) "(HIsSeg & HCells & HAuth)".
  iDestruct "HCells" as (cells) "[#HCellsCancelled %]".
  iDestruct "HAuth" as (segments' HLengths) "HAuth".
  iDestruct ("HInfArrRestore" with "[%] [HAuth] [HIsSeg]") as "$"; try done.
  iIntros "!>".
  destruct (decide (S v = Pos.to_nat segment_size)) as [HEq|HNe].
  2: {
    iRight. iExists _. iIntros "HΦ !>".
    wp_pures. rewrite bool_decide_decide decide_False.
    2: {
      intros HContra. simplify_eq.
      lia.
    }
    wp_pures.
    done.
  }
  iLeft.
  iIntros "AU !>".

  wp_pures. rewrite bool_decide_decide decide_True.
  2: {
    congr (#(LitInt _)). lia.
  }
  wp_pures.
  replace cells with (Vector.const true (Pos.to_nat segment_size)).
  2: {
    erewrite filter_induces_vector; try done.
    lia.
  }
  awp_apply remove_segment_spec; try iAssumption.
  iApply (aacc_aupd_commit with "AU"); first done.
  iIntros "HInfArr".
  iAaccIntro with "HInfArr".
  by iIntros "$ !> $ !> //".
  iIntros (?) "[$ HCanc]".
  iExists _. iIntros "!> $ !> //".
Qed.

Lemma segment_info_to_cell_info l γ id:
  own γ (◯ {[ id := (ε, l) ]}) ≡
  (([∗ list] i ↦ e ∈ l, own γ (◯ ias_cell_info' id i e)) ∗
  own γ (◯ {[ id := (ε, replicate (length l)%nat ε) ]}))%I.
Proof. by apply segment_info_to_cell_info' with (k := O). Qed.

Lemma algebra_append_new_segment p γ segments:
  own γ (● segments) -∗
      |==> ∃ z, own γ (● (segments ++ [z]))
                            ∗ segment_locations γ (length segments) p
                            ∗ cell_cancellation_parts γ (length segments)
                                (Vector.const false _)
                            ∗ [∗ list] j ∈ seq 0 (Pos.to_nat segment_size),
                                cell_cancellation_handle' γ (length segments) j.
Proof.
  iIntros "HOwn".
  iMod (own_update with "HOwn") as "[HAuth HFrag]".
  {
    apply auth_update_alloc
      with (a' :=
              (segments ++ [(Some (to_agree p),
                 replicate (Pos.to_nat segment_size)
                           (Some (Cinr 1%Qp)))])
           ).
    remember (Some _, replicate _ _) as K.
    eapply transitivity.
    apply list_append_local_update with (z := [K]); subst.
    { intros n.
      apply list_lookup_validN; case; simpl; try done.
      apply Some_validN. split; simpl; try done.
      apply list_lookup_validN; induction (Pos.to_nat segment_size);
        case; done. }
    subst; apply local_update_refl.
  }
  iModIntro. iExists _. iFrame.
  replace (Some _, replicate _ _) with
      ((Some (to_agree p), ε)
         ⋅ (ε, replicate (Pos.to_nat segment_size) (Some (Cinr 1%Qp)))) by done.
  rewrite -[replicate _ _ ++ _]list_singletonM_op auth_frag_op own_op.
  iDestruct "HFrag" as "[HSegLoc HCanc]".
  rewrite /segment_locations. iFrame "HSegLoc".
  replace (1%Qp) with ((1/4)%Qp ⋅ (3/4)%Qp) by apply Qp_quarter_three_quarter.
  rewrite Cinr_op Some_op replicate_op pair_op_2 -list_singletonM_op auth_frag_op own_op.
  iDestruct "HCanc" as "[HCancParts HCancHandles]".
  iSplitL "HCancParts".
  {
    rewrite /cell_cancellation_parts. clear.
    remember (length segments) as M.
    remember (Pos.to_nat segment_size) as N. clear.
    iApply (big_sepL_mono
              (fun k _ => own γ (◯ ias_cell_info' M k (Some (Cinr (1/4)%Qp))))).
    { intros ? ? HEl.
      apply vlookup_lookup' in HEl.
      destruct HEl as [? HEl].
      assert (y = false) as ->.
      by move: HEl; remember (nat_to_fin x) as m; clear; by induction m.
      subst.
      iIntros "HOk". iApply "HOk".
    }
    rewrite big_opL_irrelevant_element'.
    rewrite segment_info_to_cell_info.
    rewrite vec_to_list_length.
    iDestruct "HCancParts" as "[HLst _]".
    rewrite big_opL_replicate_irrelevant_element.
    rewrite big_opL_irrelevant_element'.
    by rewrite replicate_length.
  }
  rewrite segment_info_to_cell_info /cell_cancellation_handle'.
  iDestruct "HCancHandles" as "[HCancHandles _]".
  rewrite big_opL_replicate_irrelevant_element.
  rewrite big_opL_irrelevant_element'.
  by rewrite replicate_length.
Qed.

Lemma alloc_tail (E: coPset) γ ℓ dℓ cℓ pℓ nℓ pl segments:
  cell_init E -∗
  own γ (● segments) -∗
  nℓ ↦ NONEV -∗ pℓ ↦ pl -∗ is_valid_prev γ (length segments) pl -∗
  dℓ ↦∗ replicate (Z.to_nat (Z.pos segment_size)) NONEV -∗
  cℓ ↦ #0 -∗ ℓ ↦ (#(length segments), #cℓ, #dℓ, (#pℓ, #nℓ))
  ={E}=∗
  ∃ z, own γ (● (segments ++ [z])) ∗ segment_location γ (length segments) ℓ ∗
           is_tail_segment γ ℓ (length segments).
Proof.
  iIntros "#HCellInit HAuth Hnℓ Hpℓ #HValidPrev Hdℓ Hcℓ Hℓ".
  iDestruct (algebra_append_new_segment (ℓ, (dℓ, cℓ), (pℓ, nℓ)) with "HAuth")
    as ">HH".
  iDestruct "HH" as (z) "(HAuth & #HSegLocs & HCancParts & HCancHandles)".

  iAssert (segment_location γ (length segments) ℓ) as "#HSegLoc";
    first by eauto 10 with iFrame.

  iCombine "Hdℓ" "HCancHandles" as "HCellInfo".
  rewrite /array big_opL_replicate_irrelevant_element big_opL_irrelevant_element'.
  rewrite replicate_length Z2Nat.inj_pos -big_sepL_sep.
  iAssert ([∗ list] x ∈ seq 0 (Pos.to_nat segment_size),
           |={E}=> cell_invariant γ (length segments * Pos.to_nat segment_size + x) (dℓ +ₗ x))%I
    with "[HCellInfo]" as "HCellInfo".
  {
    iApply (big_sepL_impl with "HCellInfo").
    iModIntro. iIntros (a i HIn) "[Hℓ HCancHandle]".
    iApply ("HCellInit" with "[HCancHandle]").
    2: done.
    rewrite /cell_cancellation_handle.
    rewrite -(ias_cell_info_view_eq (length segments) i); try done.
    2: lia.
    replace (Pos.to_nat segment_size)
      with (length (seq 0 (Pos.to_nat segment_size)))
      by (rewrite seq_length; auto).
    apply lookup_lt_is_Some.
    assert (a < length (seq 0 (Pos.to_nat segment_size)))%nat as HLt.
    { apply lookup_lt_is_Some; by eexists. }
    assert (a = i) as ->.
    { apply nth_lookup_Some with (d := O) in HIn.
      rewrite seq_nth in HIn. done.
      rewrite seq_length in HLt. done. }
    by eexists.
  }
  iDestruct (big_sepL_fupd with "HCellInfo") as ">HCellInfo".

  iExists z. iFrame "HAuth HSegLoc".
  iExists pl. rewrite /is_segment. iExists dℓ, cℓ, pℓ, nℓ, O.
  rewrite /segment_invariant.
  iFrame. iFrame "HValidPrev HSegLocs".
  iSplitL "HCellInfo". by iExists dℓ; iFrame; eauto 10 with iFrame.
  iExists (Vector.const false _). iFrame. iModIntro; iSplit.
  - iPureIntro; induction (Pos.to_nat segment_size); done.
  - rewrite /cells_are_cancelled.
    iApply (big_sepL_mono (fun _ _ => True%I)).
    2: by iApply big_sepL_forall.
    intros ? ? HEl.
    apply vlookup_lookup' in HEl. destruct HEl as [? HEl].
    assert (y = false) as ->; last done.
    move: HEl. remember (nat_to_fin x) as m. clear. by induction m.
Qed.

Theorem initial_segment_spec:
  {{{ cell_init ⊤ }}}
    (new_segment segment_size) #O NONEV
  {{{ γ (ℓ: loc), RET #ℓ; is_infinite_array γ ∗ segment_location γ O ℓ }}}.
Proof.
  iIntros (Φ) "#HCellInit HPost". wp_lam. wp_pures.
  wp_alloc nℓ as "Hnℓ". wp_alloc pℓ as "Hpℓ".
  wp_alloc dℓ as "Hdℓ"; first by lia. wp_alloc cℓ as "Hcℓ". wp_pures.
  rewrite -wp_fupd.
  wp_alloc ℓ as "Hℓ".
  iMod (own_alloc (● [] ⋅ ◯ [])) as (γ) "[HOwn _]".
  { apply auth_both_valid; split; try done. apply list_lookup_valid; by case. }

  iDestruct (alloc_tail with "HCellInit HOwn Hnℓ Hpℓ [] Hdℓ Hcℓ Hℓ") as ">HTail".
  by iLeft; iSplit; done.

  iApply "HPost".

  iDestruct "HTail" as (z) "(HAuth & $ & HTailSeg)".
  rewrite /is_infinite_array.
  iExists []; simpl. iSplitR; first done.
  iSplitL "HTailSeg".
  - by iExists _.
  - iExists _; iFrame. by iPureIntro.
Qed.

Lemma seq_lookup start len n:
  (n < len)%nat ->
  seq start len !! n = Some (start + n)%nat.
Proof.
  intros HLt.
  replace len with (length (seq start len)) in HLt.
  2: by rewrite seq_length.
  destruct (lookup_lt_is_Some_2 _ _ HLt) as [? HOk].
  rewrite HOk.
  apply nth_lookup_Some with (d := O) in HOk.
  rewrite -(@seq_nth len _ _ O); auto.
  by rewrite seq_length in HLt.
Qed.

Lemma seq_lookup' start len n x:
  seq start len !! n = Some x ->
  x = (start + n)%nat /\ (n < len)%nat.
Proof.
  intros HSome.
  assert (is_Some (seq start len !! n)) as HIsSome by eauto.
  move: (lookup_lt_is_Some_1 _ _ HIsSome).
  rewrite seq_length.
  apply nth_lookup_Some with (d := O) in HSome.
  intros.
  rewrite seq_nth in HSome; auto.
Qed.

Lemma try_swap_tail γ id ℓ:
  segment_location γ id ℓ -∗ is_infinite_array γ -∗
  ((is_normal_segment γ ℓ id ∗ (is_normal_segment γ ℓ id -∗ is_infinite_array γ)) ∨
   (is_tail_segment γ ℓ id ∗ ∃ segments', ⌜S id = length segments'⌝ ∗
                                          own γ (● segments') ∗
                    (∀ ℓ' z, is_normal_segment γ ℓ id -∗
                             is_tail_segment γ ℓ' (S id) -∗
                             own γ (● (segments' ++ [z])) -∗
                             is_infinite_array γ))).
Proof.
  iIntros "#HSegLoc HInfArr".
  iDestruct "HInfArr" as (segments) "[HNormSegs [HTailSeg HAuth]]".
  iDestruct "HAuth" as (segments') "[% HAuth]".
  destruct (le_lt_dec (length segments) id).
  { inversion l; subst.
    2: {
      rewrite /segment_location /segment_locations.
      iDestruct "HSegLoc" as (? ? ? ?) "#HSeg".
      iDestruct (own_valid_2 with "HAuth HSeg")
        as %[HValid _]%auth_both_valid.
      exfalso. revert HValid. rewrite list_lookup_included.
      intro HValid. specialize (HValid (S m)).
      rewrite list_lookup_singletonM in HValid.
      assert (length segments' <= S m)%nat as HIsNil by lia.
      apply lookup_ge_None in HIsNil. rewrite HIsNil in HValid.
      apply option_included in HValid.
      destruct HValid as [[=]|[a [b [_ [[=] _]]]]].
    }
    iDestruct "HTailSeg" as (ℓ' pl) "HIsSeg".
    destruct (decide (ℓ = ℓ')); subst.
    2: {
      iDestruct "HIsSeg" as (? ? ? ? ?) "[_ [HLocs _]]".
      iAssert (segment_location γ (length segments) ℓ') as "#HLoc";
        first by eauto 6.
      iDestruct (segment_location_agree with "HSegLoc HLoc") as %->.
      contradiction.
    }
    iRight.
    iSplitL "HIsSeg"; first by rewrite /is_tail_segment; eauto with iFrame.
    iExists segments'. iFrame. iSplitR; first done.
    iIntros (ℓ'' z) "HExTail HNewTail HAuth". rewrite /is_infinite_array.
    iExists (segments ++ [ℓ']). iFrame "HNormSegs". simpl. rewrite -plus_n_O.
    iFrame "HExTail". iSplitR "HAuth"; iExists _;
                        rewrite app_length /= Nat.add_1_r.
    done.
    iFrame. rewrite app_length /= Nat.add_1_r. auto.
  }
  apply lookup_lt_is_Some_2 in l. destruct l as [x Hx].
  iDestruct (big_sepL_lookup_acc with "[HNormSegs]") as "[HIsSeg HRestSegs]".
  2: by iApply "HNormSegs".
  apply Hx.
  simpl.
  iLeft.
  destruct (decide (ℓ = x)); subst.
  2: {
    iDestruct "HIsSeg" as (pl nl) "[HIsSeg #HValNext]".
    iDestruct "HIsSeg" as (? ? ? ? ?) "[_ [HLocs _]]".
    iAssert (segment_location γ id x) as "#HLoc";
      first by eauto 6.
    iDestruct (segment_location_agree with "HSegLoc HLoc") as %->.
    contradiction.
  }
  iFrame.
  iIntros "HNormSeg". rewrite /is_infinite_array.
  iExists segments. iFrame. iSplitR "HAuth".
  { by iApply "HRestSegs". }
  eauto 10 with iFrame.
Qed.

Lemma cell_invariant_by_segment_invariant γ id ix:
  (ix < Pos.to_nat segment_size)%nat ->
  segment_invariant γ id -∗
  ∃ ℓ, cell_invariant γ (id * Pos.to_nat segment_size + ix)%nat ℓ ∗
                      array_mapsto' γ id ix ℓ.
Proof.
  iIntros (HLt) "HSegInv".
  rewrite /segment_invariant /array_mapsto'.
  iDestruct "HSegInv" as (dℓ) "[#HDataLoc #HCellInv]".
  iExists (dℓ +ₗ Z.of_nat ix). iSplit.
  - iApply (big_sepL_lookup with "HCellInv").
    by rewrite seq_lookup.
  - iExists _; iSplit; done.
Qed.

Theorem find_segment_spec Ec γ (ℓ: loc) (id fid: nat):
  cell_init Ec -∗
  segment_location γ id ℓ -∗
  ∀ Φ,
    AU << ▷ is_infinite_array γ >> @ ⊤, Ec
       << ∃ (id': nat) (ℓ': loc), ▷ is_infinite_array γ ∗
          ([∗ list] i ∈ seq 0 (S id'), ▷ segment_invariant γ i) ∗
          segment_location γ id' ℓ' ∗
          ((⌜fid <= id⌝ ∧ ⌜id = id'⌝) ∨
            ⌜id < fid⌝ ∧ ⌜fid <= id'⌝ ∗
            [∗ list] i ∈ seq fid (id' - fid), segment_is_cancelled γ i),
          COMM Φ #ℓ' >> -∗
  WP ((find_segment segment_size) #ℓ) #fid {{ v, Φ v }}.
Proof.
  iIntros "#HCellInit #HHeadLoc". iIntros (Φ) "AU".

  iLöb as "IH" forall (id ℓ) "HHeadLoc". wp_lam. wp_pures.

  awp_apply segment_id_spec. iApply (aacc_aupd with "AU"); first done.
  iIntros "HInfArr".

  iAssert (▷ [∗ list] i ∈ seq 0 (S id), segment_invariant γ i)%I as "#HSegInv".
  {
    rewrite big_opL_commute. iApply big_sepL_forall.
    iIntros (k x HEl).
    apply seq_lookup' in HEl. simpl in *. destruct HEl as [<- HEl].

    iDestruct (segment_exists_from_location with "HHeadLoc") as "HSegExists".
    iDestruct (is_segment_by_location_prev' with "[%] HSegExists HInfArr")
      as (? ?) "[HH _]".
    2: by iDestruct "HH" as (? ? ? ? ? ?) "(_ & _ & $ & _)".
    lia.
  }

  iDestruct (is_segment_by_location with "HHeadLoc HInfArr")
    as (? ?) "[HIsSeg HArrRestore]".
  iAaccIntro with "HIsSeg"; iIntros "HIsSeg".
  { iDestruct ("HArrRestore" with "HIsSeg") as "$". by eauto with iFrame. }

  iDestruct (bi.later_wand with "HArrRestore HIsSeg") as "$".
  destruct (decide (fid <= id)%Z) eqn:E.
  { iRight. iModIntro. iExists _, _. iFrame "HHeadLoc".
    iSplit. iSplit.
    { rewrite big_sepL_later. by iFrame "HSegInv". }
    iLeft; (repeat iSplit; iPureIntro); [lia|done].
    iIntros "HΦ !>". wp_pures. rewrite bool_decide_decide E. by wp_pures. }
  iLeft. iIntros "!> AU !>". wp_pures. rewrite bool_decide_decide E. wp_pures.

  awp_apply segment_next_spec. iApply (aacc_aupd_abort with "AU"); first done.
  iIntros "HInfArr".
  iDestruct (is_segment_by_location with "HHeadLoc HInfArr")
    as (? ?) "[HIsSeg HArrRestore]".
  iAaccIntro with "HIsSeg".
  { iIntros "HIsSeg !>". iDestruct ("HArrRestore" with "HIsSeg") as "$".
    by eauto with iFrame. }
  iIntros (?) "[HIsSeg #HNextLoc] !>".
  iDestruct (bi.later_wand with "HArrRestore HIsSeg") as "$".
  iIntros "AU !>".

  iAssert (□ ∀ v, ▷ is_valid_next γ id v -∗
    AU << ▷ is_infinite_array γ >> @ ⊤, Ec
       << ∃ (id': nat) (ℓ': loc), ▷ is_infinite_array γ ∗
          ([∗ list] i ∈ seq 0 (S id'), ▷ segment_invariant γ i) ∗
          segment_location γ id' ℓ' ∗
          ((⌜fid <= id⌝ ∧ ⌜id = id'⌝) ∨
            ⌜id < fid⌝ ∧ ⌜fid <= id'⌝ ∗
            [∗ list] i ∈ seq fid (id' - fid), segment_is_cancelled γ i),
          COMM Φ #ℓ' >> -∗
      WP ((find_segment segment_size) (from_some v)) #fid {{ v, Φ v }})%I as "#IH'".
  {
    iModIntro.
    iIntros (v) "#HValidNext AU".
    iDestruct "HValidNext" as (nnid ?) "(>% & >-> & >#SegLoc & #HSegCanc)".
    rewrite /from_some. wp_pures.
    iApply ("IH" with "[AU]").
    2: done.
    iAuIntro. iApply (aacc_aupd_commit with "AU"); first done.
    iIntros "HInfArr". iAaccIntro with "HInfArr".
    by iIntros "$ !> $ !>".
    iIntros (? ?) "[$ [#HSegInv' [#HRetSegLoc HH]]] !>". iExists _, _; iSplit.
    2: by eauto. iFrame "HRetSegLoc". iSplitR. done. iRight.
    iSplitR; first by iPureIntro; lia.
    iDestruct "HH" as "[(% & <-)|(% & % & #HCanc')]".
    2: by eauto.
    iSplit; try done.
    iApply big_sepL_forall.
    iIntros (k ? HLt).
    apply seq_lookup' in HLt. inversion HLt; subst.
    eassert (seq (S id) (nnid - S id) !! (fid + k - S id)%nat = Some _).
    by apply seq_lookup; lia.
    iDestruct (big_sepL_lookup with "HSegCanc") as "#HCanc". eassumption.
    replace ((S id + ((fid + k - S id))))%nat with (fid + k)%nat by lia.
    done.
  }

  awp_apply segment_next_read_spec; first done.
  iApply (aacc_aupd_abort with "AU"); first done.
  iIntros "HInfArr".
  iDestruct (segment_by_location with "HHeadLoc HInfArr")
    as "[[HNormSeg HArrRestore]|[HTailSeg HArrRestore]]".
  {
    iDestruct "HNormSeg" as (? ?) "[HIsSeg #HValidNext]".
    iAaccIntro with "HIsSeg"; iIntros "HIsSeg !>".
    { iSplitL.
      - iModIntro. iApply "HArrRestore". iExists _, _.
        iFrame "HIsSeg HValidNext".
      - eauto with iFrame. }
    iSplitL. iApply "HArrRestore"; iExists _, _; by iFrame.
    iIntros "AU !>".
    iDestruct "HValidNext" as (nnid ?) "(>% & >-> & >#SegLoc & #HSegCanc)".
    wp_alloc snextℓ as "Hnextℓ". wp_pures. wp_load.
    wp_pures. wp_load.
    iApply ("IH'" with "[] AU").
    rewrite /is_valid_next.
    iExists nnid, _. iFrame "SegLoc HSegCanc". eauto with iFrame.
  }

  iDestruct "HTailSeg" as (?) "HIsSeg".
  iAaccIntro with "HIsSeg"; iIntros "HIsSeg !>".
  { iSplitL.
    - iModIntro. iApply "HArrRestore". iExists _.
      iFrame "HIsSeg HValidNext".
    - eauto with iFrame. }
  iSplitL. iApply "HArrRestore"; iExists _; by iFrame.
  iIntros "AU !>".

  wp_alloc snextℓ as "Hnextℓ". wp_pures. wp_load. wp_pures.

  awp_apply segment_id_spec. iApply (aacc_aupd_abort with "AU"); first done.
  iIntros "HInfArr".
  iDestruct (is_segment_by_location with "HHeadLoc HInfArr")
    as (? ?) "[HIsSeg HArrRestore]".
  iAaccIntro with "HIsSeg".
  { iIntros "HIsSeg !>". iDestruct ("HArrRestore" with "HIsSeg") as "$".
    by eauto with iFrame. }
  iIntros "HIsSeg !>".
  iDestruct (bi.later_wand with "HArrRestore HIsSeg") as "$".
  iIntros "AU !>".

  rewrite /new_segment. wp_pures.
  wp_alloc nℓ as "Hnℓ". wp_alloc pℓ as "Hpℓ". wp_alloc dℓ as "Hdℓ". lia.
  wp_alloc cℓ as "Hcℓ". wp_alloc tℓ as "Hℓ". wp_pures.

  awp_apply segment_next_spec. iApply (aacc_aupd_abort with "AU"); first done.
  iIntros "HInfArr".
  iDestruct (is_segment_by_location with "HHeadLoc HInfArr")
    as (? ?) "[HIsSeg HArrRestore]".
  iAaccIntro with "HIsSeg".
  { iIntros "HIsSeg !>". iDestruct ("HArrRestore" with "HIsSeg") as "$".
    by eauto with iFrame. }
  iIntros (?) "[HIsSeg #HNextLoc'] !>".
  iDestruct (bi.later_wand with "HArrRestore HIsSeg") as "$".
  iIntros "AU !>".

  iDestruct (segment_next_location_agree with "HNextLoc' HNextLoc") as %->.
  iClear "HNextLoc'".
  wp_bind (CmpXchg _ _ _).

  iMod "AU" as "[HInfArr [HClose _]]".
  iDestruct (try_swap_tail with "HHeadLoc HInfArr")
    as "[[HNormSeg HArrRestore]|[HTailSeg HArrRestore]]".
  {
    iDestruct "HNormSeg" as (? ?) "[HIsSeg #HValidNext]".
    iDestruct "HIsSeg" as (? ? ? nnℓ ?) "(HIsSeg' & >HSegLocs & HIsSegCanc)".
    iAssert (segment_next_location γ id nnℓ) as "#HNextLoc'"; first by eauto 6.
    iDestruct (segment_next_location_agree with "HNextLoc' HNextLoc") as %->.
    iClear "HNextLoc'".
    iDestruct "HIsSeg'" as "(((HMem'' & HMem) & HMem') & HIsSegCells)".

    iDestruct (can_not_be_tail_if_has_next with "HValidNext") as "HNotTail".

    iDestruct "HValidNext" as (? ?) "(>% & >-> & HValidNext')".

    wp_cmpxchg_fail.

    iMod ("HClose" with "[HMem'' HMem HMem' HIsSegCells
                          HSegLocs HIsSegCanc HArrRestore]") as "AU".
    {
      iApply "HArrRestore". rewrite /is_normal_segment. iExists _, _.
      iSplitL.
      rewrite /is_segment /is_segment'; by eauto 20 with iFrame.
      rewrite /is_valid_next; by eauto 20 with iFrame.
    }

    iModIntro. wp_pures.

    awp_apply segment_next_spec. iApply (aacc_aupd_abort with "AU"); first done.
    iIntros "HInfArr".
    iDestruct (is_segment_by_location with "HHeadLoc HInfArr")
      as (? ?) "[HIsSeg HArrRestore]".
    iAaccIntro with "HIsSeg".
    { iIntros "HIsSeg !>". iDestruct ("HArrRestore" with "HIsSeg") as "$".
      by eauto with iFrame. }
    iIntros (?) "[HIsSeg #HNextLoc'] !>".
    iDestruct (bi.later_wand with "HArrRestore HIsSeg") as "$".
    iIntros "AU !>".

    iDestruct (segment_next_location_agree with "HNextLoc' HNextLoc") as %->.
    iClear "HNextLoc'".

    iClear "Hnℓ Hpℓ Hdℓ Hcℓ Hℓ".

    awp_apply segment_next_read_spec without "Hnextℓ"; first done.
    iApply (aacc_aupd_abort with "AU"); first done.
    iIntros "HInfArr".
    iDestruct (normal_segment_by_location with "HHeadLoc HNotTail HInfArr")
      as "[HNormSeg HArrRestore]".
    iDestruct "HNormSeg" as (? ?) "[HIsSeg #HValidNext]".
    iAaccIntro with "HIsSeg"; iIntros "HIsSeg !>".
    { iSplitL.
      - iModIntro. iApply "HArrRestore". iExists _, _.
        iFrame "HIsSeg HValidNext".
      - eauto with iFrame. }
    iSplitL. iApply "HArrRestore"; iExists _, _; by iFrame.
    iIntros "AU !>".

    iIntros "Hnextℓ".
    iDestruct "HValidNext" as (? ?) "(>% & >-> & HValidNext'')".
    wp_store. wp_load. wp_pures.

    iApply ("IH'" with "[] AU").
    rewrite /is_valid_next.
    iExists _, _. iFrame "HValidNext''". eauto with iFrame.
  }

  iDestruct "HTailSeg" as (?) "HIsSeg".
  iDestruct "HIsSeg" as (? ? ? nnℓ ?) "(HIsSeg' & >HSegLocs & HIsSegCanc)".
  iAssert (segment_next_location γ id nnℓ) as "#HNextLoc'"; first by eauto 6.
  iDestruct (segment_next_location_agree with "HNextLoc' HNextLoc") as %->.
  iClear "HNextLoc'".
  iDestruct "HIsSeg'" as "(((HMem'' & HMem) & HMem') & HIsSegCells)".

  wp_cmpxchg_suc.
  iDestruct "HArrRestore" as (segments' HLt) "(HAuth & HArrRestore)".

  replace (#(1%nat + id)) with (#(length segments')).
  2: rewrite -HLt; congr LitV; congr LitInt; lia.

  iDestruct (alloc_tail with "HCellInit HAuth Hnℓ Hpℓ [] Hdℓ Hcℓ Hℓ") as ">HTail".
  {
    iRight.
    iExists _, _. iFrame "HHeadLoc".
    repeat iSplit; try (iPureIntro; try done; lia).
    rewrite HLt -minus_n_n /=. done.
  }

  iDestruct "HTail" as (?) "(HAuth & #HNewTailSegLoc & HIsTail)".

  iAssert (is_valid_next γ id (SOMEV #tℓ)) as "#HValidTrueNext".
  {
    rewrite /is_valid_next. iExists (length segments'), _.
    iSplit; first by iPureIntro; lia.
    iSplit; first by eauto.
    rewrite HLt -minus_n_n /=. by eauto with iFrame.
  }

  iMod ("HClose" with "[HMem HMem' HMem'' HIsSegCells HIsTail HAuth
                        HSegLocs HIsSegCanc HArrRestore]") as "AU".
  {
    rewrite HLt.
    iApply ("HArrRestore" with "[-HIsTail HAuth] HIsTail HAuth").
    iExists _, _. iSplitL. rewrite /is_segment /is_segment'.
    iExists _, _, _, _, _. iFrame "HIsSegCanc HSegLocs". by iFrame.
    done.
  }

  iModIntro. wp_pures.

  awp_apply segment_is_removed_spec without "Hnextℓ".
  iApply (aacc_aupd_abort with "AU"); first done.
  iIntros "HInfArr".
  iDestruct (is_segment_by_location with "HHeadLoc HInfArr")
    as (? ?) "[HIsSeg HArrRestore]".
  iAaccIntro with "HIsSeg".
  { iIntros "HIsSeg !>"; iDestruct ("HArrRestore" with "HIsSeg") as "$".
    by eauto with iFrame. }
  iIntros (is_removed) "(HIsSeg & #HCanc)".
  iDestruct (bi.later_wand with "HArrRestore HIsSeg") as "$".
  iIntros "!> AU !> Hnextℓ".

  iDestruct "HCanc" as "[->|[-> #HSegCanc]]"; wp_pures.

  1: wp_store; wp_load; iApply ("IH'" with "[$] AU").

  awp_apply remove_segment_spec without "Hnextℓ"; try done.
  iApply (aacc_aupd_abort with "AU"); first done.
  iIntros "HInfArr".
  iAaccIntro with "HInfArr".
  iIntros "$"; by eauto.
  iIntros (?) "[$ _] !> AU !> Hnextℓ".
  wp_pures.

  1: wp_store; wp_load; iApply ("IH'" with "[$] AU").

Qed.

Theorem new_infinite_array_spec γ E:
  {{{ cell_init E ∗ own γ (● []) }}}
    new_infinite_array segment_size #()
  {{{ ℓ, RET #ℓ; is_infinite_array γ ∗ segment_location γ 0 ℓ }}}.
Proof.
  iIntros (Φ) "[#HCellInit HAuth] HΦ". wp_lam. wp_pures. rewrite -wp_fupd.
  wp_lam. wp_pures.
  wp_bind ((_, _))%E.
  wp_bind (ref _)%E. wp_alloc nℓ as "Hnℓ".
  wp_bind (ref _)%E. wp_alloc pℓ as "Hpℓ".
  wp_pures.
  wp_bind (AllocN _ _)%E. wp_alloc dℓ as "Hdℓ"; first done.
  wp_bind (ref _)%E. wp_alloc cℓ as "Hcℓ".
  wp_pures.
  wp_alloc ℓ as "Hℓ".

  iMod (alloc_tail with "[] HAuth Hnℓ Hpℓ [] Hdℓ Hcℓ Hℓ")
    as (z) "(HAuth & #HNewTailSegLoc & HIsTail)".
  {
    rewrite /cell_init. iModIntro.
    iIntros (γ' id ℓ') "HCancHandle Hℓ'".
    iDestruct ("HCellInit" with "HCancHandle Hℓ'") as "HCI".

    iApply (fupd_mask_mono with "HCI"); done.
  }
  {
    iLeft. simpl. done.
  }
  simpl.

  iApply "HΦ".
  rewrite /is_infinite_array.
  iSplitL.
  2: done.
  iExists []. simpl.
  iSplitR; first done.
  iSplitR "HAuth".
  2: {
    iExists _. iFrame. done.
  }
  eauto.
Qed.

End proof.
