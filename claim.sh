#!/bin/bash

if [ $# -ne 2 ]; then
  echo "Provide the delegation contract address and a staker private key as arguments."
  exit 1
fi

staker=$(cast wallet address $2) && \
forge script script/claim_Delegation.s.sol --rpc-url http://localhost:4201 --broadcast --legacy --sig "run(address payable)" $1 --private-key $2 -vvvv && \
block=$(cast rpc eth_blockNumber --rpc-url http://localhost:4201) && \
block_num=$(echo $block | tr -d '"' | cast to-dec --base-in 16) && \
echo rewardsAfterClaiming = $(cast call $1 "getRewards()(uint256)" --block $block_num --rpc-url http://localhost:4201 | sed 's/\[[^]]*\]//g') && \
echo taxedRewardsAfterClaiming = $(cast call $1 "getTaxedRewards()(uint256)" --block $block_num --rpc-url http://localhost:4201 | sed 's/\[[^]]*\]//g') && \
staker_wei_after=$(cast rpc eth_getBalance $staker $block --rpc-url http://localhost:4201 | tr -d '"' | cast to-dec --base-in 16) && \
echo $(date +"%T,%3N") $block_num && \
block_num=$((block_num-1)) && \
block=$(echo $block_num | cast to-hex --base-in 10) && \
echo rewardsBeforeClaiming = $(cast call $1 "getRewards()(uint256)" --block $block_num --rpc-url http://localhost:4201 | sed 's/\[[^]]*\]//g') && \
echo taxedRewardsBeforeClaiming = $(cast call $1 "getTaxedRewards()(uint256)" --block $block_num --rpc-url http://localhost:4201 | sed 's/\[[^]]*\]//g') && \
staker_wei_before=$(cast rpc eth_getBalance $staker $block --rpc-url http://localhost:4201 | tr -d '"' | cast to-dec --base-in 16) && \
echo claimed amount - gas fee = $(bc -l <<< $staker_wei_after-$staker_wei_before) wei
echo $(date +"%T,%3N") $block_num
