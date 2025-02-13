// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity ^0.8.26;

library WithdrawalQueue {

    struct Item {
        uint256 blockNumber;
        uint256 amount;
    }

    struct Fifo {
        uint256 first;
        uint256 last;
        mapping(uint256 => Item) items;
    }

    function enqueue(Fifo storage fifo, uint256 amount, uint256 period) internal {
        fifo.items[fifo.last] = Item(block.number + period, amount);
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

    function notReady(Fifo storage fifo, uint256 index) internal view returns(bool) {
        return index < fifo.last && fifo.items[index].blockNumber > block.number;
    }

    function ready(Fifo storage fifo) internal view returns(bool) {
        return ready(fifo, fifo.first);
    }
}
