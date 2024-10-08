// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {NonRebasingLST} from "src/NonRebasingLST.sol";
import {DelegationV3} from "src/DelegationV3.sol";
import "forge-std/console.sol";

contract Stake is Script {
    function run(address payable proxy) external {

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address owner = vm.addr(deployerPrivateKey);
        //console.log("Owner is %s", owner);

        //address staker = 0xd819fFcE7A58b1E835c25617Db7b46a00888B013;
        address staker = msg.sender;
        //address payable proxy = payable(0x7A0b7e6D24eDe78260c9ddBD98e828B0e11A8EA2);

        DelegationV3 delegation = DelegationV3(
                proxy
            );

        console.log("Running version: %s",
            delegation.version()
        );

        console.log("Current stake: %s \r\n  Current rewards: %s",
            delegation.getStake(),
            delegation.getRewards()
        );

        NonRebasingLST lst = NonRebasingLST(delegation.getLST());
        console.log("LST address: %s",
            address(lst)
        );

        console.log("Owner balance: %s",
            lst.balanceOf(owner)
        );

        console.log("Staker balance: %s",
            lst.balanceOf(staker)
        );

        //vm.broadcast(staker);
        vm.broadcast();

        delegation.stake{
            value: 200 ether
        }();

        console.log("Staker balance: %s",
            lst.balanceOf(staker)
        );
    }
}