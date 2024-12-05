// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity ^0.8.26;

import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ERC165Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol";

import {WithdrawalQueue} from "./utils/WithdrawalQueue.sol";
import {Delegation} from "./Delegation.sol";

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
    bytes32 private constant BASE_DELEGATION_STORAGE_LOCATION = 0xc8ff0e571ef581b660c1651f85bbac921a40f9489bd04631c07fa723c13c6000;

    function _getBaseDelegationStorage() private pure returns (BaseDelegationStorage storage $) {
        assembly {
            $.slot := BASE_DELEGATION_STORAGE_LOCATION
        }
    }

    uint256 public constant MIN_DELEGATION = 100 ether;
    address public constant DEPOSIT_CONTRACT = WithdrawalQueue.DEPOSIT_CONTRACT;
    uint256 public constant DENOMINATOR = 10_000;

    function version() public view returns(uint64) {
        return _getInitializedVersion();
    } 

    function __baseDelegationInit(address initialOwner) internal onlyInitializing {
        __Pausable_init_unchained();
        __Ownable2Step_init_unchained();
        __Ownable_init_unchained(initialOwner);
        __UUPSUpgradeable_init_unchained();
        __ERC165_init_unchained();
    }

    // solhint-disable-next-line no-empty-blocks
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

    function deposit(
        bytes calldata blsPubKey,
        bytes calldata peerId,
        bytes calldata signature
    ) public virtual payable;

    function deposit2(
        bytes calldata blsPubKey,
        bytes calldata peerId,
        bytes calldata signature
    ) public virtual;

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
