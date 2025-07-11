#!/bin/bash

if [ $# -ne 2 ]; then
    echo "Provide the delegation contract address and a staker private key as arguments."
    exit 1
fi

staker=$(cast wallet address $2)

temp=$(forge script script/CheckVariant.s.sol --sig "run(address payable)" $1 | tail -n 1)
variant=$(sed -E 's/\s\s([a-zA-Z0-9]+)/\1/' <<< "$temp")
if [[ "$variant" == "$temp" ]]; then
    echo Incompatible delegation contract at $1
    exit 1
fi

# ensure there are no other transactions from the staker in 5 block before the forge script is executed
# because we will compare the stakers balance after the forge script and before the forge script and
# the latter is queried from 5 blocks before the first block number we get after the script execution 
echo "Waiting 10 seconds..."
sleep 10

forge script script/Claim.s.sol --broadcast --legacy --sig "run(address payable)" $1 --private-key $2 -vvvv

block=$(cast rpc eth_blockNumber)
block_num=$(echo $block | tr -d '"' | cast to-dec --base-in 16)

echo rewardsAfterClaiming = $(cast call $1 "getRewards()(uint256)" --block $block_num | sed 's/\[[^]]*\]//g')
if [[ "$variant" == "LiquidStaking" ]]; then
    echo taxedRewardsAfterClaiming = $(cast call $1 "getTaxedRewards()(uint256)" --block $block_num | sed 's/\[[^]]*\]//g')
fi

stakerWeiAfter=$(cast rpc eth_getBalance $staker $block | tr -d '"' | cast to-dec --base-in 16)

tmp=$(cast logs --from-block $block_num --to-block $block_num --address $1 "Claimed(address,uint256,bytes)" | grep "data")
if [[ "$tmp" != "" ]]; then
    tmp=${tmp#*: }
    tmp=$(cast abi-decode --input "x(uint256,bytes)" $tmp | sed 's/\[[^]]*\]//g')
    tmp=(${tmp})
    d1=${tmp[0]}
    d2=${tmp[1]}
    #d1=$(echo $tmp | sed -n -e 1p | sed 's/\[[^]]*\]//g')
    #d2=$(echo $tmp | sed -n -e 2p | sed 's/\[[^]]*\]//g')
fi

echo $(date +"%T,%3N") $block_num

block_num=$((block_num - 5))
block=$(echo $block_num | cast to-hex --base-in 10)

echo rewardsBeforeClaiming = $(cast call $1 "getRewards()(uint256)" --block $block_num | sed 's/\[[^]]*\]//g')
if [[ "$variant" == "LiquidStaking" ]]; then
    echo taxedRewardsBeforeClaiming = $(cast call $1 "getTaxedRewards()(uint256)" --block $block_num | sed 's/\[[^]]*\]//g')
fi

stakerWeiBefore=$(cast rpc eth_getBalance $staker $block | tr -d '"' | cast to-dec --base-in 16)

echo claimed amount - gas fee = $(bc -l <<< "scale=18; $stakerWeiAfter-$stakerWeiBefore") wei

if [[ "$tmp" != "" ]]; then echo event Claimed\($staker, $d1, $d2\) emitted; fi

echo $(date +"%T,%3N") $block_num
