#!/bin/bash

if [ $# -lt 2 ]; then
  echo "Provide the delegation contract address, a staker private key and optionally the number of shares as arguments."
  exit 1
fi

if [ $# -eq 3 ]; then
    amount="$3"
else
    amount=0
fi

staker=$(cast wallet address $2) && \
forge script script/unstake_Delegation.s.sol --rpc-url http://localhost:4201 --broadcast --legacy --sig "run(address payable, uint256)" $1 $amount --private-key $2 && \
block=$(cast rpc eth_blockNumber --rpc-url http://localhost:4201) && \
block_num=$(echo $block | tr -d '"' | cast to-dec --base-in 16) && \
echo rewardsAfterUnstaking = $(cast call $1 "getRewards()(uint256)" --block $block_num --rpc-url http://localhost:4201 | sed 's/\[[^]]*\]//g') && \
echo taxedRewardsAfterUnstaking = $(cast call $1 "getTaxedRewards()(uint256)" --block $block_num --rpc-url http://localhost:4201 | sed 's/\[[^]]*\]//g') && \
echo $(date +"%T,%3N") $block_num && \
block_num=$((block_num-1)) && \
block=$(echo $block_num | cast to-hex --base-in 10) && \
echo rewardsBeforeUnstaking = $(cast call $1 "getRewards()(uint256)" --block $block_num --rpc-url http://localhost:4201 | sed 's/\[[^]]*\]//g') && \
echo taxedRewardsBeforeUnstaking = $(cast call $1 "getTaxedRewards()(uint256)" --block $block_num --rpc-url http://localhost:4201 | sed 's/\[[^]]*\]//g') && \
lst=$(cast call $1 "getLST()(address)" --block $block_num --rpc-url http://localhost:4201) && \
if [[ "$amount" == "0" ]]; then amount=$(cast call $lst "balanceOf(address)(uint256)" $staker --block $block_num --rpc-url http://localhost:4201 | sed 's/\[[^]]*\]//g'); fi && \
x=$(cast call $lst "totalSupply()(uint256)" --block $block_num --rpc-url http://localhost:4201 | sed 's/\[[^]]*\]//g') && \
y=$(cast call $1 "getRewards()(uint256)" --block $block_num --rpc-url http://localhost:4201 | sed 's/\[[^]]*\]//g') && \
z=$(cast call $1 "getStake()(uint256)" --block $block_num --rpc-url http://localhost:4201 | sed 's/\[[^]]*\]//g') && \
price=$(bc -l <<< \($y+$z\)/$x) && \
echo LST price: $price && \
echo unstaked LST value: $(bc -l <<< $amount*$price/10^18) ZIL && \
echo $(date +"%T,%3N") $block_num