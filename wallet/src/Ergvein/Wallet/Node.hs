{-
  Application level
-}
module Ergvein.Wallet.Node
  (
    addNodeConn
  , getNodeConn
  , getAllConnByCurrency
  , initializeNodes
  , reinitNodes
  , requestNodeWait
  , requestNodeNow
  , closeNodeIfUp
  , module Ergvein.Wallet.Node.Types
  ) where

import Control.Monad.IO.Class
import Data.Maybe
import Data.Foldable
import Servant.Client(BaseUrl)

import Ergvein.Types.Currency
import Ergvein.Wallet.Monad.Front
import Ergvein.Wallet.Native
import Ergvein.Wallet.Node.BTC
import Ergvein.Wallet.Node.ERGO
import Ergvein.Wallet.Node.Prim
import Ergvein.Wallet.Node.Types
import Ergvein.Wallet.Util

import qualified Data.Dependent.Map as DM
import qualified Data.Map as M
import qualified Data.Set as S

addNodeConn :: NodeConn t -> ConnMap t -> ConnMap t
addNodeConn nc cm = case nc of
  NodeConnBTC conn -> let
    u = nodeconUrl conn
    in DM.insertWith M.union BTCTag (M.singleton u conn) cm
  NodeConnERG conn -> let
    u = nodeconUrl conn
    in DM.insertWith M.union ERGOTag (M.singleton u conn) cm

addMultipleConns :: Foldable f => ConnMap t -> f (NodeConn t) -> ConnMap t
addMultipleConns = foldl' (flip addNodeConn)

getNodeConn :: CurrencyTag t a -> BaseUrl -> ConnMap t -> Maybe a
getNodeConn t url cm = M.lookup url =<< DM.lookup t cm

getAllConnByCurrency :: Currency -> ConnMap t -> Maybe (M.Map BaseUrl (NodeConn t))
getAllConnByCurrency cur cm = case cur of
  BTC  -> (fmap . fmap) NodeConnBTC $ DM.lookup BTCTag cm
  ERGO -> (fmap . fmap) NodeConnERG $ DM.lookup ERGOTag cm

initNode :: MonadBaseConstr t m => Currency -> BaseUrl -> m (NodeConn t)
initNode cur url = case cur of
  BTC   -> fmap NodeConnBTC $ initBTCNode url
  ERGO  -> fmap NodeConnERG $ initErgoNode url

initializeNodes :: MonadBaseConstr t m => M.Map Currency [BaseUrl] -> m (ConnMap t)
initializeNodes urlmap = do
  let ks = M.keys urlmap
  conns <- fmap join $ flip traverse ks $ \k -> traverse (initNode k) $ fromMaybe [] $ M.lookup k urlmap
  pure $ addMultipleConns DM.empty conns

reinitNodes :: MonadBaseConstr t m
  => M.Map Currency [BaseUrl]   -- Map with all urls
  -> M.Map Currency Bool        -- True -- initialize or keep existing conns. False -- remove conns
  -> ConnMap t                  -- Inital map of connections
  -> m (ConnMap t)
reinitNodes urls cs conMap = foldlM updCurr conMap $ M.toList cs
  where
    updCurr :: MonadBaseConstr t m => ConnMap t -> (Currency, Bool) -> m (ConnMap t)
    updCurr cm (cur, b) = case cur of
      BTC -> case (DM.lookup BTCTag cm, b) of
        (Nothing, True) -> do
          conns <- traverse (fmap NodeConnBTC . initBTCNode) $ fromMaybe [] $ M.lookup BTC urls
          pure $ addMultipleConns cm conns
        (Just _, False) -> pure $ DM.delete BTCTag cm
        _ -> pure cm
      ERGO -> case (DM.lookup ERGOTag cm, b) of
        (Nothing, True) -> do
          conns <- traverse (fmap NodeConnERG . initErgoNode) $ fromMaybe [] $ M.lookup ERGO urls
          pure $ addMultipleConns cm conns
        (Just _, False) -> pure $ DM.delete ERGOTag cm
        _ -> pure cm

-- Send a request to a node. Wait until the connection is up
requestNodeWait :: (MonadBaseConstr t m, HasNode cur)
  => NodeConnection t cur -> Event t (NodeReq cur) -> m ()
requestNodeWait NodeConnection{..} reqE = do
  reqD <- holdDyn Nothing $ Just <$> reqE
  let passValE = updated $ (,) <$> reqD <*> nodeconIsUp
  performEvent_ $ ffor passValE $ \case
    (Just _, False) -> logWrite $
      (nodeString nodeconCurrency nodeconUrl) <> "Connection is not active. Waiting."
    (Just v, True) -> liftIO . nodeconReqFire $ v
    _ -> pure ()

-- Send a request to a node and return the connection status.
requestNodeNow :: (MonadBaseConstr t m, HasNode cur)
  => NodeConnection t cur -> Event t (NodeReq cur) -> m (Event t Bool)
requestNodeNow NodeConnection{..} reqE = do
  performEvent $ ffor (current nodeconIsUp `attach` reqE) $ \(isUp, v) -> do
    if isUp
      then liftIO . nodeconReqFire $ v
      else logWrite $ (nodeString nodeconCurrency nodeconUrl) <> "Connection is not active"
    pure isUp

closeNodeIfUp :: (MonadBaseConstr t m, HasNode cur)
  => NodeConnection t cur -> Event t () -> m ()
closeNodeIfUp NodeConnection{..} closeE =
  performEvent_ $ ffor (current nodeconIsUp `tag` closeE) $ \case
    True -> liftIO nodeconCloseFire
    False -> pure ()