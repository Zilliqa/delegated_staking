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

    function commissionRate(address payable proxy) external view {
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
    }

    function commissionRate(address payable proxy, uint16 commissionNumerator) external {
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

        vm.broadcast(deployerPrivateKey);

        delegation.setCommissionNumerator(commissionNumerator);

        Console.log("New commission rate: %s.%s%s%%",
            delegation.getCommissionNumerator(),
            2
        );
    }

    function commissionReceiver(address payable proxy) external view {
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
    }

    function commissionReceiver(address payable proxy, address commissionAddress) external {
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

        vm.broadcast(deployerPrivateKey);

        delegation.setCommissionReceiver(commissionAddress);

        console.log("New commission receiver: %s",
            delegation.getCommissionReceiver()
        );
    }
}