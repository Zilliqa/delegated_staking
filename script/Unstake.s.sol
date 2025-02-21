// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity ^0.8.26;

/* solhint-disable no-console */
import {Script} from "forge-std/Script.sol";
import {NonRebasingLST} from "src/NonRebasingLST.sol";
import {BaseDelegation} from "src/BaseDelegation.sol";
import {ILiquidDelegation} from "src/LiquidDelegation.sol";
import {INonLiquidDelegation} from "src/NonLiquidDelegation.sol";
import {ERC165Checker} from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import {Console} from "script/Console.sol";

contract Unstake is Script {
    using ERC165Checker for address;

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

        if (address(delegation).supportsInterface(type(ILiquidDelegation).interfaceId)) {
            NonRebasingLST lst = NonRebasingLST(ILiquidDelegation(payable(address(delegation))).getLST());
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

        } else if (address(delegation).supportsInterface(type(INonLiquidDelegation).interfaceId)) {
            Console.log("Staker balance before: %s wei",
                staker.balance
            );

            if (amount == 0) {
                vm.prank(msg.sender);
                amount = INonLiquidDelegation(address(delegation)).getDelegatedAmount();
            }
        } else
            return;

        vm.broadcast();

        delegation.unstake(
            amount
        );

        if (address(delegation).supportsInterface(type(ILiquidDelegation).interfaceId)) {
            NonRebasingLST lst = NonRebasingLST(ILiquidDelegation(payable(address(delegation))).getLST());
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