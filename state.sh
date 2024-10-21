#!/bin/bash

if [ $# -ne 2 ]; then
  echo "Provide the delegation contract address and a staker address as arguments."
  exit 1
fi

block=$(cast rpc eth_blockNumber --rpc-url http://localhost:4201) && \
block_num=$(echo $block | tr -d '"' | cast to-dec --base-in 16) && \
echo $(date +"%T,%3N") $block_num && \
owner=$(cast call $1 "owner()(address)" --block $block_num --rpc-url http://localhost:4201) && \
lst=$(cast call $1 "getLST()(address)" --block $block_num --rpc-url http://localhost:4201) && \
echo rewardsBeforeUnstaking = $(cast rpc eth_getBalance $1 $block --rpc-url http://localhost:4201 | tr -d '"' | cast to-dec --base-in 16) && \
x=$(cast call $lst "balanceOf(address)(uint256)" $owner --block $block_num --rpc-url http://localhost:4201 | sed 's/\[[^]]*\]//g') && \
owner_lst=$(cast to-unit $x ether) && \
x=$(cast rpc eth_getBalance $owner $block --rpc-url http://localhost:4201 | tr -d '"' | cast to-dec --base-in 16) && \
owner_zil=$(cast to-unit $x ether) && \
echo owner: $owner_lst LST && echo owner: $owner_zil ZIL && \
x=$(cast call $lst "balanceOf(address)(uint256)" $2 --block $block_num --rpc-url http://localhost:4201 | sed 's/\[[^]]*\]//g') && \
staker_lst=$(cast to-unit $x ether) && \
x=$(cast rpc eth_getBalance $2 $block --rpc-url http://localhost:4201 | tr -d '"' | cast to-dec --base-in 16) && \
staker_zil=$(cast to-unit $x ether) && \
echo staker: $staker_lst LST && echo staker: $staker_zil ZIL && \
x=$(cast call $lst "totalSupply()(uint256)" --block $block_num --rpc-url http://localhost:4201 | sed 's/\[[^]]*\]//g') && \
y=$(cast call $1 "getRewards()(uint256)" --block $block_num --rpc-url http://localhost:4201 | sed 's/\[[^]]*\]//g') && \
z=$(cast call $1 "getStake()(uint256)" --block $block_num --rpc-url http://localhost:4201 | sed 's/\[[^]]*\]//g') && \
price=$(bc -l <<< \($y+$z\)/$x) && \
echo LST supply: $(cast to-unit $x ether) && \
echo LST price: $price && \
echo staker LST value: $(bc -l <<< $staker_lst*$price) ZIL && \
echo getStake = $z && \
echo getRewards = $y && \
echo getTaxedRewards = $(cast call $1 "getTaxedRewards()(uint256)" --block $block_num --rpc-url http://localhost:4201 | sed 's/\[[^]]*\]//g') && \
echo getTotalWithdrawals = $(cast call $1 "getTotalWithdrawals()(uint256)" --block $block_num --rpc-url http://localhost:4201 | sed 's/\[[^]]*\]//g')