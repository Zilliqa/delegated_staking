// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity ^0.8.26;

/* solhint-disable no-console */
import {Script} from "forge-std/Script.sol";
import {NonRebasingLST} from "src/NonRebasingLST.sol";
import {BaseDelegation} from "src/BaseDelegation.sol";
import {ILiquidDelegation, LiquidDelegation} from "src/LiquidDelegation.sol";
import {ERC165Checker} from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import {console} from "forge-std/console.sol";

contract Stake is Script {
    using ERC165Checker for address;

    function run(address payable proxy, uint256 amount) external {
        address staker = msg.sender;

        BaseDelegation delegation = BaseDelegation(
                proxy
            );

        (uint24 major, uint24 minor, uint24 patch) = delegation.decodedVersion();
        console.log("Running version: %s.%s.%s",
            uint256(major),
            uint256(minor),
            uint256(patch)
        );

        console.log("Current stake: %s wei \r\n  Current rewards: %s wei",
            delegation.getStake(),
            delegation.getRewards()
        );

        if (address(delegation).supportsInterface(type(ILiquidDelegation).interfaceId)) {
            NonRebasingLST lst = NonRebasingLST(LiquidDelegation(payable(address(delegation))).getLST());
            console.log("LST address: %s",
                address(lst)
            );

            console.log("Staker balance before: %s wei %s %s",
                staker.balance,
                lst.balanceOf(staker),
                lst.symbol()
            );
        } else {
            console.log("Staker balance before: %s wei",
                staker.balance
            );
        }

        vm.broadcast();

        delegation.stake{
            value: amount
        }();

        if (address(delegation).supportsInterface(type(ILiquidDelegation).interfaceId)) {
            NonRebasingLST lst = NonRebasingLST(LiquidDelegation(payable(address(delegation))).getLST());
            console.log("Staker balance after: %s wei %s %s",
                staker.balance,
                lst.balanceOf(staker),
                lst.symbol()
            );
        } else {
            console.log("Staker balance after: %s wei",
                staker.balance
            );
        }
    }
}