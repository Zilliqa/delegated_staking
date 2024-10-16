// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {NonRebasingLST} from "src/NonRebasingLST.sol";
import {DelegationV2} from "src/DelegationV2.sol";
import "forge-std/console.sol";

contract Unstake is Script {
    function run(address payable proxy, uint256 amount) external {

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address owner = vm.addr(deployerPrivateKey);
        address staker = msg.sender;

        DelegationV2 delegation = DelegationV2(
                proxy
            );

        console.log("Running version: %s",
            delegation.version()
        );

        console.log("Current stake: %s ZIL \r\n  Current rewards: %s ZIL",
            delegation.getStake(),
            delegation.getRewards()
        );

        NonRebasingLST lst = NonRebasingLST(delegation.getLST());
        console.log("LST address: %s",
            address(lst)
        );

        console.log("Owner LST balance: %s LST",
            lst.balanceOf(owner)
        );

        console.log("Staker balance before: %s ZIL %s LST",
            staker.balance,
            lst.balanceOf(staker)
        );

        if (amount == 0) {
            amount = lst.balanceOf(staker);
        }

        vm.broadcast();

        delegation.unstake(
            amount
        );

        console.log("Staker balance after: %s ZIL %s LST",
            staker.balance,
            lst.balanceOf(staker)
        );
    }
}