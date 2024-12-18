// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity ^0.8.26;

/* solhint-disable no-console */
import {Script} from "forge-std/Script.sol";
import {ILiquidDelegation} from "src/LiquidDelegation.sol";
import {INonLiquidDelegation} from "src/NonLiquidDelegation.sol";
import {ERC165Checker} from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import {console} from "forge-std/console.sol";

contract CheckVariant is Script {
    using ERC165Checker for address;

    function run(address proxy) external view {

        if (proxy.supportsInterface(type(ILiquidDelegation).interfaceId))
            console.log("ILiquidDelegation");

        if (proxy.supportsInterface(type(INonLiquidDelegation).interfaceId))
            console.log("INonLiquidDelegation");

    }
}