// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity ^0.8.26;

/**
 * @notice Queue of pending withdrawals. Unstaked amounts are enqueued for withdrawal
 * after the unbonding period. When users claim their available unstaked funds, the
 * corresponding {Item}s are dequeued.
 */
library WithdrawalQueue {

    /**
    * @dev Each item in the queue consists of the `blockNumber` when the unbonding
    * period ends and the `amount` that can be withdrawn afterwards.
    */
    struct Item {
        uint256 blockNumber;
        uint256 amount;
    }

    /**
    * @dev The first in, first out data structure keeps track of the indices of
    * the `first` and the `last` item. `items` maps each {Item} to its respective
    * index i.e. position in the queue.
    */
    struct Fifo {
        uint256 first;
        uint256 last;
        mapping(uint256 => Item) items;
    }

    /**
    * @dev Thrown if the operation requires a non-empty queue.
    */
    error EmptyQueue();

    /**
    * @dev Add a new {Item} to the back of the queue.
    */
    function enqueue(Fifo storage fifo, uint256 amount, uint256 period) internal {
        fifo.items[fifo.last] = Item(block.number + period, amount);
        fifo.last++;
    }

    /**
    * @dev Remove an {Item} from the front of the queue and returns it.
    */
    function dequeue(Fifo storage fifo) internal returns(Item memory result) {
        require(fifo.first < fifo.last, EmptyQueue());
        result = fifo.items[fifo.first];
        delete fifo.items[fifo.first];
        fifo.first++;
    }

    /**
    * @dev Return whether an {Item} at `index` has already been enqueued and is now
    * ready to be dequeued i.e. its unbonding period is over.
    */
    function ready(Fifo storage fifo, uint256 index) internal view returns(bool) {
        return index < fifo.last && fifo.items[index].blockNumber <= block.number;
    }

    /**
    * @dev Return whether an {Item} at `index` has already been enqueued but is not
    * yet ready to be dequeued i.e. its unbonding period is not over.
    */
    function notReady(Fifo storage fifo, uint256 index) internal view returns(bool) {
        return index < fifo.last && fifo.items[index].blockNumber > block.number;
    }

    /**
    * @dev Return whether the first {Item} is ready to be dequeued i.e. its unbonding
    * period is over.
    */
    function ready(Fifo storage fifo) internal view returns(bool) {
        return ready(fifo, fifo.first);
    }
}
