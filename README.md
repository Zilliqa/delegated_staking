# Delegated Staking

This repository contains the contracts and scripts needed to activate a validator that users can delegate stake to. Currently, there are two variants of the contracts: 
1. When delegating stake to the **liquid variant**, users receive a non-rebasing liquid staking token (LST) that anyone can send to the validator's contract later on to withdraw the stake plus the corresponding share of the validator rewards.
1. When delegating stake to the **non-liquid variant**, the users can regularly withdraw their share of the rewards without withdrawing their stake.

## Prerequisites
To interact with the contracts throught the CLI, you can use the Forge scripts provided in this repository and described further below. First, install Foundry (https://book.getfoundry.sh/getting-started/installation) and the OpenZeppelin contracts before proceeding with the deployment:
```
forge install OpenZeppelin/openzeppelin-contracts-upgradeable --no-commit
forge install OpenZeppelin/openzeppelin-contracts --no-commit
```
To allow stakers to interact with the contracts through your dapp, use the events and methods defined in the `Deposit` interface and the `BaseDelegation` contract:
```solidity
event Staked(address indexed delegator, uint256 amount, bytes data);
event Unstaked(address indexed delegator, uint256 amount, bytes data);
event Claimed(address indexed delegator, uint256 amount, bytes data);

function stake() external payable;
function unstake(uint256) external returns(uint256 unstakedZil);
function claim() external;

function getClaimable() external virtual view returns(uint256 total);
function getPendingClaims() external virtual view returns(uint256[2][] memory blockNumbersAndAmounts);
function getMinDelegation() external view returns(uint256 amount);
function getCommission() external view returns(uint256 numerator, uint256 denominator);
function getStake() external view returns(uint256 validatorStake);
```
as well as the additional events and methods applicable to a specific staking variant only such as
```solidity
function getLST() external view returns(address erc20Contract);
function getPrice() external view returns(uint256 oneTokenToZil);
```
for liquid staking and
```solidity
event RewardPaid(address indexed delegator, uint256 reward);

function rewards() external view returns(uint256 total);
function withdrawAllRewards() external returns(uint256 taxedRewards);
function withdrawRewards(uint256 amount) external returns(uint256 taxedRewards);
function stakeRewards() external;
```
and a few more for the non-liquid variant.

To enable the tests included in this repository to interact with the Zilliqa 2.0 deposit contract, it must be compiled along with the test contracts. Specify the folder containing the `deposit.sol` file in `remappings.txt`:
```
@zilliqa/zq2/=/home/user/zq2/zilliqa/src/contracts/
```

## Contract Deployment
The delegation contract is used by delegators to stake and unstake ZIL with the respective validator. It acts as the validator node's control address and interacts with the deposit contract.

`BaseDelegation` is an abstract contract that concrete implementations inherit from.
`LiquidDelegation` is the initial version of the liquid staking variant of the delegation contract that creates a `NonRebasingLST` contract when it is initialized. `LiquidDelegationV2` contains the full implementation including the LST price calculation and other features. `NonLiquidDelegation` is the initial version of the non-liquid staking variant of the delegation contract. `NonLiquidDelegationV2` contains the full implementation that allows delegators to withdraw rewards.

Before running the deployment script, set the `PRIVATE_KEY` environment variable to the private key of the contract owner. Note that only the contract owner will be able to upgrade the contract, change the commission rate and activate the node as a validator.

To deploy `LiquidDelegation` run
```bash
forge script script/deploy_Delegation.s.sol --rpc-url http://localhost:4201 --broadcast --legacy --sig "run(string,string,string)" LiquidDelegation Name Symbol
```
using the `Name` and the `Symbol` of your LST.

To deploy ``NonLiquidDelegation` run
```bash
forge script script/deploy_Delegation.s.sol --rpc-url http://localhost:4201 --broadcast --legacy --sig "run(string,string,string)" NonLiquidDelegation "" ""
```

You will see an output like this:
```
  Signer is 0x15fc323DFE5D5DCfbeEdc25CEcbf57f676634d77
  Proxy deployed: 0x7A0b7e6D24eDe78260c9ddBD98e828B0e11A8EA2 
  Implementation deployed: 0x7C623e01c5ce2e313C223ef2aEc1Ae5C6d12D9DD
  Deployed version: 1
  Owner is 0x15fc323DFE5D5DCfbeEdc25CEcbf57f676634d77
```

You and your delegators will need the proxy address from the above output in all commands below. If you know the address of a proxy contract but don't know which variant of staking it supports, run
```bash
forge script script/variant_Delegation.s.sol --rpc-url http://localhost:4201 --sig "run(address payable)" 0x7A0b7e6D24eDe78260c9ddBD98e828B0e11A8EA2
```
The output will be `ILiquidStaking`, `INonLiquidStaking` or none of them if the address is not a valid delegation contract.

To use the delegation contract, upgrade it to the latest version of `LiquidDelegationV2` or `NonLiquidDelegationV2` depending on the staking model it implements, by running
```bash
forge script script/upgrade_Delegation.s.sol --rpc-url http://localhost:4201 --broadcast --legacy --sig "run(address payable)" 0x7A0b7e6D24eDe78260c9ddBD98e828B0e11A8EA2
```

The output will look like this:
```
  Signer is 0x15fc323DFE5D5DCfbeEdc25CEcbf57f676634d77
  Upgrading from version: 1
  Owner is 0x15fc323DFE5D5DCfbeEdc25CEcbf57f676634d77
  New implementation deployed: 0x64Fa96a67910956141cc481a43f242C045c10165
  Upgraded to version: 2
```

To adapt the contract to your needs, create your own copy of `LiquidDelegationV2` or `NonLiquidDelegationV2` and run the above upgrade script again.


## Contract Configuration

Now or at a later time you can set the commission on the rewards the validator earns to e.g. 10% as follows:
```bash
forge script script/commission_Delegation.s.sol --rpc-url http://localhost:4201 --broadcast --legacy --sig "run(address payable, string, bool)" 0x7A0b7e6D24eDe78260c9ddBD98e828B0e11A8EA2 1000 false
```

The output will contain the following information:
```
  Running version: 2
  Commission rate: 0.0%
  New commission rate: 10.0%
```

Note that the commission rate is specified as an integer to be divided by the `DENOMINATOR` which can be retrieved from the delegation contract:
```bash
cast call 0x7A0b7e6D24eDe78260c9ddBD98e828B0e11A8EA2 "DENOMINATOR()(uint256)" --rpc-url http://localhost:4201  | sed 's/\[[^]]*\]//g'
```

Once the validator is activated and starts earning rewards, commissions are transferred automatically to the validator node's account. Commissions of a non-liquid staking validator are deducted when delegators withdraw rewards. In case of the liquid staking variant, commissions are deducted each time delegators stake, unstake or claim what they unstaked, or when the node requests the outstanding commissions that haven't been transferred yet. To collect them, run
```bash
forge script script/commission_Delegation.s.sol --rpc-url http://localhost:4201 --broadcast --legacy --sig "run(address payable, string, bool)" 0x7A0b7e6D24eDe78260c9ddBD98e828B0e11A8EA2 same true
```
using `same` for the second argument to leave the commission percentage unchanged and `true` for the third argument. Replacing the second argument with `same` and the third argument with `false` only displays the current commission rate.


## Validator Activation
If your node's account has enough ZIL for the minimum stake required, you can activate your node as a validator with a deposit of e.g. 10 million ZIL. Run
```bash
cast send --legacy --value 10000000ether --rpc-url http://localhost:4201 --private-key $PRIVATE_KEY \
0x7a0b7e6d24ede78260c9ddbd98e828b0e11a8ea2 "deposit(bytes,bytes,bytes)" \
0x92fbe50544dce63cfdcc88301d7412f0edea024c91ae5d6a04c7cd3819edfc1b9d75d9121080af12e00f054d221f876c \
0x002408011220d5ed74b09dcbe84d3b32a56c01ab721cf82809848b6604535212a219d35c412f \
0xb14832a866a49ddf8a3104f8ee379d29c136f29aeb8fccec9d7fb17180b99e8ed29bee2ada5ce390cb704bc6fd7f5ce814f914498376c4b8bc14841a57ae22279769ec8614e2673ba7f36edc5a4bf5733aa9d70af626279ee2b2cde939b4bd8a
```
with the BLS public key, the peer id and the BLS signature of your node. Note that the peer id must be converted from base58 to hex. Make sure your node is fully synced before you run the above command.

Note that the reward address registered for your validator node will be the address of the delegation contract (the proxy contract to be more precise).

Alternatively, you can proceed to the next section and delegate stake until the contract's balance reaches the 10 million ZIL minimum stake required for the activation, and then run
```bash
cast send --legacy --rpc-url http://localhost:4201 --private-key $PRIVATE_KEY \
0x7a0b7e6d24ede78260c9ddbd98e828b0e11a8ea2 "deposit2(bytes,bytes,bytes)" \
0x92fbe50544dce63cfdcc88301d7412f0edea024c91ae5d6a04c7cd3819edfc1b9d75d9121080af12e00f054d221f876c \
0x002408011220d5ed74b09dcbe84d3b32a56c01ab721cf82809848b6604535212a219d35c412f \
0xb14832a866a49ddf8a3104f8ee379d29c136f29aeb8fccec9d7fb17180b99e8ed29bee2ada5ce390cb704bc6fd7f5ce814f914498376c4b8bc14841a57ae22279769ec8614e2673ba7f36edc5a4bf5733aa9d70af626279ee2b2cde939b4bd8a
```
to deposit all of it.

Note that the deposit will not take effect and the node will not start earning rewards until the epoch after next.


## Staking and Unstaking
Once the delegation contract has been deployed and upgraded to the latest version, your node can accept delegations. In order to stake e.g. 200 ZIL, your delegators must run
```bash
forge script script/stake_Delegation.s.sol --rpc-url http://localhost:4201 --broadcast --legacy --sig "run(address payable, uint256)" 0x7A0b7e6D24eDe78260c9ddBD98e828B0e11A8EA2 200000000000000000000 --private-key 0x...
```
with the private key of their account. It's important to make sure the account's balance can cover the transaction fees plus the 200 ZIL to be delegated.

The output will look like this for liquid staking:
```
  Running version: 2
  Current stake: 10000000000000000000000000 wei
  Current rewards: 110314207650273223687 wei
  LST address: 0x9e5c257D1c6dF74EaA54e58CdccaCb924669dc83
  Staker balance before: 99899145245801454561224 wei 0 LST
  Staker balance after: 99699145245801454561224 wei 199993793908430833324 LST
```
and like this for the non-liquid variant:
```
  Running version: 2
  Current stake: 10000000000000000000000000 wei
  Current rewards: 110314207650273223687 wei
  Staker balance before: 99899145245801454561224 wei
  Staker balance after: 99699145245801454561224 wei
```

Due to the fact that the above output was generated based on the local script execution before the transaction got submitted to the network, the ZIL balance does not reflect the gas fees of the staking transaction and the LST balance is also different from the actual LST balance which you can query by running
```bash
cast call 0x9e5c257D1c6dF74EaA54e58CdccaCb924669dc83 "balanceOf(address)(uint256)" 0xd819fFcE7A58b1E835c25617Db7b46a00888B013 --rpc-url http://localhost:4201  | sed 's/\[[^]]*\]//g'
```

Your delegators can copy the LST address from the above output and add it to their wallet to transfer their liquid staking tokens to another account if they want to.

To query the current price of an LST, run
```bash
cast to-unit $(cast call 0x7A0b7e6D24eDe78260c9ddBD98e828B0e11A8EA2 "getPrice()(uint256)" --block latest --rpc-url http://localhost:4201 | sed 's/\[[^]]*\]//g') ether
```

To unstake e.g. 100 LST (liquid variant) or 100 ZIL (non-liquid variant), run
```bash
forge script script/unstake_Delegation.s.sol --rpc-url http://localhost:4201 --broadcast --legacy --sig "run(address payable, uint256)" 0x7A0b7e6D24eDe78260c9ddBD98e828B0e11A8EA2 100000000000000000000 --private-key 0x...
```
using the private key of an account that holds some LST in case of the liquid variant or using the private key of the delegator account in case of the non-liquid variant.

The output will look like this for liquid staking:
```
  Running version: 2
  Current stake: 10000000000000000000000000 wei
  Current rewards: 331912568306010928520 wei
  LST address: 0x9e5c257D1c6dF74EaA54e58CdccaCb924669dc83
  Staker balance before: 99698814298179759361224 wei 199993784619390291653 LST
  Staker balance after: 99698814298179759361224 wei 99993784619390291653 LST
```
and like this for the non-liquid variant:
```
  Running version: 2
  Current stake: 10000000000000000000000000 wei
  Current rewards: 331912568306010928520 wei
  Staker balance before: 99698814298179759361224 wei
  Staker balance after: 99698814298179759361224 wei
```

The ZIL balance hasn't increased because the unstaked amount can not be transferred immediately. To claim the amount that is available after the unbonding period, run
```bash
forge script script/claim_Delegation.s.sol --rpc-url http://localhost:4201 --broadcast --legacy --sig "run(address payable)" 0x7A0b7e6D24eDe78260c9ddBD98e828B0e11A8EA2 --private-key 0x...
```
with the private key of the account that unstaked in the previous step above.

The output will look like this:
```
  Running version: 2
  Staker balance before: 99698086421983460161224 wei
  Staker balance after: 99798095485861371162343 wei
```

To query how much ZIL a user can already claim, run
```bash
cast to-unit $(cast call 0x7A0b7e6D24eDe78260c9ddBD98e828B0e11A8EA2 "getClaimable()(uint256)" --from 0xd819fFcE7A58b1E835c25617Db7b46a00888B013 --block latest --rpc-url http://localhost:4201 | sed 's/\[[^]]*\]//g') ether
```
with the user's address as an argument.


## Staking and Withdrawing Rewards
In the liquid staking variant, only you as the node operator can stake the rewards accrued by the node. To do so, run
```bash
forge script script/stakeRewards_Delegation.s.sol --rpc-url http://localhost:4201 --broadcast --legacy --sig "run(address payable)" 0x7A0b7e6D24eDe78260c9ddBD98e828B0e11A8EA2 --private-key 0x...
```

In the non-liquid variant of staking, your delegators can stake or withdraw their share of the rewards. To query the amount of rewards available, run
```bash
cast to-unit $(cast call 0x7A0b7e6D24eDe78260c9ddBD98e828B0e11A8EA2 "rewards()(uint256)" --from 0xd819fFcE7A58b1E835c25617Db7b46a00888B013 --block latest --rpc-url http://localhost:4201 | sed 's/\[[^]]*\]//g') ether
```

In case users haven't withdrawn rewards for a long time during which many delegators staked or unstaked, the gas used by the above function might hit the block limit. In this case rewards can be withdrawn from the period between the (un)staking until which they were withdrawn last time and the `n`th subsequent (un)staking. This can be repeated several times to withdraw all rewards using multiple transactions. To calculate the rewards that can be withdrawn in the next transaction, choose a number `0 <= n <= 11000` e.g. `100` and run
```bash
cast to-unit $(cast call 0x7A0b7e6D24eDe78260c9ddBD98e828B0e11A8EA2 "rewards(uint64)(uint256)" 100 --from 0xd819fFcE7A58b1E835c25617Db7b46a00888B013 --block latest --rpc-url http://localhost:4201 | sed 's/\[[^]]*\]//g') ether
```
Note that `n` actually denotes the number of additional (un)stakings so that at least one is always reflected in the result, even if you specified `n = 0`.

To withdraw e.g. 1 ZIL of rewards using `n = 100`, run
```bash
forge script script/withdrawRewards_Delegation.s.sol --rpc-url http://localhost:4201 --broadcast --legacy --sig "run(address payable, string, string)" 0x7A0b7e6D24eDe78260c9ddBD98e828B0e11A8EA2 1000000000000000000 100 --private-key 0x...
```
with the private key of a delegator account. To withdraw as much as possible with the given value of `n` set the amount to `all`. To withdraw the chosen amount without setting `n` replace `n` with `all`. To withdraw all rewards replace both the amount and `n` with `all`.

Last but not least, in order to stake rewards instead of withdrawing them, your delegators can run
```bash
forge script script/stakeRewards_Delegation.s.sol --rpc-url http://localhost:4201 --broadcast --legacy --sig "run(address payable)" 0x7A0b7e6D24eDe78260c9ddBD98e828B0e11A8EA2 --private-key 0x...
```
using the private key of their account.

## Development and Testing
Staking pool operators are encouraged to fork and adapt the above contracts to implement features such as instant unstaking for a premium fee, automated staking of rewards to achieve the best possible APR or issuing a rebasing liquid staking token with a constant price of 1 ZIL but holder balances adjusted according to the rewards accrued.

The tests included in this repository should also be adjusted and extended accordingly. They can be executed by running
```bash
forge test
```

The following bash scripts with verbose output can be used to test staking, unstaking and claiming of unstaked funds as well as withdrawing and staking of rewards and to print the current state of a delegator's stake queried from the validator's local node. Their output is useful for checking the results of these operations. Here a few examples of how to use them (private key replaced with `0x...`):
```bash
# stake 200 ZIL
chmod +x stake.sh && ./stake.sh 0x7A0b7e6D24eDe78260c9ddBD98e828B0e11A8EA2 0x... 200000000000000000000

# unstake 100 ZIL
chmod +x unstake.sh && ./unstake.sh 0x7A0b7e6D24eDe78260c9ddBD98e828B0e11A8EA2 0x... 100000000000000000000

# unstake all staked ZIL
chmod +x unstake.sh && ./unstake.sh 0x7A0b7e6D24eDe78260c9ddBD98e828B0e11A8EA2 0x...

# claim the unstaked ZIL
chmod +x claim.sh && ./claim.sh 0x7A0b7e6D24eDe78260c9ddBD98e828B0e11A8EA2 0x...

# stake all rewards accrued so far
chmod +x stakeRewards.sh && ./stakeRewards.sh 0x7A0b7e6D24eDe78260c9ddBD98e828B0e11A8EA2 0x...

# withdraw all rewards accrued so far
chmod +x withdrawRewards.sh && ./withdrawRewards.sh 0x7A0b7e6D24eDe78260c9ddBD98e828B0e11A8EA2 0x...

# withdraw 10 ZIL from the rewards accrued so far
chmod +x withdrawRewards.sh && ./withdrawRewards.sh 0x7A0b7e6D24eDe78260c9ddBD98e828B0e11A8EA2 0x... 10000000000000000000

# withdraw 10 ZIL from the rewards accrued during the next 1000 (un)stakings
chmod +x withdrawRewards.sh && ./withdrawRewards.sh 0x7A0b7e6D24eDe78260c9ddBD98e828B0e11A8EA2 0x... 10000000000000000000 1000

# display the current state of the stake of the below delegator address
chmod +x state.sh && ./state.sh 0x7A0b7e6D24eDe78260c9ddBD98e828B0e11A8EA2 0xd819fFcE7A58b1E835c25617Db7b46a00888B013

# display the state of the stake of the below delegator at block 4800000
chmod +x state.sh && ./state.sh 0x7A0b7e6D24eDe78260c9ddBD98e828B0e11A8EA2 0xd819fFcE7A58b1E835c25617Db7b46a00888B013 4800000
```
