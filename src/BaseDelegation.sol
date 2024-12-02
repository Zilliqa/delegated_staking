// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity ^0.8.26;

import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol";
import "src/Delegation.sol";

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

    function unbondingPeriod() view internal returns(uint256) {
        (bool success, bytes memory data) = DEPOSIT_CONTRACT.staticcall(
            abi.encodeWithSignature("withdrawalPeriod()")
        );
        require(success, "unbonding period unknown");
        return abi.decode(data, (uint256));
    }

    function enqueue(Fifo storage fifo, uint256 amount) internal {
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

abstract contract BaseDelegation is Delegation, PausableUpgradeable, Ownable2StepUpgradeable, UUPSUpgradeable, ERC165Upgradeable {

    using WithdrawalQueue for WithdrawalQueue.Fifo;

    /// @custom:storage-location erc7201:zilliqa.storage.BaseDelegation
    struct BaseDelegationStorage {
        bytes blsPubKey;
        bytes peerId;
        uint256 commissionNumerator;
        mapping(address => WithdrawalQueue.Fifo) withdrawals;
        uint256 totalWithdrawals;
    }

    // keccak256(abi.encode(uint256(keccak256("zilliqa.storage.BaseDelegation")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant BaseDelegationStorageLocation = 0xc8ff0e571ef581b660c1651f85bbac921a40f9489bd04631c07fa723c13c6000;

    function _getBaseDelegationStorage() private pure returns (BaseDelegationStorage storage $) {
        assembly {
            $.slot := BaseDelegationStorageLocation
        }
    }

    uint256 public constant MIN_DELEGATION = 100 ether;
    address public constant DEPOSIT_CONTRACT = 0x000000000000000000005a494C4445504F534954;
    uint256 public constant DENOMINATOR = 10_000;

    function version() public view returns(uint64) {
        return _getInitializedVersion();
    } 

    function __BaseDelegation_init(address initialOwner) internal onlyInitializing {
        __Pausable_init_unchained();
        __Ownable2Step_init_unchained();
        __Ownable_init_unchained(initialOwner);
        __UUPSUpgradeable_init_unchained();
        __ERC165_init_unchained();
        __BaseDelegation_init_unchained();
    }

    function __BaseDelegation_init_unchained() internal onlyInitializing {
    }

    function _authorizeUpgrade(address newImplementation) internal onlyOwner virtual override {}

    function _deposit(
        bytes calldata blsPubKey,
        bytes calldata peerId,
        bytes calldata signature,
        uint256 depositAmount
    ) internal virtual {
        BaseDelegationStorage storage $ = _getBaseDelegationStorage();
        require($.blsPubKey.length == 0, "deposit already performed");
        $.blsPubKey = blsPubKey;
        $.peerId = peerId;
        (bool success, ) = DEPOSIT_CONTRACT.call{
            value: depositAmount
        }(
            abi.encodeWithSignature("deposit(bytes,bytes,bytes,address)",
                blsPubKey,
                peerId,
                signature,
                address(this)
            )
        );
        require(success, "deposit failed");
    }

    function _increaseDeposit(uint256 amount) internal virtual {
        // topup the deposit only if already activated as a validator
        if (_isActivated()) {
            (bool success, ) = DEPOSIT_CONTRACT.call{
                value: amount
            }(
                abi.encodeWithSignature("depositTopup()")
            );
            require(success, "deposit increase failed");
        }
    }

    function _decreaseDeposit(uint256 amount) internal virtual {
        // unstake the deposit only if already activated as a validator
        if (_isActivated()) {
            (bool success, ) = DEPOSIT_CONTRACT.call(
                abi.encodeWithSignature("unstake(uint256)",
                    amount
                )
            );
            require(success, "deposit decrease failed");
        }
    }

    function _withdrawDeposit() internal virtual {
        // withdraw the unstaked deposit only if already activated as a validator
        if (_isActivated()) {
            (bool success, ) = DEPOSIT_CONTRACT.call(
                abi.encodeWithSignature("withdraw()")
            );
            require(success, "deposit withdrawal failed");
        }
    }

    function _isActivated() internal virtual view returns(bool) {
        BaseDelegationStorage storage $ = _getBaseDelegationStorage();
        return $.blsPubKey.length > 0;
    }

    function getCommissionNumerator() public virtual view returns(uint256) {
        BaseDelegationStorage storage $ = _getBaseDelegationStorage();
        return $.commissionNumerator;
    }

    function setCommissionNumerator(uint256 _commissionNumerator) public virtual onlyOwner {
        require(_commissionNumerator < DENOMINATOR, "invalid commission");
        BaseDelegationStorage storage $ = _getBaseDelegationStorage();
        $.commissionNumerator = _commissionNumerator;
    }

    function stake() external virtual payable;

    function unstake(uint256) external virtual;

    function claim() external virtual;

    function collectCommission() public virtual;

    function stakeRewards() public virtual;

    function getClaimable() public virtual view returns(uint256 total) {
        BaseDelegationStorage storage $ = _getBaseDelegationStorage();
        WithdrawalQueue.Fifo storage fifo = $.withdrawals[_msgSender()];
        uint256 index = fifo.first;
        while (fifo.ready(index)) {
            total += fifo.items[index].amount;
            index++;
        }
    }

    function _dequeueWithdrawals() internal virtual returns (uint256 total) {
        BaseDelegationStorage storage $ = _getBaseDelegationStorage();
        while ($.withdrawals[_msgSender()].ready())
            total += $.withdrawals[_msgSender()].dequeue().amount;
        $.totalWithdrawals -= total;
    }

    function _enqueueWithdrawal(uint256 amount) internal virtual {
        BaseDelegationStorage storage $ = _getBaseDelegationStorage();
        $.withdrawals[_msgSender()].enqueue(amount);
        $.totalWithdrawals += amount;
    }

    function getTotalWithdrawals() public virtual view returns(uint256) {
        BaseDelegationStorage storage $ = _getBaseDelegationStorage();
        return $.totalWithdrawals;
    }

    function getRewards() public virtual view returns(uint256) {
        BaseDelegationStorage storage $ = _getBaseDelegationStorage();
        if (!_isActivated())
            return 0;
        (bool success, bytes memory data) = DEPOSIT_CONTRACT.staticcall(
            abi.encodeWithSignature("getRewardAddress(bytes)", $.blsPubKey)
        );
        require(success, "could not retrieve reward address");
        address rewardAddress = abi.decode(data, (address));
        return rewardAddress.balance;
    }

    function getStake() public virtual view returns(uint256) {
        BaseDelegationStorage storage $ = _getBaseDelegationStorage();
        if (!_isActivated())
            return address(this).balance;
        (bool success, bytes memory data) = DEPOSIT_CONTRACT.staticcall(
            abi.encodeWithSignature("getFutureStake(bytes)", $.blsPubKey)
        );
        require(success, "could not retrieve staked amount");
        return abi.decode(data, (uint256));
    }

}
