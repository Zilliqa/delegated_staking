// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {NonLiquidDelegation} from "src/NonLiquidDelegation.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import "forge-std/console.sol";

contract Rewards is Script {
    using Strings for string;

    function run(address payable proxy, string calldata amount, string calldata additionalSteps) external {
        address staker = msg.sender;

        NonLiquidDelegation delegation = NonLiquidDelegation(
                proxy
            );

        console.log("Running version: %s",
            delegation.version()
        );

        console.log("Staker balance before: %s wei",
            staker.balance
        );

        vm.broadcast();

        //TODO: figure out why Strings.parseUint() is not found
        if (amount.equal("all"))
            if (additionalSteps.equal("all"))
                delegation.withdrawAllRewards();
            else
                delegation.withdrawAllRewards(uint64(vm.parseUint(additionalSteps)));
        else
            if (additionalSteps.equal("all"))
                delegation.withdrawRewards(vm.parseUint(amount));
            else
                delegation.withdrawRewards(vm.parseUint(amount), uint64(vm.parseUint(additionalSteps)));

        console.log("Staker balance after: %s wei",
            staker.balance
        );
    }
}