#!/bin/bash

if [ $# -ne 2 ]; then
  echo "Provide a staker private key and the amount in wei as arguments."
  exit 1
fi

forge script script/stake_Delegation.s.sol --rpc-url http://localhost:4201 --broadcast --legacy --sig "run(address payable, uint256)" 0x7A0b7e6D24eDe78260c9ddBD98e828B0e11A8EA2 $2 --private-key $1 && \
block=$(cast rpc eth_blockNumber --rpc-url http://localhost:4201 | tr -d '"' | cast to-dec --base-in 16) && \
echo rewardsAfterStaking = $(cast call 0x7A0b7e6D24eDe78260c9ddBD98e828B0e11A8EA2 "getRewards()(uint256)" --block $block --rpc-url http://localhost:4201 | sed 's/\[[^]]*\]//g') && \
echo taxedRewardsAfterStaking = $(cast call 0x7A0b7e6D24eDe78260c9ddBD98e828B0e11A8EA2 "getTaxedRewards()(uint256)" --block $block --rpc-url http://localhost:4201 | sed 's/\[[^]]*\]//g') && \
echo $(date +"%T,%3N") $block && \
block=$((block-1)) && \
echo rewardsBeforeStaking = $(cast call 0x7A0b7e6D24eDe78260c9ddBD98e828B0e11A8EA2 "getRewards()(uint256)" --block $block --rpc-url http://localhost:4201 | sed 's/\[[^]]*\]//g') && \
echo taxedRewardsBeforeStaking = $(cast call 0x7A0b7e6D24eDe78260c9ddBD98e828B0e11A8EA2 "getTaxedRewards()(uint256)" --block $block --rpc-url http://localhost:4201 | sed 's/\[[^]]*\]//g') && \
echo $(date +"%T,%3N") $block