// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity ^0.8.26;

import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "src/NonRebasingLST.sol";

library WithdrawalQueue {

    //TODO: add it to the variables and implement a getter and an onlyOwner setter
    //      since a governance vote can change the unbonding period anytime or fetch
    //      it from the deposit contract
    uint256 public constant UNBONDING_PERIOD = 30; //approx. 30s, used only for testing

    struct Item {
        uint256 blockNumber;
        uint256 amount;
    }

    struct Fifo {
        uint256 first;
        uint256 last;
        mapping(uint256 => Item) items;
    }

    function queue(Fifo storage fifo, uint256 amount) internal {
        fifo.items[fifo.last] = Item(block.number + UNBONDING_PERIOD, amount);
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

// the contract is supposed to be deployed with the node's signer account
abstract contract BaseDelegation is Initializable, PausableUpgradeable, Ownable2StepUpgradeable, UUPSUpgradeable {

    using WithdrawalQueue for WithdrawalQueue.Fifo;

    /// @custom:storage-location erc7201:zilliqa.storage.BaseDelegation
    struct BaseStorage {
        bytes blsPubKey;
        bytes peerId;
        uint256 commissionNumerator;
        mapping(address => WithdrawalQueue.Fifo) withdrawals;
        uint256 totalWithdrawals;
    }

    // keccak256(abi.encode(uint256(keccak256("zilliqa.storage.BaseDelegation")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant BaseStorageLocation = 0xc8ff0e571ef581b660c1651f85bbac921a40f9489bd04631c07fa723c13c6000;

    function _getBaseStorage() private pure returns (BaseStorage storage $) {
        assembly {
            $.slot := BaseStorageLocation
        }
    }

    uint256 public constant MIN_DELEGATION = 100 ether;
    address public constant DEPOSIT_CONTRACT = 0x000000000000000000005a494C4445504F534954;
    uint256 public constant DENOMINATOR = 10_000;

    //TODO: check
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function version() public view returns(uint64) {
        return _getInitializedVersion();
    } 

    //TODO: check
    function initialize(address initialOwner) initializer public {
        __Pausable_init();
        __Ownable_init(initialOwner);
        __Ownable2Step_init();
        __UUPSUpgradeable_init();
    }

    //TODO: check
    function __BaseStorage_init() internal onlyInitializing {
        __BaseStorage_init_unchained();
    }

    //TODO: check
    function __BaseStorage_init_unchained() internal onlyInitializing {
    }

    //TODO: check
    function _authorizeUpgrade(address newImplementation) internal onlyOwner override {}
    
    }
