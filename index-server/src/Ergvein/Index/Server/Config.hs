module Ergvein.Index.Server.Config where

import Prelude
import Control.Monad.IO.Class
import Data.Text 
import Data.Yaml.Config
import Ergvein.Aeson
import GHC.Generics

data Config = Config 
  { configServerPort :: !Int
  , configDbHost     :: !String
  , configDbPort     :: !Int
  , configDbUser     :: !String
  , configDbPassword :: !String
  , configDbName     :: !String
  } deriving (Show, Generic)
deriveJSON (aesonOptionsStripPrefix "config") ''Config

connectionStringFromConfig :: Config -> String
connectionStringFromConfig cfg = let
  params = [ ("host", configDbHost)
           , ("port", show . configDbPort)
           , ("user", configDbUser)
           , ("password", configDbPassword)
           , ("dbname", configDbName)
           ] 
  in unpack $ intercalate " " $ segment <$> params
  where
    segment (label, accessor) = mconcat [label, "=", pack $ accessor cfg]

loadConfig :: MonadIO m => FilePath -> m Config
loadConfig path = liftIO $ loadYamlSettings [path] [] useEnv