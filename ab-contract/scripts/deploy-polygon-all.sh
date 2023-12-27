#!/bin/bash

# 全局变量，网络名称
NETWORK="polygon"
source scripts/deploy-default-all.sh


# 部署所有合约
deployAll() {
  # 核心模块
  deploy "DiamondCutFacet"
  deploy "DiamondLoupeFacet"
  deploy "OwnershipFacet"
  deploy "DexManagerFacet"
  deploy "AccessManagerFacet"
  deploy "WithdrawFacet"
  deploy "PeripheryRegistryFacet"
  deploy "Diamond"
  update "CoreFacets"
  # 更新交易所及签名
  syncDexs
  syncSigs

  # 通用swap
  deploy "GenericSwapFacet"
  update "GenericSwapFacet"
  # 平台收费
  deploy "FeeCollector"
  registerFeeCollector

  # 各个桥，根据需要部署
  deploy "StargateFacet"
  update "StargateFacet"

  deploy "HyphenFacet"
  update "HyphenFacet"

  deploy "MultichainFacet"
  update "MultichainFacet"

  deploy "AcrossFacet"
  update "AcrossFacet"

  deploy "CBridgeFacet"
  update "CBridgeFacet"

  deploy "HopFacet"
  update "HopFacet"

  # 即connext桥
  deploy "AmarokFacet"
  update "AmarokFacet"
}


deployAll
