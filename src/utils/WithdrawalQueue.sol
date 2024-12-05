// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity ^0.8.26;

library WithdrawalQueue {

    address public constant DEPOSIT_CONTRACT = 0x000000000000000000005a494C4445504F534954;

    struct Item {
        uint256 blockNumber;
        uint256 amount;
    }

    struct Fifo {
        uint256 first;
        uint256 last;
        mapping(uint256 => Item) items;
    }

    function unbondingPeriod() internal view returns(uint256) {
        (bool success, bytes memory data) = DEPOSIT_CONTRACT.staticcall(
            abi.encodeWithSignature("withdrawalPeriod()")
        );
        require(success, "unbonding period unknown");
        return abi.decode(data, (uint256));
    }

    function queue(Fifo storage fifo, uint256 amount) internal {
        fifo.items[fifo.last] = Item(block.number + unbondingPeriod(), amount);
        fifo.last++;
    }

    function dequeue(Fifo storage fifo) internal returns(Item memory result) {
        require(fifo.first < fifo.last, "queue empty");
        result = fifo.items[fifo.first];
        delete fifo.items[fifo.first];
        fifo.first++;
    }

    function ready(Fifo storage fifo, uint256 index) internal view returns(bool) {
        return index < fifo.last && fifo.items[index].blockNumber <= block.number;
    }

    function ready(Fifo storage fifo) internal view returns(bool) {
        return ready(fifo, fifo.first);
    }
}