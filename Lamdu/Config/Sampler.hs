{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE NoImplicitPrelude, DeriveFunctor, DeriveFoldable, DeriveTraversable #-}
module Lamdu.Config.Sampler
    ( Sampler, new
    , Sample(..), sConfigPath, sConfig, sThemePath, sTheme
    , getSample, onEachSample, setTheme
    ) where

import           Control.Concurrent (threadDelay, ThreadId)
import           Control.Concurrent.MVar
import           Control.Concurrent.Utils (forkIOUnmasked)
import qualified Control.Exception as E
import qualified Control.Lens as Lens
import qualified Data.Aeson as Aeson
import qualified Data.ByteString.Lazy as LBS
import qualified Data.Text as Text
import           Data.Time.Clock (UTCTime)
import           Lamdu.Config (Config)
import           Lamdu.Config.Theme (Theme)
import qualified Lamdu.DataFile as DataFile
import           System.Directory (getModificationTime)
import           System.FilePath (takeDirectory, takeFileName, dropExtension, (</>))

import           Lamdu.Prelude

type ModificationTime = UTCTime

-- TODO: FRP-style sampling of (mtime, file content) of the config
-- file, then map over that to Config

data Sample = Sample
    { sVersion :: [ModificationTime]
    , _sConfigPath :: FilePath
    , _sConfig :: Config
    , _sThemePath :: FilePath
    , _sTheme :: Theme
    } deriving (Eq)
Lens.makeLenses ''Sample

data Sampler = Sampler
    { _sThreadId :: ThreadId
    , getSample :: IO Sample
    , setTheme :: Text -> IO ()
    }

onEachSample :: (Sample -> IO Sample) -> Sampler -> Sampler
onEachSample act (Sampler t get setT) = Sampler t (get >>= act) setT

withMTime :: FilePath -> IO (Config, FilePath, Theme) -> IO Sample
withMTime configPath act =
    do
        (config, themePath, theme) <- act
        mtimesAfter <- traverse getModificationTime [configPath, themePath]
        Sample mtimesAfter configPath config themePath theme & return

calcThemePath :: FilePath -> Text -> FilePath
calcThemePath configPath theme =
    takeDirectory configPath </> "themes" </>
    Text.unpack theme ++ ".json"

load :: Text -> FilePath -> IO Sample
load themeName configPath =
    do
        config <- readJson configPath
        theme <- readJson themePath
        return (config, themePath, theme)
    & withMTime configPath
    where
        readJson path =
            Aeson.eitherDecode' <$> LBS.readFile path
            >>= either (fail . (msg path ++)) return
        msg path = "Failed to parse config file contents at " ++ show path ++ ": "
        themePath = calcThemePath configPath themeName

maybeReload :: Sample -> FilePath -> IO Sample
maybeReload old newConfigPath =
    do
        mtime <-
            traverse getModificationTime [old ^. sConfigPath, old ^. sThemePath]
        if mtime == sVersion old
            then return old
            else load theme newConfigPath
    where
        theme = old ^. sThemePath & takeFileName & dropExtension & Text.pack

new :: Text -> IO Sampler
new initialTheme =
    do
        ref <-
            getConfigPath
            >>= load initialTheme
            >>= E.evaluate
            >>= newMVar
        tid <-
            forkIOUnmasked . forever $
            do
                threadDelay 300000
                modifyMVar_ ref $ \old ->
                    (getConfigPath >>= maybeReload old)
                    `E.catch` \E.SomeException {} -> return old
        return Sampler
            { _sThreadId = tid
            , getSample = readMVar ref
            , setTheme =
                \theme ->
                takeMVar ref
                >> getConfigPath
                >>= load theme
                >>= E.evaluate
                >>= putMVar ref
            }
    where
        getConfigPath = DataFile.getPath "config.json"
