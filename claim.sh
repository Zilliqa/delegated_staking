#!/bin/bash

if [ $# -ne 2 ]; then
  echo "Provide the delegation contract address and a staker private key as arguments."
  exit 1
fi

staker=$(cast wallet address $2)

forge script script/claim_Delegation.s.sol --rpc-url http://localhost:4201 --broadcast --legacy --sig "run(address payable)" $1 --private-key $2 -vvvv

block=$(cast rpc eth_blockNumber --rpc-url http://localhost:4201)
block_num=$(echo $block | tr -d '"' | cast to-dec --base-in 16)

echo rewardsAfterClaiming = $(cast call $1 "getRewards()(uint256)" --block $block_num --rpc-url http://localhost:4201 | sed 's/\[[^]]*\]//g')
echo taxedRewardsAfterClaiming = $(cast call $1 "getTaxedRewards()(uint256)" --block $block_num --rpc-url http://localhost:4201 | sed 's/\[[^]]*\]//g')

staker_wei_after=$(cast rpc eth_getBalance $staker $block --rpc-url http://localhost:4201 | tr -d '"' | cast to-dec --base-in 16)

tmp=$(cast logs --from-block $block_num --to-block $block_num --address $1 "Claimed(address,uint256)" --rpc-url http://localhost:4201 | grep "data")
if [[ "$tmp" != "" ]]; then
    tmp=${tmp#*: }
    tmp=$(cast abi-decode --input "x(uint256)" $tmp | sed 's/\[[^]]*\]//g')
    tmp=(${tmp})
    d1=${tmp[0]}
    #d1=$(echo $tmp | sed -n -e 1p | sed 's/\[[^]]*\]//g')
fi

echo $(date +"%T,%3N") $block_num

block_num=$((block_num-1))
block=$(echo $block_num | cast to-hex --base-in 10)

echo rewardsBeforeClaiming = $(cast call $1 "getRewards()(uint256)" --block $block_num --rpc-url http://localhost:4201 | sed 's/\[[^]]*\]//g')
echo taxedRewardsBeforeClaiming = $(cast call $1 "getTaxedRewards()(uint256)" --block $block_num --rpc-url http://localhost:4201 | sed 's/\[[^]]*\]//g')

staker_wei_before=$(cast rpc eth_getBalance $staker $block --rpc-url http://localhost:4201 | tr -d '"' | cast to-dec --base-in 16)

echo claimed amount - gas fee = $(bc -l <<< "scale=18; $staker_wei_after-$staker_wei_before") wei
if [[ "$tmp" != "" ]]; then echo event Claimed\($staker, $d1\) emitted; fi
echo $(date +"%T,%3N") $block_num
