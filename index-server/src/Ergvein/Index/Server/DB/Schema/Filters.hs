{-# LANGUAGE DeriveAnyClass #-}
module Ergvein.Index.Server.DB.Schema.Filters
  (
    ScannedHeightRecKey(..)
  , ScannedHeightRec(..)
  , TxRecKey(..)
  , TxRec(..)
  , BlockMetaRecKey(..)
  , BlockMetaRec(..)
  , scannedHeightTxKey
  , txRecKey
  , metaRecKey
  , unPrefixedKey
  , schemaVersionRecKey
  , schemaVersion
  ) where

import Crypto.Hash.SHA256
import Data.ByteString (ByteString)
import Data.FileEmbed
import Data.Flat
import Data.Serialize (Serialize)
import Data.Word

import Ergvein.Index.Server.DB.Utils
import Ergvein.Types.Block
import Ergvein.Types.Currency
import Ergvein.Types.Transaction

import qualified Data.ByteString as BS
import qualified Data.Serialize as S

data KeyPrefix = ScannedHeight | Meta | Tx | SchemaVersion deriving Enum

schemaVersion :: ByteString
schemaVersion = hash $(embedFile "src/Ergvein/Index/Server/DB/Schema/Filters.hs")

keyString :: (Serialize k) => KeyPrefix -> k -> ByteString
keyString keyPrefix key = (fromIntegral $ fromEnum keyPrefix) `BS.cons` S.encode key

--ScannedHeight

scannedHeightTxKey :: Currency -> ByteString
scannedHeightTxKey = keyString ScannedHeight . ScannedHeightRecKey

data ScannedHeightRecKey = ScannedHeightRecKey
  { scannedHeightRecKey      :: Currency
  } deriving (Generic, Show, Eq, Ord, Serialize)

data ScannedHeightRec = ScannedHeightRec
  { scannedHeightRecHeight   :: BlockHeight
  } deriving (Generic, Show, Eq, Ord, Flat)


--Tx

txRecKey:: TxHash -> ByteString
txRecKey = keyString Tx . TxRecKey

data TxRecKey = TxRecKey
  { txRecKeyHash      :: TxHash
  } deriving (Generic, Show, Eq, Ord, Serialize)

data TxRec = TxRec
  { txRecHash         :: TxHash
  , txRecHexView      :: TxHexView
  , txRecUnspentOutputsCount :: Word32
  } deriving (Generic, Show, Eq, Ord, Flat)

--BlockMeta

metaRecKey :: (Currency, BlockHeight) -> ByteString
metaRecKey = keyString Meta . uncurry BlockMetaRecKey

data BlockMetaRecKey = BlockMetaRecKey
  { blockMetaRecKeyCurrency     :: Currency
  , blockMetaRecKeyBlockHeight  :: BlockHeight
  } deriving (Generic, Show, Eq, Ord, Serialize)

data BlockMetaRec = BlockMetaRec
  { blockMetaRecHeaderHashHexView  :: BlockHeaderHashHexView
  , blockMetaRecAddressFilterHexView :: AddressFilterHexView
  } deriving (Generic, Show, Eq, Ord, Flat)

--SchemaVersion

schemaVersionRecKey :: ByteString
schemaVersionRecKey  = keyString SchemaVersion $ mempty @String

data SchemaVersionRec = Text  deriving (Generic, Show, Eq, Ord, Flat)
