{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE DeriveFunctor #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE DeriveTraversable #-}

module CloTT.Eval where

import Control.Monad.RWS.Strict hiding ((<>))
import Control.Monad.Except
import Control.Monad.State ()
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as M

import CloTT.AST.Name
import CloTT.Annotated
import qualified CloTT.AST.Prim as P
import CloTT.AST.Expr (Expr)
import qualified CloTT.AST.Expr as E

-- |A Value is an expression that is evaluated to normal form
data Value a
  = Prim (P.Prim)
  | Var Name
  | Closure (Env a) Name (E.Expr a)
  deriving (Show, Eq)

type Env a = Map Name (Value a)

type EvalRead a = Env a
type EvalWrite = ()
type EvalState = ()

data EvalErr = Other String
  deriving (Show, Eq)

newtype EvalM a r = Eval { unEvalM :: ExceptT EvalErr (RWS (EvalRead a) EvalWrite EvalState) r }
  deriving ( Functor
           , Applicative
           , Monad
           , MonadError  EvalErr 
           , MonadState  EvalState
           , MonadWriter EvalWrite 
           , MonadReader (EvalRead a)
           )

type EvalMRes r = Either EvalErr r

runEvalM :: EvalM a r -> (EvalRead a) -> EvalMRes r
runEvalM tm r = let (x, _, _) = runRWS (runExceptT (unEvalM tm)) r () in x

getEnv :: EvalM a (Env a)
getEnv = ask

evalExpr :: Expr a -> EvalM a (Value a)
evalExpr (A _ expr') = 
  case expr' of
    E.Prim p -> pure (Prim p)
    E.Var nm ->
      M.lookup nm <$> getEnv >>= \case
        Just v -> pure v
        Nothing -> throwError (Other $ "Cannot lookup" ++ show nm)

    E.Lam x _mty e -> do
      env <- getEnv
      pure (Closure env x e)