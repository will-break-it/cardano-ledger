{-# LANGUAGE FlexibleContexts    #-}
{-# LANGUAGE LambdaCase          #-}
{-# LANGUAGE OverloadedStrings   #-}
{-# LANGUAGE ScopedTypeVariables #-}

module Cardano.Chain.Epoch.Validation
  ( EpochError(..)
  , validateEpochFile
  , validateEpochFiles
  )
where

import Cardano.Prelude hiding (trace)

import Control.Monad.Trans.Resource (ResIO, runResourceT)
import Formatting (Format, build, sformat)
import Streaming (Of(..), Stream, hoist)
import qualified Streaming.Prelude as S

import Cardano.Shell.Features.Logging (LoggingLayer(..), Trace)
import qualified Cardano.Shell.Features.Logging as Log

import Cardano.Chain.Block
  ( ABlockOrBoundary(..)
  , ChainValidationError
  , ChainValidationState(..)
  , HeapSize
  , UTxOSize
  , blockSlot
  , calcUTxOSize
  , updateChainBlockOrBoundary
  )
import Cardano.Chain.Block.ValidationMode (BlockValidationMode)
import Cardano.Chain.Epoch.File
  ( ParseError
  , mainnetEpochSlots
  , parseEpochFileWithBoundary
  , parseEpochFilesWithBoundary
  )
import qualified Cardano.Chain.Genesis as Genesis
import Cardano.Chain.Slotting
  (EpochNumber, EpochAndSlotCount, slotNumberEpoch, fromSlotNumber)
import Cardano.Chain.UTxO (UTxO)


data EpochError
  = EpochParseError ParseError
  | EpochChainValidationError (Maybe EpochAndSlotCount) ChainValidationError
  | Initial
  deriving (Eq, Show)


-- | Check that a single epoch's `Block`s are valid by folding over them
validateEpochFile
  :: forall m
   . (MonadIO m, MonadError EpochError m)
  => BlockValidationMode
  -> Genesis.Config
  -> LoggingLayer
  -> ChainValidationState
  -> FilePath
  -> m ChainValidationState
validateEpochFile bvmode config ll cvs fp = do
  subTrace     <- llAppendName ll "epoch-validation" (llBasicTrace ll)
  utxoSubTrace <- llAppendName ll "utxo-stats" subTrace
  res          <- llBracketMonadX ll subTrace Log.Info "benchmark" $
      liftIO $ runResourceT $ runExceptT $ foldChainValidationState
        bvmode
        config
        cvs
        stream
  either throwError (logResult subTrace utxoSubTrace) res
 where
  stream = parseEpochFileWithBoundary mainnetEpochSlots fp

  logResult
    :: Trace m Text
    -> Trace m Text
    -> ChainValidationState
    -> m ChainValidationState
  logResult trace' utxoTrace cvs' = do
    llLogNotice ll
      trace'
      (sformat
        epochValidationFormat
        (slotNumberEpoch (Genesis.configEpochSlots config) (cvsLastSlot cvs))
      )
    llLogDebug ll
      utxoTrace
      (sformat
        utxoStatsFormat
        utxoSize
        heapSize
      )
    pure cvs'
   where
    (heapSize, utxoSize) = calcUTxOSize (cvsUtxo cvs')

  epochValidationFormat :: Format r (EpochNumber -> r)
  epochValidationFormat =
    "Succesfully validated epoch " . build . "\n"

  utxoStatsFormat :: Format r (UTxOSize -> HeapSize UTxO -> r)
  utxoStatsFormat =
    "Number of UTxO entries at the end of the epoch: " . build . "\n" .
    "UTxO heap size in words at the end of the epoch: " . build . "\n"


-- | Check that a list of epochs 'Block's are valid.
validateEpochFiles
  :: BlockValidationMode
  -> Genesis.Config
  -> ChainValidationState
  -> [FilePath]
  -> IO (Either EpochError ChainValidationState)
validateEpochFiles bvmode config cvs fps =
    runResourceT . runExceptT $ foldChainValidationState bvmode config cvs stream
  where stream = parseEpochFilesWithBoundary mainnetEpochSlots fps


-- | Fold chain validation over a 'Stream' of 'Block's
foldChainValidationState
  :: BlockValidationMode
  -> Genesis.Config
  -> ChainValidationState
  -> Stream (Of (ABlockOrBoundary ByteString)) (ExceptT ParseError ResIO) ()
  -> ExceptT EpochError ResIO ChainValidationState
foldChainValidationState bvmode config chainValState blocks = S.foldM_
  (\cvs block ->
    withExceptT (EpochChainValidationError (blockOrBoundarySlot block))
      $ updateChainBlockOrBoundary bvmode config cvs block
  )
  (pure chainValState)
  pure $ hoist (withExceptT EpochParseError) blocks
 where
  blockOrBoundarySlot :: ABlockOrBoundary a -> Maybe EpochAndSlotCount
  blockOrBoundarySlot = \case
    ABOBBoundary _     -> Nothing
    ABOBBlock    block -> Just . fromSlotNumber mainnetEpochSlots $ blockSlot block
