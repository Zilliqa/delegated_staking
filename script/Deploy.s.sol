// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity ^0.8.26;

/* solhint-disable no-console */
import {Script} from "forge-std/Script.sol";
import {BaseDelegation} from "src/BaseDelegation.sol";
import {LiquidDelegation} from "src/LiquidDelegation.sol";
import {NonLiquidDelegation} from "src/NonLiquidDelegation.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {Console} from "script/Console.sol";

contract Deploy is Script {
    using Strings for string;

    function liquidDelegation(string calldata name, string calldata symbol) external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address owner = vm.addr(deployerPrivateKey);
        Console.log("Signer is %s", owner);

        vm.startBroadcast(deployerPrivateKey);

        address implementation;
        bytes memory initializerCall;


        implementation = address(new LiquidDelegation());
        initializerCall = abi.encodeWithSignature(
            "initialize(address,string,string)",
            owner,
            name,
            symbol
        );

        address payable proxy = payable(
            new ERC1967Proxy(implementation, initializerCall)
        );

        Console.log(
            "Proxy deployed: %s \r\n  Implementation deployed: %s",
            proxy,
            implementation
        );

        BaseDelegation delegation = BaseDelegation(
                proxy
            );

        Console.log("Owner is %s",
            delegation.owner()
        );

        bytes memory reinitializerCall = abi.encodeWithSignature(
            "reinitialize(uint64)",
            1
        );

        delegation.upgradeToAndCall(
            implementation,
            reinitializerCall
        );

        (uint24 major, uint24 minor, uint24 patch) = delegation.decodedVersion();
        Console.log("Upgraded to version: %s.%s.%s",
            uint256(major),
            uint256(minor),
            uint256(patch)
        );

        vm.stopBroadcast();

    }

    function nonLiquidDelegation() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address owner = vm.addr(deployerPrivateKey);
        Console.log("Signer is %s", owner);

        vm.startBroadcast(deployerPrivateKey);

        address implementation;
        bytes memory initializerCall;


        implementation = address(new NonLiquidDelegation());
        initializerCall = abi.encodeWithSignature(
            "initialize(address)",
            owner
        );

        address payable proxy = payable(
            new ERC1967Proxy(implementation, initializerCall)
        );

        Console.log(
            "Proxy deployed: %s \r\n  Implementation deployed: %s",
            proxy,
            implementation
        );

        BaseDelegation delegation = BaseDelegation(
                proxy
            );

        Console.log("Owner is %s",
            delegation.owner()
        );

        bytes memory reinitializerCall = abi.encodeWithSignature(
            "reinitialize(uint64)",
            1
        );

        delegation.upgradeToAndCall(
            implementation,
            reinitializerCall
        );

        (uint24 major, uint24 minor, uint24 patch) = delegation.decodedVersion();
        Console.log("Upgraded to version: %s.%s.%s",
            uint256(major),
            uint256(minor),
            uint256(patch)
        );

        vm.stopBroadcast();
    }
}
