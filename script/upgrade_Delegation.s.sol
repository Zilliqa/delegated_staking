// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {Delegation} from "src/Delegation.sol";
import {DelegationV2} from "src/DelegationV2.sol";
import "forge-std/console.sol";

contract Upgrade is Script {
    function run(address payable proxy) external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address owner = vm.addr(deployerPrivateKey);
        console.log("Signer is %s", owner);

        Delegation oldDelegation = Delegation(
            proxy
        );

        console.log("Upgrading from version: %s",
            oldDelegation.version()
        );

        console.log("Owner is %s",
            oldDelegation.owner()
        );

        vm.startBroadcast(deployerPrivateKey);

        address payable newImplementation = payable(
            new DelegationV2()
        );

        console.log("New implementation deployed: %s",
            newImplementation
        );

        bytes memory reinitializerCall = abi.encodeWithSelector(
            DelegationV2.reinitialize.selector
        );

        oldDelegation.upgradeToAndCall(
            newImplementation,
            reinitializerCall
        );

        DelegationV2 newDelegation = DelegationV2(
                proxy
            );

        console.log("Upgraded to version: %s",
            newDelegation.version()
        );

        vm.stopBroadcast();
    }
}