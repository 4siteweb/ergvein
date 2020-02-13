module Ergvein.Wallet.Storage.Data
  (
    PrivateStorage(..)
  , EncryptedPrivateStorage(..)
  , EgvPrvKeyсhain(..)
  , EgvPubKeyсhain(..)
  , ErgveinStorage(..)
  , EncryptedErgveinStorage(..)
  ) where

import Data.Aeson
import Data.ByteArray (convert, Bytes)
import Data.ByteString (ByteString)
import Data.Proxy
import Data.Sequence
import Data.Text
import Ergvein.Aeson
import Ergvein.Crypto

import qualified Data.ByteString.Base64   as B64
import qualified Data.IntMap.Strict       as MI
import qualified Data.Map.Strict          as M
import qualified Data.Text.Encoding.Error as TEE
import qualified Data.Text.Encoding       as TE

byteStringToText :: ByteString -> Text
byteStringToText bs = TE.decodeUtf8With TEE.lenientDecode $ B64.encode bs

textToByteString :: Text -> ByteString
textToByteString = B64.decodeLenient . TE.encodeUtf8

data EgvPrvKeyсhain = EgvPrvKeyсhain {
  egvPrvKeyсhain'master   :: EgvXPrvKey
  -- ^BIP44 private key with derivation path /m\/purpose'\/coin_type'\/account'/.
, egvPrvKeyсhain'external :: MI.IntMap EgvXPrvKey
  -- ^Map with BIP44 external private keys.
  -- Private key indices are map keys, and the private keys are map values.
  -- This private keys must have the following derivation path:
  -- /m\/purpose'\/coin_type'\/account'\/0\/address_index/.
, egvPrvKeyсhain'internal :: MI.IntMap EgvXPrvKey
  -- ^Map with BIP44 internal private keys.
  -- Private key indices are map keys, and the private keys are map values.
  -- This private keys must have the following derivation path:
  -- /m\/purpose'\/coin_type'\/account'\/1\/address_index/.
} deriving (Eq)

$(deriveJSON aesonOptionsStripToApostroph ''EgvPrvKeyсhain)

data EgvPubKeyсhain = EgvPubKeyсhain {
  egvPubKeyсhain'master   :: EgvXPubKey
  -- ^BIP44 public key with derivation path /m\/purpose'\/coin_type'\/account'/.
, egvPubKeyсhain'external :: MI.IntMap EgvXPubKey
  -- ^Map with BIP44 external public keys.
  -- Public key indices are map keys, and the public keys are map values.
  -- This public keys must have the following derivation path:
  -- /m\/purpose'\/coin_type'\/account'\/0\/address_index/.
, egvPubKeyсhain'internal :: MI.IntMap EgvXPubKey
  -- ^Map with BIP44 internal keys.
  -- Public key indices are map keys, and the public keys are map values.
  -- This public keys must have the following derivation path:
  -- /m\/purpose'\/coin_type'\/account'\/1\/address_index/.
} deriving (Eq)

$(deriveJSON aesonOptionsStripToApostroph ''EgvPubKeyсhain)

data PrivateStorage = PrivateStorage {
    privateStorage'seed        :: Seed
  , privateStorage'root        :: EgvRootPrvKey
  , privateStorage'privateKeys :: M.Map Currency EgvPrvKeyсhain
  }

instance ToJSON PrivateStorage where
  toJSON PrivateStorage{..} = object [
      "seed"        .= toJSON (byteStringToText privateStorage'seed)
    , "root"        .= toJSON privateStorage'root
    , "privateKeys" .= toJSON privateStorage'privateKeys
    ]

instance FromJSON PrivateStorage where
  parseJSON = withObject "PrivateStorage" $ \o -> PrivateStorage
    <$> fmap textToByteString (o .: "seed")
    <*> o .: "root"
    <*> o .: "privateKeys"

data EncryptedPrivateStorage = EncryptedPrivateStorage {
    encryptedPrivateStorage'ciphertext :: ByteString
  , encryptedPrivateStorage'salt       :: ByteString
  , encryptedPrivateStorage'iv         :: IV AES256
  }

instance ToJSON EncryptedPrivateStorage where
  toJSON EncryptedPrivateStorage{..} = object [
      "ciphertext" .= toJSON (byteStringToText encryptedPrivateStorage'ciphertext)
    , "salt"       .= toJSON (byteStringToText encryptedPrivateStorage'salt)
    , "iv"         .= toJSON (byteStringToText (convert encryptedPrivateStorage'iv :: ByteString))
    ]

instance FromJSON EncryptedPrivateStorage where
  parseJSON = withObject "EncryptedPrivateStorage" $ \o -> do
    ciphertext <- fmap textToByteString (o .: "ciphertext")
    salt       <- fmap textToByteString (o .: "salt")
    iv         <- fmap textToByteString (o .: "iv")
    case makeIV iv of
      Nothing -> fail "failed to read iv"
      Just iv' -> pure $ EncryptedPrivateStorage ciphertext salt iv'

data ErgveinStorage = ErgveinStorage {
    storage'encryptedPrivateStorage :: EncryptedPrivateStorage
  , storage'publicKeys              :: M.Map Currency EgvPubKeyсhain
  , storage'walletName              :: Text
  }

instance Eq ErgveinStorage where
  a == b = storage'walletName a == storage'walletName b

$(deriveJSON aesonOptionsStripToApostroph ''ErgveinStorage)

data EncryptedErgveinStorage = EncryptedErgveinStorage {
    encryptedStorage'ciphertext :: ByteString
  , encryptedStorage'salt       :: ByteString
  , encryptedStorage'iv         :: IV AES256
  , encryptedStorage'eciesPoint :: Point Curve_X25519
  , encryptedStorage'authTag    :: AuthTag
  }

instance ToJSON EncryptedErgveinStorage where
  toJSON EncryptedErgveinStorage{..} = object [
      "ciphertext" .= toJSON (byteStringToText encryptedStorage'ciphertext)
    , "salt"       .= toJSON (byteStringToText encryptedStorage'salt)
    , "iv"         .= toJSON (byteStringToText (convert encryptedStorage'iv :: ByteString))
    , "eciesPoint" .= toJSON (byteStringToText eciesPoint)
    , "authTag"    .= toJSON (byteStringToText (convert encryptedStorage'authTag :: ByteString))
    ]
    where
      curve = Proxy :: Proxy Curve_X25519
      eciesPoint = encodePoint curve encryptedStorage'eciesPoint :: ByteString

instance FromJSON EncryptedErgveinStorage where
  parseJSON = withObject "EncryptedErgveinStorage" $ \o -> do
    ciphertext <- fmap textToByteString (o .: "ciphertext")
    salt <- fmap textToByteString (o .: "salt")
    iv <- fmap textToByteString (o .: "iv")
    eciesPoint <- fmap textToByteString (o .: "eciesPoint")
    authTag <- fmap textToByteString (o .: "authTag")
    case makeIV iv of
      Nothing -> fail "failed to read iv"
      Just iv' -> case decodePoint curve eciesPoint of
        CryptoFailed _ -> fail "failed to read eciesPoint"
        CryptoPassed eciesPoint' -> pure $ EncryptedErgveinStorage ciphertext salt iv' eciesPoint' authTag'
        where 
          curve = Proxy :: Proxy Curve_X25519
          authTag' = AuthTag (convert authTag :: Bytes)