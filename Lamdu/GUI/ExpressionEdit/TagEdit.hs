{-# LANGUAGE OverloadedStrings #-}
module Lamdu.GUI.ExpressionEdit.TagEdit(make, makeView) where

import Control.Applicative ((<$>))
import Control.Lens.Operators
import Control.MonadA (MonadA)
import Graphics.UI.Bottle.Animation (AnimId)
import Lamdu.Config (Config)
import Lamdu.GUI.ExpressionGui (ExpressionGui)
import Lamdu.GUI.ExpressionGui.Monad (ExprGuiM)
import Lamdu.GUI.ExpressionGui.Types (WidgetT)
import qualified Graphics.UI.Bottle.EventMap as E
import qualified Graphics.UI.Bottle.Widget as Widget
import qualified Graphics.UI.Bottle.Widgets.FocusDelegator as FocusDelegator
import qualified Lamdu.Config as Config
import qualified Lamdu.GUI.ExpressionGui as ExpressionGui
import qualified Lamdu.GUI.ExpressionGui.Monad as ExprGuiM
import qualified Lamdu.GUI.WidgetEnvT as WE
import qualified Lamdu.Sugar.Types as Sugar

fdConfig :: FocusDelegator.Config
fdConfig = FocusDelegator.Config
  { FocusDelegator.startDelegatingKeys = [E.ModKey E.noMods E.Key'Enter]
  , FocusDelegator.startDelegatingDoc = E.Doc ["Edit", "Rename tag"]
  , FocusDelegator.stopDelegatingKeys = [E.ModKey E.noMods E.Key'Escape]
  , FocusDelegator.stopDelegatingDoc = E.Doc ["Edit", "Stop renaming tag"]
  }

onTagWidget :: Config -> WidgetT m -> WidgetT m
onTagWidget config =
  Widget.scale (realToFrac <$> Config.tagScaleFactor config) .
  Widget.tint (Config.fieldTint config)

make ::
  MonadA m => Sugar.TagG Sugar.Name m -> Widget.Id -> ExprGuiM m (ExpressionGui m)
make t myId = do
  config <- ExprGuiM.widgetEnv WE.readConfig
  ExpressionGui.fromValueWidget <$>
    ExprGuiM.wrapDelegated fdConfig FocusDelegator.NotDelegating id
    ( fmap (onTagWidget config)
    . ExpressionGui.makeNameEdit (t ^. Sugar.tagGName)
    ) myId

makeView ::
  MonadA m => Sugar.TagG Sugar.Name m -> AnimId -> ExprGuiM m (ExpressionGui m)
makeView t animId = do
  config <- ExprGuiM.widgetEnv WE.readConfig
  fmap ExpressionGui.fromValueWidget .
    ExprGuiM.widgetEnv . fmap (onTagWidget config) $
    ExpressionGui.makeNameView (t ^. Sugar.tagGName . Sugar.npName) animId
