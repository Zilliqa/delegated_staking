// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {NonRebasingLST} from "src/NonRebasingLST.sol";
import {BaseDelegation} from "src/BaseDelegation.sol";
import {ILiquidDelegation} from "src/LiquidDelegation.sol";
import {LiquidDelegationV2} from "src/LiquidDelegationV2.sol";
import {ERC165Checker} from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import "forge-std/console.sol";

contract Unstake is Script {
    using ERC165Checker for address;

    function run(address payable proxy, uint256 amount) external {

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address owner = vm.addr(deployerPrivateKey);
        address staker = msg.sender;

        BaseDelegation delegation = BaseDelegation(
                proxy
            );

        console.log("Running version: %s",
            delegation.version()
        );

        console.log("Current stake: %s wei \r\n  Current rewards: %s wei",
            delegation.getStake(),
            delegation.getRewards()
        );

        if (address(delegation).supportsInterface(type(ILiquidDelegation).interfaceId)) {
            NonRebasingLST lst = NonRebasingLST(LiquidDelegationV2(payable(address(delegation))).getLST());
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

            if (amount == 0) {
                amount = lst.balanceOf(staker);
            }

        } else {
            console.log("Staker balance before: %s wei",
                staker.balance
            );
        }

        vm.broadcast();

        delegation.unstake(
            amount
        );

        if (address(delegation).supportsInterface(type(ILiquidDelegation).interfaceId)) {
            NonRebasingLST lst = NonRebasingLST(LiquidDelegationV2(payable(address(delegation))).getLST());
            console.log("Staker balance after: %s wei %s LST",
                staker.balance,
                lst.balanceOf(staker)
            );
        } else {
            console.log("Staker balance after: %s wei",
                staker.balance
            );
        }
    }
}