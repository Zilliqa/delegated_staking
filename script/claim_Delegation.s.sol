// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {DelegationV2} from "src/DelegationV2.sol";
import "forge-std/console.sol";

contract Claim is Script {
    function run(address payable proxy) external {

        address staker = msg.sender;

        DelegationV2 delegation = DelegationV2(
                proxy
            );

        console.log("Running version: %s",
            delegation.version()
        );

        console.log("Staker balance before: %s ZIL",
            staker.balance
        );

        vm.broadcast();

        delegation.claim();

        console.log("Staker balance after: %s ZIL",
            staker.balance
        );
    }
}