{-# LANGUAGE NoImplicitPrelude, OverloadedStrings, DeriveFunctor, TemplateHaskell, NamedFieldPuns, DisambiguateRecordFields #-}
module Lamdu.GUI.CodeEdit
    ( make
    , Env(..), ExportActions(..)
    , M(..), m, mLiftTrans
    ) where

import           Control.Applicative (liftA2)
import qualified Control.Lens as Lens
import           Data.CurAndPrev (CurAndPrev(..))
import           Data.Functor.Identity (Identity(..))
import qualified Data.List as List
import           Data.Orphans () -- Imported for Monoid (IO ()) instance
import           Data.Store.Transaction (Transaction)
import qualified Data.Store.Transaction as Transaction
import qualified Graphics.UI.Bottle.EventMap as E
import           Graphics.UI.Bottle.MetaKey (MetaKey)
import           Graphics.UI.Bottle.Widget (Widget)
import qualified Graphics.UI.Bottle.Widget as Widget
import qualified Graphics.UI.Bottle.Widget.Aligned as AlignedWidget
import           Graphics.UI.Bottle.Widget.TreeLayout (TreeLayout)
import qualified Graphics.UI.Bottle.Widget.TreeLayout as TreeLayout
import qualified Graphics.UI.Bottle.Widgets as BWidgets
import qualified Graphics.UI.Bottle.Widgets.Box as Box
import           Graphics.UI.Bottle.WidgetsEnvT (WidgetEnvT)
import qualified Graphics.UI.Bottle.WidgetsEnvT as WE
import qualified Lamdu.Calc.Type.Scheme as Scheme
import           Lamdu.Config (Config)
import qualified Lamdu.Config as Config
import           Lamdu.Config.Theme (Theme)
import qualified Lamdu.Config.Theme as Theme
import qualified Lamdu.Data.Anchors as Anchors
import           Lamdu.Data.Definition (Definition(..))
import qualified Lamdu.Data.Definition as Definition
import qualified Lamdu.Data.Ops as DataOps
import           Lamdu.Eval.Results (EvalResults)
import           Lamdu.Expr.IRef (DefI, ValI)
import           Lamdu.GUI.CodeEdit.Settings (Settings)
import qualified Lamdu.GUI.DefinitionEdit as DefinitionEdit
import qualified Lamdu.GUI.ExpressionEdit as ExpressionEdit
import qualified Lamdu.GUI.ExpressionEdit.EventMap as ExprEventMap
import qualified Lamdu.GUI.ExpressionGui as ExpressionGui
import           Lamdu.GUI.ExpressionGui.Monad (ExprGuiM)
import qualified Lamdu.GUI.ExpressionGui.Monad as ExprGuiM
import qualified Lamdu.GUI.ExpressionGui.Types as ExprGuiT
import qualified Lamdu.GUI.RedundantAnnotations as RedundantAnnotations
import qualified Lamdu.GUI.WidgetIds as WidgetIds
import           Lamdu.Style (Style)
import qualified Lamdu.Sugar.Convert as SugarConvert
import qualified Lamdu.Sugar.Names.Add as AddNames
import           Lamdu.Sugar.Names.Types (DefinitionN, Name)
import           Lamdu.Sugar.NearestHoles (NearestHoles)
import qualified Lamdu.Sugar.NearestHoles as NearestHoles
import qualified Lamdu.Sugar.Types as Sugar

import           Lamdu.Prelude

type T = Transaction

newtype M m a = M { _m :: IO (T m (IO (), a)) }
    deriving (Functor)
Lens.makeLenses ''M

instance Monad m => Applicative (M m) where
    pure = M . pure . pure . pure
    M f <*> M x = (liftA2 . liftA2 . liftA2) ($) f x & M

mLiftTrans :: Functor m => T m a -> M m a
mLiftTrans = M . pure . fmap pure

mLiftWidget :: Functor m => Widget (T m a) -> Widget (M m a)
mLiftWidget = Widget.events %~ mLiftTrans

data ExportActions m = ExportActions
    { exportRepl :: M m ()
    , exportAll :: M m ()
    , -- Fancy export is intended for sending code to someone who doesn't have
      -- Lamdu installed. It bundles together in a zipfile a screenshot,
      -- a README, the repl export, and compiled JS  (that requires a new
      -- version of nodejs supporting TCO).  It is intended to enable Lamdu
      -- to be used in competitions such as Google codejam which require
      -- [readable] code upload.
      exportFancy :: M m ()
    , exportDef :: DefI m -> M m ()
    , importAll :: FilePath -> M m ()
    }

data Env m = Env
    { codeProps :: Anchors.CodeProps m
    , exportActions :: ExportActions m
    , evalResults :: CurAndPrev (EvalResults (ValI m))
    , config :: Config
    , theme :: Theme
    , settings :: Settings
    , style :: Style
    }

toExprGuiMPayload :: ([Sugar.EntityId], NearestHoles) -> ExprGuiT.Payload
toExprGuiMPayload (entityIds, nearestHoles) =
    ExprGuiT.emptyPayload nearestHoles & ExprGuiT.plStoredEntityIds .~ entityIds

traverseAddNearestHoles ::
    Traversable t =>
    t (Sugar.Expression name m a) ->
    t (Sugar.Expression name m (a, NearestHoles))
traverseAddNearestHoles binder =
    binder
    <&> Lens.mapped %~ (,)
    & NearestHoles.add traverse

exprAddNearestHoles ::
    Sugar.Expression name m a ->
    Sugar.Expression name m (a, NearestHoles)
exprAddNearestHoles expr =
    Identity expr
    & traverseAddNearestHoles
    & runIdentity

postProcessExpr ::
    Sugar.Expression name m ([Sugar.EntityId], NearestHoles) ->
    Sugar.Expression name m ExprGuiT.Payload
postProcessExpr expr =
    expr
    <&> toExprGuiMPayload
    & RedundantAnnotations.markAnnotationsToDisplay

loadWorkArea :: Monad m => Env m -> T m (Sugar.WorkArea (Name m) m ExprGuiT.Payload)
loadWorkArea env =
    do
        Sugar.WorkArea { _waPanes, _waRepl } <-
            SugarConvert.loadWorkArea (evalResults env) (codeProps env)
            >>= AddNames.addToWorkArea
        Sugar.WorkArea
            (_waPanes <&> Sugar.paneDefinition %~ fmap postProcessExpr . traverseAddNearestHoles)
            (_waRepl & exprAddNearestHoles & postProcessExpr)
            & pure

makeReplEdit ::
    Monad m =>
    Env m -> ExprGuiT.SugarExpr m ->
    ExprGuiM m (TreeLayout (M m Widget.EventResult))
makeReplEdit env replExpr =
    ExpressionGui.combineSpaced
    <*> sequence
    [ ExpressionGui.makeFocusableView (Widget.joinId WidgetIds.replId ["symbol"])
      <*> ExpressionGui.makeLabel "⋙" (Widget.toAnimId WidgetIds.replId)
      <&> TreeLayout.fromAlignedWidget
    , ExprGuiM.makeSubexpressionWith 0 id replExpr
    ]
    <&> TreeLayout.widget %~
        Widget.weakerEvents (replEventMap env replExpr) . mLiftWidget
    & ExprGuiM.assignCursor WidgetIds.replId exprId
    where
        exprId = replExpr ^. Sugar.rPayload . Sugar.plEntityId & WidgetIds.fromEntityId

make ::
    Monad m =>
    Env m -> WidgetEnvT (T m) (Widget.R -> Widget (M m Widget.EventResult))
make env =
    do
        workArea <- loadWorkArea env & ExprGuiM.transaction
        replGui <- makeReplEdit env (workArea ^. Sugar.waRepl)
        panesEdits <- workArea ^. Sugar.waPanes & traverse (makePaneEdit env)
        newDefinitionButton <- makeNewDefinitionButton <&> mLiftWidget
        eventMap <- panesEventMap env & ExprGuiM.widgetEnv
        vspace <- ExpressionGui.stdVSpace
        return $ \width ->
            ExpressionGui.render width replGui ^. AlignedWidget.widget
            : (panesEdits ?? width) ++ [newDefinitionButton]
            & List.intersperse vspace
            & Box.vboxAlign 0
            & Widget.weakerEvents eventMap
    & ExprGuiM.run ExpressionEdit.make
      (codeProps env) (config env) (theme env) (settings env) (style env)

makePaneEdit ::
    Monad m =>
    Env m -> Sugar.Pane (Name m) m ExprGuiT.Payload ->
    ExprGuiM m (Widget.R -> Widget (M m Widget.EventResult))
makePaneEdit env pane =
    makePaneWidget (pane ^. Sugar.paneDefinition)
    <&> Lens.mapped %~ Widget.weakerEvents paneEventMap . mLiftWidget
    where
        delKeys = Config.delKeys (config env)
        Config.Pane{paneCloseKeys} =
            Config.pane (config env)
        Config.Export{exportKeys} = Config.export (config env)
        paneEventMap =
            [ pane ^. Sugar.paneClose & mLiftTrans
              <&> WidgetIds.fromEntityId
              & Widget.keysEventMapMovesCursor paneCloseKeys
                (E.Doc ["View", "Pane", "Close"])
            , do
                  Transaction.setP (pane ^. Sugar.paneDefinition . Sugar.drDefinitionState)
                      Sugar.DeletedDefinition
                  pane ^. Sugar.paneClose
              & mLiftTrans
              <&> WidgetIds.fromEntityId
              & Widget.keysEventMapMovesCursor delKeys
                (E.Doc ["Edit", "Definition", "Delete"])
            , exportDef (exportActions env) (pane ^. Sugar.paneDefinition . Sugar.drDefI)
              & Widget.keysEventMap exportKeys
                (E.Doc ["Collaboration", "Export definition to JSON file"])
            ] & mconcat

makeNewDefinitionEventMap ::
    Monad m =>
    Anchors.CodeProps m ->
    WidgetEnvT (T m) ([MetaKey] -> Widget.EventMap (T m Widget.EventResult))
makeNewDefinitionEventMap cp =
    do
        curCursor <- WE.readCursor
        let newDefinition =
                do
                    holeI <- DataOps.newHole
                    newDefI <-
                        Definition
                        (Definition.BodyExpr (Definition.Expr holeI mempty))
                        Scheme.any ()
                        & DataOps.newPublicDefinitionWithPane "" cp
                    DataOps.savePreJumpPosition cp curCursor
                    return newDefI
                <&> WidgetIds.nameEditOf . WidgetIds.fromIRef
        return $ \newDefinitionKeys ->
            Widget.keysEventMapMovesCursor newDefinitionKeys
            (E.Doc ["Edit", "New definition"]) newDefinition

makeNewDefinitionButton :: Monad m => ExprGuiM m (Widget (T m Widget.EventResult))
makeNewDefinitionButton =
    do
        codeAnchors <- ExprGuiM.readCodeAnchors
        newDefinitionEventMap <-
            makeNewDefinitionEventMap codeAnchors & ExprGuiM.widgetEnv

        Config.Pane{newDefinitionButtonPressKeys} <- ExprGuiM.readConfig <&> Config.pane
        Theme.Pane{newDefinitionActionColor}      <- ExprGuiM.readTheme  <&> Theme.pane

        BWidgets.makeFocusableTextView "New..." newDefinitionButtonId
            & WE.localEnv (WE.setTextColor newDefinitionActionColor)
            & ExprGuiM.widgetEnv
            <&> Widget.weakerEvents
                (newDefinitionEventMap newDefinitionButtonPressKeys)
    where
        newDefinitionButtonId = Widget.Id ["NewDefinition"]

replEventMap ::
    Monad m =>
    Env m -> Sugar.Expression name m a -> Widget.EventMap (M m Widget.EventResult)
replEventMap env replExpr =
    mconcat
    [ replExpr ^. Sugar.rPayload . Sugar.plActions . Sugar.extract
      <&> ExprEventMap.extractCursor & mLiftTrans
      & Widget.keysEventMapMovesCursor newDefinitionButtonPressKeys
        (E.Doc ["Edit", "Extract to definition"])
    , Widget.keysEventMap exportKeys
      (E.Doc ["Collaboration", "Export repl to JSON file"]) exportRepl
    , Widget.keysEventMap exportFancyKeys
      (E.Doc ["Collaboration", "Export repl for Codejam"]) exportFancy
    ]
    where
        ExportActions{exportRepl, exportFancy} = exportActions env
        Config.Export{exportKeys, exportFancyKeys} = Config.export (config env)
        Config.Pane{newDefinitionButtonPressKeys} = Config.pane (config env)

panesEventMap ::
    Monad m =>
    Env m -> WidgetEnvT (T m) (Widget.EventMap (M m Widget.EventResult))
panesEventMap Env{config,codeProps,exportActions} =
    do
        mJumpBack <- DataOps.jumpBack codeProps & lift <&> fmap mLiftTrans
        newDefinitionEventMap <- makeNewDefinitionEventMap codeProps
        return $ mconcat
            [ newDefinitionEventMap (Config.newDefinitionKeys (Config.pane config))
              <&> mLiftTrans
            , E.dropEventMap "Drag&drop JSON files"
              (E.Doc ["Collaboration", "Import JSON file"]) (Just . traverse_ importAll)
              <&> fmap (\() -> mempty)
            , maybe mempty
              (Widget.keysEventMapMovesCursor (Config.previousCursorKeys config)
               (E.Doc ["Navigation", "Go back"])) mJumpBack
            , Widget.keysEventMap exportAllKeys
              (E.Doc ["Collaboration", "Export everything to JSON file"]) exportAll
            , importAll exportPath
              & Widget.keysEventMap importKeys
                (E.Doc ["Collaboration", "Import repl from JSON file"])
            ]
    where
        ExportActions{importAll,exportAll} = exportActions
        Config.Export{exportPath,importKeys,exportAllKeys} = Config.export config

makePaneWidget ::
    Monad m =>
    DefinitionN m ExprGuiT.Payload ->
    ExprGuiM m (Widget.R -> Widget (T m Widget.EventResult))
makePaneWidget defS =
    do
        Theme.Pane{paneActiveBGColor,paneInactiveTintColor} <-
            ExprGuiM.readTheme <&> Theme.pane
        let colorizeInactivePane = Widget.tint paneInactiveTintColor
        let colorizeActivePane =
                Widget.backgroundColor WidgetIds.activePaneBackground
                paneActiveBGColor
        let colorize widget
                | Widget.isFocused widget = colorizeActivePane widget
                | otherwise = colorizeInactivePane widget
        DefinitionEdit.make defS <&> Lens.mapped %~ colorize
