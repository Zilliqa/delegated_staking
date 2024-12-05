// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity ^0.8.26;

/// Interal WithdrawalQueue error
error WithdrawalQueueError(string msg);

/// Queue implementation for withdrawals from staking contract awaiting an unbonding period
library WithdrawalQueue {

    address public constant DEPOSIT_CONTRACT = address(0x5A494C4445504F53495450524F5859);

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
        require(success, WithdrawalQueueError("unbonding period unknown"));
        return abi.decode(data, (uint256));
    }

    function enqueue(Fifo storage fifo, uint256 amount) internal {
        fifo.items[fifo.last] = Item(block.number + unbondingPeriod(), amount);
        fifo.last++;
    }

    function dequeue(Fifo storage fifo) internal returns(Item memory result) {
        require(fifo.first < fifo.last, WithdrawalQueueError("queue empty"));
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