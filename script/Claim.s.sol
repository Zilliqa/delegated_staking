// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity 0.8.28;

/* solhint-disable no-console */
import { Script } from "forge-std/Script.sol";
import { Console } from "script/Console.s.sol";
import { BaseDelegation } from "src/BaseDelegation.sol";

contract Claim is Script {
    function run(address payable proxy) external {
        address staker = msg.sender;

        BaseDelegation delegation = BaseDelegation(
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

        delegation.claim();

        Console.log("Staker balance after: %s wei",
            staker.balance
        );
    }
}