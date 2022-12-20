{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TupleSections #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE UndecidableInstances #-}
{-# OPTIONS_GHC -Wno-orphans #-}

module Test.Cardano.Ledger.Alonzo.Serialisation.Generators where

import Cardano.Ledger.Allegra.Scripts (ValidityInterval (..))
import Cardano.Ledger.Alonzo (AlonzoEra)
import Cardano.Ledger.Alonzo.Core
import Cardano.Ledger.Alonzo.Scripts (
  AlonzoScript (..),
 )
import Cardano.Ledger.Alonzo.Scripts.Data (
  BinaryData,
  Data (..),
 )
import Cardano.Ledger.Alonzo.Tx (
  AlonzoTxBody (..),
 )
import Cardano.Ledger.Alonzo.TxAuxData (
  AuxiliaryDataHash,
 )
import Cardano.Ledger.Alonzo.TxBody (AlonzoTxOut (..))
import Cardano.Ledger.BaseTypes
import Cardano.Ledger.Binary (EncCBOR (..))
import Cardano.Ledger.Coin (Coin)
import Cardano.Ledger.Crypto
import Cardano.Ledger.Keys (KeyHash)
import Cardano.Ledger.Mary.Value (MultiAsset)
import Cardano.Ledger.Shelley.PParams (Update)
import Cardano.Ledger.Shelley.TxBody (DCert)
import Cardano.Ledger.TxIn (TxIn)
import Cardano.Ledger.Val (Val)
import Codec.CBOR.Term (Term (..))
import Data.Maybe (catMaybes)
import Data.Typeable (Typeable)
import Test.Cardano.Ledger.Alonzo.Arbitrary ()
import Test.Cardano.Ledger.Binary.Twiddle
import Test.Cardano.Ledger.Shelley.Serialisation.EraIndepGenerators ()
import Test.Cardano.Ledger.Shelley.Serialisation.Generators ()
import Test.QuickCheck


instance Era era => Arbitrary (Data era) where
  arbitrary = Data <$> arbitrary

instance Era era => Arbitrary (BinaryData era) where
  arbitrary = dataToBinaryData <$> arbitrary

instance Arbitrary PV1.Data where
  arbitrary = resize 5 (sized gendata)
    where
      gendata n
        | n > 0 =
            oneof
              [ PV1.I <$> arbitrary
              , PV1.B <$> arbitrary
              , PV1.Map <$> listOf ((,) <$> gendata (n `div` 2) <*> gendata (n `div` 2))
              , PV1.Constr
                  <$> fmap fromIntegral (arbitrary :: Gen Natural)
                  <*> listOf (gendata (n `div` 2))
              , PV1.List <$> listOf (gendata (n `div` 2))
              ]
      gendata _ = oneof [PV1.I <$> arbitrary, PV1.B <$> arbitrary]

instance
  ( Script era ~ AlonzoScript era
  , Arbitrary (Script era)
  , Era era
  ) =>
  Arbitrary (AlonzoTxAuxData era)
  where
  arbitrary = mkAlonzoTxAuxData @[] <$> arbitrary <*> arbitrary

instance Arbitrary Tag where
  arbitrary = elements [Spend, Mint, Cert, Rewrd]

instance Arbitrary RdmrPtr where
  arbitrary = RdmrPtr <$> arbitrary <*> arbitrary

instance Arbitrary ExUnits where
  arbitrary = ExUnits <$> genUnit <*> genUnit
    where
      genUnit = fromIntegral <$> choose (0, maxBound :: Int64)

instance (Era era) => Arbitrary (Redeemers era) where
  arbitrary = Redeemers <$> arbitrary

instance
  ( Arbitrary (Script era)
  , AlonzoScript era ~ Script era
  , EraScript era
  ) =>
  Arbitrary (AlonzoTxWits era)
  where
  arbitrary =
    AlonzoTxWits
      <$> arbitrary
      <*> arbitrary
      <*> genScripts
      <*> genData
      <*> arbitrary

keyBy :: Ord k => (a -> k) -> [a] -> Map k a
keyBy f xs = Map.fromList ((\x -> (f x, x)) <$> xs)

genScripts ::
  forall era.
  ( Script era ~ AlonzoScript era
  , EraScript era
  , Arbitrary (AlonzoScript era)
  ) =>
  Gen (Map (ScriptHash (EraCrypto era)) (Script era))
genScripts = keyBy (hashScript @era) <$> (arbitrary :: Gen [Script era])

genData :: forall era. Era era => Gen (TxDats era)
genData = TxDats . keyBy hashData <$> arbitrary

instance
  ( EraTxOut era
  , Arbitrary (Value era)
  ) =>
  Arbitrary (AlonzoTxOut era)
  where
  arbitrary =
    AlonzoTxOut
      <$> arbitrary
      <*> scale (`div` 15) arbitrary
      <*> arbitrary

instance
  (EraTxOut era, Arbitrary (TxOut era)) =>
  Arbitrary (AlonzoTxBody era)
  where
  arbitrary =
    AlonzoTxBody
      <$> arbitrary
      <*> arbitrary
      <*> arbitrary
      <*> arbitrary
      <*> arbitrary
      <*> arbitrary
      <*> arbitrary
      <*> scale (`div` 15) arbitrary
      <*> arbitrary
      <*> scale (`div` 15) (genMintValues @(EraCrypto era))
      <*> arbitrary
      <*> arbitrary
      <*> arbitrary

deriving newtype instance Arbitrary IsValid

instance
  ( Arbitrary (TxBody era)
  , Arbitrary (TxWits era)
  , Arbitrary (TxAuxData era)
  ) =>
  Arbitrary (AlonzoTx era)
  where
  arbitrary =
    AlonzoTx
      <$> arbitrary
      <*> arbitrary
      <*> arbitrary
      <*> arbitrary

instance Era era => Arbitrary (AlonzoScript era) where
  arbitrary = do
    lang <- arbitrary -- The language is not present in the Script serialization
    frequency
      [ (1, pure (alwaysSucceeds lang 1))
      , (1, pure (alwaysFails lang 1))
      , (10, TimelockScript <$> arbitrary)
      ]

-- ==========================
--

instance Arbitrary Language where
  arbitrary = elements nonNativeLanguages

instance Arbitrary Prices where
  arbitrary = Prices <$> arbitrary <*> arbitrary

genValidCostModel :: Language -> Gen CostModel
genValidCostModel lang = do
  newParamValues <- (vectorOf (costModelParamsCount lang) (arbitrary :: Gen Integer))
  pure $ fromRight (error "Corrupt cost model") (mkCostModel lang newParamValues)

genValidCostModelPair :: Language -> Gen (Language, CostModel)
genValidCostModelPair lang = (,) lang <$> genValidCostModel lang

-- | This Arbitrary instance assumes the inflexible deserialization
-- scheme prior to version 9.
instance Arbitrary CostModels where
  arbitrary = do
    langs <- sublistOf nonNativeLanguages
    cms <- mapM genValidCostModelPair langs
    pure $ CostModels (Map.fromList cms) mempty mempty

listAtLeast :: Int -> Gen [Integer]
listAtLeast x = do
  y <- getNonNegative <$> arbitrary
  replicateM (x + y) arbitrary

genCostModelValues :: Language -> Gen (Word8, [Integer])
genCostModelValues lang =
  (lang',)
    <$> oneof
      [ listAtLeast (costModelParamsCount lang) -- Valid Cost Model for known language
      , take tooFew <$> arbitrary -- Invalid Cost Model for known language
      ]
  where
    lang' = fromIntegral (fromEnum lang)
    tooFew = costModelParamsCount lang - 1

genUnknownCostModelValues :: Gen (Word8, [Integer])
genUnknownCostModelValues = do
  lang <- chooseInt (firstInvalid, fromIntegral (maxBound :: Word8))
  vs <- arbitrary
  return (fromIntegral . fromEnum $ lang, vs)
  where
    firstInvalid = fromEnum (maxBound :: Language) + 1

genUnknownCostModels :: Gen (Map Word8 [Integer])
genUnknownCostModels = Map.fromList <$> listOf genUnknownCostModelValues

genKnownCostModels :: Gen (Map Word8 [Integer])
genKnownCostModels = do
  langs <- sublistOf nonNativeLanguages
  cms <- mapM genCostModelValues langs
  return $ Map.fromList cms

-- | This Arbitrary instance assumes the flexible deserialization
-- scheme of 'CostModels' starting at version 9.
newtype FlexibleCostModels = FlexibleCostModels CostModels
  deriving (Show, Eq, Ord)
  deriving newtype (EncCBOR, DecCBOR)

instance Arbitrary FlexibleCostModels where
  arbitrary = do
    known <- genKnownCostModels
    unknown <- genUnknownCostModels
    let cms = known `Map.union` unknown
    pure . FlexibleCostModels $ mkCostModelsLenient cms

instance Arbitrary (AlonzoPParams Identity era) where
  arbitrary =
    AlonzoPParams
      <$> arbitrary
      <*> arbitrary
      <*> arbitrary
      <*> arbitrary
      <*> arbitrary
      <*> arbitrary
      <*> arbitrary
      <*> arbitrary
      <*> arbitrary
      <*> arbitrary
      <*> arbitrary
      <*> arbitrary
      <*> arbitrary
      <*> arbitrary
      <*> arbitrary
      <*> arbitrary
      <*> arbitrary
      <*> arbitrary
      <*> arbitrary
      <*> arbitrary
      <*> arbitrary
      <*> arbitrary
      <*> arbitrary
      <*> arbitrary

deriving instance Arbitrary OrdExUnits

instance Arbitrary (AlonzoPParams StrictMaybe era) where
  arbitrary =
    AlonzoPParams
      <$> arbitrary
      <*> arbitrary
      <*> arbitrary
      <*> arbitrary
      <*> arbitrary
      <*> arbitrary
      <*> arbitrary
      <*> arbitrary
      <*> arbitrary
      <*> arbitrary
      <*> arbitrary
      <*> arbitrary
      <*> arbitrary
      <*> arbitrary
      <*> arbitrary
      <*> arbitrary
      <*> arbitrary
      <*> arbitrary
      <*> arbitrary
      <*> arbitrary
      <*> arbitrary
      <*> arbitrary
      <*> arbitrary
      <*> arbitrary

instance Arbitrary FailureDescription where
  arbitrary = PlutusFailure <$> (pack <$> arbitrary) <*> arbitrary

instance Arbitrary TagMismatchDescription where
  arbitrary =
    oneof [pure PassedUnexpectedly, FailedUnexpectedly <$> ((:|) <$> arbitrary <*> arbitrary)]

instance
  (Era era, Arbitrary (PredicateFailure (EraRule "PPUP" era))) =>
  Arbitrary (AlonzoUtxosPredFailure era)
  where
  arbitrary =
    oneof
      [ ValidationTagMismatch <$> arbitrary <*> arbitrary
      , UpdateFailure <$> arbitrary
      ]

instance
  ( EraTxOut era
  , Arbitrary (Value era)
  , Arbitrary (TxOut era)
  , Arbitrary (PredicateFailure (EraRule "UTXOS" era))
  ) =>
  Arbitrary (AlonzoUtxoPredFailure era)
  where
  arbitrary =
    oneof
      [ BadInputsUTxO <$> arbitrary
      , OutsideValidityIntervalUTxO <$> arbitrary <*> arbitrary
      , MaxTxSizeUTxO <$> arbitrary <*> arbitrary
      , pure InputSetEmptyUTxO
      , FeeTooSmallUTxO <$> arbitrary <*> arbitrary
      , ValueNotConservedUTxO <$> arbitrary <*> arbitrary
      , OutputTooSmallUTxO <$> arbitrary
      , UtxosFailure <$> arbitrary
      , WrongNetwork <$> arbitrary <*> arbitrary
      , WrongNetworkWithdrawal <$> arbitrary <*> arbitrary
      , OutputBootAddrAttrsTooBig <$> arbitrary
      , pure TriesToForgeADA
      , OutputTooBigUTxO <$> arbitrary
      , InsufficientCollateral <$> arbitrary <*> arbitrary
      , ScriptsNotPaidUTxO <$> arbitrary
      , ExUnitsTooBigUTxO <$> arbitrary <*> arbitrary
      , CollateralContainsNonADA <$> arbitrary
      ]

instance
  ( Era era
  , Arbitrary (PredicateFailure (EraRule "UTXO" era))
  ) =>
  Arbitrary (AlonzoUtxowPredFailure era)
  where
  arbitrary =
    oneof
      [ ShelleyInAlonzoUtxowPredFailure <$> arbitrary
      , MissingRedeemers <$> arbitrary
      , MissingRequiredDatums <$> arbitrary <*> arbitrary
      , PPViewHashesDontMatch <$> arbitrary <*> arbitrary
      ]

instance Crypto c => Arbitrary (ScriptPurpose c) where
  arbitrary =
    oneof
      [ Minting <$> arbitrary
      , Spending <$> arbitrary
      , Rewarding <$> arbitrary
      , Certifying <$> arbitrary
      ]

instance
  ( AlonzoEraPParams era
  , Arbitrary (PParams era)
  ) =>
  Arbitrary (ScriptIntegrity era)
  where
  arbitrary =
    ScriptIntegrity
      <$> arbitrary
      <*> genData
      -- FIXME: why singleton? We should generate empty as well as many value sets
      <*> (Set.singleton <$> (getLanguageView @era <$> arbitrary <*> arbitrary))

instance
  Era era =>
  Arbitrary (Datum era)
  where
  arbitrary =
    oneof
      [ pure NoDatum
      , DatumHash <$> arbitrary
      , Datum . dataToBinaryData <$> arbitrary
      ]

deriving instance Arbitrary CoinPerWord

instance Arbitrary AlonzoGenesis where
  arbitrary =
    AlonzoGenesis
      <$> arbitrary
      <*> arbitrary
      <*> arbitrary
      <*> arbitrary
      <*> arbitrary
      <*> arbitrary
      <*> arbitrary
      <*> arbitrary

instance (Era era, Val (Value era)) => Twiddle (AlonzoTxOut era) where
  twiddle v = twiddle v . toTerm v

instance Twiddle SlotNo where
  twiddle v = twiddle v . toTerm v

instance Crypto c => Twiddle (DCert c) where
  twiddle v = twiddle v . toTerm v

instance Crypto c => Twiddle (Withdrawals c) where
  twiddle v = twiddle v . toTerm v

instance Crypto c => Twiddle (AuxiliaryDataHash c) where
  twiddle v = twiddle v . toTerm v

instance Crypto c => Twiddle (Update (AlonzoEra c)) where
  twiddle v = twiddle v . toTerm v

instance Crypto c => Twiddle (MultiAsset c) where
  twiddle v = twiddle v . encodingToTerm v . encCBOR

instance Crypto c => Twiddle (ScriptIntegrityHash c) where
  twiddle v = twiddle v . toTerm v

instance (Crypto c, Typeable t) => Twiddle (KeyHash t c) where
  twiddle v = twiddle v . toTerm v

instance Twiddle Network where
  twiddle v = twiddle v . toTerm v

instance Crypto c => Twiddle (TxIn c) where
  twiddle v = twiddle v . toTerm v

instance Twiddle Coin where
  twiddle v = twiddle v . toTerm v

instance Crypto c => Twiddle (AlonzoTxBody (AlonzoEra c)) where
  twiddle v txBody = do
    inputs' <- twiddle v $ atbInputs txBody
    outputs' <- twiddle v $ atbOutputs txBody
    fee' <- twiddle v $ atbTxFee txBody
    -- Empty collateral can be represented by empty set or the
    -- value can be omitted entirely
    ttl' <- twiddleStrictMaybe v . invalidHereafter $ atbValidityInterval txBody
    cert' <- emptyOrNothing v $ atbCerts txBody
    withdrawals' <- twiddle v $ atbWithdrawals txBody
    update' <- twiddleStrictMaybe v $ atbUpdate txBody
    auxDataHash' <- twiddleStrictMaybe v $ atbAuxDataHash txBody
    validityStart' <- twiddleStrictMaybe v . invalidBefore $ atbValidityInterval txBody
    mint' <- twiddle v $ atbMint txBody
    scriptDataHash' <- twiddleStrictMaybe v $ atbScriptIntegrityHash txBody
    collateral' <- emptyOrNothing v $ atbCollateral txBody
    requiredSigners' <- emptyOrNothing v $ atbReqSignerHashes txBody
    networkId' <- twiddleStrictMaybe v $ atbTxNetworkId txBody
    mp <- elements [TMap, TMapI]
    let fields =
          [ (TInt 0, inputs')
          , (TInt 1, outputs')
          , (TInt 2, fee')
          ]
            <> catMaybes
              [ (TInt 3,) <$> ttl'
              , (TInt 4,) <$> cert'
              , (TInt 5,) <$> Just withdrawals'
              , (TInt 6,) <$> update'
              , (TInt 7,) <$> auxDataHash'
              , (TInt 8,) <$> validityStart'
              , (TInt 9,) <$> Just mint'
              , (TInt 11,) <$> scriptDataHash'
              , (TInt 13,) <$> collateral'
              , (TInt 14,) <$> requiredSigners'
              , (TInt 15,) <$> networkId'
              ]
    fields' <- shuffle fields
    pure $ mp fields'

instance Crypto c => Twiddle (AlonzoScript (AlonzoEra c)) where
  twiddle v = twiddle v . toTerm v

instance Typeable c => Twiddle (Data (AlonzoEra c)) where
  twiddle v = twiddle v . toTerm v

instance Crypto c => Twiddle (BinaryData (AlonzoEra c)) where
  twiddle v = twiddle v . toTerm v
