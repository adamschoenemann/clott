{-# LANGUAGE DeriveDataTypeable #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE OverloadedStrings #-}

module CloTT.AST.Datatype 
( module CloTT.AST.Datatype
, module CloTT.AST.Constr
) where

import Data.Data (Data, Typeable)
import Data.Text.Prettyprint.Doc

import CloTT.Annotated 
import CloTT.AST.Name
import CloTT.AST.Type
import CloTT.AST.Kind
import CloTT.AST.Constr

data Datatype a = 
  Datatype
    { dtName    :: Name
    , dtBound   :: [(Name, Kind)]
    , dtClocks  :: [Name]
    , dtConstrs :: [Constr a]
    } deriving (Show, Eq, Data, Typeable)


instance Pretty (Datatype a) where
  pretty (Datatype {dtName = nm, dtBound = b, dtClocks = clks, dtConstrs = cs}) =
    let pclks = if null clks then "" else " clocks" <+> cat (map pretty clks) <+> " "
    in  "data" <+> pretty nm <+> (sep $ map pretty b) <> pclks <> <+> "=" <+> (encloseSep "" "" " | " $ map pretty cs)

instance Unann (Datatype a) (Datatype ()) where
  unann dt@(Datatype {dtConstrs = cstrs}) =
     dt {dtConstrs = map unannConstr cstrs}

dtKind :: Datatype a -> Kind
dtKind (Datatype {dtBound = bs}) = foldr (\k acc -> k :->*: acc) Star (map snd bs)