// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {NonRebasingLST} from "src/NonRebasingLST.sol";
import {DelegationV2} from "src/DelegationV2.sol";
import "forge-std/console.sol";

contract Stake is Script {
    function run(address payable proxy, uint16 commissionNumerator) external {

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

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

        console.log("Old commission rate: %s.%s%%",
            uint256(delegation.getCommissionNumerator()) * 100 / uint256(delegation.DENOMINATOR()),
            //TODO: check if the decimals are printed correctly e.g. 12.01% vs 12.1%
            uint256(delegation.getCommissionNumerator()) % (uint256(delegation.DENOMINATOR()) / 100)
        );

        vm.broadcast(deployerPrivateKey);

        delegation.setCommissionNumerator(commissionNumerator);

        console.log("New commission rate: %s.%s%%",
            uint256(delegation.getCommissionNumerator()) * 100 / uint256(delegation.DENOMINATOR()),
            //TODO: check if the decimals are printed correctly e.g. 12.01% vs 12.1%
            uint256(delegation.getCommissionNumerator()) % (uint256(delegation.DENOMINATOR()) / 100)
        );
    }
}