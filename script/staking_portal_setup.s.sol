// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {BaseDelegation} from "src/BaseDelegation.sol";
import {LiquidDelegationV2} from "src/LiquidDelegationV2.sol";
import {NonLiquidDelegation} from "src/NonLiquidDelegation.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import "forge-std/console.sol";
import {Console} from "src/Console.sol";
import { Deposit, Staker } from "src/Deposit.sol";

contract Create2Helper {
    error Create2EmptyBytecode();

    error Create2FailedDeployment();

    function deploy(bytes32 salt, bytes memory bytecode) external payable returns (address addr) {
        if (bytecode.length == 0) {
            revert Create2EmptyBytecode();
        }

        assembly {
            addr := create2(callvalue(), add(bytecode, 0x20), mload(bytecode), salt)
        }

        if (addr == address(0)) {
            revert Create2FailedDeployment();
        }
    }

    function computeAddress(bytes32 salt, bytes32 bytecodeHash) external view returns (address addr) {

        address contractAddress = address(this);
        
        assembly {
            let ptr := mload(0x40)

            mstore(add(ptr, 0x40), bytecodeHash)
            mstore(add(ptr, 0x20), salt)
            mstore(ptr, contractAddress)
            let start := add(ptr, 0x0b)
            mstore8(start, 0xff)
            addr := keccak256(start, 85)
        }
    }

}

contract StakingPortalSetup is Script {
    using Strings for string;

    function _deployLiquidityPool(uint256 ownerPrivKey, bytes32 liquidityPoolId, uint16 commissionNumerator) internal {

      Create2Helper create2Helper = new Create2Helper();

      address owner = vm.addr(ownerPrivKey);

      vm.startBroadcast(ownerPrivKey);

      bytes memory liquidDelegationV2Code = abi.encodePacked(type(LiquidDelegationV2).creationCode);
      address implementation = create2Helper.deploy(liquidityPoolId , liquidDelegationV2Code);

      bytes memory initializerCall = abi.encodeWithSignature(
          "initialize(address)",
          owner
      );

      bytes memory proxyCode = abi.encodePacked(type(ERC1967Proxy).creationCode, abi.encode(implementation, initializerCall));
      address payable proxy = payable(create2Helper.deploy(liquidityPoolId, proxyCode));

      BaseDelegation delegation = BaseDelegation(
            proxy
        );

      delegation.setCommissionNumerator(commissionNumerator);

      console.log(
          "Owner: %s\nProxy deployed: %s \r\nImplementation deployed: %s",
          owner,
          proxy,
          implementation
      );

      Console.log("Commission rate: %s.%s%s%%",
          delegation.getCommissionNumerator(),
          2
      );

      console.log("\n\n\n");

      vm.stopBroadcast();
    }

    function run() external {
        // Deposit deposit = Deposit(address(0x000000000000000000005a494C4445504F534954));

        // (bytes[] memory stakerKeys, uint256[] memory balances, Staker[] memory stakers) = deposit.getStakersData();

        // for (uint256 i = 0; i < stakers.length; i++) {
        //     console.logBytes(stakerKeys[i]);
        //     console.logBytes(stakers[i].peerId);
        //     // console.log("Amount: %s\n\n", balances[i]);
        // }

        _deployLiquidityPool(vm.envUint("PRIVATE_KEY_VP_1"), bytes32(uint256(2)), 15);
        _deployLiquidityPool(vm.envUint("PRIVATE_KEY_VP_1"), bytes32(uint256(2)), 15);

        // _deployLiquidityPool(vm.envUint("PRIVATE_KEY_VP_2"), bytes32(uint256(2)), 5);
        // _deployLiquidityPool(vm.envUint("PRIVATE_KEY_VP_3"), bytes32(uint256(2)), 30);
        // _deployLiquidityPool(vm.envUint("PRIVATE_KEY_VP_4"), bytes32(uint256(2)), 0);

    }
}
