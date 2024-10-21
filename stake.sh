#!/bin/bash

if [ $# -ne 3 ]; then
  echo "Provide the delegation contract address, a staker private key and an amount in wei as arguments."
  exit 1
fi

staker=$(cast wallet address $2)

forge script script/stake_Delegation.s.sol --rpc-url http://localhost:4201 --broadcast --legacy --sig "run(address payable, uint256)" $1 $3 --private-key $2

block=$(cast rpc eth_blockNumber --rpc-url http://localhost:4201)
block_num=$(echo $block | tr -d '"' | cast to-dec --base-in 16)

echo rewardsAfterStaking = $(cast call $1 "getRewards()(uint256)" --block $block_num --rpc-url http://localhost:4201 | sed 's/\[[^]]*\]//g')
echo taxedRewardsAfterStaking = $(cast call $1 "getTaxedRewards()(uint256)" --block $block_num --rpc-url http://localhost:4201 | sed 's/\[[^]]*\]//g')

staker_wei_after=$(cast rpc eth_getBalance $staker $block --rpc-url http://localhost:4201 | tr -d '"' | cast to-dec --base-in 16)

tmp=$(cast logs --from-block $block_num --to-block $block_num --address $1 "Staked(address,uint256,uint256)" --rpc-url http://localhost:4201 | grep "data")
if [[ "$tmp" != "" ]]; then
    tmp=${tmp#*: }
    tmp=$(cast abi-decode --input "x(uint256,uint256)" $tmp | sed 's/\[[^]]*\]//g')
    tmp=(${tmp})
    d1=${tmp[0]}
    d2=${tmp[1]}
    #d1=$(echo $tmp | sed -n -e 1p | sed 's/\[[^]]*\]//g')
    #d2=$(echo $tmp | sed -n -e 2p | sed 's/\[[^]]*\]//g')
fi

echo $(date +"%T,%3N") $block_num

block_num=$((block_num-1))
block=$(echo $block_num | cast to-hex --base-in 10)

echo rewardsBeforeStaking = $(cast call $1 "getRewards()(uint256)" --block $block_num --rpc-url http://localhost:4201 | sed 's/\[[^]]*\]//g')
echo taxedRewardsBeforeStaking = $(cast call $1 "getTaxedRewards()(uint256)" --block $block_num --rpc-url http://localhost:4201 | sed 's/\[[^]]*\]//g')

staker_wei_before=$(cast rpc eth_getBalance $staker $block --rpc-url http://localhost:4201 | tr -d '"' | cast to-dec --base-in 16)

echo staked amount + gas fee = $(bc -l <<< $staker_wei_before-$staker_wei_after) wei
if [[ "$tmp" != "" ]]; then echo event Staked\($staker, $d1, $d2\) emitted; fi
echo $(date +"%T,%3N") $block_num