{-# LANGUAGE CPP #-}
{-# OPTIONS_GHC -Wno-orphans #-}
module Ergvein.Wallet.Settings (
    Settings(..)
  , loadSettings
  , storeSettings
  , defaultSettings
  , defaultIndexers
  , defaultIndexersNum
  , defaultIndexerTimeout
  , defaultActUrlNum
  , ExplorerUrls(..)
  , defaultExplorerUrl
  , btcDefaultExplorerUrls
  ) where

import Control.Lens hiding ((.=))
import Control.Monad.IO.Class
import Data.Aeson hiding (encodeFile)
import Data.Maybe
import Data.Text(Text, pack, unpack)
import Data.Time (NominalDiffTime)
import Data.Yaml (encodeFile)
import Network.Socket
import System.Directory
import Ergvein.Wallet.Native
import Network.DNS.Lookup
import Network.DNS.Types
import Network.DNS.Resolver
import Data.IP
import Data.Either

import Ergvein.Aeson
import Ergvein.Wallet.Util
import Ergvein.Text
import Ergvein.Wallet.Native
import Ergvein.Lens
import Ergvein.Types.Currency
import Ergvein.Wallet.Language
import Debug.Trace
import Ergvein.Wallet.Yaml(readYamlEither')

import qualified Data.Map.Strict as M
import qualified Data.Text as T

#ifdef ANDROID
import Android.HaskellActivity
import Ergvein.Wallet.Native
#endif

data ExplorerUrls = ExplorerUrls {
  testnetUrl :: !Text
, mainnetUrl :: !Text
} deriving (Eq, Show)

instance ToJSON ExplorerUrls where
  toJSON ExplorerUrls{..} = object [
      "testnetUrl"  .= toJSON testnetUrl
    , "mainnetUrl"  .= toJSON mainnetUrl
   ]

instance FromJSON ExplorerUrls where
  parseJSON = withObject "ExplorerUrls" $ \o -> do
    testnetUrl          <- o .: "testnetUrl"
    mainnetUrl          <- o .: "mainnetUrl"
    pure ExplorerUrls{..}

defaultExplorerUrl :: M.Map Currency ExplorerUrls
defaultExplorerUrl = M.fromList $ btcDefaultUrls <> ergoDefaultUrls
  where
    btcDefaultUrls  = [(BTC, btcDefaultExplorerUrls)]
    ergoDefaultUrls = [(ERGO, ExplorerUrls "" "")]

btcDefaultExplorerUrls :: ExplorerUrls
btcDefaultExplorerUrls = ExplorerUrls "https://www.blockchain.com/btc-testnet" "https://www.blockchain.com/btc"

data Settings = Settings {
  settingsLang              :: Language
, settingsStoreDir          :: Text
, settingsConfigPath        :: Text
, settingsUnits             :: Maybe Units
, settingsReqTimeout        :: NominalDiffTime
, settingsActiveAddrs       :: [Text]
, settingsDeactivatedAddrs  :: [Text]
, settingsArchivedAddrs     :: [Text]
, settingsReqUrlNum         :: (Int, Int) -- ^ First is minimum required answers. Second is sufficient amount of answers from indexers.
, settingsActUrlNum         :: Int
, settingsExplorerUrl       :: M.Map Currency ExplorerUrls
, settingsPortfolio         :: Bool
, settingsFiatCurr          :: Fiat
} deriving (Eq, Show)


makeLensesWith humbleFields ''Settings

$(deriveJSON defaultOptions ''PortNumber)
$(deriveJSON defaultOptions ''SockAddr)

instance FromJSON Settings where
  parseJSON = withObject "Settings" $ \o -> do
    settingsLang              <- o .: "lang"
    settingsStoreDir          <- o .: "storeDir"
    settingsConfigPath        <- o .: "configPath"
    settingsUnits             <- o .: "units"
    settingsReqTimeout        <- o .: "reqTimeout"
    mActiveAddrs              <- o .: "activeAddrs"
    mDeactivatedAddrs         <- o .: "deactivatedAddrs"
    mArchivedAddrs            <- o .: "archivedAddrs"
    settingsReqUrlNum         <- o .:? "reqUrlNum"  .!= defaultIndexersNum
    settingsActUrlNum         <- o .:? "actUrlNum"  .!= 10
    let (settingsActiveAddrs, settingsDeactivatedAddrs, settingsArchivedAddrs) =
          case (mActiveAddrs, mDeactivatedAddrs, mArchivedAddrs) of
            (Nothing, Nothing, Nothing) -> (defaultIndexers, [], [])
            (Just [], Just [], Just []) -> (defaultIndexers, [], [])
            _ -> (fromMaybe [] mActiveAddrs, fromMaybe [] mDeactivatedAddrs, fromMaybe [] mArchivedAddrs)
    settingsExplorerUrl       <- o .:? "explorerUrl" .!= defaultExplorerUrl
    settingsPortfolio         <- o .:? "portfolio" .!= False
    settingsFiatCurr          <- o .:? "fiatCurr"  .!= USD
    pure Settings{..}

instance ToJSON Settings where
  toJSON Settings{..} = object [
      "lang"              .= toJSON settingsLang
    , "storeDir"          .= toJSON settingsStoreDir
    , "configPath"        .= toJSON settingsConfigPath
    , "units"             .= toJSON settingsUnits
    , "reqTimeout"        .= toJSON settingsReqTimeout
    , "activeAddrs"       .= toJSON settingsActiveAddrs
    , "deactivatedAddrs"  .= toJSON settingsDeactivatedAddrs
    , "archivedAddrs"     .= toJSON settingsArchivedAddrs
    , "reqUrlNum"         .= toJSON settingsReqUrlNum
    , "actUrlNum"         .= toJSON settingsActUrlNum
    , "explorerUrl"       .= toJSON settingsExplorerUrl
    , "portfolio"         .= toJSON settingsPortfolio
    , "fiatCurr"          .= toJSON settingsFiatCurr
   ]

defaultIndexers :: [Text]
defaultIndexers = [
  "127:0:0:8667"       -- OwO
  ]

defaultIndexersNum :: (Int, Int)
defaultIndexersNum = (2, 4)

defaultIndexerTimeout :: NominalDiffTime
defaultIndexerTimeout = 20

defaultActUrlNum :: Int
defaultActUrlNum = 10

defaultSettings :: (MonadIO m) => FilePath -> m Settings
defaultSettings home = do
  let storePath   = home <> "/store"
      configPath  = home <> "/config.yaml"
  
  pure $ Settings {
        settingsLang              = English
      , settingsStoreDir          = pack storePath
      , settingsConfigPath        = pack configPath
      , settingsUnits             = Just defUnits
      , settingsReqTimeout        = defaultIndexerTimeout
      , settingsReqUrlNum         = defaultIndexersNum
      , settingsActUrlNum         = defaultActUrlNum
      , settingsExplorerUrl       = defaultExplorerUrl
      , settingsPortfolio         = False
      , settingsFiatCurr          = USD
      , settingsActiveAddrs       = defaultIndexers
      , settingsDeactivatedAddrs  = []
      , settingsArchivedAddrs     = []
      }
 
-- | TODO: Implement some checks to see if the configPath folder is ok to write to
storeSettings :: MonadIO m => Settings -> m ()
storeSettings s = liftIO $ do
  let configPath = settingsConfigPath s
  createDirectoryIfMissing True $ unpack $ T.dropEnd 1 $ fst $ T.breakOnEnd "/" configPath
  encodeFile (unpack configPath) s

dnsList :: [Domain]
dnsList = ["seed.cypra.io"]

getDNS :: [Domain] -> IO (Maybe [SockAddr])
getDNS domains = findMapMMaybe f domains
  where
    f :: Domain -> IO (Maybe [SockAddr])
    f x = do
      r <- resolve x
      pure $ if length r < 2 then Nothing else Just r
    resolve :: Domain -> IO [SockAddr]
    resolve domain = do
      rs <- makeResolvSeed defaultResolvConf
      withResolver rs $ \r -> do 
        v4 <- lookupA r domain
        v6 <- lookupAAAA r domain
        pure $ [] ++ (concat $ rights [(fmap tran4 <$> v4), (fmap tran6 <$> v6)])

    tran4 :: IPv4 -> SockAddr
    tran4 v4 = let 
      [a] = fromIntegral <$> fromIPv4 v4
      in SockAddrInet 8667 a

    tran6 :: IPv6 -> SockAddr
    tran6 v6 = let 
      [a,b,c,d] = fromIntegral <$> fromIPv6 v6
      in SockAddrInet6 8667 0 (a, b, c, d) 0
    
    findMapMMaybe :: Monad m => (a -> m (Maybe b)) -> [a] -> m (Maybe b)
    findMapMMaybe f (x:xs) = do
      r <- f x
      if isJust r then
        pure r
      else
        findMapMMaybe f xs
    findMapMMaybe f [] = pure Nothing

#ifdef ANDROID
loadSettings :: (MonadIO m, PlatformNatives) => Maybe FilePath -> m Settings
loadSettings = const $ liftIO $ do
  
  
  mpath <- getFilesDir =<< getHaskellActivity
  case mpath of
    Nothing -> fail "Ergvein panic! No local folder!"
    Just path -> do
      let configPath = path <> "/config.yaml"
      ex <- doesFileExist configPath
      cfg <- if not ex
        then defaultSettings path
        else fmap (either (const $ defaultSettings path) id) $ readYamlEither' configPath
      createDirectoryIfMissing True (unpack $ settingsStoreDir cfg)
      encodeFile (unpack $ settingsConfigPath cfg) cfg
      pure cfg

#else
mkDefSettings :: MonadIO m => m Settings
mkDefSettings = liftIO $ do
  home <- getHomeDirectory
  putStrLn   "[ WARNING ]: Failed to load config. Reverting to default values: "
  putStrLn $ "Config path: " <> home <> "/.ergvein/config.yaml"
  putStrLn $ "Store  path: " <> home <> "/.ergvein/store"
  putStrLn $ "Language   : English"
  defaultSettings (home <> "/.ergvein")

loadSettings :: MonadIO m => Maybe FilePath -> m Settings
loadSettings mpath = liftIO $ case mpath of
  Nothing -> do
    home <- getHomeDirectory
    let path = home <> "/.ergvein/config.yaml"
    putStrLn "[ WARNING ]: No path provided. Trying the default: "
    putStrLn path
    loadSettings $ Just path
  Just path -> do
    dns <- liftIO $ getDNS dnsList
    traceM "================================================"
    traceM $ show dns
    traceM $ "================================================"
    ex <- doesFileExist path
    cfg <- if not ex
      then mkDefSettings
      else either (const mkDefSettings) pure =<< readYamlEither' path
    createDirectoryIfMissing True (unpack $ settingsStoreDir cfg)
    encodeFile (unpack $ settingsConfigPath cfg) cfg
    pure cfg
#endif
