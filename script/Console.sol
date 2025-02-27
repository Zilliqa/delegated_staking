// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity ^0.8.26;

/* solhint-disable no-console */
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {console} from "forge-std/console.sol";
import {console2} from "forge-std/console2.sol";

// A library wrapping and extending console.sol from Hardhat and console2.sol from
// the Forge Standard Library. It is only meant to be used in Forge tests and scripts.
library Console {

    function convert(int256 amount, uint8 precision) internal pure returns (
        int256 predecimal,
        string memory zeros,
        uint256 postdecimal
    ) {
        uint256 absAmount = amount < 0 ? uint256(-amount) : uint256(amount);
        uint256 decimals = absAmount % 10**precision;
        while (decimals > 0 && decimals < 10**(precision - 1)) {
            //Console.log("%s %s", zeros, decimals);
            zeros = string.concat(zeros, "0");
            decimals *= 10;
        }
        predecimal = amount / int256(10**precision);
        postdecimal = absAmount % 10**precision;
        while (postdecimal > 0 && postdecimal % 10 == 0)
            postdecimal /= 10;
    }

    function toString(uint256 amount, uint8 precision) internal pure returns (string memory result) {
        return toString(int256(amount), precision);
    }

    function toString(int256 amount, uint8 precision) internal pure returns (string memory result) {
        (int256 predecimal, string memory zeros, uint256 postdecimal) = convert(amount, precision);
        result = string.concat(Strings.toStringSigned(predecimal), ".");
        result = string.concat(result, zeros);
        result = string.concat(result, Strings.toString(postdecimal));
    }

    function logP(string memory format, uint256 amount, uint8 precision) internal pure {
        logP(format, int256(amount), precision);
    }

    function logP(string memory format, int256 amount, uint8 precision) internal pure {
        (int256 predecimal, string memory zeros, uint256 postdecimal) = convert(amount, precision);
        console.log(format, Strings.toStringSigned(predecimal), zeros, postdecimal);
    }

    function log18(string memory format, uint256 amount) internal pure {
        return logP(format, amount, 18);
    }

    function log18(string memory format, int256 amount) internal pure {
        return logP(format, amount, 18);
    }

    function log(string memory format, uint64[] memory array) internal pure {
        string memory s;
        for (uint256 i = 0; i < array.length; i++) {
            s = string.concat(s, Strings.toString(array[i]));
            s = string.concat(s, " ");
        }
        console.log(format, s);
    }

    function log(address first, uint256 second, uint256 third, uint256 fourth) internal pure {
        return console.log(first, Strings.toString(second), Strings.toString(third), Strings.toString(fourth));
    }

    function log(string memory format, uint256 first, uint256 second, uint256 third) internal pure {
        return console.log(format, Strings.toString(first), Strings.toString(second), Strings.toString(third));
    }

    function log(string memory format, uint256 first, uint256 second, string memory third) internal pure {
        return console.log(format, Strings.toString(first), Strings.toString(second), third);
    }

    function log(string memory format, uint256 first, uint256 second) internal pure {
        return console.log(format, Strings.toString(first), Strings.toString(second));
    }

    function log(string memory format, uint256 first, address second) internal pure {
        return console.log(format, Strings.toString(first), second);
    }

    function log(string memory format, address first, address second, address third) internal pure {
        return console.log(format, first, second, third);
    }

    function log(string memory format, address first, uint256 second, uint256 third) internal pure {
        return console.log(format, first, Strings.toString(second), Strings.toString(third));
    }

    function log(string memory format, address first, address second) internal pure {
        return console.log(format, first, second);
    }

    function log(string memory format, uint256 first) internal pure {
        return console.log(format, Strings.toString(first));
    }

    function log(string memory format, address first) internal pure {
        return console.log(format, first);
    }

    function log(uint256 first) internal pure {
        return console.log(Strings.toString(first));
    }

    function log(address first) internal pure {
        return console.log(first);
    }

    function log(string memory first) internal pure {
        return console.log(first);
    }

}