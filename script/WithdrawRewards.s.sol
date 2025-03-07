// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity ^0.8.26;

/* solhint-disable no-console */
import {Script} from "forge-std/Script.sol";
import {NonLiquidDelegation} from "src/NonLiquidDelegation.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {Console} from "script/Console.s.sol";

contract WithdrawRewards is Script {
    using Strings for string;

    function run(address payable proxy, string calldata amount, string calldata additionalSteps) external {
        address staker = msg.sender;

        NonLiquidDelegation delegation = NonLiquidDelegation(
                proxy
            );

        (uint24 major, uint24 minor, uint24 patch) = delegation.decodedVersion();
        Console.log("Running version: %s.%s.%s",
            uint256(major),
            uint256(minor),
            uint256(patch)
        );

        Console.log("Staker balance before: %s wei",
            staker.balance
        );

        vm.broadcast();

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

        Console.log("Staker balance after: %s wei",
            staker.balance
        );
    }
}