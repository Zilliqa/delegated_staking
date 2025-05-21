// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity 0.8.28;

/* solhint-disable no-console */
import { Script } from "forge-std/Script.sol";
import { Console } from "script/Console.s.sol";
import { BaseDelegation } from "src/BaseDelegation.sol";
import { LIQUID_VARIANT } from "src/LiquidDelegation.sol";
import { NONLIQUID_VARIANT } from "src/NonLiquidDelegation.sol";

function variant(address proxy) pure returns(bytes32) {
    BaseDelegation delegation = BaseDelegation(payable(proxy));
    return delegation.variant();
}

contract CheckVariant is Script {

    function run(address proxy) external pure {

        if (variant(proxy) == LIQUID_VARIANT)
            Console.log("LiquidStaking");
        else if (variant(proxy) == NONLIQUID_VARIANT)
            Console.log("NonLiquidStaking");
    }
}