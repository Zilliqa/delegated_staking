// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {BaseDelegation} from "src/BaseDelegation.sol";
import {ILiquidDelegation} from "src/LiquidDelegation.sol";
import {INonLiquidDelegation} from "src/NonLiquidDelegation.sol";
import {LiquidDelegationV2} from "src/LiquidDelegationV2.sol";
import {NonLiquidDelegationV2} from "src/NonLiquidDelegationV2.sol";
import {ERC165Checker} from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import "forge-std/console.sol";

contract Upgrade is Script {
    using ERC165Checker for address;

    function run(address payable proxy) external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address owner = vm.addr(deployerPrivateKey);
        console.log("Signer is %s", owner);

        BaseDelegation oldDelegation = BaseDelegation(
            proxy
        );

        console.log("Upgrading from version: %s",
            oldDelegation.version()
        );

        console.log("Owner is %s",
            oldDelegation.owner()
        );

        vm.startBroadcast(deployerPrivateKey);

        address payable newImplementation;

        if (address(oldDelegation).supportsInterface(type(ILiquidDelegation).interfaceId))
            newImplementation = payable(new LiquidDelegationV2());
        else if (address(oldDelegation).supportsInterface(type(INonLiquidDelegation).interfaceId))
            newImplementation = payable(new NonLiquidDelegationV2());
        else
            return;

        console.log("New implementation deployed: %s",
            newImplementation
        );

        bytes memory reinitializerCall = abi.encodeWithSignature(
            "reinitialize()"
        );

        oldDelegation.upgradeToAndCall(
            newImplementation,
            reinitializerCall
        );

        BaseDelegation newDelegation = BaseDelegation(
            proxy
        );

        console.log("Upgraded to version: %s",
            newDelegation.version()
        );

        vm.stopBroadcast();
    }
}