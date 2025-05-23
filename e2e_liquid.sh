#!/bin/bash

export FOUNDRY_ETH_RPC_URL=http://198.51.100.100:4201
export PRIVATE_KEY=0x$(openssl rand -hex 32)
OWNER_KEY=$PRIVATE_KEY
OWNER_ADDRESS=$(cast wallet address $OWNER_KEY)
STAKER_KEY=0x$(openssl rand -hex 32)
STAKER_ADDRESS=$(cast wallet address $STAKER_KEY)
CONTRACT_ADDRESS=$(cast compute-address $(cast wallet address $OWNER_KEY) --nonce 1  | cut -d ' ' -f 3)
COMMISSION_ADDRESS=$(cast wallet address 0x$(openssl rand -hex 32))
DEPOSIT_ADDRESS=0x00000000005a494c4445504f53495450524f5859
BLS_PUB_KEY_1=0xb27aebb3b54effd7af87c4a064a711554ee0f3f5abf56ca910b46422f2b21603bc383d42eb3b927c4c3b0b8381ca30a3
CONTROL_KEY_1=0x65d7f4da9bedc8fb79cbf6722342960bbdfb9759bc0d9e3fb4989e831ccbc227
BLS_PUB_KEY_2=0xb37fd66aef29ca78a82d519a284789d59c2bb3880698b461c6c732d094534707d50e345128db372a1e0a4c5d5c42f49c
CONTROL_KEY_2=0x62070b1a3b5b30236e43b4f1bfd617e1af7474635558314d46127a708b9d302e
BLS_PUB_KEY_3=0xab035d6cd3321c3b57d14ea09a4f3860899542d2187b5ec87649b1f40980418a096717a671cf62b73880afac252fc5dc
CONTROL_KEY_3=0x56d7a450d75c6ba2706ef71da6ca80143ec4971add9c44d7d129a12fa7d3a364
BLS_PUB_KEY_4=0x985e3a4d367cbfc966d48710806612cc00f6bfd06aa759340cfe13c3990d26a7ddde63f64468cdba5b2ff132a4639a7f
CONTROL_KEY_4=0xdb670cbff28f4b15297d03fafdab8f5303d68b7591bd59e31eaef215dd0f246a



staker() {
    # $1 = 2-digit index
    # $2 = STAKER_KEY or STAKER_ADDRESS
    STAKER_KEY=${STAKER_KEY:0:64}$1
    STAKER_ADDRESS=$(cast wallet address $STAKER_KEY)
    local var=$2
    echo ${!var}
}



unbond() {
    # sleep two times as many seconds as many blocks the deposit withdrawal period
    # consists of to wait long enough even if there is a 2 second average block time
    sleep $(cast call $DEPOSIT_ADDRESS "withdrawalPeriod()(uint256)")
    sleep $(cast call $DEPOSIT_ADDRESS "withdrawalPeriod()(uint256)")
}



join_one() {
    # $1 = blsPubKey
    # $2 = privKey
    echo "🔽🔽🔽🔽🔽🔽🔽🔽🔽🔽🔽🔽🔽🔽🔽🔽"
    cast send --legacy --value 100ether --private-key 0x0000000000000000000000000000000000000000000000000000000000000002 $(cast wallet address $2) 1>/dev/null
    status=$(cast send --legacy --json --private-key $2 $CONTRACT_ADDRESS "registerControlAddress(bytes)" $1 | jq '.status') 1>/dev/null
    if [[ "$status" == "\"0x1\"" ]]; then
        echo "🟢 registerControlAddress($1)"
    else
        echo "🔴 registerControlAddress($1)"
    fi
    status=$(cast send --legacy --json --private-key $2 $DEPOSIT_ADDRESS "setControlAddress(bytes,address)" $1 $CONTRACT_ADDRESS | jq '.status') 1>/dev/null
    if [[ "$status" == "\"0x1\"" ]]; then
        echo "🟢 setControlAddress($1, $(cast wallet address $2))"
    else
        echo "🔴 setControlAddress($1, $(cast wallet address $2))"
    fi
    status=$(cast send --legacy --json --private-key $OWNER_KEY $CONTRACT_ADDRESS "joinPool(bytes)" $1 | jq '.status') 1>/dev/null
    if [[ "$status" == "\"0x1\"" ]]; then
        echo "🟢 joinPool($1)"
    else
        echo "🔴 joinPool($1)"
    fi
    echo -n "🟢 validators: " && cast call $CONTRACT_ADDRESS "validators()((bytes,uint256,bool,bool,bool,bool)[])" | sed 's/ \[[0-9]e[0-9][0-9]\]//g' | sed 's/, true//g' | sed 's/, false//g' | sed 's/0x[0-9a-f]*,//g' | sed 's/( //g' | sed 's/)//g'
    echo "🔼🔼🔼🔼🔼🔼🔼🔼🔼🔼🔼🔼🔼🔼🔼🔼"
}



leave_one() {
    # $1 = blsPubKey
    # $2 = privKey
    echo "🔽🔽🔽🔽🔽🔽🔽🔽🔽🔽🔽🔽🔽🔽🔽🔽"
    echo -n "🟢 controller balance: " && cast to-unit $(cast balance $(cast wallet address $2)) ether
    echo -n "🟢 committee: " && cast call $DEPOSIT_ADDRESS "getStakersData()(bool[],uint256[],uint256[])" | tail -1 | sed 's/ \[[0-9]e[0-9][0-9]\]//g'
    echo -n "🟢 validators: " && cast call $CONTRACT_ADDRESS "validators()((bytes,uint256,bool,bool,bool,bool)[])" | sed 's/ \[[0-9]e[0-9][0-9]\]//g' | sed 's/, true//g' | sed 's/, false//g' | sed 's/0x[0-9a-f]*,//g' | sed 's/( //g' | sed 's/)//g'
    pending=$(cast call $CONTRACT_ADDRESS "pendingWithdrawals(bytes)(bool)" $1)
    echo -n "🟢 pending withdrawals: " && echo $pending

    while [[ "$pending" == "true" ]]; do
        status=$(cast send --legacy --json --private-key $2 $CONTRACT_ADDRESS "leavePool(bytes)" $1 | jq '.status') 1>/dev/null
        if [[ "$status" == "\"0x1\"" ]]; then
            echo "🟢 leavePool($1)"
        else
            echo "🔴 leavePool($1)"
        fi

        echo "############################### UNBONDING ##############################"
        unbond
        echo "############################### RETRYING ##############################"

        count=$(cast call $CONTRACT_ADDRESS "validators()((bytes,uint256,bool,bool,bool,bool)[])" | grep -c -o "$1")
        if [[ $count -gt 0 ]]; then
            pending=$(cast call $CONTRACT_ADDRESS "pendingWithdrawals(bytes)(bool)" $1)
            echo -n "🟢 pending withdrawals: " && echo $pending
        else
            pending="false"
        fi
    done

    count=$(cast call $CONTRACT_ADDRESS "validators()((bytes,uint256,bool,bool,bool,bool)[])" | grep -c -o "$1")
    if [[ $count -gt 0 ]]; then
        temp=$(cast send --legacy --gas-limit 1000000 --json --private-key $2 $CONTRACT_ADDRESS "leavePool(bytes)" $1)
        #temp=$(cast send --legacy --json --private-key $2 $CONTRACT_ADDRESS "leavePool(bytes)" $1)
        status=$(echo $temp | jq '.status')
        if [[ "$status" == "\"0x1\"" ]]; then
            echo "🟢 leavePool($1) $(echo $temp | jq '.transactionHash')"
        else
            echo "🔴 leavePool($1) $(echo $temp | jq '.transactionHash')"
        fi
    fi

    echo -n "🟢 committee: " && cast call $DEPOSIT_ADDRESS "getStakersData()(bool[],uint256[],uint256[])" | tail -1 | sed 's/ \[[0-9]e[0-9][0-9]\]//g'
    echo -n "🟢 validators: " && cast call $CONTRACT_ADDRESS "validators()((bytes,uint256,bool,bool,bool,bool)[])"  | sed 's/ \[[0-9]e[0-9][0-9]\]//g' | sed 's/, true//g' | sed 's/, false//g' | sed 's/0x[0-9a-f]*,//g' | sed 's/( //g' | sed 's/)//g'
    count=$(cast call $CONTRACT_ADDRESS "validators()((bytes,uint256,bool,bool,bool,bool)[])" | grep -c -o "$1")
    if [[ $count -gt 0 ]]; then
        pending=$(cast call $CONTRACT_ADDRESS "pendingWithdrawals(bytes)(bool)" $1)
        echo -n "🟢 pending withdrawals: " && echo $pending
    fi

    echo "############################### UNBONDING DEPOSIT DECREASE / STAKE REFUND ##############################"
    unbond

    count=$(cast call $CONTRACT_ADDRESS "validators()((bytes,uint256,bool,bool,bool,bool)[])" | grep -c -o "$1")
    if [[ $count -gt 0 ]]; then
        echo "############################### COMPLETING ##############################"

        echo -n "🟢 committee: " && cast call $DEPOSIT_ADDRESS "getStakersData()(bool[],uint256[],uint256[])" | tail -1 | sed 's/ \[[0-9]e[0-9][0-9]\]//g'
        echo -n "🟢 validators: " && cast call $CONTRACT_ADDRESS "validators()((bytes,uint256,bool,bool,bool,bool)[])" | sed 's/ \[[0-9]e[0-9][0-9]\]//g' | sed 's/, true//g' | sed 's/, false//g' | sed 's/0x[0-9a-f]*,//g' | sed 's/( //g' | sed 's/)//g'
        pending=$(cast call $CONTRACT_ADDRESS "pendingWithdrawals(bytes)(bool)" $1)
        echo -n "🟢 pending withdrawals: " && echo $pending

        temp=$(cast send --legacy --gas-limit 1000000 --json --private-key $2 $CONTRACT_ADDRESS "completeLeaving(bytes)" $1)
        #temp=$(cast send --legacy --json --private-key $2 $CONTRACT_ADDRESS "completeLeaving(bytes)" $1)
        status=$(echo $temp | jq '.status')
        if [[ "$status" == "\"0x1\"" ]]; then
            echo "🟢 completeLeaving($1) $(echo $temp | jq '.transactionHash')"
        else
            echo "🔴 completeLeaving($1) $(echo $temp | jq '.transactionHash')"
        fi
    fi

    status=$(cast send --legacy --json --private-key $2 $CONTRACT_ADDRESS "claim()" | jq '.status') 1>/dev/null
    if [[ "$status" == "\"0x1\"" ]]; then
        echo "🟢 claim()"
    else
        echo "🔴 claim()"
    fi

    # sleep four times as many seconds as many blocks an epoch consists of
    # to wait long enough even if there is a 2 second average block time
    sleep $(cast call $DEPOSIT_ADDRESS "blocksPerEpoch()(uint64)")
    sleep $(cast call $DEPOSIT_ADDRESS "blocksPerEpoch()(uint64)")
    sleep $(cast call $DEPOSIT_ADDRESS "blocksPerEpoch()(uint64)")
    sleep $(cast call $DEPOSIT_ADDRESS "blocksPerEpoch()(uint64)")

    echo -n "🟢 committee: " && cast call $DEPOSIT_ADDRESS "getStakersData()(bool[],uint256[],uint256[])" | tail -1 | sed 's/ \[[0-9]e[0-9][0-9]\]//g'
    echo -n "🟢 validators: " && cast call $CONTRACT_ADDRESS "validators()((bytes,uint256,bool,bool,bool,bool)[])" | sed 's/ \[[0-9]e[0-9][0-9]\]//g' | sed 's/, true//g' | sed 's/, false//g' | sed 's/0x[0-9a-f]*,//g' | sed 's/( //g' | sed 's/)//g'
    echo -n "🟢 controller balance: " && cast to-unit $(cast balance $(cast wallet address $2)) ether
    echo "🔼🔼🔼🔼🔼🔼🔼🔼🔼🔼🔼🔼🔼🔼🔼🔼"
}



#: '🟪🟪🟪🟪🟪🟪🟪🟪🟪🟪🟪🟪🟪🟪🟪🟪🟪🟪🟪🟪🟪🟪🟪🟪🟪🟪🟪🟪🟪🟪🟪🟪🟪🟪🟪🟪🟪🟪🟪🟪🟪🟪🟪🟪🟪🟪
#   🟪 remove # at the beginning of the line above to continue execution at the marked location  🟪
echo "############################### RESTARTING ##############################"
cd ../zq2/
docker-compose down
docker-compose up -d
cd ../delegated_staking/
errors=1
while [ $errors -gt 0 ]; do
    echo "🔴 block production has not started"
    sleep 5s
    temp=$(cast block-number 2>&1)
    errors=$(echo $temp | grep -o -i -e "error" | wc -l)
done
echo "🟢 block production has started"



echo "############################### DEPLOYING ##############################"
cast send --legacy --value 100ether --private-key 0x0000000000000000000000000000000000000000000000000000000000000002 $OWNER_ADDRESS 1>/dev/null
temp=$(forge script script/Deploy.s.sol --broadcast --legacy --sig "liquidDelegation(string,string)" Token LST 2>&1 1>/dev/null)
errors=$(echo $temp | grep -o -i -e "error" -e "fail" -e "revert" | wc -l)
if [ $errors -eq 0 ]; then
    echo "🟢 Deploy liquidDelegation(string,string)"
else
    echo "🔴 Deploy liquidDelegation(string,string) $temp"
fi
echo $CONTRACT_ADDRESS
temp=$(forge script script/Configure.s.sol --broadcast --legacy --sig "commissionRate(address payable, uint16)" $CONTRACT_ADDRESS 1000 2>&1 1>/dev/null)
errors=$(echo $temp | grep -o -i -e "error" -e "fail" -e "revert" | wc -l)
if [ $errors -eq 0 ]; then
    echo "🟢 Configure commissionRate(address payable, uint16)"
else
    echo "🔴 Configure commissionRate(address payable, uint16) $temp"
fi
temp=$(forge script script/Configure.s.sol --broadcast --legacy --sig "commissionReceiver(address payable, address)" $CONTRACT_ADDRESS $COMMISSION_ADDRESS 2>&1 1>/dev/null)
errors=$(echo $temp | grep -o -i -e "error" -e "fail" -e "revert" | wc -l)
if [ $errors -eq 0 ]; then
    echo "🟢 Configure commissionReceiver(address payable, address)"
else
    echo "🔴 Configure commissionReceiver(address payable, address) $temp"
fi



join_all() {
    echo "############################### JOINING ##############################"
    echo -n "🟢 committee: " && cast call $DEPOSIT_ADDRESS "getStakersData()(bool[],uint256[],uint256[])" | tail -1 | sed 's/ \[[0-9]e[0-9][0-9]\]//g'
    echo -n "🟢 validators: " && cast call $CONTRACT_ADDRESS "validators()((bytes,uint256,bool,bool,bool,bool)[])" | sed 's/ \[[0-9]e[0-9][0-9]\]//g' | sed 's/, true//g' | sed 's/, false//g' | sed 's/0x[0-9a-f]*,//g' | sed 's/( //g' | sed 's/)//g'
    join_one $BLS_PUB_KEY_1 $CONTROL_KEY_1
    join_one $BLS_PUB_KEY_2 $CONTROL_KEY_2
    join_one $BLS_PUB_KEY_3 $CONTROL_KEY_3
    join_one $BLS_PUB_KEY_4 $CONTROL_KEY_4
}



stake_one() {
    # $1 = 2-digit staker index
    # $2 = amount
    echo "############################### STAKING ##############################"
    echo -n "🟢 staker balance: " && cast to-unit $(cast balance $(staker $1 STAKER_ADDRESS)) ether
    echo -n "🟢 lst balance: " && cast to-unit $(cast call $(cast call $CONTRACT_ADDRESS "getLST()(address)") "balanceOf(address)(uint256)" $(staker $1 STAKER_ADDRESS) | sed 's/\[[^]]*\]//g') ether
    echo -n "🟢 lst price: " && cast to-unit $(cast call $CONTRACT_ADDRESS "getPrice()(uint256)" | sed 's/\[[^]]*\]//g') ether
    echo -n "🟢 commission: " && cast to-unit $(cast balance $COMMISSION_ADDRESS) ether
    temp=$(forge script script/Stake.s.sol --broadcast --legacy --sig "run(address payable, uint256)" $CONTRACT_ADDRESS $2 --private-key $(staker $1 STAKER_KEY) 2>&1 1>/dev/null)
    errors=$(echo $temp | grep -o -i -e "error" -e "fail" -e "revert" | wc -l)
    if [ $errors -eq 0 ]; then
        echo "🟢 Stake $1"
    else
        echo "🔴 Stake $1 $temp"
    fi
    echo -n "🟢 commission: " && cast to-unit $(cast balance $COMMISSION_ADDRESS) ether
    echo -n "🟢 lst balance: " && cast to-unit $(cast call $(cast call $CONTRACT_ADDRESS "getLST()(address)") "balanceOf(address)(uint256)" $(staker $1 STAKER_ADDRESS) | sed 's/\[[^]]*\]//g') ether
    echo -n "🟢 lst price: " && cast to-unit $(cast call $CONTRACT_ADDRESS "getPrice()(uint256)" | sed 's/\[[^]]*\]//g') ether
    echo -n "🟢 staker balance: " && cast to-unit $(cast balance $(staker $1 STAKER_ADDRESS)) ether
    sleep 2s
}



unstake_one() {
    # $1 = 2-digit staker index
    # $2 = amount
    echo "############################### UNSTAKING ##############################"
    echo -n "🟢 commission: " && cast to-unit $(cast balance $COMMISSION_ADDRESS) ether
    echo -n "🟢 lst balance: " && cast to-unit $(cast call $(cast call $CONTRACT_ADDRESS "getLST()(address)") "balanceOf(address)(uint256)" $(staker $1 STAKER_ADDRESS) | sed 's/\[[^]]*\]//g') ether
    echo -n "🟢 lst price: " && cast to-unit $(cast call $CONTRACT_ADDRESS "getPrice()(uint256)" | sed 's/\[[^]]*\]//g') ether
    echo -n "🟢 staker balance: " && cast to-unit $(cast balance $(staker $1 STAKER_ADDRESS)) ether
    temp=$(forge script script/Unstake.s.sol --broadcast --legacy --sig "run(address payable, uint256)" $CONTRACT_ADDRESS $2 --private-key $(staker $1 STAKER_KEY) 2>&1 1>/dev/null)
    errors=$(echo $temp | grep -o -i -e "error" -e "fail" -e "revert" | wc -l)
    if [ $errors -eq 0 ]; then
        echo "🟢 Unstake $1"
    else
        echo "🔴 Unstake $1 $temp"
    fi
    echo -n "🟢 commission: " && cast to-unit $(cast balance $COMMISSION_ADDRESS) ether
    echo -n "🟢 lst balance: " && cast to-unit $(cast call $(cast call $CONTRACT_ADDRESS "getLST()(address)") "balanceOf(address)(uint256)" $(staker $1 STAKER_ADDRESS) | sed 's/\[[^]]*\]//g') ether
    echo -n "🟢 lst price: " && cast to-unit $(cast call $CONTRACT_ADDRESS "getPrice()(uint256)" | sed 's/\[[^]]*\]//g') ether
    echo -n "🟢 staker balance: " && cast to-unit $(cast balance $(staker $1 STAKER_ADDRESS)) ether
    sleep 2s
}



claim_one() {
    # $1 = 2-digit staker index
    echo "############################### CLAIMING ##############################"
    echo -n "🟢 claimable: " && cast to-unit $(cast call $CONTRACT_ADDRESS "getClaimable()(uint256)" --from $(staker $1 STAKER_ADDRESS) | sed 's/\[[^]]*\]//g') ether
    echo -n "🟢 commission: " && cast to-unit $(cast balance $COMMISSION_ADDRESS) ether
    echo -n "🟢 lst balance: " && cast to-unit $(cast call $(cast call $CONTRACT_ADDRESS "getLST()(address)") "balanceOf(address)(uint256)" $(staker $1 STAKER_ADDRESS) | sed 's/\[[^]]*\]//g') ether
    echo -n "🟢 lst price: " && cast to-unit $(cast call $CONTRACT_ADDRESS "getPrice()(uint256)" | sed 's/\[[^]]*\]//g') ether
    echo -n "🟢 staker balance: " && cast to-unit $(cast balance $(staker $1 STAKER_ADDRESS)) ether
    temp=$(forge script script/Claim.s.sol --broadcast --legacy --sig "run(address payable)" $CONTRACT_ADDRESS --private-key $(staker $1 STAKER_KEY) 2>&1 1>/dev/null)
    errors=$(echo $temp | grep -o -i -e "error" -e "fail" -e "revert" | wc -l)
    if [ $errors -eq 0 ]; then
        echo "🟢 Claim $1"
    else
        echo "🔴 Claim $1 $temp"
    fi
    echo -n "🟢 claimable: " && cast to-unit $(cast call $CONTRACT_ADDRESS "getClaimable()(uint256)" --from $(staker $1 STAKER_ADDRESS) | sed 's/\[[^]]*\]//g') ether
    echo -n "🟢 commission: " && cast to-unit $(cast balance $COMMISSION_ADDRESS) ether
    echo -n "🟢 lst balance: " && cast to-unit $(cast call $(cast call $CONTRACT_ADDRESS "getLST()(address)") "balanceOf(address)(uint256)" $(staker $1 STAKER_ADDRESS) | sed 's/\[[^]]*\]//g') ether
    echo -n "🟢 lst price: " && cast to-unit $(cast call $CONTRACT_ADDRESS "getPrice()(uint256)" | sed 's/\[[^]]*\]//g') ether
    echo -n "🟢 staker balance: " && cast to-unit $(cast balance $(staker $1 STAKER_ADDRESS)) ether
    sleep 2s
}



stake_all() {
    echo "############################### EARNING ##############################"
    sleep 10s

    cast send --legacy --value 300ether --private-key 0x0000000000000000000000000000000000000000000000000000000000000002 $(staker 01 STAKER_ADDRESS) 1>/dev/null
    stake_one 01 200000000000000000000

    cast send --legacy --value 2100ether --private-key 0x0000000000000000000000000000000000000000000000000000000000000002 $(staker 02 STAKER_ADDRESS) 1>/dev/null
    stake_one 02 2000000000000000000000

    cast send --legacy --value 20100ether --private-key 0x0000000000000000000000000000000000000000000000000000000000000002 $(staker 03 STAKER_ADDRESS) 1>/dev/null
    stake_one 03 20000000000000000000000

    validators=$(cast call $CONTRACT_ADDRESS "validators()(bool[])" | grep -o "true" | wc -l)
    if [ $validators -gt 0 ]; then
        priv_key=$CONTROL_KEY_3
        cast send --legacy --value 1000ether --private-key 0x0000000000000000000000000000000000000000000000000000000000000002 $(cast wallet address $priv_key) 1>/dev/null
        echo -n "🟢 staker balance: " && cast to-unit $(cast balance $(cast wallet address $priv_key)) ether

        echo -n "🟢 commission: " && cast to-unit $(cast balance $COMMISSION_ADDRESS) ether
        temp=$(forge script script/Stake.s.sol --broadcast --legacy --sig "run(address payable, uint256)" $CONTRACT_ADDRESS 1000000000000000000000 --private-key $priv_key 2>&1 1>/dev/null)
        errors=$(echo $temp | grep -o -i -e "error" -e "fail" -e "revert" | wc -l)
        if [ $errors -eq 0 ]; then
            echo "🟢 Stake"
        else
            echo "🔴 Stake $temp"
        fi
        echo -n "🟢 commission: " && cast to-unit $(cast balance $COMMISSION_ADDRESS) ether
        echo -n "🟢 lst balance: " && cast to-unit $(cast call $(cast call $CONTRACT_ADDRESS "getLST()(address)") "balanceOf(address)(uint256)" $(cast wallet address $priv_key) | sed 's/\[[^]]*\]//g') ether
        echo -n "🟢 lst price: " && cast to-unit $(cast call $CONTRACT_ADDRESS "getPrice()(uint256)" | sed 's/\[[^]]*\]//g') ether
        echo -n "🟢 controller balance: " && cast to-unit $(cast balance $(cast wallet address $priv_key)) ether
    fi
    echo "############################### EARNING ##############################"
    sleep 10s

    unstake_one 01 100000000000000000000

    unstake_one 02 1000000000000000000000

    unstake_one 03 10000000000000000000000

    echo "############################### UNBONDING ##############################"
    unbond

    echo "############################### STAKING REWARDS ##############################"
    echo -n "🟢 commission: " && cast to-unit $(cast balance $COMMISSION_ADDRESS) ether
    echo -n "🟢 lst balance: " && cast to-unit $(cast call $(cast call $CONTRACT_ADDRESS "getLST()(address)") "balanceOf(address)(uint256)" $(staker 01 STAKER_ADDRESS) | sed 's/\[[^]]*\]//g') ether
    echo -n "🟢 lst price: " && cast to-unit $(cast call $CONTRACT_ADDRESS "getPrice()(uint256)" | sed 's/\[[^]]*\]//g') ether
    temp=$(forge script script/StakeRewards.s.sol --broadcast --legacy --sig "run(address payable)" $CONTRACT_ADDRESS --private-key $OWNER_KEY 2>&1 1>/dev/null)
    errors=$(echo $temp | grep -o -i -e "error" -e "fail" -e "revert" | wc -l)
    if [ $errors -eq 0 ]; then
        echo "🟢 StakeRewards"
    else
        echo "🔴 StakeRewards $temp"
    fi
    echo -n "🟢 commission: " && cast to-unit $(cast balance $COMMISSION_ADDRESS) ether
    echo -n "🟢 lst balance: " && cast to-unit $(cast call $(cast call $CONTRACT_ADDRESS "getLST()(address)") "balanceOf(address)(uint256)" $(staker 01 STAKER_ADDRESS) | sed 's/\[[^]]*\]//g') ether
    echo -n "🟢 lst price: " && cast to-unit $(cast call $CONTRACT_ADDRESS "getPrice()(uint256)" | sed 's/\[[^]]*\]//g') ether

    claim_one 01

    claim_one 02

    claim_one 03

    echo "############################### EARNING ##############################"
    sleep 10s

    echo "############################### COLLECTING ##############################"
    echo -n "🟢 commission: " && cast to-unit $(cast balance $COMMISSION_ADDRESS) ether
    temp=$(forge script script/CollectCommission.s.sol --broadcast --legacy --sig "run(address payable)" $CONTRACT_ADDRESS 2>&1 1>/dev/null)
    errors=$(echo $temp | grep -o -i -e "error" -e "fail" -e "revert" | wc -l)
    if [ $errors -eq 0 ]; then
        echo "🟢 CollectCommission"
    else
        echo "🔴 CollectCommission $temp"
    fi
    echo -n "🟢 commission: " && cast to-unit $(cast balance $COMMISSION_ADDRESS) ether
}



leave_all() {
    echo "############################### LEAVING ##############################"
    echo -n "🟢 exposure: " && bc -l <<< "scale=18; $(cast to-unit $(cast call $(cast call $CONTRACT_ADDRESS "getLST()(address)") "totalSupply()(uint256)" | sed 's/\[[^]]*\]//g') ether)*$(cast to-unit $(cast call $CONTRACT_ADDRESS "getPrice()(uint256)" | sed 's/\[[^]]*\]//g') ether)"
    echo -n "🟢 funds: " && bc -l <<< "scale=18; $(cast to-unit $(cast call $CONTRACT_ADDRESS "getStake()(uint256)" | sed 's/\[[^]]*\]//g') ether)+$(cast to-unit $(cast call $CONTRACT_ADDRESS "getTaxedRewards()(uint256)" | sed 's/\[[^]]*\]//g') ether)+($(cast to-unit $(cast call $CONTRACT_ADDRESS "getRewards()(uint256)" | sed 's/\[[^]]*\]//g') ether)-$(cast to-unit $(cast call $CONTRACT_ADDRESS "getTaxedRewards()(uint256)" | sed 's/\[[^]]*\]//g') ether))*0.9"
    echo -n "🟢 total deposit: " && cast to-unit $(cast call $CONTRACT_ADDRESS "getStake()(uint256)" | sed 's/\[[^]]*\]//g') ether
    echo -n "🟢 taxed rewards: " && cast to-unit $(cast call $CONTRACT_ADDRESS "getTaxedRewards()(uint256)" | sed 's/\[[^]]*\]//g') ether
    echo -n "🟢 total rewards: " && cast to-unit $(cast call $CONTRACT_ADDRESS "getRewards()(uint256)" | sed 's/\[[^]]*\]//g') ether
    echo -n "🟢 lst price: " && cast to-unit $(cast call $CONTRACT_ADDRESS "getPrice()(uint256)" | sed 's/\[[^]]*\]//g') ether
    echo -n "🟢 lst supply: " && cast to-unit $(cast call $(cast call $CONTRACT_ADDRESS "getLST()(address)") "totalSupply()(uint256)" | sed 's/\[[^]]*\]//g') ether
    leave_one $BLS_PUB_KEY_1 $CONTROL_KEY_1
    echo -n "🟢 exposure: " && bc -l <<< "scale=18; $(cast to-unit $(cast call $(cast call $CONTRACT_ADDRESS "getLST()(address)") "totalSupply()(uint256)" | sed 's/\[[^]]*\]//g') ether)*$(cast to-unit $(cast call $CONTRACT_ADDRESS "getPrice()(uint256)" | sed 's/\[[^]]*\]//g') ether)"
    echo -n "🟢 funds: " && bc -l <<< "scale=18; $(cast to-unit $(cast call $CONTRACT_ADDRESS "getStake()(uint256)" | sed 's/\[[^]]*\]//g') ether)+$(cast to-unit $(cast call $CONTRACT_ADDRESS "getTaxedRewards()(uint256)" | sed 's/\[[^]]*\]//g') ether)+($(cast to-unit $(cast call $CONTRACT_ADDRESS "getRewards()(uint256)" | sed 's/\[[^]]*\]//g') ether)-$(cast to-unit $(cast call $CONTRACT_ADDRESS "getTaxedRewards()(uint256)" | sed 's/\[[^]]*\]//g') ether))*0.9"
    echo -n "🟢 total deposit: " && cast to-unit $(cast call $CONTRACT_ADDRESS "getStake()(uint256)" | sed 's/\[[^]]*\]//g') ether
    echo -n "🟢 taxed rewards: " && cast to-unit $(cast call $CONTRACT_ADDRESS "getTaxedRewards()(uint256)" | sed 's/\[[^]]*\]//g') ether
    echo -n "🟢 total rewards: " && cast to-unit $(cast call $CONTRACT_ADDRESS "getRewards()(uint256)" | sed 's/\[[^]]*\]//g') ether
    echo -n "🟡 lst price: " && cast to-unit $(cast call $CONTRACT_ADDRESS "getPrice()(uint256)" | sed 's/\[[^]]*\]//g') ether
    echo -n "🟢 lst supply: " && cast to-unit $(cast call $(cast call $CONTRACT_ADDRESS "getLST()(address)") "totalSupply()(uint256)" | sed 's/\[[^]]*\]//g') ether
    leave_one $BLS_PUB_KEY_2 $CONTROL_KEY_2
    echo -n "🟢 exposure: " && bc -l <<< "scale=18; $(cast to-unit $(cast call $(cast call $CONTRACT_ADDRESS "getLST()(address)") "totalSupply()(uint256)" | sed 's/\[[^]]*\]//g') ether)*$(cast to-unit $(cast call $CONTRACT_ADDRESS "getPrice()(uint256)" | sed 's/\[[^]]*\]//g') ether)"
    echo -n "🟢 funds: " && bc -l <<< "scale=18; $(cast to-unit $(cast call $CONTRACT_ADDRESS "getStake()(uint256)" | sed 's/\[[^]]*\]//g') ether)+$(cast to-unit $(cast call $CONTRACT_ADDRESS "getTaxedRewards()(uint256)" | sed 's/\[[^]]*\]//g') ether)+($(cast to-unit $(cast call $CONTRACT_ADDRESS "getRewards()(uint256)" | sed 's/\[[^]]*\]//g') ether)-$(cast to-unit $(cast call $CONTRACT_ADDRESS "getTaxedRewards()(uint256)" | sed 's/\[[^]]*\]//g') ether))*0.9"
    echo -n "🟢 total deposit: " && cast to-unit $(cast call $CONTRACT_ADDRESS "getStake()(uint256)" | sed 's/\[[^]]*\]//g') ether
    echo -n "🟢 taxed rewards: " && cast to-unit $(cast call $CONTRACT_ADDRESS "getTaxedRewards()(uint256)" | sed 's/\[[^]]*\]//g') ether
    echo -n "🟢 total rewards: " && cast to-unit $(cast call $CONTRACT_ADDRESS "getRewards()(uint256)" | sed 's/\[[^]]*\]//g') ether
    echo -n "🟡 lst price: " && cast to-unit $(cast call $CONTRACT_ADDRESS "getPrice()(uint256)" | sed 's/\[[^]]*\]//g') ether
    echo -n "🟢 lst supply: " && cast to-unit $(cast call $(cast call $CONTRACT_ADDRESS "getLST()(address)") "totalSupply()(uint256)" | sed 's/\[[^]]*\]//g') ether
    leave_one $BLS_PUB_KEY_3 $CONTROL_KEY_3
    echo -n "🟢 exposure: " && bc -l <<< "scale=18; $(cast to-unit $(cast call $(cast call $CONTRACT_ADDRESS "getLST()(address)") "totalSupply()(uint256)" | sed 's/\[[^]]*\]//g') ether)*$(cast to-unit $(cast call $CONTRACT_ADDRESS "getPrice()(uint256)" | sed 's/\[[^]]*\]//g') ether)"
    echo -n "🟢 funds: " && bc -l <<< "scale=18; $(cast to-unit $(cast call $CONTRACT_ADDRESS "getStake()(uint256)" | sed 's/\[[^]]*\]//g') ether)+$(cast to-unit $(cast call $CONTRACT_ADDRESS "getTaxedRewards()(uint256)" | sed 's/\[[^]]*\]//g') ether)+($(cast to-unit $(cast call $CONTRACT_ADDRESS "getRewards()(uint256)" | sed 's/\[[^]]*\]//g') ether)-$(cast to-unit $(cast call $CONTRACT_ADDRESS "getTaxedRewards()(uint256)" | sed 's/\[[^]]*\]//g') ether))*0.9"
    echo -n "🟢 total deposit: " && cast to-unit $(cast call $CONTRACT_ADDRESS "getStake()(uint256)" | sed 's/\[[^]]*\]//g') ether
    echo -n "🟢 taxed rewards: " && cast to-unit $(cast call $CONTRACT_ADDRESS "getTaxedRewards()(uint256)" | sed 's/\[[^]]*\]//g') ether
    echo -n "🟢 total rewards: " && cast to-unit $(cast call $CONTRACT_ADDRESS "getRewards()(uint256)" | sed 's/\[[^]]*\]//g') ether
    echo -n "🟡 lst price: " && cast to-unit $(cast call $CONTRACT_ADDRESS "getPrice()(uint256)" | sed 's/\[[^]]*\]//g') ether
    echo -n "🟢 lst supply: " && cast to-unit $(cast call $(cast call $CONTRACT_ADDRESS "getLST()(address)") "totalSupply()(uint256)" | sed 's/\[[^]]*\]//g') ether
    leave_one $BLS_PUB_KEY_4 $CONTROL_KEY_4
    #🟪 move the line below to mark the location where execution shall continue when running the script again  🟪
    #🟪🟪🟪🟪🟪🟪🟪🟪🟪🟪🟪🟪🟪🟪🟪🟪🟪🟪🟪🟪🟪🟪🟪🟪🟪🟪🟪🟪🟪🟪🟪🟪🟪🟪🟪🟪🟪🟪🟪🟪🟪🟪🟪🟪🟪🟪🟪🟪🟪🟪🟪🟪'
    echo -n "🟢 exposure: " && bc -l <<< "scale=18; $(cast to-unit $(cast call $(cast call $CONTRACT_ADDRESS "getLST()(address)") "totalSupply()(uint256)" | sed 's/\[[^]]*\]//g') ether)*$(cast to-unit $(cast call $CONTRACT_ADDRESS "getPrice()(uint256)" | sed 's/\[[^]]*\]//g') ether)"
    echo -n "🟢 funds: " && bc -l <<< "scale=18; $(cast to-unit $(cast call $CONTRACT_ADDRESS "getStake()(uint256)" | sed 's/\[[^]]*\]//g') ether)+$(cast to-unit $(cast call $CONTRACT_ADDRESS "getTaxedRewards()(uint256)" | sed 's/\[[^]]*\]//g') ether)+($(cast to-unit $(cast call $CONTRACT_ADDRESS "getRewards()(uint256)" | sed 's/\[[^]]*\]//g') ether)-$(cast to-unit $(cast call $CONTRACT_ADDRESS "getTaxedRewards()(uint256)" | sed 's/\[[^]]*\]//g') ether))*0.9"
    echo -n "🟢 total deposit: " && cast to-unit $(cast call $CONTRACT_ADDRESS "getStake()(uint256)" | sed 's/\[[^]]*\]//g') ether
    echo -n "🟢 taxed rewards: " && cast to-unit $(cast call $CONTRACT_ADDRESS "getTaxedRewards()(uint256)" | sed 's/\[[^]]*\]//g') ether
    echo -n "🟢 total rewards: " && cast to-unit $(cast call $CONTRACT_ADDRESS "getRewards()(uint256)" | sed 's/\[[^]]*\]//g') ether
    echo -n "🟠 lst price: " && cast to-unit $(cast call $CONTRACT_ADDRESS "getPrice()(uint256)" | sed 's/\[[^]]*\]//g') ether
    echo -n "🟢 lst supply: " && cast to-unit $(cast call $(cast call $CONTRACT_ADDRESS "getLST()(address)") "totalSupply()(uint256)" | sed 's/\[[^]]*\]//g') ether
    echo -n "🟢 total withdrawals: " && cast to-unit $(cast call $CONTRACT_ADDRESS "totalPendingWithdrawals()(uint256)" | sed 's/\[[^]]*\]//g') ether
}



unstake_all() {
    echo "############################### EARNING ##############################"
    sleep 10s
    echo -n "🟢 taxed rewards: " && cast to-unit $(cast call $CONTRACT_ADDRESS "getTaxedRewards()(uint256)" | sed 's/\[[^]]*\]//g') ether
    echo -n "🟢 total rewards: " && cast to-unit $(cast call $CONTRACT_ADDRESS "getRewards()(uint256)" | sed 's/\[[^]]*\]//g') ether
    echo -n "🟢 lst price: " && cast to-unit $(cast call $CONTRACT_ADDRESS "getPrice()(uint256)" | sed 's/\[[^]]*\]//g') ether

    unstake_one 01 $(cast call $(cast call $CONTRACT_ADDRESS "getLST()(address)") "balanceOf(address)(uint256)" $(staker 01 STAKER_ADDRESS))

    unstake_one 02 $(cast call $(cast call $CONTRACT_ADDRESS "getLST()(address)") "balanceOf(address)(uint256)" $(staker 02 STAKER_ADDRESS))

    unstake_one 03 $(cast call $(cast call $CONTRACT_ADDRESS "getLST()(address)") "balanceOf(address)(uint256)" $(staker 03 STAKER_ADDRESS))

    echo "############################### UNBONDING ##############################"
    unbond
    echo -n "🟢 taxed rewards: " && cast to-unit $(cast call $CONTRACT_ADDRESS "getTaxedRewards()(uint256)" | sed 's/\[[^]]*\]//g') ether
    echo -n "🟢 total rewards: " && cast to-unit $(cast call $CONTRACT_ADDRESS "getRewards()(uint256)" | sed 's/\[[^]]*\]//g') ether
    echo -n "🟢 lst price: " && cast to-unit $(cast call $CONTRACT_ADDRESS "getPrice()(uint256)" | sed 's/\[[^]]*\]//g') ether

    claim_one 01

    claim_one 02

    claim_one 03
}



report() {
    echo -n "🟢 exposure: " && bc -l <<< "scale=18; $(cast to-unit $(cast call $(cast call $CONTRACT_ADDRESS "getLST()(address)") "totalSupply()(uint256)" | sed 's/\[[^]]*\]//g') ether)*$(cast to-unit $(cast call $CONTRACT_ADDRESS "getPrice()(uint256)" | sed 's/\[[^]]*\]//g') ether)"
    echo -n "🟢 funds: " && bc -l <<< "scale=18; $(cast to-unit $(cast call $CONTRACT_ADDRESS "getStake()(uint256)" | sed 's/\[[^]]*\]//g') ether)+$(cast to-unit $(cast call $CONTRACT_ADDRESS "getTaxedRewards()(uint256)" | sed 's/\[[^]]*\]//g') ether)+($(cast to-unit $(cast call $CONTRACT_ADDRESS "getRewards()(uint256)" | sed 's/\[[^]]*\]//g') ether)-$(cast to-unit $(cast call $CONTRACT_ADDRESS "getTaxedRewards()(uint256)" | sed 's/\[[^]]*\]//g') ether))*0.9"
    echo -n "🟢 total deposit: " && cast to-unit $(cast call $CONTRACT_ADDRESS "getStake()(uint256)" | sed 's/\[[^]]*\]//g') ether
    echo -n "🟢 taxed rewards: " && cast to-unit $(cast call $CONTRACT_ADDRESS "getTaxedRewards()(uint256)" | sed 's/\[[^]]*\]//g') ether
    echo -n "🟢 total rewards: " && cast to-unit $(cast call $CONTRACT_ADDRESS "getRewards()(uint256)" | sed 's/\[[^]]*\]//g') ether
    echo -n "🟢 lst supply: " && cast to-unit $(cast call $(cast call $CONTRACT_ADDRESS "getLST()(address)") "totalSupply()(uint256)" | sed 's/\[[^]]*\]//g') ether
    echo -n "🟢 lst price: " && cast to-unit $(cast call $CONTRACT_ADDRESS "getPrice()(uint256)" | sed 's/\[[^]]*\]//g') ether
}



join_all # all validators join the pool
stake_all # all users stake then unstake and claim part of it
leave_all # all validators leave
unstake_all # all users unstake everything
report # print the status
echo "1️⃣ 1️⃣ 1️⃣ 1️⃣ 1️⃣ 1️⃣ 1️⃣ 1️⃣ 1️⃣ 1️⃣ 1️⃣ 1️⃣ 1️⃣ 1️⃣ 1️⃣ 1️⃣"

sleep 5s

stake_all
unstake_all
report
echo "2️⃣ 2️⃣ 2️⃣ 2️⃣ 2️⃣ 2️⃣ 2️⃣ 2️⃣ 2️⃣ 2️⃣ 2️⃣ 2️⃣ 2️⃣ 2️⃣ 2️⃣ 2️⃣"

sleep 5s

join_all
stake_all
leave_all
unstake_all
report
echo "3️⃣ 3️⃣ 3️⃣ 3️⃣ 3️⃣ 3️⃣ 3️⃣ 3️⃣ 3️⃣ 3️⃣ 3️⃣ 3️⃣ 3️⃣ 3️⃣ 3️⃣ 3️⃣"
