{-# OPTIONS_GHC -fno-warn-orphans #-}
{-# LANGUAGE FlexibleContexts  #-}
{-# LANGUAGE FlexibleInstances #-}
-- | Futhark prettyprinter.  This module defines 'Pretty' instances
-- for the AST defined in "Language.Futhark.Syntax".
module Language.Futhark.Pretty
  ( pretty
  , prettyTuple
  , leadingOperator
  , Annot
  )
where

import           Control.Monad
import           Data.Array
import           Data.Functor
import qualified Data.Map.Strict       as M
import           Data.List
import           Data.Maybe
import           Data.Monoid
import           Data.Ord
import           Data.Word

import           Prelude

import           Futhark.Util.Pretty

import           Language.Futhark.Syntax
import           Language.Futhark.Attributes

commastack :: [Doc] -> Doc
commastack = align . stack . punctuate comma

-- | Class for type constructors that represent annotations.  Used in
-- the prettyprinter to either print the original AST, or the computed
-- attribute.
class Annot f where
  unAnnot :: f a -> Maybe a

instance Annot NoInfo where
  unAnnot = const Nothing

instance Annot Info where
  unAnnot = Just . unInfo

pprAnnot :: (Annot f, Pretty a, Pretty b) => a -> f b -> Doc
pprAnnot a b = maybe (ppr a) ppr $ unAnnot b

instance Pretty Value where
  ppr (PrimValue bv) = ppr bv
  ppr (ArrayValue a t)
    | [] <- elems a = text "empty" <> parens (ppr t)
    | Array{} <- t  = brackets $ commastack $ map ppr $ elems a
    | otherwise     = brackets $ commasep $ map ppr $ elems a

instance Pretty PrimValue where
  ppr (UnsignedValue (Int8Value v)) =
    text (show (fromIntegral v::Word8)) <> text "u8"
  ppr (UnsignedValue (Int16Value v)) =
    text (show (fromIntegral v::Word16)) <> text "u16"
  ppr (UnsignedValue (Int32Value v)) =
    text (show (fromIntegral v::Word32)) <> text "u32"
  ppr (UnsignedValue (Int64Value v)) =
    text (show (fromIntegral v::Word64)) <> text "u64"
  ppr (SignedValue v) = ppr v
  ppr (BoolValue True) = text "true"
  ppr (BoolValue False) = text "false"
  ppr (FloatValue v) = ppr v

instance Pretty vn => Pretty (DimDecl vn) where
  ppr AnyDim       = mempty
  ppr (NamedDim v) = ppr v
  ppr (ConstDim n) = ppr n


instance Pretty vn => Pretty (ShapeDecl (DimDecl vn)) where
  ppr (ShapeDecl ds) = mconcat (map (brackets . ppr) ds)

instance Pretty (ShapeDecl ()) where
  ppr (ShapeDecl ds) = mconcat $ replicate (length ds) $ text "[]"

instance Pretty (ShapeDecl dim) => Pretty (RecordArrayElemTypeBase dim as) where
  ppr (RecordArrayElem et) = ppr et
  ppr (RecordArrayArrayElem et shape u) =
    ppr u <> ppr shape <> ppr et

instance Pretty (ShapeDecl dim) => Pretty (ArrayElemTypeBase dim as) where
  ppr (ArrayPrimElem pt _) = ppr pt
  ppr (ArrayPolyElem v args _) =
    ppr (baseName <$> qualNameFromTypeName v) <+> spread (map ppr args)
  ppr (ArrayRecordElem fs)
    | Just ts <- areTupleFields fs =
        parens (commasep $ map ppr ts)
    | otherwise =
        braces (commasep $ map ppField $ M.toList fs)
    where ppField (name, t) = text (nameToString name) <> colon <+> ppr t

instance Pretty (ShapeDecl dim) => Pretty (TypeBase dim as) where
  ppr (Prim et) = ppr et
  ppr (TypeVar et targs) = ppr (baseName <$> qualNameFromTypeName et) <+>
                           spread (map ppr targs)
  ppr (Array at shape u) = ppr u <> ppr shape <> ppr at
  ppr (Record fs)
    | Just ts <- areTupleFields fs =
        parens $ commasep $ map ppr ts
    | otherwise =
        braces $ commasep $ map ppField $ M.toList fs
    where ppField (name, t) = text (nameToString name) <> colon <+> ppr t
  ppr (Arrow _ (Just v) t1 t2) =
    parens (ppr (baseName v) <> colon <+> ppr t1) <+> text "->" <+> ppr t2
  ppr (Arrow _ Nothing t1 t2) =
    ppr t1 <+> text "->" <+> ppr t2

instance Pretty (ShapeDecl dim) => Pretty (TypeArg dim as) where
  ppr (TypeArgDim d _) = ppr $ ShapeDecl [d]
  ppr (TypeArgType t _) = ppr t

instance (Eq vn, Pretty vn) => Pretty (TypeExp vn) where
  ppr (TEUnique t _) = text "*" <> ppr t
  ppr (TEArray at d _) = ppr (ShapeDecl [d]) <> ppr at
  ppr (TETuple ts _) = parens $ commasep $ map ppr ts
  ppr (TERecord fs _) = braces $ commasep $ map ppField fs
    where ppField (name, t) = text (nameToString name) <> colon <+> ppr t
  ppr (TEVar name _) = ppr name
  ppr (TEApply t arg _) = ppr t <+> ppr arg
  ppr (TEArrow (Just v) t1 t2 _) = parens v' <+> text "->" <+> ppr t2
    where v' = ppr v <> colon <+> ppr t1
  ppr (TEArrow Nothing t1 t2 _) = ppr t1 <+> text "->" <+> ppr t2

instance (Eq vn, Pretty vn) => Pretty (TypeArgExp vn) where
  ppr (TypeArgExpDim d _) = ppr $ ShapeDecl [d]
  ppr (TypeArgExpType d) = ppr d

instance (Eq vn, Pretty vn, Annot f) => Pretty (TypeDeclBase f vn) where
  ppr x = pprAnnot (declaredType x) (expandedType x)

instance Pretty vn => Pretty (QualName vn) where
  ppr (QualName names name) =
    mconcat $ punctuate (text ".") $ map ppr names ++ [ppr name]

instance Pretty vn => Pretty (IdentBase f vn) where
  ppr = ppr . identName

hasArrayLit :: ExpBase ty vn -> Bool
hasArrayLit ArrayLit{}     = True
hasArrayLit (TupLit es2 _) = any hasArrayLit es2
hasArrayLit _              = False

instance (Eq vn, Pretty vn, Annot f) => Pretty (DimIndexBase f vn) where
  ppr (DimFix e)       = ppr e
  ppr (DimSlice i j (Just s)) =
    maybe mempty ppr i <> text ":" <>
    maybe mempty ppr j <> text ":" <>
    ppr s
  ppr (DimSlice i (Just j) s) =
    maybe mempty ppr i <> text ":" <>
    ppr j <>
    maybe mempty ((text ":" <>) . ppr) s
  ppr (DimSlice i Nothing Nothing) =
    maybe mempty ppr i <> text ":"

instance (Eq vn, Pretty vn, Annot f) => Pretty (ExpBase f vn) where
  ppr = pprPrec (-1)
  pprPrec _ (Var name _ _) = ppr name
  pprPrec _ (Parens e _) = align $ parens $ ppr e
  pprPrec _ (QualParens v e _) = ppr v <> text "." <> align (parens $ ppr e)
  pprPrec _ (Ascript e t _) = pprPrec 0 e <> colon <+> pprPrec 0 t
  pprPrec _ (Literal v _) = ppr v
  pprPrec _ (IntLit v _ _) = ppr v
  pprPrec _ (FloatLit v _ _) = ppr v
  pprPrec _ (TupLit es _)
    | any hasArrayLit es = parens $ commastack $ map ppr es
    | otherwise          = parens $ commasep $ map ppr es
  pprPrec _ (RecordLit fs _)
    | any fieldArray fs = braces $ commastack $ map ppr fs
    | otherwise                     = braces $ commasep $ map ppr fs
    where fieldArray (RecordFieldExplicit _ e _) = hasArrayLit e
          fieldArray RecordFieldImplicit{} = False
  pprPrec _ (Empty (TypeDecl t _) _ _) =
    text "empty" <> parens (ppr t)
  pprPrec _ (ArrayLit es _ _) =
    brackets $ commasep $ map ppr es
  pprPrec _ (Range start maybe_step end _ _) =
    brackets $
    ppr start <>
    maybe mempty ((text ".." <>) . ppr) maybe_step <>
    case end of
      DownToExclusive end' -> text "..>" <> ppr end'
      ToInclusive     end' -> text "..." <> ppr end'
      UpToExclusive   end' -> text "..<" <> ppr end'
  pprPrec p (BinOp bop _ (x,_) (y,_) _ _) = prettyBinOp p bop x y
  pprPrec _ (Project k e _ _) = ppr e <> text "." <> ppr k
  pprPrec _ (If c t f _ _) = text "if" <+> ppr c </>
                             text "then" <+> align (ppr t) </>
                             text "else" <+> align (ppr f)
  pprPrec p (Apply f arg _ _ _) =
    parensIf (p >= 10) $ ppr f <+> pprPrec 10 arg
  pprPrec _ (Negate e _) = text "-" <> ppr e
  pprPrec p (LetPat tparams pat e body _) =
    mparens $ align $
    text "let" <+> align (spread $ map ppr tparams ++ [ppr pat]) <+>
    (if linebreak
     then equals </> indent 2 (ppr e)
     else equals <+> align (ppr e)) <+> text "in" </>
    ppr body
    where mparens = if p == -1 then id else parens
          linebreak = case e of
                        Map{}      -> True
                        Reduce{}   -> True
                        Filter{}   -> True
                        Scan{}     -> True
                        DoLoop{}   -> True
                        LetPat{}   -> True
                        LetWith{}  -> True
                        If{}       -> True
                        ArrayLit{} -> False
                        _          -> hasArrayLit e
  pprPrec _ (LetFun fname (tparams, params, retdecl, rettype, e) body _) =
    text "let" <+> ppr fname <+> spread (map ppr tparams ++ map ppr params) <>
    retdecl' <+> equals </> indent 2 (ppr e) <+> text "in" </>
    ppr body
    where retdecl' = case (ppr <$> unAnnot rettype) `mplus` (ppr <$> retdecl) of
                       Just rettype' -> text ":" <+> rettype'
                       Nothing       -> mempty
  pprPrec _ (LetWith dest src idxs ve body _)
    | dest == src =
      text "let" <+> ppr dest <+> list (map ppr idxs) <+>
      equals <+> align (ppr ve) <+>
      text "in" </> ppr body
    | otherwise =
      text "let" <+> ppr dest <+> equals <+> ppr src <+>
      text "with" <+> brackets (commasep (map ppr idxs)) <+>
      text "<-" <+> align (ppr ve) <+>
      text "in" </> ppr body
  pprPrec _ (Update src idxs ve _) =
    ppr src <+> text "with" <+>
    brackets (commasep (map ppr idxs)) <+>
    text "<-" <+> align (ppr ve)
  pprPrec _ (Index e idxs _ _) =
    pprPrec 9 e <> brackets (commasep (map ppr idxs))
  pprPrec _ (Map lam a _ _) = ppSOAC "map" [lam] [a]
  pprPrec _ (Reduce Commutative lam e a _) = ppSOAC "reduce_comm" [lam] [e, a]
  pprPrec _ (Reduce Noncommutative lam e a _) = ppSOAC "reduce" [lam] [e, a]
  pprPrec _ (Stream form lam arr _) =
    case form of
      MapLike o ->
        let ord_str = if o == Disorder then "_per" else ""
        in  text ("stream_map"++ord_str) <>
            ppr lam </> pprPrec 10 arr
      RedLike o comm lam0 ->
        let ord_str = if o == Disorder then "_per" else ""
            comm_str = case comm of Commutative    -> "_comm"
                                    Noncommutative -> ""
        in  text ("stream_red"++ord_str++comm_str) <>
            ppr lam0 </> ppr lam </> pprPrec 10 arr
  pprPrec _ (Scan lam e a _) = ppSOAC "scan" [lam] [e, a]
  pprPrec _ (Filter lam a _) = ppSOAC "filter" [lam] [a]
  pprPrec _ (Partition k lam a _) = text "partition" <+> ppr k <+> spread (map (pprPrec 10) [lam, a])
  pprPrec _ (Zip 0 e es _ _) = text "zip" <+> spread (map (pprPrec 10) (e:es))
  pprPrec _ (Zip i e es _ _) = text "zip@" <> ppr i <+> spread (map (pprPrec 10) (e:es))
  pprPrec _ (Unzip e _ _) = text "unzip" <+> pprPrec 10 e
  pprPrec _ (Unsafe e _) = text "unsafe" <+> pprPrec 10 e
  pprPrec _ (Assert e1 e2 _ _) = text "assert" <+> pprPrec 10 e1 <+> pprPrec 10 e2
  pprPrec p (Lambda tparams params body ascript _ _) =
    parensIf (p /= -1) $
    text "\\" <> spread (map ppr tparams ++ map ppr params) <>
    ppAscription ascript <+>
    text "->" </> indent 2 (ppr body)
  pprPrec _ (OpSection binop _ _) =
    parens $ ppr binop
  pprPrec _ (OpSectionLeft binop _ x _ _ _) =
    parens $ ppr x <+> ppr binop
  pprPrec _ (OpSectionRight binop _ x _ _ _) =
    parens $ ppr binop <+> ppr x
  pprPrec _ (ProjectSection fields _ _) =
    parens $ mconcat $ map p fields
    where p name = text "." <> ppr name
  pprPrec _ (IndexSection idxs _ _) =
    parens $ text "." <> brackets (commasep (map ppr idxs))
  pprPrec _ (DoLoop tparams pat initexp form loopbody _) =
    text "loop" <+> parens (spread (map ppr tparams ++ [ppr pat]) <+> equals
                            <+> ppr initexp) <+> equals <+>
    ppr form <+> text "do" </> indent 2 (ppr loopbody)

instance (Eq vn, Pretty vn, Annot f) => Pretty (FieldBase f vn) where
  ppr (RecordFieldExplicit name e _) = ppr name <> equals <> ppr e
  ppr (RecordFieldImplicit name _ _) = ppr name

instance (Eq vn, Pretty vn, Annot f) => Pretty (LoopFormBase f vn) where
  ppr (For i ubound) =
    text "for" <+> ppr i <+> text "<" <+> align (ppr ubound)
  ppr (ForIn x e) =
    text "for" <+> ppr x <+> text "in" <+> ppr e
  ppr (While cond) =
    text "while" <+> ppr cond

instance (Eq vn, Pretty vn, Annot f) => Pretty (PatternBase f vn) where
  ppr (PatternAscription p t _) = ppr p <> text ":" <+> ppr t
  ppr (PatternParens p _)       = parens $ ppr p
  ppr (Id v t _)                = case unAnnot t of
                                    Just t' -> parens $ ppr v <> colon <+> ppr t'
                                    Nothing -> ppr v
  ppr (TuplePattern pats _)     = parens $ commasep $ map ppr pats
  ppr (RecordPattern fs _)      = braces $ commasep $ map ppField fs
    where ppField (name, t) = text (nameToString name) <> equals <> ppr t
  ppr (Wildcard t _)            = case unAnnot t of
                                    Just t' -> parens $ text "_" <> colon <+> ppr t'
                                    Nothing -> text "_"

ppAscription :: (Eq vn, Pretty vn, Annot f) => Maybe (TypeDeclBase f vn) -> Doc
ppAscription Nothing  = mempty
ppAscription (Just t) = text ":" <> ppr t

instance (Eq vn, Pretty vn, Annot f) => Pretty (ProgBase f vn) where
  ppr = stack . punctuate line . map ppr . progDecs

instance (Eq vn, Pretty vn, Annot f) => Pretty (DecBase f vn) where
  ppr (ValDec dec)       = ppr dec
  ppr (TypeDec dec)      = ppr dec
  ppr (SigDec sig)       = ppr sig
  ppr (ModDec sd)        = ppr sd
  ppr (OpenDec x xs _ _) = text "open" <+> spread (map ppr (x:xs))
  ppr (LocalDec dec _)   = text "local" <+> ppr dec

instance (Eq vn, Pretty vn, Annot f) => Pretty (ModExpBase f vn) where
  ppr (ModVar v _) = ppr v
  ppr (ModParens e _) = parens $ ppr e
  ppr (ModImport v _ _) = text "import" <+> ppr (show v)
  ppr (ModDecs ds _) = nestedBlock "{" "}" (stack $ punctuate line $ map ppr ds)
  ppr (ModApply f a _ _ _) = parens $ ppr f <+> parens (ppr a)
  ppr (ModAscript me se _ _) = ppr me <> colon <+> ppr se
  ppr (ModLambda param maybe_sig body _) =
    text "\\" <> ppr param <> maybe_sig' <+>
    text "->" </> indent 2 (ppr body)
    where maybe_sig' = case maybe_sig of Nothing       -> mempty
                                         Just (sig, _) -> colon <+> ppr sig

instance (Eq vn, Pretty vn, Annot f) => Pretty (TypeBindBase f vn) where
  ppr (TypeBind name params usertype _ _) =
    text "type" <+> ppr name <+> spread (map ppr params) <+> equals <+> ppr usertype

instance (Eq vn, Pretty vn) => Pretty (TypeParamBase vn) where
  ppr (TypeParamDim name _) = brackets $ ppr name
  ppr (TypeParamType name _) = text "'" <> ppr name
  ppr (TypeParamLiftedType name _) = text "'^" <> ppr name

instance (Eq vn, Pretty vn, Annot f) => Pretty (ValBindBase f vn) where
  ppr (ValBind entry name retdecl rettype tparams args body _ _) =
    text fun <+> ppr name <+>
    spread (map ppr tparams ++ map ppr args) <> retdecl' <> text " =" </>
    indent 2 (ppr body)
    where fun | entry     = "entry"
              | otherwise = "let"
          retdecl' = case (ppr <$> unAnnot rettype) `mplus` (ppr <$> retdecl) of
                       Just rettype' -> text ":" <+> rettype'
                       Nothing       -> mempty

instance (Eq vn, Pretty vn, Annot f) => Pretty (SpecBase f vn) where
  ppr (TypeAbbrSpec tpsig) = ppr tpsig
  ppr (TypeSpec name ps _ _) = text "type" <+> ppr name <+> spread (map ppr ps)
  ppr (ValSpec name tparams vtype _ _) =
    text "val" <+> ppr name <+> spread (map ppr tparams) <> colon <+> ppr vtype
  ppr (ModSpec name sig _ _) =
    text "module" <+> ppr name <> colon <+> ppr sig
  ppr (IncludeSpec e _) =
    text "include" <+> ppr e

instance (Eq vn, Pretty vn, Annot f) => Pretty (SigExpBase f vn) where
  ppr (SigVar v _) = ppr v
  ppr (SigParens e _) = parens $ ppr e
  ppr (SigSpecs ss _) = nestedBlock "{" "}" (stack $ punctuate line $ map ppr ss)
  ppr (SigWith s (TypeRef v td _) _) =
    ppr s <+> text "with" <+> ppr v <> text " =" <+> ppr td
  ppr (SigArrow (Just v) e1 e2 _) =
    parens (ppr v <> colon <+> ppr e1) <+> text "->" <+> ppr e2
  ppr (SigArrow Nothing e1 e2 _) =
    ppr e1 <+> text "->" <+> ppr e2

instance (Eq vn, Pretty vn, Annot f) => Pretty (SigBindBase f vn) where
  ppr (SigBind name e _ _) =
    text "module type" <+> ppr name <+> equals <+> ppr e

instance (Eq vn, Pretty vn, Annot f) => Pretty (ModParamBase f vn) where
  ppr (ModParam pname psig _ _) =
    parens (ppr pname <> colon <+> ppr psig)

instance (Eq vn, Pretty vn, Annot f) => Pretty (ModBindBase f vn) where
  ppr (ModBind name ps sig e _ _) =
    text "module" <+> ppr name <+> spread (map ppr ps) <+> sig' <> text " =" <+> ppr e
    where sig' = case sig of Nothing    -> mempty
                             Just (s,_) -> colon <+> ppr s <> text " "

prettyBinOp :: (Eq vn, Pretty vn, Annot f) =>
               Int -> QualName vn -> ExpBase f vn -> ExpBase f vn -> Doc
prettyBinOp p bop x y = parensIf (p > symPrecedence) $
                        pprPrec symPrecedence x <+/>
                        bop' <+>
                        pprPrec symRPrecedence y
  where bop' = case leading of Backtick -> text "`" <> ppr bop <> text "`"
                               _        -> ppr bop
        leading = leadingOperator $ nameFromString $ pretty $ qualLeaf bop
        symPrecedence = precedence leading
        symRPrecedence = rprecedence leading
        precedence PipeRight = -1
        precedence PipeLeft  = -1
        precedence LogAnd   = 0
        precedence LogOr    = 0
        precedence Band     = 1
        precedence Bor      = 1
        precedence Xor      = 1
        precedence Equal    = 2
        precedence NotEqual = 2
        precedence Less     = 2
        precedence Leq      = 2
        precedence Greater  = 2
        precedence Geq      = 2
        precedence ShiftL   = 3
        precedence ShiftR   = 3
        precedence ZShiftR  = 3
        precedence Plus     = 4
        precedence Minus    = 4
        precedence Times    = 5
        precedence Divide   = 5
        precedence Mod      = 5
        precedence Quot     = 5
        precedence Rem      = 5
        precedence Pow      = 6
        precedence Backtick = 9
        rprecedence Minus  = 10
        rprecedence Divide = 10
        rprecedence op     = precedence op

ppSOAC :: (Eq vn, Pretty vn, Pretty fn, Annot f) =>
          String -> [fn] -> [ExpBase f vn] -> Doc
ppSOAC name funs es =
  text name <+> align (spread (map (parens . ppr) funs) </>
                       spread (map (pprPrec 10) es))
