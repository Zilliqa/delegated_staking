// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity ^0.8.26;

/* solhint-disable no-console */
import {Script} from "forge-std/Script.sol";
import {BaseDelegation} from "src/BaseDelegation.sol";
import {ILiquidDelegation, LiquidDelegation} from "src/LiquidDelegation.sol";
import {INonLiquidDelegation, NonLiquidDelegation} from "src/NonLiquidDelegation.sol";
import {ERC165Checker} from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import {console} from "forge-std/console.sol";

contract Upgrade is Script {
    using ERC165Checker for address;

    function run(address payable proxy) external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address owner = vm.addr(deployerPrivateKey);
        console.log("Signer is %s", owner);

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
            console.log("Upgrading from version: %s.%s.%s",
                uint256(major),
                uint256(minor),
                uint256(patch)
            );
        } else if (oldVersion == 1)
            console.log("Upgrading from initial version",
                oldVersion
            );
        else
            console.log("Upgrading from version: %s",
                oldVersion
            );

        console.log("Owner is %s",
            oldDelegation.owner()
        );

        vm.startBroadcast(deployerPrivateKey);

        address payable newImplementation;

        if (address(oldDelegation).supportsInterface(type(ILiquidDelegation).interfaceId))
            newImplementation = payable(new LiquidDelegation());
        else if (address(oldDelegation).supportsInterface(type(INonLiquidDelegation).interfaceId))
            newImplementation = payable(new NonLiquidDelegation());
        else
            return;

        console.log("New implementation deployed: %s",
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
        console.log("Upgraded to version: %s.%s.%s",
            uint256(major),
            uint256(minor),
            uint256(patch)
        );

        vm.stopBroadcast();
    }
}