{-# LANGUAGE OverloadedStrings #-}

import Lamdu.Eval

import Control.Lens
import Control.Monad.Trans.Either (EitherT(..))
import Control.Monad.Trans.State (evalStateT)
import Control.Monad.Writer
import Lamdu.Data.Definition
import qualified Data.Map as Map
import qualified Lamdu.Expr.Pure as P

test :: (Either String (ValHead ()), [Event ()])
test =
    expr
    & ScopedVal emptyScope
    & whnfScopedVal
    & runEvalT
    & runEitherT
    & (`evalStateT` initialState actions)
    & runWriter
    where
        expr = P.app (P.global "f") (P.global "v")
        actions =
            EvalActions
            { _aReportEvent = tell . (:[])
            , _aRunBuiltin = runBuiltin
            , _aLoadGlobal = return . (`Map.lookup` globals)
            }
        globals =
            Map.fromList
            [ ("f", Right $ P.abs "r" $ P.getField (P.var "r") "y")
            , ("g", Right $ P.app (P.global "negate") $ P.litInt 3)
            , ("negate", Left $ FFIName ["Prelude"] "negate")
            , ( "v"
              , Right $
                P.recExtend "x" (P.litInt 5) $
                P.recExtend "y" (P.global "g") P.recEmpty
              )
            ]
        runBuiltin (FFIName _ name) argThunk
            | name == "negate" =
                do
                    arg <- whnfThunk argThunk
                    case arg of
                        HLiteralInteger i -> return $ HLiteralInteger $ negate i
                        _ -> evalError $ "negate expected integer not " ++ show arg
            | otherwise = evalError "Builtin not implemented"