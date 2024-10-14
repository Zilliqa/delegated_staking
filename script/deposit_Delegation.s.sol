// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {NonRebasingLST} from "src/NonRebasingLST.sol";
import {DelegationV2} from "src/DelegationV2.sol";
import "forge-std/console.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

contract Deposit is Script {
    function run(address payable proxy) external {

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address owner = vm.addr(deployerPrivateKey);

        //address payable proxy = payable(0x7A0b7e6D24eDe78260c9ddBD98e828B0e11A8EA2);

        DelegationV2 delegation = DelegationV2(
                proxy
            );
/*
        console.log("Running version: %s",
            delegation.version()
        );
*/
        //TODO: output the arguments to use with cast send since forge script will fail when it tries to execute the script locally and can't call the BLS signature verification precompile
        /*vm.broadcast(deployerPrivateKey);

        delegation.deposit{
            value: 10_000_000 ether
        }(
            bytes(hex"92fbe50544dce63cfdcc88301d7412f0edea024c91ae5d6a04c7cd3819edfc1b9d75d9121080af12e00f054d221f876c"),
            bytes(hex"002408011220d5ed74b09dcbe84d3b32a56c01ab721cf82809848b6604535212a219d35c412f"), //"12D3KooWQDT1rcThrxoSmnCt9n35jrhy5wo4BHsM5JuVz8LstQpN"
            bytes(hex"b14832a866a49ddf8a3104f8ee379d29c136f29aeb8fccec9d7fb17180b99e8ed29bee2ada5ce390cb704bc6fd7f5ce814f914498376c4b8bc14841a57ae22279769ec8614e2673ba7f36edc5a4bf5733aa9d70af626279ee2b2cde939b4bd8a")
        );

        console.log("Current stake: %s \r\n  Current rewards: %s",
            delegation.getStake(),
            delegation.getRewards()
        );
        */
        bytes memory input = abi.encodeWithSignature(
            "deposit(bytes,bytes,bytes)",
            bytes(hex"92fbe50544dce63cfdcc88301d7412f0edea024c91ae5d6a04c7cd3819edfc1b9d75d9121080af12e00f054d221f876c"),
            bytes(hex"002408011220d5ed74b09dcbe84d3b32a56c01ab721cf82809848b6604535212a219d35c412f"), //"12D3KooWQDT1rcThrxoSmnCt9n35jrhy5wo4BHsM5JuVz8LstQpN"
            bytes(hex"b14832a866a49ddf8a3104f8ee379d29c136f29aeb8fccec9d7fb17180b99e8ed29bee2ada5ce390cb704bc6fd7f5ce814f914498376c4b8bc14841a57ae22279769ec8614e2673ba7f36edc5a4bf5733aa9d70af626279ee2b2cde939b4bd8a")
        );
        string memory output = 'cast send';
        output = string.concat(output, ' --legacy --value 10000000ether --rpc-url https://api.zq2-devnet.zilliqa.com --private-key ');
        output = string.concat(output, Strings.toHexString(deployerPrivateKey));
        output = string.concat(output, ' ');
        output = string.concat(output, Strings.toHexString(address(delegation)));
        /*console.log("%s \\", output);
        console.logBytes(input);*/
        output = string.concat(output, ' "deposit(bytes,bytes,bytes)"');
        output = string.concat(output, ' 0x92fbe50544dce63cfdcc88301d7412f0edea024c91ae5d6a04c7cd3819edfc1b9d75d9121080af12e00f054d221f876c');
        output = string.concat(output, ' 0x002408011220d5ed74b09dcbe84d3b32a56c01ab721cf82809848b6604535212a219d35c412f');
        output = string.concat(output, ' 0xb14832a866a49ddf8a3104f8ee379d29c136f29aeb8fccec9d7fb17180b99e8ed29bee2ada5ce390cb704bc6fd7f5ce814f914498376c4b8bc14841a57ae22279769ec8614e2673ba7f36edc5a4bf5733aa9d70af626279ee2b2cde939b4bd8a');
        console.log(output);

        // use this only for testing if deposit transaction not possible (e.g. no fully synced node available)
        /*delegation.setup(
            bytes(hex"b0447d886f8499bc0fd4aa21da63d71a0175ddd005d217a00c5304e1272e4a79a7df0ecb878a343582c9f2ca78c8c17f"),
            bytes(hex"0024080112203f260505ee97570cbc034831097eddf177c4a49151dffb129abdc209329cc7e0")
        );
        */
/*
        NonRebasingLST lst = NonRebasingLST(delegation.getLST());
        console.log("LST address: %s",
            address(lst)
        );

        console.log("Owner LST balance: %s",
            lst.balanceOf(owner)
        );
*/
    }
}