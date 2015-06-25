module Lamdu.Sugar.Convert.Inject
    ( convert
    ) where

import           Control.Applicative (Applicative(..), (<$>))
import qualified Control.Lens as Lens
import           Control.Lens.Operators
import           Control.MonadA (MonadA)
import           Data.Monoid (Monoid(..))
import qualified Data.Store.Property as Property
import           Data.Traversable (traverse)
import qualified Lamdu.Expr.UniqueId as UniqueId
import           Lamdu.Expr.Val (Val)
import qualified Lamdu.Expr.Val as V
import           Lamdu.Sugar.Convert.Expression.Actions (addActions)
import qualified Lamdu.Sugar.Convert.Input as Input
import           Lamdu.Sugar.Convert.Monad (ConvertM)
import qualified Lamdu.Sugar.Convert.Monad as ConvertM
import           Lamdu.Sugar.Internal
import qualified Lamdu.Sugar.Internal.EntityId as EntityId
import           Lamdu.Sugar.Types

convert :: (MonadA m, Monoid a) => V.Inject (Val (Input.Payload m a)) -> Input.Payload m a -> ConvertM m (ExpressionU m a)
convert (V.Inject tag val) exprPl =
    do
        protectedSetToVal <- ConvertM.typeProtectedSetToVal
        -- TODO: Lots of duplication here from getField, generalize both!
        Inject
            { _iVal = val
            , _iTag =
                TagG
                { _tagInstance = EntityId.ofInjectTag entityId
                , _tagVal = tag
                , _tagGName = UniqueId.toGuid tag
                }
            , _iMDeleteInject =
                protectedSetToVal
                <$> exprPl ^. Input.mStored
                <*> ( val ^. V.payload . Input.mStored
                    <&> Property.value
                    )
                <&> Lens.mapped %~ EntityId.ofValI
            }
            & traverse ConvertM.convertSubexpression
            <&> BodyInject
            >>= addActions exprPl
    where
        entityId = exprPl ^. Input.entityId
