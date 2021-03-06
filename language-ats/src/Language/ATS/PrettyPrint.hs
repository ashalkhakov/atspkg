{-# OPTIONS_GHC -fno-warn-orphans #-}

{-# LANGUAGE DeriveAnyClass       #-}
{-# LANGUAGE DeriveGeneric        #-}
{-# LANGUAGE FlexibleContexts     #-}
{-# LANGUAGE FlexibleInstances    #-}
{-# LANGUAGE OverloadedStrings    #-}
{-# LANGUAGE PatternSynonyms      #-}
{-# LANGUAGE StandaloneDeriving   #-}
{-# LANGUAGE TypeSynonymInstances #-}

module Language.ATS.PrettyPrint ( printATS
                                , printATSCustom
                                , printATSFast
                                ) where

import           Control.Composition          hiding ((&))
import           Control.Lens                 hiding (op, pre)
import           Data.Functor.Foldable        (cata)
import           Language.ATS.Types
import           Prelude                      hiding ((<$>))
import           Text.PrettyPrint.ANSI.Leijen hiding (bool)

infixr 5 $$

pattern NoA :: [Arg a]
pattern NoA = [NoArgs]

-- | Pretty-print with sensible defaults.
printATS :: Eq a => ATS a -> String
printATS = (<> "\n") . printATSCustom 0.6 120

printATSCustom :: Eq a
               => Float -- ^ Ribbon fraction
               -> Int -- ^ Ribbon width
               -> ATS a -> String
printATSCustom r i x = g mempty
    where g = (displayS . renderSmart r i . pretty) x

-- | Slightly faster pretty-printer without indendation (for code generation).
printATSFast :: Eq a => ATS a -> String
printATSFast x = g mempty
    where g = (displayS . renderCompact . (<> "\n") . pretty) x

instance Pretty (Name a) where
    pretty (Unqualified n)    = text n
    pretty (Qualified _ i n)  = "$" <> text n <> "." <> text i
    pretty (SpecialName _ s)  = "$" <> text s
    pretty (Functorial s s')  = text s <> "$" <> text s'
    pretty (FieldName _ n n') = text n <> "." <> text n'

instance Pretty (LambdaType a) where
    pretty Plain{}    = "=>"
    pretty Spear{}    = "=>>"
    pretty (Full _ v) = "=<" <> text v <> ">"

instance Pretty (BinOp a) where
    pretty Mult               = "*"
    pretty Add                = "+"
    pretty Div                = "/"
    pretty Sub                = "-"
    pretty GreaterThan        = ">"
    pretty LessThan           = "<"
    pretty Equal              = "="
    pretty NotEq              = "!="
    pretty LogicalAnd         = "&&"
    pretty LogicalOr          = "||"
    pretty LessThanEq         = "<="
    pretty GreaterThanEq      = ">="
    pretty StaticEq           = "=="
    pretty Mod                = "%"
    pretty Mutate             = ":="
    pretty SpearOp            = "->"
    pretty At                 = "@"
    pretty (SpecialInfix _ s) = text s

splits :: BinOp a -> Bool
splits Mult       = True
splits Add        = True
splits Div        = True
splits Sub        = True
splits LogicalAnd = True
splits LogicalOr  = True
splits _          = False

startsParens :: Doc -> Bool
startsParens d = f (show d) where
    f ('(':_) = True
    f _       = False

prettySmall :: Doc -> [Doc] -> Doc
prettySmall op es = mconcat (punctuate (" " <> op <> " ") es)

prettyBinary :: Doc -> [Doc] -> Doc
prettyBinary op es
    | length (showFast $ mconcat es) < 80 = prettySmall op es
    | otherwise = prettyLarge op es

prettyLarge :: Doc -> [Doc] -> Doc
prettyLarge _ []      = mempty
prettyLarge op (e:es) = e <$> vsep (fmap (op <+>) es)

-- FIXME we really need a monadic pretty printer lol.
lengthAlt :: Doc -> Doc -> Doc
lengthAlt d1 d2
    | length (showFast d2) >= 30 = d1 <$> indent 4 d2
    | otherwise = d1 <+> d2

prettyArgsProof :: (Pretty a) => Maybe [a] -> [Doc] -> Doc
prettyArgsProof (Just e) = prettyArgsG ("(" <> prettyArgsG mempty mempty (fmap pretty e) <+> "| ") ")"
prettyArgsProof Nothing  = prettyArgs

instance Pretty (UnOp a) where
    pretty Negate          = "~"
    pretty Deref           = "!"
    pretty (SpecialOp _ s) = text s

instance Eq a => Pretty (Expression a) where
    pretty = cata a where
        a (IfF e e' (Just e''))         = "if" <+> e <+> "then" <$> indent 2 e' <$> "else" <$> indent 2 e''
        a (IfF e e' Nothing)            = "if" <+> e <+> "then" <$> indent 2 e'
        a (LetF _ e e')          = flatAlt
            ("let" <$> indent 2 (pretty e) <$> endLet e')
            ("let" <+> pretty e <$> endLet e')
        a (UintLitF u)                  = pretty u <> "u"
        a (IntLitF i)                   = pretty i
        a (LambdaF _ lt p e)            = let pre = "lam" <+> pretty p <+> pretty lt in flatAlt (lengthAlt pre e) (pre <+> e)
        a (LinearLambdaF _ lt p e)      = let pre = "llam" <+> pretty p <+> pretty lt in flatAlt (lengthAlt pre e) (pre <+> e)
        a (FloatLitF f)                 = pretty f
        a (StringLitF s)                = text s -- FIXME escape indentation in multi-line strings.
        a (ParenExprF _ e)              = parens e
        a (UnaryF op e) = pretty op <> pretty e
        a (BinListF op@Add es)          = prettyBinary (pretty op) es
        a (BinaryF op e e')
            | splits op = e </> pretty op <+> e'
            | otherwise = e <+> pretty op <+> e'
        a (IndexF _ n e)                = pretty n <> "[" <> e <> "]"
        a (NamedValF nam)              = pretty nam
        a (CallF nam [] [] Nothing []) = pretty nam <> "()"
        a (CallF nam [] [] e xs) = pretty nam <> prettyArgsProof e xs
        a (CallF nam [] us Nothing []) = pretty nam <> prettyArgsU "{" "}" us
        a (CallF nam [] us e xs) = pretty nam <> prettyArgsU "{" "}" us <> prettyArgsProof e xs
        a (CallF nam is [] Nothing []) = pretty nam <> prettyImplicits is
        a (CallF nam is [] Nothing [x])
            | startsParens x = pretty nam <> prettyImplicits is <> pretty x
        a (CallF nam is [] e xs) = pretty nam <> prettyImplicits is <> prettyArgsProof e xs
        a (CallF nam is us e xs) = pretty nam <> prettyImplicits is <> prettyArgsU "{" "}" us <> prettyArgsProof e xs
        a (CaseF _ add' e cs)           = "case" <> pretty add' <+> e <+> "of" <$> indent 2 (prettyCases cs)
        a (IfCaseF _ cs)                = "ifcase" <$> indent 2 (prettyIfCase cs)
        a (VoidLiteralF _)              = "()"
        a (RecordValueF _ es Nothing)   = prettyRecord es
        a (RecordValueF _ es (Just x))  = prettyRecord es <+> ":" <+> pretty x
        a (PrecedeF e e')               = parens (e <+> ";" </> e')
        a (PrecedeListF es)             = lineAlt (prettyArgsList "; " "(" ")" es) ("(" <> mconcat (punctuate " ; " es) <> ")")
        a (AccessF _ e n)
            | noParens e = e <> "." <> pretty n
            | otherwise = parens e <> "." <> pretty n
        a (CharLitF '\\')              = "'\\\\'"
        a (CharLitF '\n')              = "'\\n'"
        a (CharLitF '\t')              = "'\\t'"
        a (CharLitF '\0')              = "'\\0'"
        a (CharLitF c)                 = "'" <> char c <> "'"
        a (ProofExprF _ e e')          = "(" <> e <+> "|" <+> e' <> ")"
        a (TypeSignatureF e t)         = e <+> ":" <+> pretty t
        a (WhereExpF e d)              = e <+> "where" <$> braces (" " <> nest 2 (pretty d) <> " ")
        a (TupleExF _ es)              = parens (mconcat $ punctuate ", " (reverse es))
        a (WhileF _ e e')              = "while" <> parens e <> e'
        a (ActionsF as)                = "{" <$> indent 2 (pretty as) <$> "}"
        a UnderscoreLitF{}             = "_"
        a (BeginF _ e)
            | not (startsParens e) = linebreak <> indent 2 ("begin" <$> indent 2 e <$> "end")
            | otherwise = e
        a (FixAtF _ n (StackF s as t e))  = "fix@" <+> text n <+> prettyArgs as <+> ":" <> pretty s <+> pretty t <+> "=>" <$> indent 2 (pretty e)
        a (LambdaAtF _ (StackF s as t e)) = "lam@" <+> prettyArgs as <+> ":" <> pretty s <+> pretty t <+> "=>" <$> indent 2 (pretty e)
        a (AddrAtF _ e)                   = "addr@" <> e
        a (ViewAtF _ e)                   = "view@" <> e
        a (ListLiteralF _ s t es)         = "list" <> string s <> "{" <> pretty t <> "}" <> prettyArgs es
        a (CommentExprF c e) = text c <$> e
        a (MacroVarF _ s) = ",(" <> text s <> ")"
        a BinListF{} = undefined -- Shouldn't happen
        prettyImplicits = mconcat . fmap (prettyArgsU "<" ">") . reverse
        prettyIfCase []              = mempty
        prettyIfCase [(s, l, t)]     = "|" <+> s <+> pretty l <+> t
        prettyIfCase ((s, l, t): xs) = prettyIfCase xs $$ "|" <+> s <+> pretty l <+> t
        prettyCases []              = mempty
        prettyCases [(s, l, t)]     = "|" <+> pretty s <+> pretty l <+> t
        prettyCases ((s, l, t): xs) = prettyCases xs $$ "|" <+> pretty s <+> pretty l <+> t -- FIXME can leave space with e.g. => \n begin ...

noParens :: Doc -> Bool
noParens = all (`notElem` ("()" :: String)) . show

patternHelper :: [Doc] -> Doc
patternHelper ps = mconcat (punctuate ", " (reverse ps))

instance Eq a => Pretty (Pattern a) where
    pretty = cata a where
        a (WildcardF _)                = "_"
        a (PSumF s x)                  = string s <+> x
        a (PLiteralF e)                = pretty e
        a (PNameF s [])                = pretty s
        a (PNameF s [x])               = pretty s <> parens x
        a (PNameF s ps)                = pretty s <> parens (patternHelper ps)
        a (FreeF p)                    = "~" <> p
        a (GuardedF _ e p)             = p <+> "when" <+> pretty e
        a (ProofF _ p p')              = parens (patternHelper p <+> "|" <+> patternHelper p')
        a (TuplePatternF ps)           = parens (patternHelper ps)
        a (AtPatternF _ p)             = "@" <> p
        a (UniversalPatternF _ n us p) = text n <> prettyArgsU "" "" us <> p
        a (ExistentialPatternF e p)    = pretty e <> p

argHelper :: Eq a => (Doc -> Doc -> Doc) -> Arg a -> Doc
argHelper _ (Arg (First s))   = pretty s
argHelper _ (Arg (Second t))  = pretty t
argHelper op (Arg (Both s t)) = pretty s `op` colon `op` pretty t
argHelper op (PrfArg a a')    = prettyArgs' ", " mempty mempty a </> "|" `op` pretty a'
argHelper _ NoArgs            = undefined

instance Eq a => Pretty (SortArg a) where
    pretty (SortArg n st) = text n <> ":" <+> pretty st
    pretty (Anonymous s)  = pretty s

instance Eq a => Pretty (Arg a) where
    pretty = argHelper (<+>)

squish :: BinOp a -> Bool
squish Add  = True
squish Sub  = True
squish Mult = True
squish _    = False

endLet :: Maybe Doc -> Doc
endLet Nothing  = "in end"
endLet (Just d) = "in" <$> indent 2 d <$> "end"

instance Eq a => Pretty (StaticExpression a) where
    pretty = cata a where
        a (StaticValF n)            = pretty n
        a (StaticBinaryF op se se')
            | squish op = se <> pretty op <> se'
            | otherwise = se <+> pretty op <+> se'
        a (StaticIntF i)            = pretty i
        a StaticVoidF{}             = "()"
        a (SifF e e' e'')           = "sif" <+> e <+> "then" <$> indent 2 e' <$> "else" <$> indent 2 e''
        a (SCallF n cs)             = pretty n <> parens (mconcat (punctuate "," . reverse . fmap pretty $ cs))
        a (SPrecedeF e e')          = e <> ";" <+> e'
        a (SUnaryF op e)            = pretty op <> e
        a (SLetF _ e e') = flatAlt
            ("let" <$> indent 2 (pretty e) <$> endLet e')
            ("let" <+> pretty e <$> endLet e')

instance Eq a => Pretty (Sort a) where
    pretty (T0p ad)           = "t@ype" <> pretty ad
    pretty (Vt0p ad)          = "vt@ype" <> pretty ad
    pretty (NamedSort s)      = text s
    pretty Addr               = "addr"
    pretty (View _ t)         = "view" <> pretty t
    pretty (VType _ a)        = "vtype" <> pretty a
    pretty (TupleSort _ s s') = parens (pretty s <> "," <+> pretty s')

instance Eq a => Pretty (Type a) where
    pretty = cata a where
        a (NamedF n)                       = pretty n
        a (ViewTypeF _ t)                  = "view@" <> parens t
        a (ExF e (Just t))
            | head (show t) == '['         = pretty e <> t -- FIXME this is a hack
            | otherwise                    = pretty e <+> t
        a (ExF e Nothing)                  = pretty e
        a (DependentF n@SpecialName{} [t]) = pretty n <+> pretty t
        a (DependentF n ts)                = pretty n <> parens (mconcat (punctuate ", " (fmap pretty (reverse ts))))
        a (ForAF u t)                      = pretty u <+> t
        a (UnconsumedF t)                  = "!" <> t
        a (AsProofF t (Just t'))           = t <+> ">>" <+> t'
        a (AsProofF t Nothing)             = t <+> ">> _"
        a (FromVTF t)                      = t <> "?!"
        a (MaybeValF t)                    = t <> "?"
        a (AtExprF _ t t')                 = t <+> "@" <+> pretty t'
        a (AtTypeF _ t)                    = "@" <> t
        a (ProofTypeF _ t t')              = parens (prettyArgsG "" "" t <+> "|" <+> t')
        a (ConcreteTypeF e)                = pretty e
        a (TupleF _ ts)                    = parens (mconcat (punctuate ", " (fmap pretty (reverse ts))))
        a (RefTypeF t)                     = "&" <> t
        a (FunctionTypeF s t t')           = t <+> string s <+> t'
        a (ViewLiteralF c)                 = "view" <> pretty c
        a NoneTypeF{}                      = "()"
        a ImplicitTypeF{}                  = ".."
        a (AnonymousRecordF _ rs)          = prettyRecord rs
        a (ParenTypeF _ t)                 = parens t
        a (WhereTypeF _ t i sa t')         = t <#> indent 2 ("where" </> pretty i <+> prettySortArgs sa <+> "=" <+> pretty t')

gan :: Eq a => Maybe (Sort a) -> Doc
gan (Just t) = " : " <> pretty t <> " "
gan Nothing  = ""

withHashtag :: Bool -> Doc
withHashtag True = "#["
withHashtag _    = lbracket

instance Eq a => Pretty (Existential a) where
    pretty (Existential [] b (Just st) (Just e')) = withHashtag b <> pretty st <> pretty e' <> rbracket
    pretty (Existential [] b Nothing (Just e')) = withHashtag b <> pretty e' <> rbracket
    pretty (Existential [e] b (Just st) Nothing) = withHashtag b <> text e <> ":" <> pretty st <> rbracket
    pretty (Existential bs b st Nothing) = withHashtag b <+> mconcat (punctuate ", " (fmap pretty (reverse bs))) <> gan st <+> rbracket
    pretty (Existential bs b st (Just e)) = withHashtag b <+> mconcat (punctuate ", " (fmap pretty (reverse bs))) <> gan st <> "|" <+> pretty e <+> rbracket

instance Eq a => Pretty (Universal a) where
    pretty (Universal [x] Nothing []) = lbrace <> text x <> rbrace
    pretty (Universal [x] (Just st) []) = lbrace <> text x <> ":" <> pretty st <> rbrace
    pretty (Universal bs Nothing []) = lbrace <> mconcat (punctuate "," (fmap pretty (reverse bs))) <> rbrace
    pretty (Universal bs (Just ty) []) = lbrace <+> mconcat (punctuate ", " (fmap pretty (reverse bs))) <+> ":" <+> pretty ty <+> rbrace
    pretty (Universal bs ty es) = lbrace <+> mconcat (punctuate ", " (fmap pretty (reverse bs))) <> gan ty <> "|" <+> mconcat (punctuate "; " (fmap pretty es)) <+> rbrace

instance Eq a => Pretty (ATS a) where
    pretty (ATS xs) = concatSame (reverse xs)

prettyOr :: (Pretty a, Eq a) => [[a]] -> Doc
prettyOr [] = mempty
prettyOr is = mconcat (fmap (prettyArgsU "<" ">") is)

prettyImplExpr :: Eq a => Either (StaticExpression a) (Expression a) -> Doc
prettyImplExpr (Left se) = pretty se
prettyImplExpr (Right e) = pretty e

instance Eq a => Pretty (Implementation a) where
    pretty (Implement _ [] is [] n [] e)  = pretty n <> prettyOr is <+> "() =" <$> indent 2 (prettyImplExpr e)
    pretty (Implement _ [] is [] n NoA e)  = pretty n <> prettyOr is <+> "=" <$> indent 2 (prettyImplExpr e)
    pretty (Implement _ [] is [] n ias e) = pretty n <> prettyOr is <+> prettyArgs ias <+> "=" <$> indent 2 (prettyImplExpr e)
    pretty (Implement _ [] is us n ias e) = pretty n <> prettyOr is <+> foldMap pretty us </> prettyArgs ias <+> "=" <$> indent 2 (prettyImplExpr e)
    pretty (Implement _ ps is [] n ias e) = foldMap pretty (reverse ps) </> pretty n <> prettyOr is <+> prettyArgs ias <+> "=" <$> indent 2 (prettyImplExpr e)
    pretty (Implement _ ps is us n ias e) = foldMap pretty (reverse ps) </> pretty n <> prettyOr is </> foldMap pretty us <+> prettyArgs ias <+> "=" <$> indent 2 (prettyImplExpr e)

isVal :: Declaration a -> Bool
isVal Val{}   = True
isVal Var{}   = True
isVal PrVal{} = True
isVal _       = False

glue :: Declaration a -> Declaration a -> Bool
glue x y
    | isVal x && isVal y = True
glue Stadef{} Stadef{}             = True
glue Load{} Load{}                 = True
glue Define{} Define{}             = True
glue Include{} Include{}           = True
glue ViewTypeDef{} ViewTypeDef{}   = True
glue AbsViewType{} AbsViewType{}   = True
glue AbsType{} AbsType{}           = True
glue AbsType{} AbsViewType{}       = True
glue AbsViewType{} AbsType{}       = True
glue TypeDef{} TypeDef{}           = True
glue Comment{} _                   = True
glue (Func _ Fnx{}) (Func _ And{}) = True
glue Assume{} Assume{}             = True
glue _ _                           = False

{-# INLINE glue #-}

concatSame :: Eq a => [Declaration a] -> Doc
concatSame []  = mempty
concatSame [x] = pretty x
concatSame (x:x':xs)
    | glue x x' = pretty x <$> concatSame (x':xs)
    | otherwise = pretty x <> line <$> concatSame (x':xs)

-- TODO - soft break
($$) :: Doc -> Doc -> Doc
x $$ y = align (x <$> y)

lineAlt :: Doc -> Doc -> Doc
lineAlt = group .* flatAlt

showFast :: Doc -> String
showFast d = displayS (renderCompact d) mempty

prettyRecord :: (Pretty a) => [(String, a)] -> Doc
prettyRecord es
    | any ((>40) . length . showFast . pretty) es = prettyRecordF True es
    | otherwise = lineAlt (prettyRecordF True es) (prettyRecordS True es)

prettyRecordS :: (Pretty a) => Bool -> [(String, a)] -> Doc
prettyRecordS _ []             = mempty
prettyRecordS True [(s, t)]    = "@{" <+> text s <+> "=" <+> pretty t <+> "}"
prettyRecordS _ [(s, t)]       = "@{" <+> text s <+> "=" <+> pretty t
prettyRecordS True ((s, t):xs) = prettyRecordS False xs <> "," <+> text s <+> ("=" <+> pretty t) <+> "}"
prettyRecordS x ((s, t):xs)    = prettyRecordS x xs <> "," <+> text s <+> ("=" <+> pretty t)

prettyRecordF :: (Pretty a) => Bool -> [(String, a)] -> Doc
prettyRecordF _ []             = mempty
prettyRecordF True [(s, t)]    = "@{" <+> text s <+> align ("=" <+> pretty t) <+> "}"
prettyRecordF _ [(s, t)]       = "@{" <+> text s <+> align ("=" <+> pretty t)
prettyRecordF True ((s, t):xs) = prettyRecordF False xs $$ indent 1 ("," <+> text s <+> align ("=" <+> pretty t) <$> "}")
prettyRecordF x ((s, t):xs)    = prettyRecordF x xs $$ indent 1 ("," <+> text s <+> align ("=" <+> pretty t))

prettyUsNil :: Eq a => [Universal a] -> Doc
prettyUsNil [] = space
prettyUsNil us = space <> foldMap pretty (reverse us) <> space

prettyOf :: (Pretty a) => Maybe a -> Doc
prettyOf Nothing  = mempty
prettyOf (Just x) = space <> "of" <+> pretty x

prettyDL :: Eq a => [DataPropLeaf a] -> Doc
prettyDL []                        = mempty
prettyDL [DataPropLeaf us e e']    = indent 2 ("|" <> prettyUsNil us <> pretty e <> prettyOf e')
prettyDL (DataPropLeaf us e e':xs) = prettyDL xs $$ indent 2 ("|" <> prettyUsNil us <> pretty e <> prettyOf e')

universalHelper :: Eq a => [Universal a] -> Doc
universalHelper = mconcat . fmap pretty . reverse

prettyDSL :: Eq a => [DataSortLeaf a] -> Doc
prettyDSL []                          = mempty
prettyDSL [DataSortLeaf us sr sr']    = indent 2 ("|" <> prettyUsNil us <> pretty sr <> prettyOf sr')
prettyDSL (DataSortLeaf us sr sr':xs) = prettyDSL xs $$ indent 2 ("|" <> prettyUsNil us <> pretty sr <> prettyOf sr')

prettyLeaf :: Eq a => [Leaf a] -> Doc
prettyLeaf []                         = mempty
prettyLeaf [Leaf [] s [] Nothing]     = indent 2 ("|" <+> text s)
prettyLeaf [Leaf [] s [] (Just e)]    = indent 2 ("|" <+> text s <+> "of" <+> pretty e)
prettyLeaf (Leaf [] s [] Nothing:xs)  = prettyLeaf xs $$ indent 2 ("|" <+> text s)
prettyLeaf (Leaf [] s [] (Just e):xs) = prettyLeaf xs $$ indent 2 ("|" <+> text s <+> "of" <+> pretty e)
prettyLeaf [Leaf [] s as Nothing]     = indent 2 ("|" <+> text s <> prettyArgs as)
prettyLeaf [Leaf [] s as (Just e)]    = indent 2 ("|" <+> text s <> prettyArgs as <+> "of" <+> pretty e)
prettyLeaf (Leaf [] s as Nothing:xs)  = prettyLeaf xs $$ indent 2 ("|" <+> text s <> prettyArgs as)
prettyLeaf (Leaf [] s as (Just e):xs) = prettyLeaf xs $$ indent 2 ("|" <+> text s <> prettyArgs as <+> "of" <+> pretty e)
prettyLeaf [Leaf us s [] Nothing]     = indent 2 ("|" <+> universalHelper us <+> text s)
prettyLeaf [Leaf us s [] (Just e)]    = indent 2 ("|" <+> universalHelper us <+> text s <+> "of" <+> pretty e)
prettyLeaf (Leaf us s [] Nothing:xs)  = prettyLeaf xs $$ indent 2 ("|" <+> universalHelper us <+> text s)
prettyLeaf (Leaf us s [] (Just e):xs) = prettyLeaf xs $$ indent 2 ("|" <+> universalHelper us <+> text s <+> "of" <+> pretty e)
prettyLeaf [Leaf us s as Nothing]     = indent 2 ("|" <+> universalHelper us <+> text s <> prettyArgs as)
prettyLeaf [Leaf us s as (Just e)]    = indent 2 ("|" <+> universalHelper us <+> text s <> prettyArgs as <+> "of" <+> pretty e)
prettyLeaf (Leaf us s as Nothing:xs)  = prettyLeaf xs $$ indent 2 ("|" <+> universalHelper us <+> text s <> prettyArgs as)
prettyLeaf (Leaf us s as (Just e):xs) = prettyLeaf xs $$ indent 2 ("|" <+> universalHelper us <+> text s <> prettyArgs as <+> "of" <+> pretty e)

prettyHelper :: Doc -> [Doc] -> [Doc]
prettyHelper _ [x]    = [x]
prettyHelper c (x:xs) = flatAlt (" " <> x) x : fmap (c <>) xs
prettyHelper _ x      = x

prettyBody :: Doc -> Doc -> [Doc] -> Doc
prettyBody c1 c2 [d] = c1 <> d <> c2
prettyBody c1 c2 ds  = (c1 <>) . align . indent (-1) . cat . (<> pure c2) $ ds

prettyArgsG' :: Doc -> Doc -> Doc -> [Doc] -> Doc
prettyArgsG' c3 c1 c2 = prettyBody c1 c2 . prettyHelper c3 . reverse

prettyArgsList :: Doc -> Doc -> Doc -> [Doc] -> Doc
prettyArgsList c3 c1 c2 = prettyBody c1 c2 . va . prettyHelper c3

va :: [Doc] -> [Doc]
va = (& _tail.traverse %~ group)

prettyArgsG :: Doc -> Doc -> [Doc] -> Doc
prettyArgsG = prettyArgsG' ", "

prettyArgsU :: (Pretty a) => Doc -> Doc -> [a] -> Doc
prettyArgsU = prettyArgs' ","

prettyArgs' :: (Pretty a) => Doc -> Doc -> Doc -> [a] -> Doc
prettyArgs' = fmap pretty -.*** prettyArgsG'

prettyArgs :: (Pretty a) => [a] -> Doc
prettyArgs = prettyArgs' ", " "(" ")"

prettyArgsNil :: Eq a => [Arg a] -> Doc
prettyArgsNil NoA = mempty
prettyArgsNil as  = prettyArgs' ", " "(" ")" as

fancyU :: Eq a => [Universal a] -> Doc
fancyU = foldMap pretty . reverse

(<#>) :: Doc -> Doc -> Doc
(<#>) a b = lineAlt (a <$> indent 2 b) (a <+> b)


prettySigG :: (Pretty a) => Doc -> Doc -> Maybe String -> Maybe a -> Doc
prettySigG d d' (Just si) (Just rt) = d `op` ":" <> text si <#> pretty rt <> d'
    where op a b = lineAlt (a <$> indent 2 b) (a <> b)
prettySigG _ _ _ _                  = mempty

prettySigNull :: (Pretty a) => Maybe String -> Maybe a -> Doc
prettySigNull = prettySigG space mempty

prettySig :: (Pretty a) => Maybe String -> Maybe a -> Doc
prettySig = prettySigG space space

prettyTermetric :: Pretty a => Maybe a -> Doc
prettyTermetric (Just t) = softline <> ".<" <> pretty t <> ">." <> softline
prettyTermetric Nothing  = mempty

-- FIXME figure out a nicer algorithm for when/how to split lines.
instance Eq a => Pretty (PreFunction a) where
    pretty (PreF i si [] [] as rt Nothing (Just e)) = pretty i <> prettyArgsNil as <> prettySig si rt <> "=" <$> indent 2 (pretty e)
    pretty (PreF i si [] us as rt t (Just e)) = pretty i </> fancyU us <> prettyTermetric t <> prettyArgsNil as <> prettySig si rt <> "=" <$> indent 2 (pretty e)
    pretty (PreF i si pus [] as rt Nothing (Just e)) = fancyU pus </> pretty i <> prettyArgsNil as <> prettySig si rt <> "=" <$> indent 2 (pretty e)
    pretty (PreF i si pus us as rt t (Just e)) = fancyU pus </> pretty i </> fancyU us <> prettyTermetric t <> prettyArgsNil as <> prettySig si rt <> "=" <$> indent 2 (pretty e)
    pretty (PreF i si [] [] as rt Nothing Nothing) = pretty i <> prettyArgsNil as <> prettySigNull si rt
    pretty (PreF i si [] us NoA rt Nothing Nothing) = pretty i </> fancyU us <> prettySigNull si rt
    pretty (PreF i si [] us as rt Nothing Nothing) = pretty i </> fancyU us </> prettyArgsNil as <> prettySigNull si rt
    pretty (PreF i si pus [] as rt t Nothing) = fancyU pus </> pretty i <> prettyTermetric t </> prettyArgsNil as <> prettySigNull si rt
    pretty (PreF i si pus us as rt t Nothing) = fancyU pus </> pretty i <> prettyTermetric t </> fancyU us </> prettyArgsNil as <> prettySigNull si rt

instance Eq a => Pretty (DataPropLeaf a) where
    pretty (DataPropLeaf us e Nothing)   = "|" <+> foldMap pretty (reverse us) <+> pretty e
    pretty (DataPropLeaf us e (Just e')) = "|" <+> foldMap pretty (reverse us) <+> pretty e <+> "of" <+> pretty e'

prettyFix :: (Pretty a) => Either a String -> Doc
prettyFix (Left i)  = pretty i
prettyFix (Right s) = parens (text s)

instance Eq a => Pretty (Fixity a) where
    pretty (Infix _ i)    = "infix" <+> prettyFix i
    pretty (RightFix _ i) = "infixr" <+> prettyFix i
    pretty (LeftFix _ i)  = "infixl" <+> prettyFix i
    pretty (Pre _ i)      = "prefix" <+> prettyFix i
    pretty (Post _ i)     = "postfix" <+> prettyFix i

prettyMaybeType :: (Pretty a) => Maybe a -> Doc
prettyMaybeType (Just a) = " =" <+> pretty a
prettyMaybeType _        = mempty

valSig :: (Pretty a) => Maybe a -> Doc
valSig = prettySigG mempty mempty (Just mempty)

prettySortArgs :: (Pretty a) => Maybe [a] -> Doc
prettySortArgs Nothing   = mempty
prettySortArgs (Just as) = prettyArgs' ", " "(" ")" as

instance Eq a => Pretty (Declaration a) where
    pretty (Exception s t)                  = "exception" <+> text s <+> "of" <+> pretty t
    pretty (AbsType _ s as t)               = "abstype" <+> text s <> prettySortArgs as <> prettyMaybeType t
    pretty (AbsViewType _ s as Nothing)     = "absvtype" <+> text s <> prettySortArgs as
    pretty (AbsViewType _ s as (Just t))    = "absvtype" <+> text s <> prettySortArgs as <+> "=" <+> pretty t
    pretty (SumViewType s as ls)            = "datavtype" <+> text s <> prettySortArgs as <+> "=" <$> prettyLeaf ls
    pretty (DataView _ s as ls)             = "dataview" <+> text s <> prettySortArgs as <+> "=" <$> prettyLeaf ls
    pretty (SumType s as ls)                = "datatype" <+> text s <> prettySortArgs as <+> "=" <$> prettyLeaf ls
    pretty (DataSort _ s ls)                = "datasort" <+> text s <+> "=" <$> prettyDSL ls
    pretty (Impl as i)                      = "implement" <+> prettyArgsNil as <> pretty i -- mconcat (fmap pretty us) <+> pretty i
    pretty (ProofImpl as i)                 = "primplmnt" <+> prettyArgsNil as <> pretty i
    pretty (PrVal p (Just e) Nothing)       = "prval" <+> pretty p <+> "=" <+> pretty e
    pretty (PrVal p Nothing (Just t))       = "prval" <+> pretty p <+> ":" <+> pretty t
    pretty (PrVal p (Just e) (Just t))      = "prval" <+> pretty p <+> ":" <+> pretty t <+> "=" <+> pretty e
    pretty PrVal{}                          = undefined
    pretty (AndDecl t p e)                  = "and" <+> pretty p <> valSig t <+> "=" <+> pretty e
    pretty (Val a t p e)                    = "val" <> pretty a <+> pretty p <> valSig t <+> "=" <+> pretty e
    pretty (Var t p Nothing (Just e))       = "var" <+> pretty p <> valSig t <+> "with" <+> pretty e
    pretty (Var t p (Just e) Nothing)       = "var" <+> pretty p <> valSig t <+> "=" <+> pretty e
    pretty (Var t p Nothing Nothing)        = "var" <+> pretty p <> valSig t
    pretty (Var _ _ _ Just{})               = undefined
    pretty (Include s)                      = "#include" <+> pretty s
    pretty (Load sta b Nothing s)           = bool "" "#" b <> bool "dyn" "sta" sta <> "load" <+> pretty s
    pretty (Load sta b (Just q) s)          = bool "" "#" b <> bool "dyn" "sta" sta <> "load" <+> pretty q <+> "=" <+> pretty s
    pretty (CBlock s)                       = string s
    pretty (Comment s)                      = string s
    pretty (OverloadOp _ o n (Just n'))     = "overload" <+> pretty o <+> "with" <+> pretty n <+> "of" <+> pretty n'
    pretty (OverloadOp _ o n Nothing)       = "overload" <+> pretty o <+> "with" <+> pretty n
    pretty (OverloadIdent _ i n Nothing)    = "overload" <+> text i <+> "with" <+> pretty n
    pretty (OverloadIdent _ i n (Just n'))  = "overload" <+> text i <+> "with" <+> pretty n <+> "of" <+> pretty n'
    -- We use 'text' here, which means indentation might get fucked up for
    -- C preprocessor macros, but you absolutely deserve it if you indent your
    -- macros.
    pretty (Define s)                       = text s
    pretty (Func _ (Fn pref))               = "fn" </> pretty pref
    pretty (Func _ (Fun pref))              = "fun" </> pretty pref
    pretty (Func _ (CastFn pref))           = "castfn" </> pretty pref
    pretty (Func _ (Fnx pref))              = "fnx" </> pretty pref
    pretty (Func _ (And pref))              = "and" </> pretty pref
    pretty (Func _ (Praxi pref))            = "praxi" </> pretty pref
    pretty (Func _ (PrFun pref))            = "prfun" </> pretty pref
    pretty (Func _ (PrFn pref))             = "prfn" </> pretty pref
    pretty (Extern _ d)                     = "extern" <$> pretty d
    pretty (DataProp _ s as ls)             = "dataprop" <+> text s <> prettySortArgs as <+> "=" <$> prettyDL ls
    pretty (ViewTypeDef _ s as t)           = "vtypedef" <+> text s <> prettySortArgs as <+> "=" <#> pretty t
    pretty (TypeDef _ s as t)               = "typedef" <+> text s <> prettySortArgs as <+> "=" <+> pretty t
    pretty (AbsProp _ n as)                 = "absprop" <+> text n <+> prettyArgs as
    pretty (Assume n NoA e)                 = "assume" </> pretty n <+> "=" </> pretty e
    pretty (Assume n as e)                  = "assume" </> pretty n <> prettyArgs as <+> "=" </> pretty e
    pretty (SymIntr _ ns)                   = "symintr" <+> hsep (fmap pretty ns)
    pretty (Stacst _ n t Nothing)           = "stacst" </> pretty n <+> ":" </> pretty t
    pretty (Stacst _ n t (Just e))          = "stacst" </> pretty n <+> ":" </> pretty t <+> "=" </> pretty e
    pretty (PropDef _ s as t)               = "propdef" </> text s <+> prettyArgsNil as <+> "=" </> pretty t
    pretty (Local _ (ATS ds) (ATS []))      = "local" <$> indent 2 (pretty (ATS $ reverse ds)) <$> "in end"
    pretty (Local _ d d')                   = "local" <$> indent 2 (pretty d) <$> "in" <$> indent 2 (pretty d') <$> "end"
    pretty (FixityDecl f ss)                = pretty f <+> hsep (fmap text ss)
    pretty (StaVal us i t)                  = "val" </> mconcat (fmap pretty us) <+> text i <+> ":" <+> pretty t
    pretty (Stadef i as (Right t))          = "stadef" <+> text i <+> prettySortArgs as <+> "=" <+> pretty t
    pretty (Stadef i as (Left se))          = "stadef" <+> text i <+> prettySortArgs as <+> "=" <+> pretty se
    pretty (AndD d (Stadef i as (Right t))) = pretty d <+> "and" <+> text i <+> prettySortArgs as <+> "=" <+> pretty t
    pretty (AndD d (Stadef i as (Left se))) = pretty d <+> "and" <+> text i <+> prettySortArgs as <+> "=" <+> pretty se
    pretty (AbsView _ i as t)               = "absview" <+> text i <> prettySortArgs as <> prettyMaybeType t
    pretty (AbsVT0p _ i as t)               = "absvt@ype" <+> text i <> prettySortArgs as <> prettyMaybeType t
    pretty (AbsT0p _ i Nothing t)           = "abst@ype" <+> text i <+> "=" <+> pretty t
    pretty (AbsT0p _ i as t)                = "abst@ype" <+> text i <> prettySortArgs as <> "=" <+> pretty t
    pretty (ViewDef _ s as t)               = "viewdef" <+> text s <> prettySortArgs as <+> "=" <#> pretty t
    pretty (TKind _ n s)                    = pretty n <+> "=" <+> text s
    pretty (SortDef _ s t)                  = "sortdef" <+> text s <+> "=" <+> either pretty pretty t
    pretty (AndD d (SortDef _ i t))         = pretty d <+> "and" <+> text i <+> "=" <+> either pretty pretty t
    pretty (MacDecl _ n is e)               = "macdef" <+> text n <> "(" <> mconcat (punctuate ", " (fmap text is)) <> ") =" <+> pretty e
    pretty (ExtVar _ s e)                   = "extvar" <+> text s <+> "=" <+> pretty e
    pretty AndD{}                           = undefined -- probably not valid syntax if we get to this point
