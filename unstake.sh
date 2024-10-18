#!/bin/bash

if [ $# -lt 1 ]; then
  echo "Provide a staker private key and optionally the number of shares as arguments."
  exit 1
fi

if [ $# -eq 2 ]; then
    amount="$2"
else
    amount=0
fi

forge script script/unstake_Delegation.s.sol --rpc-url http://localhost:4201 --broadcast --legacy --sig "run(address payable, uint256)" 0x7A0b7e6D24eDe78260c9ddBD98e828B0e11A8EA2 $amount --private-key $1 && \
block=$(cast rpc eth_blockNumber --rpc-url http://localhost:4201 | tr -d '"' | cast to-dec --base-in 16) && \
echo rewardsAfterUnstaking = $(cast call 0x7A0b7e6D24eDe78260c9ddBD98e828B0e11A8EA2 "getRewards()(uint256)" --block $block --rpc-url http://localhost:4201 | sed 's/\[[^]]*\]//g') && \
echo taxedRewardsAfterUnstaking = $(cast call 0x7A0b7e6D24eDe78260c9ddBD98e828B0e11A8EA2 "getTaxedRewards()(uint256)" --block $block --rpc-url http://localhost:4201 | sed 's/\[[^]]*\]//g') && \
echo $(date +"%T,%3N") $block && \
block=$((block-1)) && \
echo rewardsBeforeUnstaking = $(cast call 0x7A0b7e6D24eDe78260c9ddBD98e828B0e11A8EA2 "getRewards()(uint256)" --block $block --rpc-url http://localhost:4201 | sed 's/\[[^]]*\]//g') && \
echo taxedRewardsBeforeUnstaking = $(cast call 0x7A0b7e6D24eDe78260c9ddBD98e828B0e11A8EA2 "getTaxedRewards()(uint256)" --block $block --rpc-url http://localhost:4201 | sed 's/\[[^]]*\]//g') && \
echo $(date +"%T,%3N") $block