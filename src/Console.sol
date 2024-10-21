// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity ^0.8.26;

import "forge-std/console.sol";

library Console {
    function log(string memory format, uint256 amount, uint8 precision) pure internal {
        string memory zeros = "";
        uint256 decimals = amount % 10**precision;
        while (decimals > 0 && decimals < 10**(precision - 1)) {
            //console.log("%s %s", zeros, decimals);
            zeros = string.concat(zeros, "0");
            decimals *= 10;
        }
        console.log(
            format,
            amount / 10**precision,
            zeros,
            amount % 10**precision
        );
    }

    function log(string memory format, uint256 amount) pure internal {
        return log(format, amount, 18);
    }
}