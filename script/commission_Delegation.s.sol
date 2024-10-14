// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {NonRebasingLST} from "src/NonRebasingLST.sol";
import {DelegationV2} from "src/DelegationV2.sol";
import "forge-std/console.sol";

contract Stake is Script {
    function run(address payable proxy, uint16 commissionNumerator, address commissionAddress) external {

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address owner = vm.addr(deployerPrivateKey);

        DelegationV2 delegation = DelegationV2(
                proxy
            );

        console.log("Running version: %s",
            delegation.version()
        );

        NonRebasingLST lst = NonRebasingLST(delegation.getLST());
        console.log("LST address: %s",
            address(lst)
        );

        console.log("Current commission rate and commission address: %s.%s%% %s",
            uint256(delegation.getCommissionNumerator()) * 100 / uint256(delegation.DENOMINATOR()),
            uint256(delegation.getCommissionNumerator()) % (uint256(delegation.DENOMINATOR()) / 100),
            delegation.getCommissionAddress()
        );

        vm.startBroadcast(deployerPrivateKey);

        delegation.setCommissionNumerator(commissionNumerator);
        delegation.setCommissionAddress(commissionAddress);

        vm.stopBroadcast();

        console.log("New commission rate and commission address: %s.%s%% %s",
            uint256(delegation.getCommissionNumerator()) * 100 / uint256(delegation.DENOMINATOR()),
            uint256(delegation.getCommissionNumerator()) % (uint256(delegation.DENOMINATOR()) / 100),
            delegation.getCommissionAddress()
        );
    }
}