{-
  Core types for handling of a collection of node connections
-}
module Ergvein.Wallet.Node.Types
  (
    NodeConnection(..)
  , ConnMap
  , CurrencyRep(..)
  , CurrencyTag(..)
  , BTCType(..)
  , ERGOType(..)
  , NodeBTC
  , NodeERG
  , HasNode(..)
  , NodeConn(..)
  , NodeStatus(..)
  ) where

import Data.GADT.Compare
import Data.Time(NominalDiffTime)
import Servant.Client(BaseUrl)

import Ergvein.Types.Currency
import Ergvein.Types.Transaction
import Reflex.Dom

import Ergvein.Wallet.Node.BTC
import Ergvein.Wallet.Node.ERGO
import Ergvein.Wallet.Node.Prim

import Data.Map.Strict (Map)
import Data.Dependent.Map (DMap)

data NodeConn t = NodeConnBTC (NodeBTC t) | NodeConnERG (NodeERG t)

data CurrencyTag t a where
  BTCTag :: CurrencyTag t (NodeBTC t)
  ERGOTag :: CurrencyTag t (NodeERG t)

instance GEq (CurrencyTag t) where
  geq BTCTag  BTCTag  = Just Refl
  geq ERGOTag ERGOTag = Just Refl
  geq _       _       = Nothing

instance GCompare (CurrencyTag t) where
  gcompare BTCTag   BTCTag  = GEQ
  gcompare ERGOTag  ERGOTag = GEQ
  gcompare BTCTag   ERGOTag = GGT
  gcompare ERGOTag  BTCTag  = GLT

type ConnMap t = DMap (CurrencyTag t) (Map BaseUrl)