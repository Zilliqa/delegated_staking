// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {ILiquidDelegation} from "src/LiquidDelegation.sol";
import {INonLiquidDelegation} from "src/NonLiquidDelegation.sol";
import {ERC165Checker} from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import "forge-std/console.sol";

contract Upgrade is Script {
    using ERC165Checker for address;

    function run(address proxy) external {

        if (proxy.supportsInterface(type(ILiquidDelegation).interfaceId))
            console.log("ILiquidDelegation");

        if (proxy.supportsInterface(type(INonLiquidDelegation).interfaceId))
            console.log("INonLiquidDelegation");

    }
}