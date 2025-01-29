// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity ^0.8.26;

/* solhint-disable no-console */
import {Script} from "forge-std/Script.sol";
import {BaseDelegation} from "src/BaseDelegation.sol";
import {Console} from "src/Console.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {console} from "forge-std/console.sol";

contract Configure is Script {
    using Strings for string;

    function commissionRate(address payable proxy, string calldata commissionNumerator, bool collectCommission) external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        BaseDelegation delegation = BaseDelegation(
            proxy
        );

        (uint24 major, uint24 minor, uint24 patch) = delegation.decodedVersion();
        console.log("Running version: %s.%s.%s",
            uint256(major),
            uint256(minor),
            uint256(patch)
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

    function commissionReceiver(address payable proxy, address commissionAddress, bool collectCommission) external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        BaseDelegation delegation = BaseDelegation(
            proxy
        );

        (uint24 major, uint24 minor, uint24 patch) = delegation.decodedVersion();
        console.log("Running version: %s.%s.%s",
            uint256(major),
            uint256(minor),
            uint256(patch)
        );

        console.log("Commission receiver: %s",
            delegation.getCommissionReceiver()
        );

        vm.startBroadcast(deployerPrivateKey);

        delegation.setCommissionReceiver(commissionAddress);

        console.log("New commission receiver: %s",
            delegation.getCommissionNumerator()
        );

        if (collectCommission) {
            delegation.collectCommission();

            console.log("Outstanding commission transferred");
        }

        vm.stopBroadcast();
    }
}