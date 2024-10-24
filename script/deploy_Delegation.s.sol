// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {LiquidDelegation} from "src/LiquidDelegation.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "forge-std/console.sol";

contract Deploy is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address owner = vm.addr(deployerPrivateKey);
        console.log("Signer is %s", owner);

        vm.startBroadcast(deployerPrivateKey);

        address implementation = address(
            new LiquidDelegation()
        );

        bytes memory initializerCall = abi.encodeWithSelector(
            LiquidDelegation.initialize.selector,
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

        LiquidDelegation delegation = LiquidDelegation(
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
