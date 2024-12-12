// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity ^0.8.26;

import {BaseDelegation} from "src/BaseDelegation.sol";
import {Delegation} from "src/Delegation.sol";
import {InitialStaker} from "@zilliqa/zq2/deposit_v1.sol";
import {Deposit} from "@zilliqa/zq2/deposit_v3.sol";
import {Console} from "src/Console.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Test, Vm} from "forge-std/Test.sol";
import "forge-std/console.sol";

contract PopVerifyPrecompile {
    function popVerify(bytes memory, bytes memory) public pure returns(bool) {
        return true;
    }
}

contract BlsVerifyPrecompile {
    function blsVerify(bytes memory, bytes memory, bytes memory) public pure returns(bool) {
        return true;
    }
}

abstract contract BaseDelegationTest is Test {
    address payable proxy;
    address oldImplementation;
    bytes initializerCall;
    address payable newImplementation;
    bytes reinitializerCall;
    address owner;
    address[4] stakers = [
        0xd819fFcE7A58b1E835c25617Db7b46a00888B013,
        0x092E5E57955437876dA9Df998C96e2BE19341670,
        0xeA78aAE5Be606D2D152F00760662ac321aB8F017,
        0x6603A37980DF7ef6D44E994B3183A15D0322B7bF
    ];

    constructor() {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        owner = vm.addr(deployerPrivateKey);
        //console.log("Signer is %s", owner);
    }

    function storeDelegation() internal virtual;

    function setUp() public {
        vm.chainId(33469);
        vm.deal(owner, 100_000 ether);
        vm.startPrank(owner);

        proxy = payable(
            new ERC1967Proxy(oldImplementation, initializerCall)
        );
        /*
        console.log(
            "Proxy deployed: %s \r\n  Implementation deployed: %s",
            proxy,
            oldImplementation
        );
        //*/

        BaseDelegation oldDelegation = BaseDelegation(
            proxy
        );
        /*
        console.log("Deployed version: %s",
            oldDelegation.version()
        );

        console.log("Owner is %s",
            oldDelegation.owner()
        );
        //*/

        /*
        console.log("New implementation deployed: %s",
            newImplementation
        );
        //*/

        oldDelegation.upgradeToAndCall(
            newImplementation,
            reinitializerCall
        );

        storeDelegation();
        BaseDelegation delegation = BaseDelegation(
            proxy
        );

        /*
        console.log("Upgraded to version: %s",
            delegation.version()
        );
        //*/
        /*
        Console.log("Old commission rate: %s.%s%s%%",
            delegation.getCommissionNumerator(),
            2
        );
        //*/
        uint256 commissionNumerator = 1_000;
        delegation.setCommissionNumerator(commissionNumerator);
        /*
        Console.log("New commission rate: %s.%s%s%%",
            delegation.getCommissionNumerator(),
            2
        );
        //*/

        InitialStaker[] memory initialStakers = new InitialStaker[](0);
        //vm.deployCodeTo("Deposit.sol", delegation.DEPOSIT_CONTRACT());
        vm.etch(
            delegation.DEPOSIT_CONTRACT(),
            // since the deposit contract is upgradeable, the constructor has no parameters
            //address(new Deposit(10_000_000 ether, 256, 10, initialStakers)).code
            address(new Deposit()).code
        );
        vm.store(delegation.DEPOSIT_CONTRACT(), bytes32(uint256(0x958a6cf6390bd7165e3519675caa670ab90f0161508a9ee714d3db7edc50740b)), bytes32(uint256(block.number / 10)));
        vm.store(delegation.DEPOSIT_CONTRACT(), bytes32(uint256(0x958a6cf6390bd7165e3519675caa670ab90f0161508a9ee714d3db7edc50740c)), bytes32(uint256(10_000_000 ether)));
        vm.store(delegation.DEPOSIT_CONTRACT(), bytes32(uint256(0x958a6cf6390bd7165e3519675caa670ab90f0161508a9ee714d3db7edc50740d)), bytes32(uint256(256)));
        vm.store(delegation.DEPOSIT_CONTRACT(), bytes32(uint256(0x958a6cf6390bd7165e3519675caa670ab90f0161508a9ee714d3db7edc50740e)), bytes32(uint256(10)));
        /* since the deposit contract is upgradeable, the storage locations changed too
        vm.store(delegation.DEPOSIT_CONTRACT(), bytes32(uint256(11)), bytes32(uint256(block.number / 10)));
        vm.store(delegation.DEPOSIT_CONTRACT(), bytes32(uint256(12)), bytes32(uint256(10_000_000 ether)));
        vm.store(delegation.DEPOSIT_CONTRACT(), bytes32(uint256(13)), bytes32(uint256(256)));
        vm.store(delegation.DEPOSIT_CONTRACT(), bytes32(uint256(14)), bytes32(uint256(10)));
        */
        /*
        console.log("Deposit.minimimStake() =", Deposit(delegation.DEPOSIT_CONTRACT()).minimumStake());
        console.log("Deposit.maximumStakers() =", Deposit(delegation.DEPOSIT_CONTRACT()).maximumStakers());
        console.log("Deposit.blocksPerEpoch() =", Deposit(delegation.DEPOSIT_CONTRACT()).blocksPerEpoch());
        //*/

        vm.etch(address(0x5a494c80), address(new PopVerifyPrecompile()).code);
        vm.etch(address(0x5a494c81), address(new BlsVerifyPrecompile()).code);

        vm.stopPrank();
    }

    function deposit(
        BaseDelegation delegation,
        uint256 depositAmount,
        bool initialDeposit
    ) internal {
        if (initialDeposit) {
            vm.deal(owner, owner.balance + depositAmount);
            vm.startPrank(owner);

            delegation.deposit{
                value: depositAmount
            }(
                bytes(hex"92fbe50544dce63cfdcc88301d7412f0edea024c91ae5d6a04c7cd3819edfc1b9d75d9121080af12e00f054d221f876c"),
                bytes(hex"002408011220d5ed74b09dcbe84d3b32a56c01ab721cf82809848b6604535212a219d35c412f"),
                bytes(hex"b14832a866a49ddf8a3104f8ee379d29c136f29aeb8fccec9d7fb17180b99e8ed29bee2ada5ce390cb704bc6fd7f5ce814f914498376c4b8bc14841a57ae22279769ec8614e2673ba7f36edc5a4bf5733aa9d70af626279ee2b2cde939b4bd8a")
            );
        } else {
            vm.deal(stakers[0], stakers[0].balance + depositAmount);
            vm.startPrank(stakers[0]);

            vm.expectEmit(
                true,
                false,
                false,
                false,
                address(delegation)
            );
            emit Delegation.Staked(
                stakers[0],
                depositAmount,
                ""
            );

            delegation.stake{
                value: depositAmount
            }();

            vm.startPrank(owner);

            delegation.deposit2(
                bytes(hex"92fbe50544dce63cfdcc88301d7412f0edea024c91ae5d6a04c7cd3819edfc1b9d75d9121080af12e00f054d221f876c"),
                bytes(hex"002408011220d5ed74b09dcbe84d3b32a56c01ab721cf82809848b6604535212a219d35c412f"),
                bytes(hex"b14832a866a49ddf8a3104f8ee379d29c136f29aeb8fccec9d7fb17180b99e8ed29bee2ada5ce390cb704bc6fd7f5ce814f914498376c4b8bc14841a57ae22279769ec8614e2673ba7f36edc5a4bf5733aa9d70af626279ee2b2cde939b4bd8a")
            );
        }
        // wait 2 epochs for the change to the deposit to take affect
        vm.roll(block.number + Deposit(delegation.DEPOSIT_CONTRACT()).blocksPerEpoch() * 2);
    }
}