{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE DeriveFunctor #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE DeriveTraversable #-}
{-# LANGUAGE TypeSynonymInstances #-}
{-# LANGUAGE FlexibleInstances #-}

module CloTT.Eval.EvalM where

import Control.Monad.RWS.Strict hiding ((<>))
import Control.Monad.Except
import Control.Monad.State ()
import Data.Text.Prettyprint.Doc 
import Control.Applicative

import CloTT.Eval.Value
import CloTT.AST.Name

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

instance Alternative (EvalM a) where 
  empty = otherErr "Alternative.empty for EvalM"
  x <|> y = x `catchError` \e -> y


runEvalM :: EvalM a r -> (EvalRead a) -> EvalMRes r
runEvalM tm r = let (x, _, _) = runRWS (runExceptT (unEvalM tm)) r () in x

getEnv :: EvalM a (Env a)
getEnv = ask

withEnv :: (EvalRead a -> EvalRead a) -> EvalM a r -> EvalM a r
withEnv = local


lookupVar :: Name -> EvalM a (Value a)
lookupVar nm = 
  envLookup nm <$> getEnv >>= \case
    Just v -> pure v
    Nothing -> do 
      env <- getEnv
      otherErr $ show $ "Cannot lookup" <+> pretty nm <+> "in env" <+> pretty env

otherErr :: String -> EvalM a r
otherErr = throwError . Other