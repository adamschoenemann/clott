{-# LANGUAGE DataKinds #-}

module CloFRP.Parser.Type where

import Text.Parsec.Pos
import Text.Parsec
import Data.Foldable (foldrM)

import qualified CloFRP.Annotated  as A
import qualified CloFRP.AST as E
import           CloFRP.Parser.Lang
import           CloFRP.AST.Name

type Type = E.Type SourcePos E.Poly

free :: Parser Type
free = ann <*> (E.TFree . UName <$> uidentifier) <?> "free"

tvar :: Parser Type
tvar = ann <*> (E.TVar . UName <$> lidentifier) <?> "tvar"

arr :: Parser (Type -> Type -> Type)
arr = pure (\p a b -> A.A p $ a E.:->: b) <*> getPosition <?> "arr"

kind :: Parser E.Kind
kind = buildExpressionParser table kindexpr where
  table = [[binary' "->" karr AssocRight]]
  karr = pure (E.:->*:)
  kindexpr = symbol "*" *> pure E.Star <|> reserved "Clock" *> pure E.ClockK

boundp :: Parser (Name, E.Kind)
boundp = (\n -> (UName n, E.Star)) <$> lidentifier 
     <|> parens ((\n k -> (UName n, k)) <$> lidentifier <* reservedOp ":" <*> kind)

forAll :: Parser Type
forAll = p <?> "forall" where
  p = do
    nms <- reserved "forall" *> (many1 boundp) <* reservedOp "."
    ty <- typep
    foldrM fn ty nms
  fn (nm,k) t = ann <*> pure (E.Forall nm k t) 

recTy :: Parser Type
recTy = (ann <*> p) <?> "Fix" where
  p = E.RecTy <$> (reserved "Fix" *> typeexpr)

ttuple :: Parser Type
ttuple = ann <*> (E.TTuple <$> parens (typep `sepBy2` comma))


typeexpr :: Parser Type
typeexpr = tvar <|> free <|> forAll <|> recTy <|> try (ttuple) <|> parens typep

typep :: Parser Type
typep = buildExpressionParser table typeexpr where
  table = 
    [ [Infix spacef AssocLeft, Prefix later]
    , [binary' "->" arr AssocRight]
    ]

  spacef :: Parser (Type -> Type -> Type)
  spacef =
    ws *> notFollowedBy (choice . map reservedOp $ opNames) *> app
       <?> "space application"

  app :: Parser (Type -> Type -> Type)
  app = fn <$> getPosition where
    fn p t1 t2 = A.A p $ E.TApp t1 t2

  later :: Parser (Type -> Type)
  later = do
    p <- getPosition
    k <- string "|>" *> (A.A p . E.TVar . UName <$> lidentifier)
    pure (\t -> A.A p $ E.Later k t)
