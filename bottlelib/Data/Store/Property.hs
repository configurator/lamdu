{-# LANGUAGE TemplateHaskell, Rank2Types #-}
module Data.Store.Property
    ( Property(..), pVal, pSet, value, set
    , compose, pureCompose, composeLens
    , modify_, pureModify
    ) where

import           Control.Lens (Lens')
import qualified Control.Lens as Lens
import           Control.Lens.Operators
import           Control.Monad ((<=<))

data Property m a = Property
    { _pVal :: a
    , _pSet :: a -> m ()
    }
Lens.makeLenses ''Property

value :: Property m a -> a
value = (^. pVal)

set :: Property m a -> a -> m ()
set = (^. pSet)

modify_ :: Monad m => Property m a -> (a -> m a) -> m ()
modify_ (Property val setter) f = setter =<< f val

pureModify :: Monad m => Property m a -> (a -> a) -> m ()
pureModify prop = modify_ prop . (return .)

compose ::
    Monad m => (a -> b) -> (b -> m a) ->
    Property m a -> Property m b
compose aToB bToA (Property val setter) =
    Property (aToB val) (setter <=< bToA)

pureCompose ::
    Monad m => (a -> b) -> (b -> a) -> Property m a -> Property m b
pureCompose ab ba = compose ab (return . ba)

composeLens :: Lens' a b -> Property m a -> Property m b
composeLens lens (Property val setter) =
    Property (val ^. lens) (setter . flip (lens .~) val)
