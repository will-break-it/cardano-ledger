{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

module Test.Cardano.Ledger.Conway.GenesisSpec (spec) where

import Cardano.Ledger.BaseTypes (textToUrl)
import Cardano.Ledger.CertState (DRep (..), DRepState (..))
import Cardano.Ledger.Coin (Coin (..))
import Cardano.Ledger.Conway
import Cardano.Ledger.Conway.Genesis (ConwayGenesis (..))
import Cardano.Ledger.Conway.Governance (Anchor (..), Committee (..))
import Cardano.Ledger.Conway.TxCert (Delegatee (..))
import Cardano.Ledger.Core
import Cardano.Ledger.Credential
import Cardano.Ledger.Crypto (StandardCrypto)
import Cardano.Ledger.Keys
import Cardano.Ledger.Slot (EpochNo (..))
import Data.Aeson hiding (Encoding)
import Data.Default.Class (Default (def))
import qualified Data.ListMap as ListMap
import Data.Map as Map
import Data.Maybe (fromJust)
import Data.Maybe.Strict (StrictMaybe (..))
import Data.Ratio ((%))
import Paths_cardano_ledger_conway (getDataFileName)
import Test.Cardano.Ledger.Common
import Test.Cardano.Ledger.Core.Utils (unsafeBoundRational)
import Test.Cardano.Slotting.Numeric ()

spec :: Spec
spec = do
  describe "Genesis Golden Spec" $ do
    goldenConwayGenesisJSON

goldenConwayGenesisJSON :: Spec
goldenConwayGenesisJSON =
  it "should deserialize to the default value" $ do
    let fileName = "test/data/conway-genesis.json"
        credMember =
          KeyHashObj
            (KeyHash "4e88cc2d27c364aaf90648a87dfb95f8ee103ba67fa1f12f5e86c42a") ::
            Credential 'ColdCommitteeRole StandardCrypto
        scriptMember =
          ScriptHashObj
            (ScriptHash "4e88cc2d27c364aaf90648a87dfb95f8ee103ba67fa1f12f5e86c42a") ::
            Credential 'ColdCommitteeRole StandardCrypto
        comm =
          Committee
            ( Map.fromList
                [
                  ( credMember
                  , EpochNo 1
                  )
                ,
                  ( scriptMember
                  , EpochNo 2
                  )
                ]
            )
            (unsafeBoundRational (1 % 2)) ::
            Committee Conway
    file <- getDataFileName fileName
    dec <- eitherDecodeFileStrict' file
    cg <- case dec of
      Left err -> error ("Failed to deserialize JSON: " ++ err)
      Right x -> pure x
    let
      expectedCg =
        def
          { cgCommittee = comm
          , cgInitialDReps =
              ListMap.fromList
                [
                  ( KeyHashObj
                      (KeyHash "78301005df84ba67fa1f12f95f8ee10335bc5e86c42afbc593ab4cdd")
                  , DRepState
                      { drepExpiry = 1000
                      , drepAnchor = SNothing
                      , drepDeposit = Coin 5000
                      }
                  )
                ,
                  ( ScriptHashObj
                      (ScriptHash "01305df84b078ac5e86c42afbc593ab4cdd67fa1f12f95f8ee10335b")
                  , DRepState
                      { drepExpiry = 300
                      , drepAnchor =
                          SJust $
                            Anchor
                              { anchorUrl = fromJust $ textToUrl 99 "example.com"
                              , anchorDataHash = def
                              }
                      , drepDeposit = Coin 6000
                      }
                  )
                ]
          , cgDelegs =
              ListMap.fromList
                [
                  ( KeyHashObj
                      (KeyHash "35bc5e86c42afbc593ab4cdd78301005df84ba67fa1f12f95f8ee103")
                  , DelegVote DRepAlwaysNoConfidence
                  )
                ,
                  ( KeyHashObj
                      (KeyHash "4e88cc2d27c364aaf90648a87dfb95f8ee103ba67fa1f12f5e86c42a")
                  , DelegVote DRepAlwaysAbstain
                  )
                ,
                  ( KeyHashObj
                      (KeyHash "5df84bcdd7a5f8ee93aafbc500b435bc5e83067fa1f12f9110386c42")
                  , DelegStake $ KeyHash "0335bc5e86c42afbc578301005df84ba67fa1f12f95f8ee193ab4cdd"
                  )
                ,
                  ( KeyHashObj
                      (KeyHash "8ee93a5df84bc42cdd7a5fafbc500b435bc5e83067fa1f12f9110386")
                  , DelegStakeVote
                      (KeyHash "086c42afbc578301005df84ba67fa1f12f95f8ee193ab4cdd335bc5e")
                      DRepAlwaysAbstain
                  )
                ,
                  ( KeyHashObj
                      (KeyHash "df93ab435bc5eafbc500583067fa1f12f9110386c42cdd784ba5f8ee")
                  , DelegVote $
                      DRepCredential
                        (ScriptHashObj (ScriptHash "01305df84b078ac5e86c42afbc593ab4cdd67fa1f12f95f8ee10335b"))
                  )
                ,
                  ( ScriptHashObj
                      (ScriptHash "afbc5005df84ba5f8ee93ab435bc5e83067fa1f12f9c42cdd7110386")
                  , DelegVote $
                      DRepCredential
                        (KeyHashObj (KeyHash "78301005df84ba67fa1f12f95f8ee10335bc5e86c42afbc593ab4cdd"))
                  )
                ]
          }
    cg `shouldBe` expectedCg
