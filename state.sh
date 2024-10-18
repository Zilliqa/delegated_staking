#!/bin/bash

if [ $# -ne 1 ]; then
  echo "Provide a staker address as an argument."
  exit 1
fi

block=$(cast rpc eth_blockNumber --rpc-url http://localhost:4201) && \
block_num=$(echo $block | tr -d '"' | cast to-dec --base-in 16) && \
echo $(date +"%T,%3N") $block_num && \
echo rewardsBeforeUnstaking = $(cast rpc eth_getBalance 0x7A0b7e6D24eDe78260c9ddBD98e828B0e11A8EA2 $block --rpc-url http://localhost:4201 | tr -d '"' | cast to-dec --base-in 16) && \
x=$(cast call 0x9e5c257D1c6dF74EaA54e58CdccaCb924669dc83 "balanceOf(address)(uint256)" 0x15fc323DFE5D5DCfbeEdc25CEcbf57f676634d77 --block $block_num --rpc-url http://localhost:4201 | sed 's/\[[^]]*\]//g') && \
owner_lst=$(cast to-unit $x ether) && \
x=$(cast rpc eth_getBalance 0x15fc323DFE5D5DCfbeEdc25CEcbf57f676634d77 $block --rpc-url http://localhost:4201 | tr -d '"' | cast to-dec --base-in 16) && \
owner_zil=$(cast to-unit $x ether) && \
echo owner: $owner_lst LST && echo owner: $owner_zil ZIL && \
x=$(cast call 0x9e5c257D1c6dF74EaA54e58CdccaCb924669dc83 "balanceOf(address)(uint256)" $1 --block $block_num --rpc-url http://localhost:4201 | sed 's/\[[^]]*\]//g') && \
staker_lst=$(cast to-unit $x ether) && \
x=$(cast rpc eth_getBalance $1 $block --rpc-url http://localhost:4201 | tr -d '"' | cast to-dec --base-in 16) && \
staker_zil=$(cast to-unit $x ether) && \
echo staker: $staker_lst LST && echo staker: $staker_zil ZIL && \
x=$(cast call 0x9e5c257D1c6dF74EaA54e58CdccaCb924669dc83 "totalSupply()(uint256)" --block $block_num --rpc-url http://localhost:4201 | sed 's/\[[^]]*\]//g') && \
y=$(cast call 0x7A0b7e6D24eDe78260c9ddBD98e828B0e11A8EA2 "getRewards()(uint256)" --block $block_num --rpc-url http://localhost:4201 | sed 's/\[[^]]*\]//g') && \
z=$(cast call 0x7A0b7e6D24eDe78260c9ddBD98e828B0e11A8EA2 "getStake()(uint256)" --block $block_num --rpc-url http://localhost:4201 | sed 's/\[[^]]*\]//g') && \
price=$(bc -l <<< \($y+$z\)/$x) && \
echo LST supply: $(cast to-unit $x ether) && \
echo LST price: $price && \
echo staker LST value: $(bc -l <<< $staker_lst*$price) ZIL && \
echo getStake = $(cast call 0x7A0b7e6D24eDe78260c9ddBD98e828B0e11A8EA2 "getStake()(uint256)" --block $block_num --rpc-url http://localhost:4201 | sed 's/\[[^]]*\]//g') && \
echo getRewards = $(cast call 0x7A0b7e6D24eDe78260c9ddBD98e828B0e11A8EA2 "getRewards()(uint256)" --block $block_num --rpc-url http://localhost:4201 | sed 's/\[[^]]*\]//g') && \
echo getTaxedRewards = $(cast call 0x7A0b7e6D24eDe78260c9ddBD98e828B0e11A8EA2 "getTaxedRewards()(uint256)" --block $block_num --rpc-url http://localhost:4201 | sed 's/\[[^]]*\]//g') && \
echo getTotalWithdrawals = $(cast call 0x7A0b7e6D24eDe78260c9ddBD98e828B0e11A8EA2 "getTotalWithdrawals()(uint256)" --block $block_num --rpc-url http://localhost:4201 | sed 's/\[[^]]*\]//g')