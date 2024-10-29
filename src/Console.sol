// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity ^0.8.26;

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import "forge-std/console.sol";

library Console {
    function convert(uint256 amount, uint8 precision) pure internal returns (
        uint256 predecimal,
        string memory zeros,
        uint256 postdecimal
    ) {
        uint256 decimals = amount % 10**precision;
        while (decimals > 0 && decimals < 10**(precision - 1)) {
            //console.log("%s %s", zeros, decimals);
            zeros = string.concat(zeros, "0");
            decimals *= 10;
        }
        predecimal = amount / 10**precision;
        postdecimal = amount % 10**precision;
        while (postdecimal > 0 && postdecimal % 10 == 0)
            postdecimal /= 10;
    }

    function slice(bytes calldata input, uint256 from, uint256 to) internal pure returns(bytes memory) {
        return input[from:to];
    }

    function toString(uint256 amount, uint8 precision) pure internal returns (string memory result) {
        (uint256 predecimal, string memory zeros, uint256 postdecimal) = convert(amount, precision);
        result = string.concat(Strings.toString(predecimal), ".");
        result = string.concat(result, zeros);
        result = string.concat(result, Strings.toString(postdecimal));
    }

    function log(string memory format, uint256 amount, uint8 precision) pure internal {
        (uint256 predecimal, string memory zeros, uint256 postdecimal) = convert(amount, precision);
        console.log(format, predecimal, zeros, postdecimal);
    }

    function log(string memory format, uint256 amount) pure internal {
        return log(format, amount, 18);
    }

    function log(string memory format, uint256[] memory array) pure internal {
        string memory s;
        for (uint256 i = 0; i < array.length; i++) {
            s = string.concat(s, Strings.toString(array[i]));
            s = string.concat(s, " ");
        }
        console.log(format, s);
    }
}