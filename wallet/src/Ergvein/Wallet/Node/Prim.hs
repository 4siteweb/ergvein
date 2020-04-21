{-
  Primary module. Holds typeclasses that all currencies must implement
-}
module Ergvein.Wallet.Node.Prim
  (
    JSON
  , CurrencyRep(..)
  , HasNode(..)
  , NodeConnection(..)
  , NodeStatus(..)
  , HostPort
  , Host
  , Port
  , nodeString
  ) where

import Data.Aeson
import Data.Serialize
import Data.Text (Text, pack)
import Data.Time (NominalDiffTime)
import Reflex
import Reflex.ExternalRef
import Servant.Client(BaseUrl(..))

import Ergvein.Text (showt)
import Ergvein.Types.Currency
import Ergvein.Types.Transaction

type JSON a = (FromJSON a, ToJSON a)

-- Type-to-value mapping
class CurrencyRep cur where
  curRep :: cur -> Currency

-- Type family for request and response
class (CurrencyRep cur) => HasNode cur where
  type NodeReq cur :: *
  type NodeResp cur :: *
  type NodeSpecific cur :: *

data NodeConnection t cur = NodeConnection {
  nodeconCurrency   :: Currency
, nodeconUrl        :: BaseUrl
, nodeconStatus     :: ExternalRef t (Maybe NodeStatus)
, nodeconOpensE     :: Event t ()
, nodeconCloseE     :: Event t ()
, nodeconCloseFire  :: IO ()
, nodeconRestart    :: IO ()
, nodeconReqFire    :: NodeReq cur -> IO ()
, nodeconRespE      :: Event t (NodeResp cur)
, nodeconExtra      :: NodeSpecific cur
, nodeconIsUp       :: Dynamic t Bool
}

data NodeStatus = NodeStatus {
  nodestatHeight :: BlockHeight
, nodestatLat    :: NominalDiffTime
} deriving (Show)

-- | Type alias for a combination of hostname and port.
type HostPort = (Host, Port)

-- | Type alias for a hostname.
type Host = String

-- | Type alias for a port number.
type Port = Int

-- | Node string for logging
nodeString :: Currency -> BaseUrl -> Text
nodeString cur BaseUrl{..} = "[" <> showt cur <> "]<" <> pack baseUrlHost <> ":" <> showt baseUrlPort <> ">: "