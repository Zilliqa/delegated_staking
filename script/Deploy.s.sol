// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity ^0.8.28;

/* solhint-disable no-console */
import {Script} from "forge-std/Script.sol";
import {BaseDelegation} from "src/BaseDelegation.sol";
import {LiquidDelegation} from "src/LiquidDelegation.sol";
import {NonLiquidDelegation} from "src/NonLiquidDelegation.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {Console} from "script/Console.s.sol";

contract Deploy is Script {
    using Strings for string;

    function _run(address implementation, bytes memory initializerCall) internal {
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
    }

    function liquidDelegation(string calldata name, string calldata symbol) external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address owner = vm.addr(deployerPrivateKey);
        Console.log("Signer is %s", owner);

        vm.startBroadcast(deployerPrivateKey);

        bytes memory initializerCall = abi.encodeWithSignature(
            "initialize(address,string,string)",
            owner,
            name,
            symbol
        );

        _run(address(new LiquidDelegation()), initializerCall);

        vm.stopBroadcast();

    }

    function nonLiquidDelegation() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address owner = vm.addr(deployerPrivateKey);
        Console.log("Signer is %s", owner);

        vm.startBroadcast(deployerPrivateKey);

        bytes memory initializerCall = abi.encodeWithSignature(
            "initialize(address)",
            owner
        );

        _run(address(new NonLiquidDelegation()), initializerCall);

        vm.stopBroadcast();
    }
}
