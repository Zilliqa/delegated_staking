#!/bin/bash

if [ $# -lt 2 ]; then
    echo "Provide the delegation contract address, a staker private key and optionally the number of shares as arguments."
    exit 1
fi

if [ $# -eq 3 ]; then
    shares="$3"
else
    shares=0
fi

staker=$(cast wallet address $2)

temp=$(forge script script/variant_Delegation.s.sol --rpc-url http://localhost:4201 --sig "run(address payable)" $1 | tail -n 1)
variant=$(sed -E 's/\s\s([a-zA-Z0-9]+)/\1/' <<< "$temp")
if [[ "$variant" == "$temp" ]]; then
    echo Incompatible delegation contract at $1
    exit 1
fi

forge script script/unstake_Delegation.s.sol --rpc-url http://localhost:4201 --broadcast --legacy --sig "run(address payable, uint256)" $1 $shares --private-key $2

block=$(cast rpc eth_blockNumber --rpc-url http://localhost:4201)
block_num=$(echo $block | tr -d '"' | cast to-dec --base-in 16)

echo rewardsAfterUnstaking = $(cast call $1 "getRewards()(uint256)" --block $block_num --rpc-url http://localhost:4201 | sed 's/\[[^]]*\]//g')
if [[ "$variant" == "ILiquidDelegation" ]]; then
    echo taxedRewardsAfterUnstaking = $(cast call $1 "getTaxedRewards()(uint256)" --block $block_num --rpc-url http://localhost:4201 | sed 's/\[[^]]*\]//g')
fi

tmp=$(cast logs --from-block $block_num --to-block $block_num --address $1 "Unstaked(address,uint256,bytes)" --rpc-url http://localhost:4201 | grep "data")
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

block_num=$((block_num-1))
block=$(echo $block_num | cast to-hex --base-in 10)

rewardsBeforeUnstaking=$(cast call $1 "getRewards()(uint256)" --block $block_num --rpc-url http://localhost:4201 | sed 's/\[[^]]*\]//g')
echo rewardsBeforeUnstaking = $rewardsBeforeUnstaking

stake=$(cast call $1 "getStake()(uint256)" --block $block_num --rpc-url http://localhost:4201 | sed 's/\[[^]]*\]//g')
commissionNumerator=$(cast call $1 "getCommissionNumerator()(uint256)" --block $block_num --rpc-url http://localhost:4201 | sed 's/\[[^]]*\]//g')
denominator=$(cast call $1 "DENOMINATOR()(uint256)" --block $block_num --rpc-url http://localhost:4201 | sed 's/\[[^]]*\]//g')
if [[ "$variant" == "ILiquidDelegation" ]]; then
    taxedRewardsBeforeUnstaking=$(cast call $1 "getTaxedRewards()(uint256)" --block $block_num --rpc-url http://localhost:4201 | sed 's/\[[^]]*\]//g')
    echo taxedRewardsBeforeUnstaking = $taxedRewardsBeforeUnstaking
    lst=$(cast call $1 "getLST()(address)" --block $block_num --rpc-url http://localhost:4201)
    if [[ "$shares" == "0" ]]; then shares=$(cast call $lst "balanceOf(address)(uint256)" $staker --block $block_num --rpc-url http://localhost:4201 | sed 's/\[[^]]*\]//g'); fi
    totalSupply=$(cast call $lst "totalSupply()(uint256)" --block $block_num --rpc-url http://localhost:4201 | sed 's/\[[^]]*\]//g')
    price=$(bc -l <<< "scale=36; ($stake+$rewardsBeforeUnstaking-($rewardsBeforeUnstaking-$taxedRewardsBeforeUnstaking)*$commissionNumerator/$denominator)/$totalSupply")
    price0=$(cast call $1 "getPrice()(uint256)" --block $block_num --rpc-url http://localhost:4201 | sed 's/\[[^]]*\]//g')
    echo LST price: $price \~ $(cast to-unit $price0 ether)
    echo unstaked LST value: $(bc -l <<< "scale=18; $shares*$price/10^18") ZIL
fi

if [[ "$tmp" != "" ]]; then echo event Unstaked\($staker, $d1, $d2\) emitted; fi

echo $(date +"%T,%3N") $block_num