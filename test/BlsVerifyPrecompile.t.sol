// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity ^0.8.26;

contract BlsVerifyPrecompile {

    function blsVerify(bytes memory, bytes memory, bytes memory) public pure returns(bool) {
        return true;
    }

}