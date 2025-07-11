#!/bin/bash

if [ $# -lt 2 ]; then
    echo "Provide the delegation contract address and the validator or staker private key."
    exit 1
fi

staker=$(cast wallet address $2)

temp=$(forge script script/CheckVariant.s.sol --sig "run(address payable)" $1 | tail -n 1)
variant=$(sed -E 's/\s\s([a-zA-Z0-9]+)/\1/' <<< "$temp")
if [[ "$variant" == "$temp" ]]; then
    echo Incompatible delegation contract at $1
    exit 1
fi

owner=$(cast call $1 "owner()(address)" --block latest)

if [ "$variant" == "LiquidStaking" ] && [ "$staker" != "$owner" ]; then
    echo Rewards must be staked by the validator and it is not $staker
    exit 1
fi

# ensure there are no other transactions from the staker in 5 block before the forge script is executed
# because we will compare the stakers balance after the forge script and before the forge script and
# the latter is queried from 5 blocks before the first block number we get after the script execution 
echo "Waiting 10 seconds..."
sleep 10

forge script script/StakeRewards.s.sol --broadcast --legacy --sig "run(address payable)" $1 --private-key $2

block=$(cast rpc eth_blockNumber)
block_num=$(echo $block | tr -d '"' | cast to-dec --base-in 16)

rewardsAfterStaking=$(cast call $1 "getRewards()(uint256)" --block $block_num | sed 's/\[[^]]*\]//g')
taxedRewardsAfterStaking=$(cast call $1 "getTaxedRewards()(uint256)" --block $block_num | sed 's/\[[^]]*\]//g')
depositAfterStaking=$(cast call $1 "getStake()(uint256)" --block $block_num | sed 's/\[[^]]*\]//g')
echo rewardsAfterStaking = $rewardsAfterStaking
echo taxedRewardsAfterStaking = $taxedRewardsAfterStaking
echo depositAfterStaking = $depositAfterStaking

stakerWeiAfter=$(cast rpc eth_getBalance $staker $block | tr -d '"' | cast to-dec --base-in 16)
ownerWeiAfter=$(cast rpc eth_getBalance $owner $block | tr -d '"' | cast to-dec --base-in 16)

tmp1=$(cast logs --from-block $block_num --to-block $block_num --address $1 "CommissionPaid(address,uint256)" | grep "data")
if [[ "$tmp1" != "" ]]; then
    tmp1=${tmp1#*: }
    tmp1=$(cast abi-decode --input "x(uint256)" $tmp1 | sed 's/\[[^]]*\]//g')
    tmp1=(${tmp1})
    d1=${tmp1[0]}
    #d1=$(echo $tmp1 | sed -n -e 1p | sed 's/\[[^]]*\]//g')
fi

echo $(date +"%T,%3N") $block_num

block_num=$((block_num - 5))
block=$(echo $block_num | cast to-hex --base-in 10)

stake=$(cast call $1 "getStake()(uint256)" --block $block_num | sed 's/\[[^]]*\]//g')
commissionNumerator=$(cast call $1 "getCommissionNumerator()(uint256)" --block $block_num | sed 's/\[[^]]*\]//g')
denominator=$(cast call $1 "DENOMINATOR()(uint256)" --block $block_num | sed 's/\[[^]]*\]//g')

stakerWeiBefore=$(cast rpc eth_getBalance $staker $block | tr -d '"' | cast to-dec --base-in 16)
ownerWeiBefore=$(cast rpc eth_getBalance $owner $block | tr -d '"' | cast to-dec --base-in 16)

rewardsBeforeStaking=$(cast call $1 "getRewards()(uint256)" --block $block_num | sed 's/\[[^]]*\]//g')
taxedRewardsBeforeStaking=$(cast call $1 "getTaxedRewards()(uint256)" --block $block_num | sed 's/\[[^]]*\]//g')
depositBeforeStaking=$(cast call $1 "getStake()(uint256)" --block $block_num | sed 's/\[[^]]*\]//g')
echo rewardsBeforeStaking = $rewardsBeforeStaking
echo taxedRewardsBeforeStaking = $taxedRewardsBeforeStaking
echo depositBeforeStaking = $depositBeforeStaking

if [[ "$variant" == "LiquidStaking" ]];  then
    echo validator commission - gas fee = $(bc -l <<< "scale=18; $ownerWeiAfter-$ownerWeiBefore") wei
else
    echo staker gas fee = $(bc -l <<< "scale=18; $stakerWeiAfter-$stakerWeiBefore") wei
    echo validator commission = $(bc -l <<< "scale=18; $ownerWeiAfter-$ownerWeiBefore") wei
fi
echo total reward reduction = $(bc -l <<< "scale=18; $rewardsBeforeStaking-$rewardsAfterStaking") wei

if [[ "$tmp1" != "" ]]; then echo event CommissionPaid\($staker, $d1\) emitted; fi

echo $(date +"%T,%3N") $block_num