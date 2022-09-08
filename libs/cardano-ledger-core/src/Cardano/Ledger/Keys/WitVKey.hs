{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingVia #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE PatternSynonyms #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE TypeApplications #-}

module Cardano.Ledger.Keys.WitVKey
  ( WitVKey (WitVKey),
    witVKeyBytes,
    witVKeyHash,
  )
where

import Cardano.Binary
  ( Annotator (..),
    FromCBOR (fromCBOR),
    ToCBOR (..),
    annotatorSlice,
    encodeListLen,
    encodePreEncoded,
    serializeEncoding,
  )
import Cardano.Ledger.Crypto
import Cardano.Ledger.Hashes (EraIndependentTxBody)
import Cardano.Ledger.Keys
  ( Hash,
    KeyHash (..),
    KeyRole (..),
    SignedDSIGN,
    VKey,
    asWitness,
    decodeSignedDSIGN,
    encodeSignedDSIGN,
    hashKey,
    hashSignature,
  )
import Cardano.Ledger.Serialization (decodeRecordNamed)
import Control.DeepSeq
import qualified Data.ByteString.Lazy as BSL
import Data.Ord (comparing)
import Data.Typeable (Typeable)
import GHC.Generics (Generic)
import NoThunks.Class (AllowThunksIn (..), NoThunks (..))

-- | Proof/Witness that a transaction is authorized by the given key holder.
data WitVKey kr c = WitVKeyInternal
  { wvkKey :: !(VKey kr c),
    wvkSig :: !(SignedDSIGN c (Hash c EraIndependentTxBody)),
    -- | Hash of the witness vkey. We store this here to avoid repeated hashing
    --   when used in ordering.
    wvkKeyHash :: KeyHash 'Witness c,
    wvkBytes :: BSL.ByteString
  }
  deriving (Generic)

deriving instance Crypto c => Show (WitVKey kr c)

deriving instance Crypto c => Eq (WitVKey kr c)

deriving via
  AllowThunksIn '["wvkBytes", "wvkKeyHash"] (WitVKey kr c)
  instance
    (Crypto c, Typeable kr) => NoThunks (WitVKey kr c)

instance NFData (WitVKey kr c) where
  rnf WitVKeyInternal {wvkKeyHash, wvkBytes} = wvkKeyHash `deepseq` rnf wvkBytes

instance (Typeable kr, Crypto c) => Ord (WitVKey kr c) where
  compare x y =
    -- It is advised against comparison on keys and signatures directly,
    -- therefore we use hashes of verification keys and signatures for
    -- implementing this Ord instance. Note that we do not need to memoize the
    -- hash of a signature, like it is done with the hash of a key, because Ord
    -- instance is only used for Sets of WitVKeys and it would be a mistake to
    -- have two WitVKeys in a same Set for different transactions. Therefore
    -- comparison on signatures is unlikely to happen and is only needed for
    -- compliance with Ord laws.
    comparing wvkKeyHash x y <> comparing (hashSignature @c . wvkSig) x y

instance (Typeable kr, Crypto c) => ToCBOR (WitVKey kr c) where
  toCBOR = encodePreEncoded . BSL.toStrict . wvkBytes

instance (Typeable kr, Crypto c) => FromCBOR (Annotator (WitVKey kr c)) where
  fromCBOR =
    annotatorSlice $
      decodeRecordNamed "WitVKey" (const 2) $
        fmap pure $
          mkWitVKey <$> fromCBOR <*> decodeSignedDSIGN
    where
      mkWitVKey k sig = WitVKeyInternal k sig (asWitness $ hashKey k)

pattern WitVKey ::
  (Typeable kr, Crypto c) =>
  VKey kr c ->
  SignedDSIGN c (Hash c EraIndependentTxBody) ->
  WitVKey kr c
pattern WitVKey k s <-
  WitVKeyInternal k s _ _
  where
    WitVKey k s =
      let bytes =
            serializeEncoding $
              encodeListLen 2
                <> toCBOR k
                <> encodeSignedDSIGN s
          hash = asWitness $ hashKey k
       in WitVKeyInternal k s hash bytes

{-# COMPLETE WitVKey #-}

-- | Acess computed hash. Evaluated lazily
witVKeyHash :: WitVKey kr c -> KeyHash 'Witness c
witVKeyHash = wvkKeyHash

-- | Access CBOR encoded representation of the witness. Evaluated lazily
witVKeyBytes :: WitVKey kr c -> BSL.ByteString
witVKeyBytes = wvkBytes
