// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity ^0.8.26;

/* solhint-disable no-console */
import {Script} from "forge-std/Script.sol";
import {BaseDelegation} from "src/BaseDelegation.sol";
import {console} from "forge-std/console.sol";

contract Claim is Script {
    function run(address payable proxy) external {
        address staker = msg.sender;

        BaseDelegation delegation = BaseDelegation(
                proxy
            );

        console.log("Running version: %s",
            delegation.version()
        );

        console.log("Staker balance before: %s wei",
            staker.balance
        );

        vm.broadcast();

        delegation.claim();

        console.log("Staker balance after: %s wei",
            staker.balance
        );
    }
}