// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {BaseDelegation} from "src/BaseDelegation.sol";
import {LiquidDelegation} from "src/LiquidDelegation.sol";
import {NonLiquidDelegation} from "src/NonLiquidDelegation.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import "forge-std/console.sol";

contract Deploy is Script {
    using Strings for string;

    function run(string calldata variant) external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address owner = vm.addr(deployerPrivateKey);
        console.log("Signer is %s", owner);

        vm.startBroadcast(deployerPrivateKey);

        address implementation;

        if (variant.equal("LiquidDelegation"))
            implementation = address(new LiquidDelegation());
        else if (variant.equal("NonLiquidDelegation"))
            implementation = address(new NonLiquidDelegation());
        else
            return;

        bytes memory initializerCall = abi.encodeWithSignature(
            "initialize(address)",
            owner
        );

        address payable proxy = payable(
            new ERC1967Proxy(implementation, initializerCall)
        );

        console.log(
            "Proxy deployed: %s \r\n  Implementation deployed: %s",
            proxy,
            implementation
        );

        BaseDelegation delegation = BaseDelegation(
                proxy
            );

        console.log("Deployed version: %s",
            delegation.version()
        );

        console.log("Owner is %s",
            delegation.owner()
        );

        vm.stopBroadcast();
    }
}
