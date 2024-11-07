// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity ^0.8.26;

import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol";
import "src/Delegation.sol";

library WithdrawalQueue {

    //TODO: value set for testing purposes, make it equal to 2 * 7 * 24 * 60 * 60
    // if governance changes the unbonding period, update the value and upgrade the contract
    uint256 public constant UNBONDING_PERIOD = 30;

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

abstract contract BaseDelegation is Delegation, Initializable, PausableUpgradeable, Ownable2StepUpgradeable, UUPSUpgradeable, ERC165Upgradeable {

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

    //TODO: check - does it make sense in an abstract contract?
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function version() public view returns(uint64) {
        return _getInitializedVersion();
    } 

    /*TODO: check - will it ever be called since the contract is abstract?
    function initialize(address initialOwner) initializer public {
        __Pausable_init();
        __Ownable_init(initialOwner);
        __Ownable2Step_init();
        __UUPSUpgradeable_init();
    }*/

    //TODO: check - call the _init() functions of all base contracts
    //      or leave it to the initializer of the inheriting contracts=
    function __BaseDelegation_init() internal onlyInitializing {
        //__Pausable_init();
        //__Ownable_init(initialOwner);
        //__Ownable2Step_init();
        //__UUPSUpgradeable_init();
        __BaseDelegation_init_unchained();
    }

    //TODO: check - call the _init_unchained() functions of all base contracts?
    function __BaseDelegation_init_unchained() internal onlyInitializing {
        //__Pausable_init_unchained();
        //__Ownable_init_unchained(initialOwner);
        //__Ownable2Step_init_unchained();
        //__UUPSUpgradeable_init_unchained();
    }

    function _authorizeUpgrade(address newImplementation) internal onlyOwner virtual override {}

    function _deposit(
        bytes calldata blsPubKey,
        bytes calldata peerId,
        bytes calldata signature,
        uint256 depositAmount
    ) internal {
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

    function _increaseDeposit(uint256 amount) internal {
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

    function _decreaseDeposit(uint256 amount) internal {
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

    function _withdrawDeposit() internal {
        // withdraw the unstaked deposit only if already activated as a validator
        if (_isActivated()) {
            (bool success, ) = DEPOSIT_CONTRACT.call(
                abi.encodeWithSignature("withdraw()")
            );
            require(success, "deposit withdrawal failed");
        }
    }

    function _isActivated() internal view returns(bool) {
        BaseDelegationStorage storage $ = _getBaseDelegationStorage();
        return $.blsPubKey.length > 0;
    }

    function getCommissionNumerator() public view returns(uint256) {
        BaseDelegationStorage storage $ = _getBaseDelegationStorage();
        return $.commissionNumerator;
    }

    function setCommissionNumerator(uint256 _commissionNumerator) public onlyOwner {
        require(_commissionNumerator < DENOMINATOR, "invalid commission");
        BaseDelegationStorage storage $ = _getBaseDelegationStorage();
        $.commissionNumerator = _commissionNumerator;
    }

    function collectCommission() public virtual;

    function getClaimable() public view returns(uint256 total) {
        BaseDelegationStorage storage $ = _getBaseDelegationStorage();
        WithdrawalQueue.Fifo storage fifo = $.withdrawals[msg.sender];
        uint256 index = fifo.first;
        while (fifo.ready(index)) {
            total += fifo.items[index].amount;
            index++;
        }
    }

    function _dequeueWithdrawals() internal returns (uint256 total) {
        BaseDelegationStorage storage $ = _getBaseDelegationStorage();
        while ($.withdrawals[msg.sender].ready())
            total += $.withdrawals[msg.sender].dequeue().amount;
        $.totalWithdrawals -= total;
    }

    function _enqueueWithdrawal(uint256 amount) internal {
        BaseDelegationStorage storage $ = _getBaseDelegationStorage();
        $.withdrawals[msg.sender].queue(amount);
        $.totalWithdrawals += amount;
    }

    function getTotalWithdrawals() public view returns(uint256) {
        BaseDelegationStorage storage $ = _getBaseDelegationStorage();
        return $.totalWithdrawals;
    }

    function getRewards() public view returns(uint256) {
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

    function getStake() public view returns(uint256) {
        BaseDelegationStorage storage $ = _getBaseDelegationStorage();
        if (!_isActivated())
            return address(this).balance;
        (bool success, bytes memory data) = DEPOSIT_CONTRACT.staticcall(
            abi.encodeWithSignature("getStake(bytes)", $.blsPubKey)
        );
        require(success, "could not retrieve staked amount");
        return abi.decode(data, (uint256));
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
       return interfaceId == type(BaseDelegation).interfaceId || super.supportsInterface(interfaceId);
    }

}
