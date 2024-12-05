/* solhint-disable no-console */
// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity ^0.8.26;

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {console} from "forge-std/console.sol";

library Console {

    function convert(int256 amount, uint8 precision) internal pure returns (
        int256 predecimal,
        string memory zeros,
        uint256 postdecimal
    ) {
        uint256 absAmount = amount < 0 ? uint256(-amount) : uint256(amount);
        uint256 decimals = absAmount % 10**precision;
        while (decimals > 0 && decimals < 10**(precision - 1)) {
            //console.log("%s %s", zeros, decimals);
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

    function log(string memory format, uint256 amount, uint8 precision) internal view {
        log(format, int256(amount), precision);
    }

    function log(string memory format, int256 amount, uint8 precision) internal view {
        (int256 predecimal, string memory zeros, uint256 postdecimal) = convert(amount, precision);
        console.log(format, Strings.toStringSigned(predecimal), zeros, postdecimal);
    }

    function log(string memory format, uint256 amount) internal view {
        return log(format, amount, 18);
    }

    function log(string memory format, int256 amount) internal view {
        return log(format, amount, 18);
    }

    function log(string memory format, uint64[] memory array) internal view {
        string memory s;
        for (uint256 i = 0; i < array.length; i++) {
            s = string.concat(s, Strings.toString(array[i]));
            s = string.concat(s, " ");
        }
        console.log(format, s);
    }
}