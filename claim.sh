#!/bin/bash

if [ $# -ne 1 ]; then
  echo "Provide a staker private key as an arguments."
  exit 1
fi

forge script script/claim_Delegation.s.sol --rpc-url http://localhost:4201 --broadcast --legacy --sig "run(address payable)" 0x7A0b7e6D24eDe78260c9ddBD98e828B0e11A8EA2 --private-key $1 -vvvv && \
block=$(cast rpc eth_blockNumber --rpc-url http://localhost:4201 | tr -d '"' | cast to-dec --base-in 16) && \
echo rewardsAfterClaiming = $(cast call 0x7A0b7e6D24eDe78260c9ddBD98e828B0e11A8EA2 "getRewards()(uint256)" --block $block --rpc-url http://localhost:4201 | sed 's/\[[^]]*\]//g') && \
echo taxedRewardsAfterClaiming = $(cast call 0x7A0b7e6D24eDe78260c9ddBD98e828B0e11A8EA2 "getTaxedRewards()(uint256)" --block $block --rpc-url http://localhost:4201 | sed 's/\[[^]]*\]//g') && \
echo $(date +"%T,%3N") $block && \
block=$((block-1)) && \
echo rewardsBeforeClaiming = $(cast call 0x7A0b7e6D24eDe78260c9ddBD98e828B0e11A8EA2 "getRewards()(uint256)" --block $block --rpc-url http://localhost:4201 | sed 's/\[[^]]*\]//g') && \
echo taxedRewardsBeforeClaiming = $(cast call 0x7A0b7e6D24eDe78260c9ddBD98e828B0e11A8EA2 "getTaxedRewards()(uint256)" --block $block --rpc-url http://localhost:4201 | sed 's/\[[^]]*\]//g') && \
echo $(date +"%T,%3N") $block
