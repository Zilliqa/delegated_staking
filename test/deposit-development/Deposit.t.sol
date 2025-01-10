// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity ^0.8.26;

import {BaseDelegation} from "src/BaseDelegation.sol";
import {InitialStaker} from "@zilliqa/zq2/deposit_v1.sol";
import {Deposit} from "@zilliqa/zq2/deposit_v5.sol";
import {Console} from "src/Console.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Test, Vm} from "forge-std/Test.sol";
import "forge-std/console.sol";

// Testing contract for deposit_v4 development

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

contract DepositTest is Test {
    address payable proxy;
    address oldImplementation;
    bytes initializerCall;
    address payable newImplementation;
    bytes reinitializerCall;
    address owner1;
    address owner2;
    address[4] stakers = [
        0xd819fFcE7A58b1E835c25617Db7b46a00888B013,
        0x092E5E57955437876dA9Df998C96e2BE19341670,
        0xeA78aAE5Be606D2D152F00760662ac321aB8F017,
        0x6603A37980DF7ef6D44E994B3183A15D0322B7bF
    ];
    bytes blsPubKey1 = bytes(hex"92370645a6ad97d8a4e4b44b8e6db63ab8409473310ac7b21063809450192bace7fb768d60c697a18bbf98b4ddb511f1");
    bytes blsPubKey2 = bytes(hex"92370645a6ad97d8a4e4b44b8e6db63ab8409473310ac7b21063809450192bace7fb768d60c697a18bbf98b4ddb511f2");

    constructor() {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        owner1 = vm.addr(deployerPrivateKey);
        owner2 = vm.addr(uint256(10));
    }

    function test_DepositOnly() public {
        vm.chainId(33469);
        vm.deal(owner1, 40_000_000 ether);
        vm.deal(owner2, 40_000_000 ether);

        vm.deal(stakers[0], 0);
        vm.deal(stakers[1], 0);
        vm.deal(stakers[2], 0);
        vm.startPrank(owner1);

        address deposit_contract_addr = address(new Deposit());
        vm.store(deposit_contract_addr, bytes32(uint256(0x958a6cf6390bd7165e3519675caa670ab90f0161508a9ee714d3db7edc507407)), bytes32(uint256(block.number / 10)));
        // minimimStake
        vm.store(deposit_contract_addr, bytes32(uint256(0x958a6cf6390bd7165e3519675caa670ab90f0161508a9ee714d3db7edc507409)), bytes32(uint256(10 ether)));
        // maximumStakers
        vm.store(deposit_contract_addr, bytes32(uint256(0x958a6cf6390bd7165e3519675caa670ab90f0161508a9ee714d3db7edc50740a)), bytes32(uint256(256)));
        // blocksPerEpoch
        vm.store(deposit_contract_addr, bytes32(uint256(0x958a6cf6390bd7165e3519675caa670ab90f0161508a9ee714d3db7edc50740b)), bytes32(uint256(10)));

        // vm.store(deposit_contract_addr, bytes32(uint256(0x958a6cf6390bd7165e3519675caa670ab90f0161508a9ee714d3db7edc50740b)), bytes32(uint256(block.number / 10)));
        // // minimimStake
        // vm.store(deposit_contract_addr, bytes32(uint256(0x958a6cf6390bd7165e3519675caa670ab90f0161508a9ee714d3db7edc50740d)), bytes32(uint256(10_000_000 ether)));
        // // maximumStakers
        // vm.store(deposit_contract_addr, bytes32(uint256(0x958a6cf6390bd7165e3519675caa670ab90f0161508a9ee714d3db7edc50740e)), bytes32(uint256(256)));
        // // blocksPerEpoch
        // vm.store(deposit_contract_addr, bytes32(uint256(0x958a6cf6390bd7165e3519675caa670ab90f0161508a9ee714d3db7edc50740f)), bytes32(uint256(10)));

        console.log(
            "deposit_contract_addr: %s",
            deposit_contract_addr
        );

        Deposit deposit_contract = Deposit(deposit_contract_addr);
        console.log("Deposit.minimimStake() =", deposit_contract.minimumStake());
        console.log("Deposit.maximumStakers() =", deposit_contract.maximumStakers());
        console.log("Deposit.blocksPerEpoch() =", deposit_contract.blocksPerEpoch());

        vm.etch(address(0x5a494c81), address(new BlsVerifyPrecompile()).code);

        // deposit owner 1
        uint256 depositOwner1Amount = 20 ether;
        console.log("\ndeposit owner1. Amount: ", depositOwner1Amount);
        uint256 gasBefore = gasleft();
        deposit_contract.deposit{
            value: depositOwner1Amount
        }(
            blsPubKey1,
            bytes(hex"002408011220bed0be7a6dfa10c2335148e04927155a726174d6bac61a09ad8e2f72ac697eda"),
            bytes(hex"90ec9a22e030a42d9b519b322d31b8090f796b3f75fc74261b04d0dcc632fd8c5b7a074c5ba61f0845b310fa9931d01c079eebe82813d7021ef4172e01a7d3710a5f9a4634e9a03a51e985836021c356a1eb476a14f558cbae1f4264edca5dac"),
            address(stakers[0]),
            address(stakers[0])
        );
        console.log("Gas used", gasBefore - gasleft());
        vm.stopPrank();

        console.log("\n\nRolling ahead 2 epochs");
        vm.roll(block.number + deposit_contract.blocksPerEpoch() * 2);

        // deposit owner 2
        uint256 depositOwner2Amount = 10 ether;
        console.log("\ndeposit owner2. Amount: ", depositOwner2Amount);
        vm.startPrank(owner2);
        gasBefore = gasleft();
        deposit_contract.deposit{
            value: depositOwner2Amount
        }(
            blsPubKey2,
            bytes(hex"002408011220bed0be7a6dfa10c2335148e04927155a726174d6bac61a09ad8e2f72ac697edb"),
            bytes(hex"90ec9a22e030a42d9b519b322d31b8090f796b3f75fc74261b04d0dcc632fd8c5b7a074c5ba61f0845b310fa9931d01c079eebe82813d7021ef4172e01a7d3710a5f9a4634e9a03a51e985836021c356a1eb476a14f558cbae1f4264edca5dad"),
            address(stakers[1]),
            address(stakers[1])
        );
        console.log("Gas used", gasBefore - gasleft());
        vm.stopPrank();

        getStakeAndFutureStake(deposit_contract, owner1);

        console.log("\n\nRolling ahead 2 epochs");
        vm.roll(block.number + deposit_contract.blocksPerEpoch() * 2);

        getStakeAndFutureStake(deposit_contract, owner1);


        // Topup
        depositTopUp(deposit_contract, 1, 1 ether);
        depositTopUp(deposit_contract, 2, 2 ether);

        getStakeAndFutureStake(deposit_contract, owner1);

        console.log("\n\nRolling ahead 2 epochs");
        vm.roll(block.number + deposit_contract.blocksPerEpoch() * 2);

        getStakeAndFutureStake(deposit_contract, owner1);

        depositTopUp(deposit_contract, 1, 1 ether);
        depositTopUp(deposit_contract, 2, 2 ether);
        console.log("depositTopUp()s above payed for fold");

        depositTopUp(deposit_contract, 1, 1 ether);
        depositTopUp(deposit_contract, 2, 2 ether);
        console.log("depositTopUp()s above do not pay for fold because in same epoch as previous topups");

        getStakeAndFutureStake(deposit_contract, owner1);
        
        // Unstake
        uint unstakeOwner1Amount = 4 ether;
        console.log("\nUnstake owner1. Amount: ", unstakeOwner1Amount);
        vm.startPrank(owner1);
        gasBefore = gasleft();
        deposit_contract.unstake(blsPubKey1, unstakeOwner1Amount);
        console.log("Gas used", gasBefore - gasleft());
        vm.stopPrank();

        getStakeAndFutureStake(deposit_contract, owner1);

        console.log("\n\nRolling ahead 2 epochs");
        vm.roll(block.number + deposit_contract.blocksPerEpoch() * 2);

        getStakeAndFutureStake(deposit_contract, owner1);

        // Withdraw
        console.log("\n\nRolling ahead withdrawal period. onwer1 balance before: ", owner1.balance);
        vm.roll(block.number + deposit_contract.withdrawalPeriod());

        console.log("\nowner1 Withdraw");
        vm.startPrank(owner1);
        gasBefore = gasleft();
        deposit_contract.withdraw(blsPubKey1);
        console.log("Gas used", gasBefore - gasleft());
        vm.stopPrank();

        console.log("owner1 balance: ", owner1.balance);
        getStakeAndFutureStake(deposit_contract, owner1);
    }

    function getStakeAndFutureStake(Deposit deposit_contract, address owner) public {
        console.log("\ngetStake");
        vm.startPrank(owner);
        uint256 gasBefore = gasleft();
        console.log("key1: %s   Gas used: %s", deposit_contract.getStake(blsPubKey1), gasBefore - gasleft());
        gasBefore = gasleft();
        console.log("key2: %s   Gas used: %s", deposit_contract.getStake(blsPubKey2), gasBefore - gasleft());
        gasBefore = gasleft();
        console.log("total: %s   Gas used: %s", deposit_contract.getTotalStake(), gasBefore - gasleft());


        console.log("\ngetFutureStake");
        gasBefore = gasleft();
        console.log("key1: %s   Gas used: %s", deposit_contract.getFutureStake(blsPubKey1), gasBefore - gasleft());
        gasBefore = gasleft();
        console.log("key2: %s   Gas used: %s", deposit_contract.getFutureStake(blsPubKey2), gasBefore - gasleft());
        gasBefore = gasleft();
        console.log("total: %s   Gas used: %s", deposit_contract.getFutureTotalStake(), gasBefore - gasleft());

        vm.stopPrank();
    }

    function depositTopUp(Deposit deposit_contract, uint ownerInt, uint amount) public {
        address owner;
        bytes memory blsPubKey;
        if (ownerInt == 1) {
            owner = owner1;
            blsPubKey = blsPubKey1;
        } else {
            owner = owner2;
            blsPubKey = blsPubKey2;
        }
        vm.startPrank(owner);
        uint256 gasBefore = gasleft();
        deposit_contract.depositTopup{
            value: amount
        }(blsPubKey);
        console.log("\ndepositTopUp owner%s. Amount: %s Gas used: %s", ownerInt, amount, gasBefore - gasleft());
        vm.stopPrank();
    }
}