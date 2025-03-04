#!/bin/bash

if [ $# -lt 2 ]; then
  echo "Provide the delegation contract address, a staker address and optionally, a block number as arguments."
  exit 1
fi

temp=$(forge script script/CheckVariant.s.sol --sig "run(address payable)" $1 | tail -n 1)
variant=$(sed -E 's/\s\s([a-zA-Z0-9]+)/\1/' <<< "$temp")
if [[ "$variant" == "$temp" ]]; then
    echo Incompatible delegation contract at $1
    exit 1
fi

if [ $# -eq 3 ]; then
    block_num=$3
    block=$(echo $block_num | cast to-hex --base-in 10)
else
    block=$(cast rpc eth_blockNumber)
    block_num=$(echo $block | tr -d '"' | cast to-dec --base-in 16)
fi
echo $(date +"%T,%3N") $block_num

owner=$(cast call $1 "owner()(address)" --block $block_num)

rewardsBeforeUnstaking=$(cast call $1 "getRewards()(uint256)" --block $block_num | sed 's/\[[^]]*\]//g')
#rewardsBeforeUnstaking=$(cast rpc eth_getBalance $1 $block | tr -d '"' | cast to-dec --base-in 16)
echo rewardsBeforeUnstaking = $rewardsBeforeUnstaking

x=$(cast rpc eth_getBalance $owner $block | tr -d '"' | cast to-dec --base-in 16)
owner_zil=$(cast to-unit $x ether)
x=$(cast rpc eth_getBalance $2 $block | tr -d '"' | cast to-dec --base-in 16)
staker_zil=$(cast to-unit $x ether)

if [[ "$variant" == "LiquidStaking" ]]; then
    taxedRewardsBeforeUnstaking=$(cast call $1 "getTaxedRewards()(uint256)" --block $block_num | sed 's/\[[^]]*\]//g')
    echo taxedRewardsBeforeUnstaking = $taxedRewardsBeforeUnstaking

    lst=$(cast call $1 "getLST()(address)" --block $block_num)
    symbol=$(cast call $lst "symbol()(string)" --block $block_num | tr -d '"')
    x=$(cast call $lst "balanceOf(address)(uint256)" $owner --block $block_num | sed 's/\[[^]]*\]//g')
    owner_lst=$(cast to-unit $x ether)
    x=$(cast call $lst "balanceOf(address)(uint256)" $2 --block $block_num | sed 's/\[[^]]*\]//g')
    staker_lst=$(cast to-unit $x ether)
    echo owner: $owner_lst $symbol && echo owner: $owner_zil ZIL unstaked
    echo staker: $staker_lst $symbol && echo staker: $staker_zil ZIL unstaked
else
    x=$(cast call $1 "getDelegatedAmount()(uint256)" --from $owner --block $block_num | sed 's/\[[^]]*\]//g')
    owner_staked=$(cast to-unit $x ether)
    x=$(cast call $1 "getDelegatedAmount()(uint256)" --from $2 --block $block_num | sed 's/\[[^]]*\]//g')
    staker_staked=$(cast to-unit $x ether)
    echo owner: $owner_staked ZIL staked && echo owner: $owner_zil ZIL unstaked
    echo staker: $staker_staked ZIL staked && echo staker: $staker_zil ZIL unstaked
fi

stake=$(cast call $1 "getStake()(uint256)" --block $block_num | sed 's/\[[^]]*\]//g')
commissionNumerator=$(cast call $1 "getCommissionNumerator()(uint256)" --block $block_num | sed 's/\[[^]]*\]//g')
denominator=$(cast call $1 "DENOMINATOR()(uint256)" --block $block_num | sed 's/\[[^]]*\]//g')
if [[ "$variant" == "LiquidStaking" ]]; then
    totalSupply=$(cast call $lst "totalSupply()(uint256)" --block $block_num | sed 's/\[[^]]*\]//g')
    if [[ $totalSupply -ne 0 ]]; then
        price=$(bc -l <<< "scale=36; ($stake+$rewardsBeforeUnstaking-($rewardsBeforeUnstaking-$taxedRewardsBeforeUnstaking)*$commissionNumerator/$denominator)/$totalSupply")
    else
        price=$(bc -l <<< "scale=36; 1/1")
    fi
    price0=$(cast call $1 "getPrice()(uint256)" --block $block_num | sed 's/\[[^]]*\]//g')
    echo $symbol supply: $(cast to-unit $totalSupply ether)
    echo $symbol price: $price \~ $(cast to-unit $price0 ether) ZIL
    echo staker $symbol value: $(bc -l <<< "scale=18; $staker_lst*$price") ZIL
else
    x=$(cast call $1 "rewards()(uint256)" --from $2 --block $block_num | sed 's/\[[^]]*\]//g')
    staker_rewards=$(cast to-unit $x ether)
    echo staker rewards: $staker_rewards ZIL
fi

claimable=$(cast call $1 "getClaimable()(uint256)" --from $2 --block $block_num | sed 's/\[[^]]*\]//g')
echo staker claimable: $(cast to-unit $claimable ether) ZIL

echo validator deposit: $(cast to-unit $stake ether) ZIL

validatorBalance=$(cast rpc eth_getBalance $1 $block | tr -d '"' | cast to-dec --base-in 16)
echo validator balance: $(cast to-unit $validatorBalance ether) ZIL

pendingWithdrawals=$(cast call $1 "totalPendingWithdrawals()(uint256)" --block $block_num | sed 's/\[[^]]*\]//g')
echo pending withdrawals: $(cast to-unit $pendingWithdrawals ether) ZIL

totalStake=$(cast call 0x00000000005A494C4445504F53495450524F5859 "getFutureTotalStake()(uint256)" --block $block_num | sed 's/\[[^]]*\]//g')
echo total stake: $(cast to-unit $totalStake ether) ZIL

depositBalance=$(cast rpc eth_getBalance 0x00000000005A494C4445504F53495450524F5859 $block | tr -d '"' | cast to-dec --base-in 16)
echo deposit balance: $(cast to-unit $depositBalance ether) ZIL
