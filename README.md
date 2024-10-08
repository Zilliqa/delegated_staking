# Liquid Staking

This repo contains the contracts and scripts needed to activate a validator that users can stake ZIL with. When delegating stake, users receive a non-rebasing **liquid staking token** (LST) that anyone can send to the validator's delegation contract later on to withdraw the staked ZIL plus the corresponding share of the validator rewards.

Install Foundry (https://book.getfoundry.sh/getting-started/installation) and the OpenZeppelin contracts before proceeding with the deployment:
```
forge install OpenZeppelin/openzeppelin-contracts-upgradeable --no-commit
forge install OpenZeppelin/openzeppelin-contracts --no-commit
```

## Contract Deployment
The delegation contract is used by delegators to stake and unstake ZIL with the respective validator. It acts as the validator node's control address and interacts with the `Deposit` system contract. `DelegationV1` is the initial implementation of the delegation contract is upgradeable: `DelegationV2` deploys a `NonRebasingLST` contract when it is initialized and `DelegationV3` adds the newest features.

The delegation contract shall be deployed and upgraded by the account with the private key that was used to run the validator node and was used to generate its BLS keypair and peer id. Make sure the `PRIVATE_KEY` environment variable is set accordingly.

To deploy `DelegationV1` run
```
forge script script/deploy_Delegation.s.sol --rpc-url https://api.zq2-devnet.zilliqa.com --broadcast --legacy
```
You will see an output like this:
```
  Signer is 0x15fc323DFE5D5DCfbeEdc25CEcbf57f676634d77
  Proxy deployed: 0x7A0b7e6D24eDe78260c9ddBD98e828B0e11A8EA2 
  Implementation deployed: 0x7C623e01c5ce2e313C223ef2aEc1Ae5C6d12D9DD
  Deployed version: 1
  Owner is 0x15fc323DFE5D5DCfbeEdc25CEcbf57f676634d77
```

You will need the proxy address from the above output in all commands below.

To upgrade the contract to `DelegationV2`, run
```
forge script script/upgrade_Delegation.s.sol --rpc-url https://api.zq2-devnet.zilliqa.com --broadcast --legacy --sig "run(address payable)" 0x7A0b7e6D24eDe78260c9ddBD98e828B0e11A8EA2
```

The output will look like this:
```
  Signer is 0x15fc323DFE5D5DCfbeEdc25CEcbf57f676634d77
  Upgrading from version: 1
  Owner is 0x15fc323DFE5D5DCfbeEdc25CEcbf57f676634d77
  New implementation deployed: 0x64Fa96a67910956141cc481a43f242C045c10165
  Upgraded to version: 2
```

To upgrade the contract to `DelegationV3`, replace line 33 in `upgrade_Delegation.s.sol` with
```solidity
new DelegationV3()
```
and run
```
forge script script/upgrade_Delegation.s.sol --rpc-url https://api.zq2-devnet.zilliqa.com --broadcast --legacy --sig "run(address payable)" 0x7A0b7e6D24eDe78260c9ddBD98e828B0e11A8EA2
```
again.

The output will look like this:
```
  Signer is 0x15fc323DFE5D5DCfbeEdc25CEcbf57f676634d77
  Upgrading from version: 2
  Owner is 0x15fc323DFE5D5DCfbeEdc25CEcbf57f676634d77
  New implementation deployed: 0x90A65311b6C7246FFD1F212C123cfE351a6d65A9
  Upgraded to version: 3
```

## Validator Activation
Now you are ready to use the contract to activate your node as a validator with a deposit of e.g. 10 million ZIL. Run
```
cast send --legacy --value 10000000ether --rpc-url https://api.zq2-devnet.zilliqa.com --private-key $PRIVATE_KEY \
0x7a0b7e6d24ede78260c9ddbd98e828b0e11a8ea2 "deposit(bytes,bytes,bytes)" \
0x92fbe50544dce63cfdcc88301d7412f0edea024c91ae5d6a04c7cd3819edfc1b9d75d9121080af12e00f054d221f876c \
0x002408011220d5ed74b09dcbe84d3b32a56c01ab721cf82809848b6604535212a219d35c412f \
0xb14832a866a49ddf8a3104f8ee379d29c136f29aeb8fccec9d7fb17180b99e8ed29bee2ada5ce390cb704bc6fd7f5ce814f914498376c4b8bc14841a57ae22279769ec8614e2673ba7f36edc5a4bf5733aa9d70af626279ee2b2cde939b4bd8a
```
with the BLS public key, the peer id and the BLS signature of your node. Note that the peer id must be converted from base58 to hex.

Make sure your node's account has the 10 million ZIL and your node is fully synced before you run the above command.

Note that the reward address registered for your validator node will be the address of the delegation contract (the proxy contract to be more precise).

## Staking and Unstaking
If the above transaction was successful and the node became a validator, it can accept delegations. In order to stake e.g. 200 ZIL, run 
```
forge script script/stake_Delegation.s.sol --rpc-url https://api.zq2-devnet.zilliqa.com --broadcast --legacy --sig "run(address payable)" 0x7A0b7e6D24eDe78260c9ddBD98e828B0e11A8EA2 --private-key 0x...
```
with the private key of the delegator account. Make sure the account's balance can cover the transaction fees plus the 200 ZIL to be delegated.

The output will look like this:
```
  Running version: 3
  Current stake: 10000000000000000000000000 
  Current rewards: 110314207650273223687
  LST address: 0x9e5c257D1c6dF74EaA54e58CdccaCb924669dc83
  Owner balance: 10000000000000000000000000
  Staker balance: 0
  Staker balance: 199993793908430833324
```

Note that the staker LST balance in the output will be different from the actual LST balance which you can query by running
```
cast call 0x9e5c257D1c6dF74EaA54e58CdccaCb924669dc83 "balanceOf(address)(uint256)" 0xd819fFcE7A58b1E835c25617Db7b46a00888B013 --rpc-url https://api.zq2-devnet.zilliqa.com
```
This is due to the fact that the above output was generated based on the local script execution before the transaction got submitted to the network.

You can copy the LST address from the above output and add it to your wallet to transfer your liquid staking tokens to another account if you want to.

Last but not least, to unstake, run 
```
forge script script/unstake_Delegation.s.sol --rpc-url https://api.zq2-devnet.zilliqa.com --broadcast --legacy --sig "run(address payable)" 0x7A0b7e6D24eDe78260c9ddBD98e828B0e11A8EA2 --private-key 0x...
```
with the private key of an account that holds some LST.

The output will look like this:
```
  Running version: 3
  Current stake: 10000000000000000000000000 
  Current rewards: 331912568306010928520
  LST address: 0x9e5c257D1c6dF74EaA54e58CdccaCb924669dc83
  Owner balance: 10000000000000000000000000
  Staker balance: 199993784619390291653
  Staker balance: 0
```
