#!/bin/bash

url=http://localhost:4201

if [ $# -lt 2 ]; then
    echo "Provide the delegation contract address, a staker private key and optionally an amount and number of steps as arguments."
    exit 1
fi

if [ $# -eq 3 ]; then
    amount="$3"
else
    amount="all"
fi

if [ $# -eq 4 ]; then
    steps="$4"
else
    steps="all"
fi

staker=$(cast wallet address $2)

temp=$(forge script script/variant_Delegation.s.sol --rpc-url $url --sig "run(address payable)" $1 | tail -n 1)
variant=$(sed -E 's/\s\s([a-zA-Z0-9]+)/\1/' <<< "$temp")
if [[ "$variant" == "$temp" ]]; then
    echo Incompatible delegation contract at $1
    exit 1
fi
if [[ "$variant" != "INonLiquidDelegation" ]]; then
    echo Reward withdrawal not supported by $1
    exit 1
fi

forge script script/withdrawRewards_Delegation.s.sol --rpc-url $url --broadcast --legacy --sig "run(address payable, string, string)" $1 $amount $steps --private-key $2

block=$(cast rpc eth_blockNumber --rpc-url $url)
block_num=$(echo $block | tr -d '"' | cast to-dec --base-in 16)

owner=$(cast call $1 "owner()(address)" --block $block_num --rpc-url $url)

rewardsAfterWithdrawal=$(cast call $1 "getRewards()(uint256)" --block $block_num --rpc-url $url | sed 's/\[[^]]*\]//g')
echo rewardsAfterWithdrawal = $rewardsAfterWithdrawal

stakerWeiAfter=$(cast rpc eth_getBalance $staker $block --rpc-url $url | tr -d '"' | cast to-dec --base-in 16)
ownerWeiAfter=$(cast rpc eth_getBalance $owner $block --rpc-url $url | tr -d '"' | cast to-dec --base-in 16)

tmp1=$(cast logs --from-block $block_num --to-block $block_num --address $1 "RewardPaid(address,uint256)" --rpc-url $url | grep "data")
if [[ "$tmp1" != "" ]]; then
    tmp1=${tmp1#*: }
    tmp1=$(cast abi-decode --input "x(uint256)" $tmp1 | sed 's/\[[^]]*\]//g')
    tmp1=(${tmp1})
    d1=${tmp1[0]}
    #d1=$(echo $tmp | sed -n -e 1p | sed 's/\[[^]]*\]//g')
fi

tmp2=$(cast logs --from-block $block_num --to-block $block_num --address $1 "CommissionPaid(address,uint256)" --rpc-url $url | grep "data")
if [[ "$tmp2" != "" ]]; then
    tmp2=${tmp2#*: }
    tmp2=$(cast abi-decode --input "x(uint256)" $tmp2 | sed 's/\[[^]]*\]//g')
    tmp2=(${tmp2})
    d2=${tmp2[0]}
    #d2=$(echo $tmp2 | sed -n -e 1p | sed 's/\[[^]]*\]//g')
fi

x=$(cast call $1 "rewards()(uint256)" --from $staker --block $block_num --rpc-url $url | sed 's/\[[^]]*\]//g')
staker_rewards_after_withdrawal=$(cast to-unit $x ether)

echo $(date +"%T,%3N") $block_num

block_num=$((block_num-1))
block=$(echo $block_num | cast to-hex --base-in 10)

rewardsBeforeWithdrawal=$(cast call $1 "getRewards()(uint256)" --block $block_num --rpc-url $url | sed 's/\[[^]]*\]//g')
echo rewardsBeforeWithdrawal = $rewardsBeforeWithdrawal

stake=$(cast call $1 "getStake()(uint256)" --block $block_num --rpc-url $url | sed 's/\[[^]]*\]//g')
commissionNumerator=$(cast call $1 "getCommissionNumerator()(uint256)" --block $block_num --rpc-url $url | sed 's/\[[^]]*\]//g')
denominator=$(cast call $1 "DENOMINATOR()(uint256)" --block $block_num --rpc-url $url | sed 's/\[[^]]*\]//g')

stakerWeiBefore=$(cast rpc eth_getBalance $staker $block --rpc-url $url | tr -d '"' | cast to-dec --base-in 16)
ownerWeiBefore=$(cast rpc eth_getBalance $owner $block --rpc-url $url | tr -d '"' | cast to-dec --base-in 16)

x=$(cast call $1 "rewards()(uint256)" --from $staker --block $block_num --rpc-url $url | sed 's/\[[^]]*\]//g')
staker_rewards_before_withdrawal=$(cast to-unit $x ether)

echo staker rewards before withdrawal: $staker_rewards_before_withdrawal ZIL
echo staker rewards after withdrawal: $staker_rewards_after_withdrawal ZIL
echo withdrawn rewards - gas fee = $(bc -l <<< "scale=18; $stakerWeiAfter-$stakerWeiBefore") wei
echo validator commission = $(bc -l <<< "scale=18; $ownerWeiAfter-$ownerWeiBefore") wei
echo total reward reduction = $(bc -l <<< "scale=18; $rewardsBeforeWithdrawal-$rewardsAfterWithdrawal") wei

if [[ "$tmp1" != "" ]]; then echo event RewardPaid\($staker, $d1\) emitted; fi
if [[ "$tmp2" != "" ]]; then echo event CommissionPaid\($owner, $d2\) emitted; fi

echo $(date +"%T,%3N") $block_num