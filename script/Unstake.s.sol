// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity ^0.8.28;

/* solhint-disable no-console */
import { Script } from "forge-std/Script.sol";
import { variant } from "script/CheckVariant.s.sol";
import { Console } from "script/Console.s.sol";
import { BaseDelegation } from "src/BaseDelegation.sol";
import { LiquidDelegation, LIQUID_VARIANT } from "src/LiquidDelegation.sol";
import { NonLiquidDelegation, NONLIQUID_VARIANT } from "src/NonLiquidDelegation.sol";
import { NonRebasingLST } from "src/NonRebasingLST.sol";

contract Unstake is Script {

    function run(address payable proxy, uint256 amount) external {
        address staker = msg.sender;

        BaseDelegation delegation = BaseDelegation(
                proxy
            );

        (uint24 major, uint24 minor, uint24 patch) = delegation.decodedVersion();
        Console.log("Running version: %s.%s.%s",
            uint256(major),
            uint256(minor),
            uint256(patch)
        );

        Console.log("Current stake: %s wei \r\n  Current rewards: %s wei",
            delegation.getStake(),
            delegation.getRewards()
        );

        if (variant(proxy) == LIQUID_VARIANT) {
            NonRebasingLST lst = NonRebasingLST(LiquidDelegation(payable(address(delegation))).getLST());
            Console.log("LST address: %s",
                address(lst)
            );

            Console.log("Staker balance before: %s wei %s %s",
                staker.balance,
                lst.balanceOf(staker),
                lst.symbol()
            );

            if (amount == 0) {
                amount = lst.balanceOf(staker);
            }

        } else if (variant(proxy) == NONLIQUID_VARIANT) {
            Console.log("Staker balance before: %s wei",
                staker.balance
            );

            if (amount == 0) {
                vm.prank(msg.sender);
                amount = NonLiquidDelegation(payable(address(delegation))).getDelegatedAmount();
            }
        } else
            return;

        vm.broadcast();

        delegation.unstake(
            amount
        );

        if (variant(proxy) == LIQUID_VARIANT) {
            NonRebasingLST lst = NonRebasingLST(LiquidDelegation(payable(address(delegation))).getLST());
            Console.log("Staker balance after: %s wei %s %s",
                staker.balance,
                lst.balanceOf(staker),
                lst.symbol()
            );
        } else {
            Console.log("Staker balance after: %s wei",
                staker.balance
            );
        }
    }
}