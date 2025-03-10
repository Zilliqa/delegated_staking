// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity ^0.8.28;

/* solhint-disable no-console */
import {Script} from "forge-std/Script.sol";
import {BaseDelegation} from "src/BaseDelegation.sol";
import {Console} from "script/Console.s.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {Console} from "script/Console.s.sol";

contract Configure is Script {
    using Strings for string;

    function commissionRate(address payable proxy) external view {
        BaseDelegation delegation = BaseDelegation(
            proxy
        );

        (uint24 major, uint24 minor, uint24 patch) = delegation.decodedVersion();
        Console.log("Running version: %s.%s.%s",
            uint256(major),
            uint256(minor),
            uint256(patch)
        );

        Console.logP("Commission rate: %s.%s%s%%",
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
        Console.log("Running version: %s.%s.%s",
            uint256(major),
            uint256(minor),
            uint256(patch)
        );

        Console.logP("Commission rate: %s.%s%s%%",
            delegation.getCommissionNumerator(),
            2
        );

        vm.broadcast(deployerPrivateKey);

        delegation.setCommissionNumerator(commissionNumerator);

        Console.logP("New commission rate: %s.%s%s%%",
            delegation.getCommissionNumerator(),
            2
        );
    }

    function commissionReceiver(address payable proxy) external view {
        BaseDelegation delegation = BaseDelegation(
            proxy
        );

        (uint24 major, uint24 minor, uint24 patch) = delegation.decodedVersion();
        Console.log("Running version: %s.%s.%s",
            uint256(major),
            uint256(minor),
            uint256(patch)
        );

        Console.log("Commission receiver: %s",
            delegation.getCommissionReceiver()
        );
    }

    function commissionReceiver(address payable proxy, address commissionAddress) external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        BaseDelegation delegation = BaseDelegation(
            proxy
        );

        (uint24 major, uint24 minor, uint24 patch) = delegation.decodedVersion();
        Console.log("Running version: %s.%s.%s",
            uint256(major),
            uint256(minor),
            uint256(patch)
        );

        Console.log("Commission receiver: %s",
            delegation.getCommissionReceiver()
        );

        vm.broadcast(deployerPrivateKey);

        delegation.setCommissionReceiver(commissionAddress);

        Console.log("New commission receiver: %s",
            delegation.getCommissionReceiver()
        );
    }
}