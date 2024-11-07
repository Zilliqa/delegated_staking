// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {BaseDelegation} from "src/BaseDelegation.sol";
import {Console} from "src/Console.sol";
import "forge-std/console.sol";

contract Stake is Script {
    function run(address payable proxy, uint16 commissionNumerator, bool collectCommission) external {

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        BaseDelegation delegation = BaseDelegation(
            proxy
        );

        console.log("Running version: %s",
            delegation.version()
        );

        Console.log("Commission rate: %s.%s%s%%",
            delegation.getCommissionNumerator(),
            2
        );

        if (commissionNumerator <= delegation.DENOMINATOR()) {
            vm.broadcast(deployerPrivateKey);

            delegation.setCommissionNumerator(commissionNumerator);

            Console.log("New commission rate: %s.%s%s%%",
                delegation.getCommissionNumerator(),
                2
            );
        }

        if (collectCommission) {
            vm.broadcast(deployerPrivateKey);

            delegation.collectCommission();

            console.log("Outstanding commission transferred");
        }
    }
}