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
import Data.Text.Prettyprint.Doc 
import Control.Applicative

import CloTT.AST.Name
import CloTT.Annotated
import CloTT.Pretty
import qualified CloTT.AST.Prim as P
import           CloTT.AST.Expr (Expr)
import qualified CloTT.AST.Expr as E
import           CloTT.AST.Pat (Pat)
import qualified CloTT.AST.Pat  as E

data PrimVal
  = IntVal Integer
  deriving (Eq)

instance Pretty PrimVal where
  pretty (IntVal i) = pretty i

instance Show PrimVal where show = show . pretty

-- |A Value is an expression that is evaluated to normal form
data Value a
  = Prim PrimVal
  | Var Name
  | TickVar Name
  | Closure (Env a) Name (E.Expr a)
  | TickClosure (Env a) Name (E.Expr a)
  | Tuple [Value a]
  | Constr Name [Value a]
  deriving (Eq)

instance Pretty (Value a) where
  pretty = \case
    Prim p -> pretty p
    Var nm  -> pretty nm
    TickVar nm  -> pretty nm
    Closure _ n e -> "\\" <> pretty e <+> "->" <+> pretty e
    TickClosure _ n e -> "\\\\" <> pretty e <+> "->" <+> pretty e
    Tuple vs -> tupled (map pretty vs)
    Constr nm [] -> pretty nm
    Constr nm vs -> parens $ pretty nm <+> sep (map pretty vs)

instance Show (Value a) where
  show = show . pretty

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

instance Alternative (EvalM a) where 
  empty = otherErr "Alternative.empty for EvalM"
  x <|> y = x `catchError` \e -> y


runEvalM :: EvalM a r -> (EvalRead a) -> EvalMRes r
runEvalM tm r = let (x, _, _) = runRWS (runExceptT (unEvalM tm)) r () in x

getEnv :: EvalM a (Env a)
getEnv = ask

withEnv :: (EvalRead a -> EvalRead a) -> EvalM a r -> EvalM a r
withEnv = local

extend :: Name -> Value a -> Env a -> Env a
extend k v = M.insert k v

otherErr :: String -> EvalM a r
otherErr = throwError . Other

evalPat :: Pat a -> Value a -> EvalM a (Env a)
evalPat (A _ p) v =
  case p of
    E.Bind nm -> extend nm v <$> getEnv
    E.PTuple ps -> 
      case v of
        Tuple vs -> M.unions <$> sequence (map (uncurry evalPat) $ zip ps vs)
        _        -> otherErr $ "Tuple pattern failed"
    E.Match nm ps ->
      case v of 
        Constr nm' vs | nm == nm' -> M.unions <$> sequence (map (uncurry evalPat) $ zip ps vs)
        _        -> otherErr $ "Constructor pattern failed"

evalClause :: Value a -> (Pat a, Expr a) -> EvalM a (Value a)
evalClause val (p, e) = do
  env' <- evalPat p val
  withEnv (const env') $ evalExpr e

evalPrim :: P.Prim -> EvalM a (Value a)
evalPrim = \case
  P.Unit             -> otherErr $ "Unit            "
  P.Nat i            -> pure . Prim . IntVal $ i
  P.Fold             -> otherErr $ "Fold            "
  P.Unfold           -> otherErr $ "Unfold          "
  P.PrimRec          -> otherErr $ "PrimRec         "
  P.Tick             -> otherErr $ "Tick            "
  P.Fix              -> otherErr $ "Fix             "
  P.Undefined        -> otherErr $ "Undefined!"

evalExpr :: Expr a -> EvalM a (Value a)
evalExpr (A _ expr') = 
  case expr' of
    E.Prim p -> evalPrim p
    E.Var nm ->
      M.lookup nm <$> getEnv >>= \case
        Just v -> pure v
        Nothing -> otherErr ("Cannot lookup" ++ show nm)
    
    E.TickVar nm -> pure $ TickVar nm

    E.Lam x _mty e -> do
      env <- getEnv
      pure (Closure env x e)

    E.TickAbs x k e -> do
      env <- getEnv
      pure (TickClosure env x e)
    
    E.App e1 e2 -> do
      v1 <- evalExpr e1
      case v1 of 
        Closure cenv nm e1' -> do
          v2 <- evalExpr e2
          env <- getEnv
          let env' = extend nm v2 env
          withEnv (const (cenv `M.union` env')) $ evalExpr e1'
        Constr nm args -> do
          v2 <- evalExpr e2
          pure $ Constr nm (args ++ [v2])
        _ -> throwError (Other $ "Expected" ++ show v1 ++ "to be a lambda")
    
    E.Ann e t -> evalExpr e

    E.Tuple ts -> Tuple <$> sequence (map evalExpr ts) 

    E.Let p e1 e2 -> do
      v1 <- evalExpr e1
      env' <- evalPat p v1
      withEnv (const env') $ evalExpr e2
    
    E.Case e1 cs -> do
      v1 <- evalExpr e1
      foldr1 (<|>) $ map (evalClause v1) cs

    E.TypeApp e t -> evalExpr e

