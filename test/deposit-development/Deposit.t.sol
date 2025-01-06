// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity ^0.8.26;

import {BaseDelegation} from "src/BaseDelegation.sol";
import {InitialStaker} from "@zilliqa/zq2/deposit_v1.sol";
import {Deposit} from "./deposit_v4.sol";
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
    }

    function test_DepositOnly() public {
        vm.chainId(33469);
        vm.deal(owner, 40_000_000 ether);

        address owner2 = vm.addr(uint256(10));
        vm.deal(owner2, 40_000_000 ether);

        vm.deal(stakers[0], 0);
        vm.deal(stakers[1], 0);
        vm.deal(stakers[2], 0);
        vm.startPrank(owner);

        address deposit_contract_addr = address(new Deposit());
        vm.store(deposit_contract_addr, bytes32(uint256(0x958a6cf6390bd7165e3519675caa670ab90f0161508a9ee714d3db7edc50740b)), bytes32(uint256(block.number / 10)));
        vm.store(deposit_contract_addr, bytes32(uint256(0x958a6cf6390bd7165e3519675caa670ab90f0161508a9ee714d3db7edc50740c)), bytes32(uint256(10_000_000 ether)));
        vm.store(deposit_contract_addr, bytes32(uint256(0x958a6cf6390bd7165e3519675caa670ab90f0161508a9ee714d3db7edc50740d)), bytes32(uint256(256)));
        vm.store(deposit_contract_addr, bytes32(uint256(0x958a6cf6390bd7165e3519675caa670ab90f0161508a9ee714d3db7edc50740e)), bytes32(uint256(10)));

        console.log(
            "deposit_contract_addr: %s",
            deposit_contract_addr
        );

        Deposit deposit_contract = Deposit(deposit_contract_addr);
        vm.etch(address(0x5a494c81), address(new BlsVerifyPrecompile()).code);

        // deposit owner 1
        bytes memory bls_pub_key_1 = bytes(hex"92370645a6ad97d8a4e4b44b8e6db63ab8409473310ac7b21063809450192bace7fb768d60c697a18bbf98b4ddb511f2");
        bytes memory peer_id_1 = bytes(hex"002408011220bed0be7a6dfa10c2335148e04927155a726174d6bac61a09ad8e2f72ac697eda");
        bytes memory signature_1 = bytes(hex"90ec9a22e030a42d9b519b322d31b8090f796b3f75fc74261b04d0dcc632fd8c5b7a074c5ba61f0845b310fa9931d01c079eebe82813d7021ef4172e01a7d3710a5f9a4634e9a03a51e985836021c356a1eb476a14f558cbae1f4264edca5dac");
        uint256 gasBefore = gasleft();
        deposit_contract.deposit{
            value: 10_000_000 ether
        }(
            bls_pub_key_1,
            peer_id_1,
            signature_1,
            address(stakers[0]),
            address(stakers[0])
        );
        console.log("deposit owner 1: Gas used", gasBefore - gasleft());
        vm.stopPrank();
        vm.roll(block.number + deposit_contract.blocksPerEpoch() * 2);

        
        // deposit owner 2
        bytes memory bls_pub_key_2 = bytes(hex"92370645a6ad97d8a4e4b44b8e6db63ab8409473310ac7b21063809450192bace7fb768d60c697a18bbf98b4ddb511f3");
        bytes memory peer_id_2 = bytes(hex"002408011220bed0be7a6dfa10c2335148e04927155a726174d6bac61a09ad8e2f72ac697edb");
        bytes memory signature_2 = bytes(hex"90ec9a22e030a42d9b519b322d31b8090f796b3f75fc74261b04d0dcc632fd8c5b7a074c5ba61f0845b310fa9931d01c079eebe82813d7021ef4172e01a7d3710a5f9a4634e9a03a51e985836021c356a1eb476a14f558cbae1f4264edca5dad");
        vm.startPrank(owner2);
        gasBefore = gasleft();
        deposit_contract.deposit{
            value: 10_000_000 ether
        }(
            bls_pub_key_2,
            peer_id_2,
            signature_2,
            address(stakers[1]),
            address(stakers[1])
        );
        uint256 gasAfter = gasleft();
        uint256 gasUsed = gasBefore - gasAfter;
        console.log("deposit owner 2: Gas used", gasUsed);
        vm.stopPrank();
        vm.roll(block.number + deposit_contract.blocksPerEpoch() * 2);

        console.log("\n1st top up owner 1");
        vm.startPrank(owner);
        gasBefore = gasleft();
        deposit_contract.depositTopup{
            value: 100_000 ether
        }();
        gasAfter = gasleft();
        gasUsed = gasBefore - gasAfter;
        console.log("1st top up owner 1: Gas used", gasUsed);
        vm.stopPrank();

        console.log("\n1st top up owner 2");
        vm.startPrank(owner2);
        gasBefore = gasleft();
        deposit_contract.depositTopup{
            value: 100_000 ether
        }();
        gasAfter = gasleft();
        gasUsed = gasBefore - gasAfter;
        console.log("1st top up owner 2: Gas used", gasUsed);
        vm.stopPrank();

        console.log("\n\nRolling ahead a 1 epoch");
        vm.roll(block.number + deposit_contract.blocksPerEpoch() * 1);

        console.log("\n2nd top up owner 1");
        vm.startPrank(owner);
        gasBefore = gasleft();
        deposit_contract.depositTopup{
            value: 100_000 ether
        }();
        gasAfter = gasleft();
        gasUsed = gasBefore - gasAfter;
        console.log("2nd top up owner 1: Gas used", gasUsed);
        vm.stopPrank();

        console.log("\n2nd top up owner 2");
        vm.startPrank(owner2);
        gasBefore = gasleft();
        deposit_contract.depositTopup{
            value: 100_000 ether
        }();
        gasAfter = gasleft();
        gasUsed = gasBefore - gasAfter;
        console.log("2nd top up owner 2: Gas used", gasUsed);
        vm.stopPrank();

        console.log("\n\nRolling ahead a 2 epochs");
        vm.roll(block.number + deposit_contract.blocksPerEpoch() * 2);

        console.log("\n3rd top up owner 1");
        vm.startPrank(owner);
        gasBefore = gasleft();
        deposit_contract.depositTopup{
            value: 100_000 ether
        }();
        gasAfter = gasleft();
        gasUsed = gasBefore - gasAfter;
        console.log("3rd top up owner 1: Gas used", gasUsed);
        vm.stopPrank();

        console.log("\n3rd top up owner 2");
        vm.startPrank(owner2);
        gasBefore = gasleft();
        deposit_contract.depositTopup{
            value: 100_000 ether
        }();
        gasAfter = gasleft();
        gasUsed = gasBefore - gasAfter;
        console.log("3rd top up owner 2: Gas used", gasUsed);
        vm.stopPrank();
    }
}