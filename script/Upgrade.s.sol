// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity ^0.8.28;

/* solhint-disable no-console */
import { Script } from "forge-std/Script.sol";
import { variant } from "script/CheckVariant.s.sol";
import { Console } from "script/Console.s.sol";
import { BaseDelegation } from "src/BaseDelegation.sol";
import { LiquidDelegation, LIQUID_VARIANT } from "src/LiquidDelegation.sol";
import { NonLiquidDelegation, NONLIQUID_VARIANT } from "src/NonLiquidDelegation.sol";

contract Upgrade is Script {

    function run(address payable proxy) external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address owner = vm.addr(deployerPrivateKey);
        Console.log("Signer is %s", owner);
        BaseDelegation oldDelegation = BaseDelegation(
            proxy
        );

        uint24 major;
        uint24 minor;
        uint24 patch;
        uint64 oldVersion = oldDelegation.version();

        // the contract has been already upgraded to a version that supports semver 
        if (oldVersion >= 2**20) {
            (major, minor, patch) = oldDelegation.decodedVersion();
            Console.log("Upgrading from version: %s.%s.%s",
                uint256(major),
                uint256(minor),
                uint256(patch)
            );
        } else if (oldVersion == 1)
            Console.log("Upgrading from initial version",
                oldVersion
            );
        else
            Console.log("Upgrading from version: %s",
                oldVersion
            );

        Console.log("Owner is %s",
            oldDelegation.owner()
        );

        vm.startBroadcast(deployerPrivateKey);

        address payable newImplementation;

        if (variant(proxy) == LIQUID_VARIANT)
            newImplementation = payable(new LiquidDelegation());
        else if (variant(proxy) == NONLIQUID_VARIANT)
            newImplementation = payable(new NonLiquidDelegation());
        else
            return;

        Console.log("New implementation deployed: %s",
            newImplementation
        );

        bytes memory reinitializerCall = abi.encodeWithSignature(
            "reinitialize(uint64)",
            oldVersion
        );

        oldDelegation.upgradeToAndCall(
            newImplementation,
            reinitializerCall
        );

        BaseDelegation newDelegation = BaseDelegation(
            proxy
        );

        (major, minor, patch) = newDelegation.decodedVersion();
        Console.log("Upgraded to version: %s.%s.%s",
            uint256(major),
            uint256(minor),
            uint256(patch)
        );

        vm.stopBroadcast();
    }
}