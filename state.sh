#!/bin/bash

if [ $# -ne 2 ]; then
  echo "Provide the delegation contract address and a staker address as arguments."
  exit 1
fi

temp=$(forge script script/variant_Delegation.s.sol --rpc-url http://localhost:4201 --sig "run(address payable)" $1 | tail -n 1)
variant=$(sed -E 's/\s\s([a-zA-Z0-9]+)/\1/' <<< "$temp")
if [[ "$variant" == "$temp" ]]; then
    echo Incompatible delegation contract at $1
    exit 1
fi

block=$(cast rpc eth_blockNumber --rpc-url http://localhost:4201)
block_num=$(echo $block | tr -d '"' | cast to-dec --base-in 16)
echo $(date +"%T,%3N") $block_num

owner=$(cast call $1 "owner()(address)" --block $block_num --rpc-url http://localhost:4201)

rewardsBeforeUnstaking=$(cast call $1 "getRewards()(uint256)" --block $block_num --rpc-url http://localhost:4201 | sed 's/\[[^]]*\]//g')
#rewardsBeforeUnstaking=$(cast rpc eth_getBalance $1 $block --rpc-url http://localhost:4201 | tr -d '"' | cast to-dec --base-in 16)
echo rewardsBeforeUnstaking = $rewardsBeforeUnstaking

x=$(cast rpc eth_getBalance $owner $block --rpc-url http://localhost:4201 | tr -d '"' | cast to-dec --base-in 16)
owner_zil=$(cast to-unit $x ether)
x=$(cast rpc eth_getBalance $2 $block --rpc-url http://localhost:4201 | tr -d '"' | cast to-dec --base-in 16)
staker_zil=$(cast to-unit $x ether)

if [[ "$variant" == "ILiquidDelegation" ]]; then
    taxedRewardsBeforeUnstaking=$(cast call $1 "getTaxedRewards()(uint256)" --block $block_num --rpc-url http://localhost:4201 | sed 's/\[[^]]*\]//g')
    echo taxedRewardsBeforeUnstaking = $taxedRewardsBeforeUnstaking

    lst=$(cast call $1 "getLST()(address)" --block $block_num --rpc-url http://localhost:4201)
    x=$(cast call $lst "balanceOf(address)(uint256)" $owner --block $block_num --rpc-url http://localhost:4201 | sed 's/\[[^]]*\]//g')
    owner_lst=$(cast to-unit $x ether)
    x=$(cast call $lst "balanceOf(address)(uint256)" $2 --block $block_num --rpc-url http://localhost:4201 | sed 's/\[[^]]*\]//g')
    staker_lst=$(cast to-unit $x ether)
    echo owner: $owner_lst LST && echo owner: $owner_zil ZIL unstaked
    echo staker: $staker_lst LST && echo staker: $staker_zil ZIL unstaked
else
    x=$(cast call $1 "getDelegatedStake()(uint256)" --from $owner --block $block_num --rpc-url http://localhost:4201 | sed 's/\[[^]]*\]//g')
    owner_staked=$(cast to-unit $x ether)
    x=$(cast call $1 "getDelegatedStake()(uint256)" --from $2 --block $block_num --rpc-url http://localhost:4201 | sed 's/\[[^]]*\]//g')
    staker_staked=$(cast to-unit $x ether)
    echo owner: $owner_staked ZIL staked && echo owner: $owner_zil ZIL unstaked
    echo staker: $staker_staked ZIL staked && echo staker: $staker_zil ZIL unstaked
fi

stake=$(cast call $1 "getStake()(uint256)" --block $block_num --rpc-url http://localhost:4201 | sed 's/\[[^]]*\]//g')
commissionNumerator=$(cast call $1 "getCommissionNumerator()(uint256)" --block $block_num --rpc-url http://localhost:4201 | sed 's/\[[^]]*\]//g')
denominator=$(cast call $1 "DENOMINATOR()(uint256)" --block $block_num --rpc-url http://localhost:4201 | sed 's/\[[^]]*\]//g')
if [[ "$variant" == "ILiquidDelegation" ]]; then
    totalSupply=$(cast call $lst "totalSupply()(uint256)" --block $block_num --rpc-url http://localhost:4201 | sed 's/\[[^]]*\]//g')
    if [[ $totalSupply -ne 0 ]]; then
        price=$(bc -l <<< "scale=36; ($stake+$rewardsBeforeUnstaking-($rewardsBeforeUnstaking-$taxedRewardsBeforeUnstaking)*$commissionNumerator/$denominator)/$totalSupply")
    else
        price=$(bc -l <<< "scale=36; 1/1")
    fi
    price0=$(cast call $1 "getPrice()(uint256)" --block $block_num --rpc-url http://localhost:4201 | sed 's/\[[^]]*\]//g')
    echo LST supply: $(cast to-unit $totalSupply ether) ZIL
    echo LST price: $price \~ $(cast to-unit $price0 ether)
    echo staker LST value: $(bc -l <<< "scale=18; $staker_lst*$price") ZIL
else
    x=$(cast call $1 "rewards()(uint256)" --from $2 --block $block_num --rpc-url http://localhost:4201 | sed 's/\[[^]]*\]//g')
    staker_rewards=$(cast to-unit $x ether)
    echo staker rewards: $staker_rewards ZIL
fi

claimable=$(cast call $1 "getClaimable()(uint256)" --from $2 --block $block_num --rpc-url http://localhost:4201 | sed 's/\[[^]]*\]//g')
echo staker claimable: $(cast to-unit $claimable ether) ZIL

echo validator stake: $(cast to-unit $stake ether) ZIL
echo pending withdrawals: $(cast call $1 "getTotalWithdrawals()(uint256)" --block $block_num --rpc-url http://localhost:4201 | sed 's/\[[^]]*\]//g') wei