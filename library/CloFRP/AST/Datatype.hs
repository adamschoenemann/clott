{-# LANGUAGE DeriveDataTypeable #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE OverloadedStrings #-}

module CloFRP.AST.Datatype 
( module CloFRP.AST.Datatype
, module CloFRP.AST.Constr
) where

import Data.Data (Data, Typeable)
import Data.Text.Prettyprint.Doc

import CloFRP.Annotated 
import CloFRP.AST.Name
import CloFRP.AST.Kind
import CloFRP.AST.Constr

data Datatype a = 
  Datatype
    { dtName    :: Name
    , dtExtern  :: Bool
    , dtBound   :: [(Name, Kind)]
    , dtConstrs :: [Constr a]
    , dtDeriving :: [String]
    } deriving (Show, Eq, Data, Typeable)


instance Pretty (Datatype a) where
  pretty (Datatype {dtName = nm, dtExtern = ex, dtBound = b, dtConstrs = cs, dtDeriving = ds}) =
     extern <> "data" <+> pretty nm <+> (sep $ map pretty b) <+> "=" <+> (encloseSep "" "" " | " $ map pretty cs)
     <> line <> "deriving" <+> tupled (map pretty ds)
     where
       extern = if ex then "extern " else ""

instance Unann (Datatype a) (Datatype ()) where
  unann dt@(Datatype {dtConstrs = cstrs}) =
     dt {dtConstrs = map unannConstr cstrs}

dtKind :: Datatype a -> Kind
dtKind (Datatype {dtBound = bs}) = foldr (\k acc -> k :->*: acc) Star (map snd bs)