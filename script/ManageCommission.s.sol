// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity ^0.8.26;

/* solhint-disable no-console */
import {Script} from "forge-std/Script.sol";
import {BaseDelegation} from "src/BaseDelegation.sol";
import {Console} from "src/Console.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {console} from "forge-std/console.sol";

contract ManageCommission is Script {
    using Strings for string;

    function run(address payable proxy, string calldata commissionNumerator, bool collectCommission) external {
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

        if (!commissionNumerator.equal("same")) {
            vm.broadcast(deployerPrivateKey);

            delegation.setCommissionNumerator(uint16(vm.parseUint(commissionNumerator)));

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