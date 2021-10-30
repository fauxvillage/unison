{-# Language BangPatterns #-}
{-# Language GeneralizedNewtypeDeriving #-}
{-# OPTIONS_GHC -fno-warn-orphans #-}

module Unison.Util.Text where

import Data.String (IsString(..))
import Data.Foldable (toList)
import Data.List (unfoldr)
import Prelude hiding (take,drop,replicate)
import qualified Data.Text as T
import qualified Data.Text.Encoding as T
import qualified Unison.Util.Bytes as B
import qualified Unison.Util.Rope as R

-- Text type represented as a `Rope` of chunks
newtype Text = Text (R.Rope Chunk) deriving (Eq,Ord,Semigroup,Monoid)

data Chunk = Chunk {-# unpack #-} !Int {-# unpack #-} !T.Text

one, singleton :: Char -> Text
one ch = Text (R.one (chunk (T.singleton ch)))  
singleton = one

threshold :: Int
threshold = 512

replicate :: Int -> Text -> Text
replicate n (Text (R.One c)) | R.size c * n < threshold = Text (R.One (chunk (T.replicate n (chunkToText c)))) 
replicate 0 _ = mempty 
replicate 1 t = t
replicate n t = 
  replicate (n `div` 2) t <> replicate (n - (n `div` 2)) t

chunkToText :: Chunk -> T.Text
chunkToText (Chunk _ t) = t

chunk :: T.Text -> Chunk
chunk t = Chunk (T.length t) t 

take :: Int -> Text -> Text
take n (Text t) = Text (R.take n t)

drop :: Int -> Text -> Text
drop n (Text t) = Text (R.drop n t)

at :: Int -> Text -> Maybe Char
at n (Text t) = R.index n t

size :: Text -> Int
size (Text t) = R.size t

reverse :: Text -> Text
reverse (Text t) = Text (R.reverse t)

fromUtf8 :: B.Bytes -> Either String Text
fromUtf8 bs = 
  case T.decodeUtf8' (B.toByteString bs) of
    Right t -> Right (fromText t)
    Left e -> Left (show e)

toUtf8 :: Text -> B.Bytes
toUtf8 (Text t) = B.Bytes (R.map (B.chunkFromByteString . T.encodeUtf8 . chunkToText) t)

fromText :: T.Text -> Text
fromText s = go (Text (R.one (chunk s)))
  where
  go t | n > threshold  = go (take (n `div` 2) t) <> go (drop (n `div` 2) t)
       | otherwise      = t
       where n = size t

pack :: String -> Text
pack = fromText . T.pack
{-# inline pack #-}

toString, unpack :: Text -> String
toString (Text bs) = toList bs >>= (T.unpack . chunkToText)
{-# inline toString #-}
{-# inline unpack #-}

unpack = toString

toText :: Text -> T.Text
toText (Text t) = T.concat (chunkToText <$> unfoldr R.uncons t)
{-# inline toText #-}

{-
dropWhile :: (Char -> Bool) -> Text -> Text
dropWhile f = let
  go t = case R.uncons t of
    Nothing -> mempty
    Just (hd, t) ->
      let hd' = T.dropWhile f hd in
      if T.null hd' then go t
      else hd' `R.cons` t
  in go
{-# INLINE dropWhile #-}

dropWhileEnd :: (Char -> Bool) -> Text -> Text
dropWhileEnd f = let
  go t = case R.unsnoc t of
    Nothing -> mempty
    Just (t, last) ->
      let last' = T.dropWhileEnd f last in
      if T.null last' then go t
      else t `R.snoc` last'
  in go
{-# INLINE dropWhileEnd #-}

takeWhile :: (Char -> Bool) -> Text -> Text
takeWhile f = let
  go :: Text -> Text -> Text
  go !acc t = case R.uncons t of
    Nothing -> mempty
    Just (hd, t) ->
      let hd' = T.takeWhile f hd in
      if R.size hd == R.size hd' then go (acc `R.snoc` hd) t
      else acc `R.snoc` hd'
  in go mempty
{-# INLINE takeWhile #-}

takeWhileEnd :: (Char -> Bool) -> Text -> Text
takeWhileEnd f = let
  go :: Text -> Text -> Text
  go !acc t = case R.unsnoc t of
    Nothing -> mempty
    Just (t, last) ->
      let last' = T.takeWhileEnd f last in
      if R.size last == R.size last' then go (last `R.cons` acc) t
      else last' `R.cons` acc
  in go mempty
{-# INLINE takeWhileEnd #-}


-}

instance Eq Chunk where (Chunk n a) == (Chunk n2 a2) = n == n2 && a == a2
instance Ord Chunk where (Chunk _ a) `compare` (Chunk _ a2) = compare a a2
instance Semigroup Chunk where (<>) = mappend
instance Monoid Chunk where
  mempty = Chunk 0 mempty
  mappend l r = Chunk (R.size l + R.size r) (chunkToText l <> chunkToText r) 

instance R.Sized Chunk where size (Chunk n _) = n 

instance R.Drop Chunk where 
  drop k c@(Chunk n t) 
    | k >= n = mempty
    | k <= 0 = c 
    | otherwise = Chunk (n-k) (T.drop k t)

instance R.Take Chunk where 
  take k c@(Chunk n t)
    | k >= n = c 
    | k <= 0 = mempty 
    | otherwise = Chunk k (T.take k t)

instance R.Index Chunk Char where
  index i (Chunk n t) | i < n     = Just (T.index t i)
                      | otherwise = Nothing

instance R.Reverse Chunk where 
  reverse (Chunk n t) = Chunk n (T.reverse t)

instance R.Sized Text where size (Text t) = R.size t

instance Show Text where
  show t = show (toText t)

instance IsString Text where
   fromString = pack