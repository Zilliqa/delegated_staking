// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity ^0.8.26;

/* solhint-disable no-console */
import {Script} from "forge-std/Script.sol";
import {BaseDelegation} from "src/BaseDelegation.sol";
import {console} from "forge-std/console.sol";

contract StakeRewards is Script {

    function run(address payable proxy) external {

        BaseDelegation delegation = BaseDelegation(
                proxy
            );

        console.log("Running version: %s",
            delegation.version()
        );

        console.log("Current stake: %s wei \r\n  Current rewards: %s wei",
            delegation.getStake(),
            delegation.getRewards()
        );

        vm.broadcast();

        delegation.stakeRewards();

        console.log("New stake: %s wei \r\n  New rewards: %s wei",
            delegation.getStake(),
            delegation.getRewards()
        );
    }
}