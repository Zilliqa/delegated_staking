// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity ^0.8.26;

/* solhint-disable no-console */
import {Script} from "forge-std/Script.sol";
import {BaseDelegation} from "src/BaseDelegation.sol";
import {Console} from "script/Console.s.sol";

contract StakeRewards is Script {

    function run(address payable proxy) external {

        BaseDelegation delegation = BaseDelegation(
                proxy
            );

        (uint24 major, uint24 minor, uint24 patch) = delegation.decodedVersion();
        Console.log("Running version: %s.%s.%s",
            uint256(major),
            uint256(minor),
            uint256(patch)
        );

        Console.log("Current stake: %s wei \r\n  Current rewards: %s wei",
            delegation.getStake(),
            delegation.getRewards()
        );

        vm.broadcast();

        delegation.stakeRewards();

        Console.log("New stake: %s wei \r\n  New rewards: %s wei",
            delegation.getStake(),
            delegation.getRewards()
        );
    }
}