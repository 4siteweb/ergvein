{-# LANGUAGE DataKinds #-}
module Ergvein.Crypto.AES256 (
    encrypt
  , decrypt
  , encryptWithAEAD
  , decryptWithAEAD
  , encryptBS
  , decryptBS
  , defaultAuthTagLength
  , genRandomSalt
  , genRandomSalt32
  , genRandomIV
  , AES256
  , AEADMode(..)
  , Key(..)
  , IV
  , makeIV
  , AuthTag(..)
  , MonadRandom(..)
  , EncryptedByteString(..)
  ) where

import Crypto.Cipher.AES (AES256)
import Crypto.Cipher.Types
import Crypto.Error (CryptoFailable(..), CryptoError(..))
import Crypto.Random.Types (MonadRandom, getRandomBytes)
import Data.ByteArray (ByteArray, ByteArrayAccess, convert)
import Data.ByteArray.Sized (SizedByteArray, unsafeSizedByteArray)
import Data.ByteString (ByteString)
import Data.Maybe
import Data.Text
import Data.Serialize
import Ergvein.Crypto.PBKDF
import Data.Text.Encoding (encodeUtf8)

type Password = Text

data Key c a where
  Key :: (BlockCipher c, ByteArray a) => a -> Key c a

defaultAuthTagLength :: Int
defaultAuthTagLength = 16

-- | Generate a random salt with length equal to 'defaultPBKDF2SaltLength'
genRandomSalt32 :: MonadRandom m => m (SizedByteArray 32 ByteString)
genRandomSalt32 = unsafeSizedByteArray <$> getRandomBytes defaultPBKDF2SaltLength

-- | Generate a random salt with length equal to 'defaultPBKDF2SaltLength'
genRandomSalt :: (MonadRandom m, ByteArray a) => m a
genRandomSalt = getRandomBytes defaultPBKDF2SaltLength

-- | Generate a random initialization vector for a given block cipher
genRandomIV :: forall m c. (MonadRandom m, BlockCipher c) => c -> m (Maybe (IV c))
genRandomIV _ = do
  bytes :: ByteString <- getRandomBytes $ blockSize (undefined :: c)
  return $ makeIV bytes

-- | Initialize a block cipher
initCipher :: (BlockCipher c, ByteArray a) => Key c a -> Either CryptoError c
initCipher (Key k) = case cipherInit k of
  CryptoFailed e -> Left e
  CryptoPassed a -> Right a

encrypt :: (BlockCipher c, ByteArray a) => Key c a -> IV c -> a -> Either CryptoError a
encrypt secretKey iv msg =
  case initCipher secretKey of
    Left e -> Left e
    Right c -> Right $ ctrCombine c iv msg

decrypt :: (BlockCipher c, ByteArray a) => Key c a -> IV c -> a -> Either CryptoError a
decrypt = encrypt

-- | Initialize an AEAD block cipher
initAEADCipher :: (BlockCipher c, ByteArray a)
  => AEADMode
  -> Key c a
  -> IV c
  -> Either CryptoError (AEAD c)
initAEADCipher mode secretKey iv =
  case initCipher secretKey of
    Left e -> Left e
    Right c -> case aeadInit mode c iv of
      CryptoFailed e -> Left e
      CryptoPassed a -> Right a

encryptWithAEAD :: (BlockCipher c, ByteArray a, ByteArrayAccess aad)
  => AEADMode
  -> Key c a
  -> IV c
  -> aad
  -> a
  -> Int
  -> Either CryptoError (AuthTag, a)
encryptWithAEAD mode secretKey iv header msg tagLength =
  case initAEADCipher mode secretKey iv of
    Left e -> Left e
    Right context -> Right $ aeadSimpleEncrypt context header msg tagLength

decryptWithAEAD :: (BlockCipher c, ByteArray a, ByteArrayAccess aad)
  => AEADMode
  -> Key c a
  -> IV c
  -> aad
  -> a
  -> AuthTag
  -> Maybe a
decryptWithAEAD mode secretKey iv header msg tag =
  case initAEADCipher mode secretKey iv of
    Left e -> error $ show e
    Right context -> aeadSimpleDecrypt context header msg tag

data EncryptedByteString = EncryptedByteString {
    encryptedByteString'salt       :: SizedByteArray 32 ByteString
  , encryptedByteString'iv         :: IV AES256
  , encryptedByteString'ciphertext :: ByteString
  }

instance Serialize EncryptedByteString where
  put EncryptedByteString{..} = do
    let saltBS = convert encryptedByteString'salt :: ByteString
        ivBS = convert encryptedByteString'iv :: ByteString
    put saltBS
    put ivBS
    put encryptedByteString'ciphertext

  get = do
    saltBS <- getBytes 32
    ivBS <- getBytes 16
    remBytes <- remaining
    ciphertext <- getBytes remBytes
    let salt = unsafeSizedByteArray saltBS :: SizedByteArray 32 ByteString
        iv = fromJust $ makeIV ivBS :: IV AES256
    return $ EncryptedByteString salt iv ciphertext

encryptBS :: MonadRandom m => ByteString -> Password -> m (Either String EncryptedByteString)
encryptBS bs pass = do
  salt <- genRandomSalt32
  let secretKey = Key (fastPBKDF2_SHA256 defaultPBKDF2Params (encodeUtf8 pass) salt) :: Key AES256 ByteString
  iv <- genRandomIV (undefined :: AES256)
  case iv of
    Nothing -> pure $ Left $ "Failed to generate an AES initialization vector"
    Just iv' -> do
      case encrypt secretKey iv' bs of
        Left err -> pure $ Left $ show err
        Right ciphertext -> pure $ Right $ EncryptedByteString salt iv' ciphertext

decryptBS :: EncryptedByteString -> Password -> Either String ByteString
decryptBS encryptedBS password =
  case decrypt secretKey iv ciphertext of
    Left err -> Left $ show err
    Right decryptedBS -> Right decryptedBS
  where
    salt = encryptedByteString'salt encryptedBS
    secretKey = Key (fastPBKDF2_SHA256 defaultPBKDF2Params (encodeUtf8 password) salt) :: Key AES256 ByteString
    iv = encryptedByteString'iv encryptedBS
    ciphertext = encryptedByteString'ciphertext encryptedBS
