{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE UndecidableInstances #-}
{-# OPTIONS_GHC -Wno-orphans #-}
{-# OPTIONS_GHC -Wno-unrecognised-pragmas #-}

{-# HLINT ignore "Use record patterns" #-}

module Cardano.Ledger.Pretty.Conway (
  ppConwayTxBody,
) where

import Cardano.Ledger.Conway (ConwayEra)
import Cardano.Ledger.Conway.Core
import Cardano.Ledger.Conway.Governance (
  Anchor,
  Committee (..),
  ConwayGovState (..),
  GovAction (..),
  GovActionId (..),
  GovActionIx (..),
  GovActionState (..),
  GovActionsState (..),
  GovProcedures,
  PrevGovActionId (..),
  ProposalProcedure (..),
  Vote (..),
  Voter (..),
  VotingProcedure (..),
  VotingProcedures (..),
 )
import Cardano.Ledger.Conway.Rules (
  ConwayCertPredFailure (..),
  ConwayCertsPredFailure (..),
  ConwayDelegPredFailure (..),
  ConwayGovCertPredFailure,
  ConwayGovPredFailure,
  ConwayLedgerPredFailure (..),
  EnactState (..),
  PredicateFailure,
  RatifyState (..),
 )
import Cardano.Ledger.Conway.TxBody (ConwayTxBody (..))
import Cardano.Ledger.Conway.TxCert (
  ConwayDelegCert (..),
  ConwayGovCert (..),
  ConwayTxCert (..),
  Delegatee (..),
 )
import Cardano.Ledger.Crypto
import Cardano.Ledger.Pretty (
  PDoc,
  PrettyA (..),
  ppAuxiliaryDataHash,
  ppCoin,
  ppKeyHash,
  ppNetwork,
  ppPoolCert,
  ppRecord,
  ppSafeHash,
  ppSet,
  ppSexp,
  ppStrictMaybe,
  ppStrictSeq,
  ppString,
  ppTxIn,
  ppWithdrawals,
 )
import Cardano.Ledger.Pretty.Babbage (ppBabbagePParams, ppBabbagePParamsUpdate)
import Cardano.Ledger.Pretty.Mary (ppMultiAsset, ppValidityInterval)
import Lens.Micro ((^.))
import Prettyprinter (viaShow)

instance
  ( ConwayEraTxBody era
  , PrettyA (TxOut era)
  , TxBody era ~ ConwayTxBody era
  ) =>
  PrettyA (ConwayTxBody era)
  where
  prettyA = ppConwayTxBody

instance PrettyA (Delegatee era) where
  prettyA (DelegStake skh) =
    ppRecord
      "DelegStake"
      [ ("Staking Key Hash", prettyA skh)
      ]
  prettyA (DelegVote vc) =
    ppRecord
      "DelegVote"
      [ ("Voting Credential", prettyA vc)
      ]
  prettyA (DelegStakeVote skh vc) =
    ppRecord
      "DelegStakeVote"
      [ ("Staking Key Hash", prettyA skh)
      , ("Voting Credential", prettyA vc)
      ]

instance PrettyA (ConwayDelegCert c) where
  prettyA (ConwayRegCert c deposit) =
    ppRecord
      "ConwayRegCert"
      [ ("StakeCredential", prettyA c)
      , ("Deposit", prettyA deposit)
      ]
  prettyA (ConwayUnRegCert c deposit) =
    ppRecord
      "ConwayUnRegCert"
      [ ("StakeCredential", prettyA c)
      , ("Deposit", prettyA deposit)
      ]
  prettyA (ConwayDelegCert stakeCredential delegatee) =
    ppRecord
      "ConwayDeleg"
      [ ("Stake Credential", prettyA stakeCredential)
      , ("Delegatee", prettyA delegatee)
      ]
  prettyA (ConwayRegDelegCert stakeCredential delegatee deposit) =
    ppRecord
      "ConwayRegDeleg"
      [ ("Stake Credential", prettyA stakeCredential)
      , ("Delegatee", prettyA delegatee)
      , ("Deposit", prettyA deposit)
      ]

ppConwayTxCert :: ConwayTxCert era -> PDoc
ppConwayTxCert = \case
  ConwayTxCertDeleg dc -> ppSexp "ConwayTxCertDeleg" [prettyA dc]
  ConwayTxCertPool pc -> ppSexp "ConwayTxCertPool" [ppPoolCert pc]
  ConwayTxCertGov gdc -> ppSexp "ConwayTxCertGov" [ppConwayGovCert gdc]

ppConwayGovCert :: ConwayGovCert c -> PDoc
ppConwayGovCert = \case
  ConwayRegDRep cred deposit mAnchor ->
    ppSexp "ConwayRegDRep" [prettyA cred, prettyA deposit, prettyA mAnchor]
  ConwayUnRegDRep cred deposit ->
    ppSexp "ConwayUnRegDRep" [prettyA cred, prettyA deposit]
  ConwayUpdateDRep cred mAnchor ->
    ppSexp "ConwayUpdateDRep" [prettyA cred, prettyA mAnchor]
  ConwayAuthCommitteeHotKey coldKey hotKey ->
    ppSexp "ConwayAuthCommitteeHotKey" [prettyA coldKey, prettyA hotKey]
  ConwayResignCommitteeColdKey coldKey ->
    ppSexp "ConwayResignCommitteeColdKey" [prettyA coldKey]

ppConwayTxBody ::
  forall era.
  ( ConwayEraTxBody era
  , PrettyA (TxOut era)
  , TxBody era ~ ConwayTxBody era
  ) =>
  ConwayTxBody era ->
  PDoc
ppConwayTxBody txb =
  ppRecord
    "TxBody (Conway)"
    [ ("spending inputs", ppSet ppTxIn $ txb ^. inputsTxBodyL)
    , ("collateral inputs", ppSet ppTxIn $ txb ^. collateralInputsTxBodyL)
    , ("reference inputs", ppSet ppTxIn $ txb ^. referenceInputsTxBodyL)
    , ("outputs", ppStrictSeq prettyA (txb ^. outputsTxBodyL))
    , ("collateral return", ppStrictMaybe prettyA (txb ^. collateralReturnTxBodyL))
    , ("total collateral", ppStrictMaybe ppCoin $ txb ^. totalCollateralTxBodyL)
    , ("withdrawals", ppWithdrawals $ txb ^. withdrawalsTxBodyL)
    , ("transaction fee", ppCoin $ txb ^. feeTxBodyL)
    , ("validity interval", ppValidityInterval $ txb ^. vldtTxBodyL)
    , ("required signer hashes", ppSet ppKeyHash $ txb ^. reqSignerHashesTxBodyL)
    , ("mint", ppMultiAsset $ txb ^. mintTxBodyL)
    , ("script integrity hash", ppStrictMaybe ppSafeHash $ txb ^. scriptIntegrityHashTxBodyL)
    , ("auxiliary data hash", ppStrictMaybe ppAuxiliaryDataHash $ txb ^. auxDataHashTxBodyL)
    , ("network id", ppStrictMaybe ppNetwork $ txb ^. networkIdTxBodyL)
    , ("voting procedures", prettyA $ unVotingProcedures (txb ^. votingProceduresTxBodyL))
    , ("proposal procedures", ppStrictSeq prettyA $ txb ^. proposalProceduresTxBodyL)
    ]

instance PrettyA Vote where
  prettyA = viaShow

instance EraPParams era => PrettyA (VotingProcedure era) where
  prettyA = viaShow

instance EraPParams era => PrettyA (ProposalProcedure era) where
  prettyA = viaShow

instance EraPParams era => PrettyA (GovProcedures era) where
  prettyA = viaShow

instance PrettyA (PrevGovActionId p c) where
  prettyA = viaShow

instance PrettyA (PParamsUpdate era) => PrettyA (GovAction era) where
  prettyA (ParameterChange pgaid ppup) =
    ppRecord
      "ParameterChange"
      [ ("previous governance action id", prettyA pgaid)
      , ("protocol parameters update", prettyA ppup)
      ]
  prettyA (HardForkInitiation pgaid pv) =
    ppRecord
      "HardForkInitiation"
      [ ("previous governance action id", prettyA pgaid)
      , ("protocol version", prettyA pv)
      ]
  prettyA (TreasuryWithdrawals ws) =
    ppRecord
      "TreasuryWithdrawals"
      [("withdrawals map", prettyA ws)]
  prettyA (NoConfidence pgaid) =
    ppRecord "NoConfidence" [("previous governance action id", prettyA pgaid)]
  prettyA (NewCommittee pgaid old committee) =
    ppRecord
      "NewCommittee"
      [ ("previous governance action id", prettyA pgaid)
      , ("oldMembers", prettyA old)
      , ("committee", prettyA committee)
      ]
  prettyA (NewConstitution pgaid Constitution {..}) =
    ppRecord
      "NewConstitution"
      [ ("previous governance action id", prettyA pgaid)
      , ("anchor", prettyA constitutionAnchor)
      , ("script", prettyA constitutionScript)
      ]
  prettyA InfoAction =
    ppRecord "InfoAction" []

instance PrettyA (Committee era) where
  prettyA Committee {..} =
    ppRecord
      "Committee"
      [ ("members", prettyA committeeMembers)
      , ("quorum", prettyA committeeQuorum)
      ]

instance forall c. PrettyA (ConwayTxCert c) where
  prettyA = ppConwayTxCert

instance Crypto c => PrettyA (PParams (ConwayEra c)) where
  prettyA = ppBabbagePParams

instance Crypto c => PrettyA (PParamsUpdate (ConwayEra c)) where
  prettyA = ppBabbagePParamsUpdate

instance
  ( PrettyA (PredicateFailure (EraRule "UTXOW" era))
  , PrettyA (PredicateFailure (EraRule "CERTS" era))
  , PrettyA (PredicateFailure (EraRule "GOV" era))
  ) =>
  PrettyA (ConwayLedgerPredFailure era)
  where
  prettyA (ConwayUtxowFailure x) = prettyA x
  prettyA (ConwayCertsFailure x) = prettyA x
  prettyA (ConwayGovFailure x) = prettyA x
  prettyA (ConwayWdrlNotDelegatedToDRep x) =
    ppSexp "ConwayWdrlNotDelegatedToDRep" [prettyA x]

instance EraPParams era => PrettyA (ConwayGovPredFailure era) where
  prettyA = viaShow

instance PrettyA (PParamsUpdate era) => PrettyA (GovActionsState era) where
  prettyA x@(GovActionsState _ _ _ _) =
    let GovActionsState {..} = x
     in ppRecord
          "GovActionsState"
          [ ("curGovActionsState", prettyA curGovActionsState)
          , ("prevGovActionsState", prettyA prevGovActionsState)
          , ("prevDRepsState", prettyA prevDRepsState)
          , ("prevCommitteeState", prettyA prevCommitteeState)
          ]

instance PrettyA (GovActionId era) where
  prettyA gaid@(GovActionId _ _) =
    let GovActionId {..} = gaid
     in ppRecord
          "GovActionId"
          [ ("Transaction ID", prettyA gaidTxId)
          , ("Gov Action Index", prettyA gaidGovActionIx)
          ]

instance PrettyA GovActionIx where
  prettyA (GovActionIx x) = prettyA x

instance PrettyA (Voter c) where
  prettyA = ppString . show

instance PrettyA (Anchor era) where
  prettyA = viaShow

instance PrettyA (PParamsUpdate era) => PrettyA (GovActionState era) where
  prettyA gas@(GovActionState _ _ _ _ _ _ _ _ _) =
    let GovActionState {..} = gas
     in ppRecord
          "GovActionState"
          [ ("Id", prettyA gasId)
          , ("CommitteVotes", prettyA gasCommitteeVotes)
          , ("DRepVotes", prettyA gasDRepVotes)
          , ("StakePoolVotes", prettyA gasStakePoolVotes)
          , ("Deposit", prettyA gasDeposit)
          , ("Return Address", prettyA gasReturnAddr)
          , ("Action", prettyA gasAction)
          , ("Proposed In", prettyA gasProposedIn)
          , ("Expires After", prettyA gasExpiresAfter)
          ]

instance PrettyA (Constitution era) where
  prettyA Constitution {..} =
    ppRecord
      "Constitution"
      [ ("anchor", prettyA constitutionAnchor)
      , ("script", prettyA constitutionScript)
      ]

instance PrettyA (PParams era) => PrettyA (EnactState era) where
  prettyA ens@(EnactState _ _ _ _ _ _ _) =
    let EnactState {..} = ens
     in ppRecord
          "EnactState"
          [ ("Constitutional Committee", prettyA ensCommittee)
          , ("PParams", prettyA ensPParams)
          , ("PrevPParams", prettyA ensPrevPParams)
          , ("ProtVer", prettyA ensProtVer)
          , ("Constitution", prettyA ensConstitution)
          , ("Treasury", prettyA ensTreasury)
          , ("Withdrawals", prettyA ensWithdrawals)
          ]

instance
  ( PrettyA (PParamsUpdate era)
  , PrettyA (PParams era)
  ) =>
  PrettyA (RatifyState era)
  where
  prettyA rs@(RatifyState _ _) =
    let RatifyState {..} = rs
     in ppRecord
          "RatifyState"
          [ ("EnactState", prettyA rsEnactState)
          , ("Removed", prettyA rsRemoved)
          ]

instance
  ( PrettyA (PParamsUpdate era)
  , PrettyA (PParams era)
  ) =>
  PrettyA (ConwayGovState era)
  where
  prettyA cg@(ConwayGovState _ _) =
    let ConwayGovState {..} = cg
     in ppRecord
          "ConwayGovState"
          [ ("GovActionsState", prettyA cgGovActionsState)
          , ("EnactState", prettyA cgEnactState)
          ]

instance
  PrettyA (PredicateFailure (EraRule "CERT" era)) =>
  PrettyA (ConwayCertsPredFailure era)
  where
  prettyA (DelegateeNotRegisteredDELEG x) =
    ppRecord
      "DelegateeNotRegisteredDELEG"
      [("KeyHash", prettyA x)]
  prettyA (WithdrawalsNotInRewardsCERTS x) =
    ppRecord
      "WithdrawalsNotInRewardsDELEGS"
      [("Missing Withdrawals", prettyA x)]
  prettyA (CertFailure x) = prettyA x

instance
  ( PrettyA (PredicateFailure (EraRule "DELEG" era))
  , PrettyA (PredicateFailure (EraRule "POOL" era))
  , PrettyA (PredicateFailure (EraRule "GOVCERT" era))
  ) =>
  PrettyA (ConwayCertPredFailure era)
  where
  prettyA = \case
    DelegFailure x ->
      ppRecord
        "ConwayDelegFailure"
        [("DELEG", prettyA x)]
    PoolFailure x ->
      ppRecord
        "ConwayPoolFailure"
        [("POOL", prettyA x)]
    GovCertFailure x ->
      ppRecord
        "ConwayGovCertFailure"
        [("GOVCERT", prettyA x)]

instance PrettyA (ConwayDelegPredFailure era) where
  prettyA = \case
    IncorrectDepositDELEG x ->
      ppRecord
        "IncorrectDepositDELEG"
        [("Coin", prettyA x)]
    StakeKeyRegisteredDELEG x ->
      ppRecord
        "StakeKeyRegisteredDELEG"
        [("Credential", prettyA x)]
    StakeKeyNotRegisteredDELEG x ->
      ppRecord
        "StakeKeyNotRegisteredDELEG"
        [("Credential", prettyA x)]
    StakeKeyHasNonZeroRewardAccountBalanceDELEG x ->
      ppRecord
        "StakeKeyHasNonZeroRewardAccountBalanceDELEG"
        [("Coin", prettyA x)]
    DRepAlreadyRegisteredForStakeKeyDELEG x ->
      ppRecord
        "DRepAlreadyRegisteredForStakeKeyDELEG"
        [("Credential", prettyA x)]
    WrongCertificateTypeDELEG ->
      ppRecord
        "WrongCertificateTypeDELEG"
        []

instance PrettyA (ConwayGovCertPredFailure era) where
  prettyA = const $ ppRecord "ConwayGovCertPredFailure" []
