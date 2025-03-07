// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity ^0.8.26;

/* solhint-disable no-console */
import {Script} from "forge-std/Script.sol";
import {BaseDelegation} from "src/BaseDelegation.sol";
import {LIQUID_VARIANT} from "src/LiquidDelegation.sol";
import {NONLIQUID_VARIANT} from "src/NonLiquidDelegation.sol";
import {Console} from "script/Console.s.sol";

function variant(address proxy) view returns(bytes32) {
        BaseDelegation delegation = BaseDelegation(payable(proxy));
        uint64 version = delegation.version();
        if (version < delegation.encodeVersion(0, 5, 2)) {
            (bool success, bytes memory result) = proxy.staticcall(abi.encodeWithSignature("interfaceId()"));
            if (!success)
                return 0;
            bytes4 interfaceId = abi.decode(result, (bytes4));
            if (interfaceId == 0x88826e8e)
                return LIQUID_VARIANT;
            else if (interfaceId == 0xa2adf26a)
                return NONLIQUID_VARIANT;
            else
                return 0;
        } else 
            return delegation.variant();
}

contract CheckVariant is Script {

    function run(address proxy) external view {

        if (variant(proxy) == LIQUID_VARIANT)
            Console.log("LiquidStaking");
        else if (variant(proxy) == NONLIQUID_VARIANT)
            Console.log("NonLiquidStaking");
    }
}