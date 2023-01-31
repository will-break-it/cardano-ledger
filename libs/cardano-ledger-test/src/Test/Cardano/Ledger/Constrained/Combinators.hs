{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeSynonymInstances #-}

module Test.Cardano.Ledger.Constrained.Combinators where

import Cardano.Ledger.Coin (Coin (..))
import Data.Char (chr)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Set (Set)
import qualified Data.Set as Set
import Test.Cardano.Ledger.Core.Arbitrary ()
import Test.QuickCheck hiding (Fixed, total)

-- import Test.Cardano.Ledger.Constrained.Monad

-- import Debug.Trace(trace)
import qualified Data.List as List

-- ==========================================================================

test1 :: Int -> (Int -> Gen Int -> Gen b) -> IO b
test1 n x = generate (x n (arbitrary :: Gen Int))

test2 :: Int -> (Int -> Gen Int -> Gen Char -> Gen b) -> IO b
test2 n x = generate (x n (arbitrary :: Gen Int) (elements [chr i | i <- [1 .. 128]]))

small :: Gen Int
small = elements [1 .. 6]

data SubsetCond = Any | NotEmpty deriving (Eq, Show)

-- =======================================================================

-- | Report an error from the current message 'extra' and the
--   [messages] 'mess' describing the path to this call site.
errorMess :: String -> [String] -> a
errorMess extra mess = error (unlines ("\nGen-time error" : (reverse (extra : mess))))

setSized :: Ord a => [String] -> Int -> Gen a -> Gen (Set a)
setSized mess size gen = do set <- (Set.fromList <$> vectorOf size gen); fixSet mess (size * 10) size gen set

fixSet :: Ord a => [String] -> Int -> Int -> Gen a -> Set a -> Gen (Set a)
fixSet mess numtrys size genA s = help numtrys s
  where
    help trys set
      | trys <= 0 =
          if Set.size set == size
            then pure set
            else errorMess ("Ran out of trys(" ++ show numtrys ++ ") in fixSet: need " ++ show size ++ " elements, have " ++ show (Set.size set)) mess
    help trys set = case compare (Set.size set) size of
      EQ -> pure set
      GT -> help (trys - 1) (iterate Set.deleteMin set !! (Set.size set - size))
      LT -> do
        new <- Set.fromList <$> vectorOf (size - Set.size set) genA
        help (trys - 1) (Set.union new set)

mapSized :: Ord a => [String] -> Int -> Gen a -> Gen b -> Gen (Map a b)
mapSized mess size genA genB = setSized (("From mapSized " ++ show size) : mess) size genA >>= addRange
  where
    addRange set = Set.foldl' accum (pure Map.empty) set
    accum ansGen dom = do ans <- ansGen; rng <- genB; pure (Map.insert dom rng ans)

coinSized :: Int -> Gen Coin
coinSized n = pure (Coin (fromIntegral n))

setFromSubsetWithSize :: Ord a => [String] -> Set a -> Int -> Gen a -> Gen (Set a)
setFromSubsetWithSize mess subset n gen = do
  additions <- setSized (("From setFromSubsetWithSize " ++ show n) : mess) n gen
  pure (Set.union subset additions)

subsetFromSetWithSize :: Ord a => [String] -> Set a -> Int -> Gen (Set a)
subsetFromSetWithSize mess set n = help set Set.empty n
  where
    help source target count
      | Set.size source < count =
          errorMess
            ( "subsetFromSetWithSize: Can't make a subset of size "
                ++ show n
                ++ " from a smaller set of size "
                ++ show (Set.size set)
            )
            mess
      | count <= 0 = pure target
      | otherwise = do
          item <- itemFromSet ("From subsetFromSetWithSize" : mess) source
          help (Set.delete item source) (Set.insert item target) (count - 1)

subsetFromSetWithSize2 :: [String] -> Set a -> Int -> Gen (Set a)
subsetFromSetWithSize2 mess set n
  | n <= 0 = pure Set.empty
  | n > size =
      errorMess
        ( "subsetFromSetWithSize: Can't make a subset of size "
            ++ show n
            ++ " from a smaller set of size "
            ++ show (Set.size set)
        )
        mess
  | n == size = pure set
  | otherwise = help set size
  where
    size = Set.size set
    help current count | count == n = pure current
    help current count = do
      index <- chooseInt (0, Set.size current - 1)
      help (Set.deleteAt index current) (count - 1)

mapFromSubset :: Ord a => [String] -> Map a b -> Int -> Gen a -> Gen b -> Gen (Map a b)
mapFromSubset mess subset n genA genB = do
  additions <- mapSized ("From MapFromSubset " : mess) n genA genB
  pure (Map.union subset additions)

{-  BROKEN 'n' could be too big for 'set'
subsetFromMap :: Map a b -> Int -> Gen (Map a b)
subsetFromMap set n |
subsetFromMap set n = do
  indexes <- vectorOf n (elements [0 .. Map.size set - 1])
  pure (List.foldl' (flip Map.deleteAt) set indexes)
-}

mapFromSet :: Ord a => Set a -> Gen b -> Gen (Map a b)
mapFromSet set genB = addRange set
  where
    addRange s = Set.foldl' accum (pure Map.empty) s
    accum ansGen dom = do ans <- ansGen; rng <- genB; pure (Map.insert dom rng ans)

itemFromSet :: [String] -> Set a -> Gen a
itemFromSet mess set | Set.null set = errorMess "itemFromSet : Can't take an item from the empty set." mess
itemFromSet _ set = elements (Set.toList set)

mapFromRange :: forall a b. Ord a => [b] -> Gen a -> Gen (Map a b)
mapFromRange bs genA = Map.fromList <$> mapM (\b -> do a <- genA; pure (a, b)) bs

mapFromProj :: Ord a => [b] -> Gen a -> (b -> Gen c) -> Gen (Map a c)
mapFromProj bs genA genC = Map.fromList <$> mapM (\b -> do a <- genA; c <- genC b; pure (a, c)) bs

mapFromDomRange :: Ord a => Set a -> [b] -> Map a b
mapFromDomRange dom bs = Map.fromList $ zip (Set.toList dom) bs

subsetSize :: Set a -> Gen Int
subsetSize s | Set.null s = pure 0
subsetSize s = frequency [(1, pure 0), (20, choose (1, n - 1)), (1, pure n)]
  where
    n = Set.size s

subsetFromSet :: Ord a => [String] -> Set a -> Gen (Set a)
subsetFromSet mess set = do
  n <- subsetSize set
  subsetFromSetWithSize ("From subsetFromSet" : mess) set n

superSetFromSet :: Ord a => Gen a -> Set a -> Gen (Set a)
superSetFromSet genA setA = do
  Positive n <- arbitrary
  superSetFromSetWithSize ["supersetFromSet"] (n + Set.size setA) genA setA

-- additions <- vectorOf n genA
-- pure (List.foldl' (flip Set.insert) setA additions)

superSetFromSetWithSize :: Ord a => [String] -> Int -> Gen a -> Set a -> Gen (Set a)
superSetFromSetWithSize mess n _ setA
  | n < Set.size setA =
      errorMess
        ( "superSetFromSetWithSize: Size of the superset ("
            ++ show n
            ++ ") is smaller than "
            ++ "the size of the given set ("
            ++ show (Set.size setA)
            ++ ")."
        )
        mess
superSetFromSetWithSize msgs size genA setA = do
  additions <-
    setSized
      ("from superSetFromSetWithSize" : msgs)
      (size - Set.size setA)
      (suchThat genA (`Set.notMember` setA))
  pure (List.foldl' (flip Set.insert) setA additions)

-- | Generates things both in (Set a) and not in (Set a) with differing frequencies.
superItemFromSet :: Ord a => Gen a -> Set a -> Gen a
superItemFromSet genA set | Set.null set = genA
superItemFromSet genA set =
  frequency
    [ (3, itemFromSet ["Not possible since set is not empty"] set)
    , (1, suchThat genA (`Set.notMember` set))
    ]