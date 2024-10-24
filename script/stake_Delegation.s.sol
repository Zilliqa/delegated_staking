// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {NonRebasingLST} from "src/NonRebasingLST.sol";
import {LiquidDelegationV2} from "src/LiquidDelegationV2.sol";
import "forge-std/console.sol";

contract Stake is Script {
    function run(address payable proxy, uint256 amount) external {

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address owner = vm.addr(deployerPrivateKey);
        address staker = msg.sender;

        LiquidDelegationV2 delegation = LiquidDelegationV2(
                proxy
            );

        console.log("Running version: %s",
            delegation.version()
        );

        console.log("Current stake: %s wei \r\n  Current rewards: %s wei",
            delegation.getStake(),
            delegation.getRewards()
        );

        NonRebasingLST lst = NonRebasingLST(delegation.getLST());
        console.log("LST address: %s",
            address(lst)
        );

        console.log("Owner balance: %s LST",
            lst.balanceOf(owner)
        );

        console.log("Staker balance before: %s wei %s LST",
            staker.balance,
            lst.balanceOf(staker)
        );

        vm.broadcast();

        delegation.stake{
            value: amount
        }();

        console.log("Staker balance after: %s wei %s LST",
            staker.balance,
            lst.balanceOf(staker)
        );
    }
}