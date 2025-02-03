// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity ^0.8.26;

/* solhint-disable no-console */
import {Script} from "forge-std/Script.sol";
import {BaseDelegation} from "src/BaseDelegation.sol";
import {console} from "forge-std/console.sol";

contract CheckVersion is Script {

    function run(address proxy) external view {

        BaseDelegation delegation = BaseDelegation(
            proxy
        );

        uint64 version = delegation.version();

        // the contract has been already upgraded to a version that supports semver 
        if (version >= 2**20) {
            (uint24 major, uint24 minor, uint24 patch) = delegation.decodedVersion();
            console.log("%s.%s.%s",
                uint256(major),
                uint256(minor),
                uint256(patch)
            );
        } else if (version == 1)
            console.log("Contract hasn't been upgraded to any version yet",
                version
            );
        else
            console.log("%s",
                version
            );

    }
}