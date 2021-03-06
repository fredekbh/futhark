{-# LANGUAGE DeriveLift         #-}
-- | This module contains very basic definitions for Futhark - so basic,
-- that they can be shared between the internal and external
-- representation.
module Language.Futhark.Core
  ( Uniqueness(..)
  , StreamOrd(..)
  , Commutativity(..)

  -- * Location utilities
  , locStr

  -- * Name handling
  , Name
  , nameToString
  , nameFromString
  , nameToText
  , nameFromText
  , VName(..)
  , baseTag
  , baseName
  , baseString
  , pretty
  -- * Special identifiers
  , defaultEntryPoint

    -- * Integer re-export
  , Int8, Int16, Int32, Int64
  , Word8, Word16, Word32, Word64
  )

where

import Data.Int (Int8, Int16, Int32, Int64)
import Data.Word (Word8, Word16, Word32, Word64)
import Data.Loc
import qualified Data.Semigroup as Sem
import qualified Data.Text as T
import Language.Haskell.TH.Syntax (Lift)
import Instances.TH.Lift()

import Futhark.Util.Pretty

-- | The uniqueness attribute of a type.  This essentially indicates
-- whether or not in-place modifications are acceptable.  With respect
-- to ordering, 'Unique' is greater than 'Nonunique'.
data Uniqueness = Nonunique -- ^ May have references outside current function.
                | Unique    -- ^ No references outside current function.
                  deriving (Eq, Ord, Show, Lift)

instance Sem.Semigroup Uniqueness where
  (<>) = min

instance Monoid Uniqueness where
  mempty = Unique
  mappend = (Sem.<>)

instance Pretty Uniqueness where
  ppr Unique = star
  ppr Nonunique = empty

data StreamOrd  = InOrder
                | Disorder
                    deriving (Eq, Ord, Show, Lift)

-- | Whether some operator is commutative or not.  The 'Monoid'
-- instance returns the least commutative of its arguments.
data Commutativity = Noncommutative
                   | Commutative
                     deriving (Eq, Ord, Show, Lift)

instance Sem.Semigroup Commutativity where
  (<>) = min

instance Monoid Commutativity where
  mempty = Commutative
  mappend = (Sem.<>)

-- | The name of the default program entry point (main).
defaultEntryPoint :: Name
defaultEntryPoint = nameFromString "main"

-- | The abstract (not really) type representing names in the Futhark
-- compiler.  'String's, being lists of characters, are very slow,
-- while 'T.Text's are based on byte-arrays.
newtype Name = Name T.Text
  deriving (Show, Eq, Ord, Lift)

instance Pretty Name where
  ppr = text . nameToString

instance Sem.Semigroup Name where
  Name t1 <> Name t2 = Name $ t1 <> t2

-- | Convert a name to the corresponding list of characters.
nameToString :: Name -> String
nameToString (Name t) = T.unpack t

-- | Convert a list of characters to the corresponding name.
nameFromString :: String -> Name
nameFromString = Name . T.pack

-- | Convert a name to the corresponding 'T.Text'.
nameToText :: Name -> T.Text
nameToText (Name t) = t

-- | Convert a 'T.Text' to the corresponding name.
nameFromText :: T.Text -> Name
nameFromText = Name

-- | A human-readable location string, of the form
-- @filename:lineno:columnno@.
locStr :: SrcLoc -> String
locStr (SrcLoc NoLoc) = "unknown location"
locStr (SrcLoc (Loc (Pos file line1 col1 _) (Pos _ line2 col2 _))) =
  -- Assume that both positions are in the same file (what would the
  -- alternative mean?)
  file ++ ":" ++ show line1 ++ ":" ++ show col1
       ++ "-" ++ show line2 ++ ":" ++ show col2

-- | A name tagged with some integer.  Only the integer is used in
-- comparisons, no matter the type of @vn@.
data VName = VName !Name !Int
  deriving (Show, Lift)

-- | Return the tag contained in the 'VName'.
baseTag :: VName -> Int
baseTag (VName _ tag) = tag

-- | Return the name contained in the 'VName'.
baseName :: VName -> Name
baseName (VName vn _) = vn

-- | Return the base 'Name' converted to a string.
baseString :: VName -> String
baseString = nameToString . baseName

instance Eq VName where
  VName _ x == VName _ y = x == y

instance Ord VName where
  VName _ x `compare` VName _ y = x `compare` y

instance Pretty VName where
  ppr (VName vn i) = ppr vn <> text "_" <> text (show i)
