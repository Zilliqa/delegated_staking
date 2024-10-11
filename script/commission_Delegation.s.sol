// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {NonRebasingLST} from "src/NonRebasingLST.sol";
import {DelegationV3} from "src/DelegationV3.sol";
import "forge-std/console.sol";

contract Stake is Script {
    function run(address payable proxy) external {

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        //address owner = vm.addr(deployerPrivateKey);

        DelegationV3 delegation = DelegationV3(
                proxy
            );

        console.log("Running version: %s",
            delegation.version()
        );

        console.log("Current stake: %s \r\n  Current rewards: %s",
            delegation.getStake(),
            delegation.getRewards()
        );

        NonRebasingLST lst = NonRebasingLST(delegation.getLST());
        console.log("LST address: %s",
            address(lst)
        );

        console.log("Current commission is: %s",
            delegation.getCommission()
        );

        vm.broadcast(deployerPrivateKey);
        delegation.setCommission(1000);

        console.log("New commission is: %s",
            delegation.getCommission()
        );
    }
}