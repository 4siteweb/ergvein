{-# LANGUAGE OverloadedLists #-}
module Ergvein.Wallet.Page.Share(
    sharePage
  ) where

import Ergvein.Text
import Ergvein.Types.Currency
import Ergvein.Types.Keys
import Ergvein.Types.Storage
import Ergvein.Wallet.Clipboard (clipboardCopy)
import Ergvein.Wallet.Elements
import Ergvein.Wallet.Id
import Ergvein.Wallet.Input
import Ergvein.Wallet.Language
import Ergvein.Wallet.Localization.Share
import Ergvein.Wallet.Menu
import Ergvein.Wallet.Monad
import Ergvein.Wallet.Settings
import Ergvein.Wallet.Wrapper

import qualified Data.Map.Strict as M
import Data.Maybe (fromMaybe)
import qualified Data.Text as T
import Network.Haskoin.Keys

sharePage :: MonadFront t m => Currency -> m ()
sharePage cur = do
  let thisWidget = Just $ pure $ sharePage cur
  menuWidget (ShareTitle cur) thisWidget
  wrapper False $ divClass "share-content" $ do
    let shareAdd = "175tWpb8K1S7NmH4Zx6rewF9WQrcZv245W"
    let shareMoney = Money cur 1
    let tempUrl = "bitcoin:" <> shareAdd <> "?amount=" <> (showt $ moneyValue shareMoney)
    textLabel ShareLink $ text tempUrl
    copyE <- fmap (tempUrl <$) $ outlineButton ShareCopy
    _ <- clipboardCopy copyE
    pure ()

textLabel :: (MonadFrontBase t m, LocalizedPrint l)
  => l -- ^ Label
  -> m a -- ^ Value
  -> m ()
textLabel lbl val = do
  i <- genId
  label i $ localizedText lbl
  elAttr "div" [("class","share-block-value"),("id",i)] $ val
  pure ()
