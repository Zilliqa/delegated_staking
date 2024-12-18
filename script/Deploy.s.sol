// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity ^0.8.26;

/* solhint-disable no-console */
import {Script} from "forge-std/Script.sol";
import {BaseDelegation} from "src/BaseDelegation.sol";
import {LiquidDelegation} from "src/LiquidDelegation.sol";
import {NonLiquidDelegation} from "src/NonLiquidDelegation.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {console} from "forge-std/console.sol";

contract Deploy is Script {
    using Strings for string;

    function run(string calldata variant, string calldata name, string calldata symbol) external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address owner = vm.addr(deployerPrivateKey);
        console.log("Signer is %s", owner);

        vm.startBroadcast(deployerPrivateKey);

        address implementation;
        bytes memory initializerCall;

        if (variant.equal("LiquidDelegation")) {
            implementation = address(new LiquidDelegation());
            initializerCall = abi.encodeWithSignature(
                "initialize(address,string,string)",
                owner,
                name,
                symbol
            );
        } else if (variant.equal("NonLiquidDelegation")) {
            implementation = address(new NonLiquidDelegation());
            initializerCall = abi.encodeWithSignature(
                "initialize(address)",
                owner
            );
        } else
            return;

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
