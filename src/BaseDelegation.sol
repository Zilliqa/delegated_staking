// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity ^0.8.26;

import {IDelegation} from "src/IDelegation.sol";
import {WithdrawalQueue} from "src/WithdrawalQueue.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ERC165Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol";

abstract contract BaseDelegation is IDelegation, PausableUpgradeable, Ownable2StepUpgradeable, UUPSUpgradeable, ERC165Upgradeable {

    using WithdrawalQueue for WithdrawalQueue.Fifo;

    struct Validator {
        bytes blsPubKey;
        uint256 futureStake;
        address rewardAddress;
        address controlAddress;
    }

    /// @custom:storage-location erc7201:zilliqa.storage.BaseDelegation
    struct BaseDelegationStorage {
        bytes deprecatedBlsPubKey;
        bool activated;
        uint256 commissionNumerator;
        mapping(address => WithdrawalQueue.Fifo) withdrawals;
        uint256 totalWithdrawals;
        Validator[] validators;
    }

    // keccak256(abi.encode(uint256(keccak256("zilliqa.storage.BaseDelegation")) - 1)) & ~bytes32(uint256(0xff))
    // solhint-disable const-name-snakecase
    bytes32 private constant BaseDelegationStorageLocation = 0xc8ff0e571ef581b660c1651f85bbac921a40f9489bd04631c07fa723c13c6000;

    function _getBaseDelegationStorage() private pure returns (BaseDelegationStorage storage $) {
        assembly {
            $.slot := BaseDelegationStorageLocation
        }
    }

    uint256 public constant MIN_DELEGATION = 100 ether;
    address public constant DEPOSIT_CONTRACT = WithdrawalQueue.DEPOSIT_CONTRACT;
    uint256 public constant DENOMINATOR = 10_000;

    event ValidatorJoined(bytes blsPubKey);
    event ValidatorLeft(bytes blsPubKey);

    function version() public view returns(uint64) {
        return _getInitializedVersion();
    } 

    // solhint-disable func-name-mixedcase
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

    // this re-initializer is to be called when upgrading from the old V2
    function migrateFromOldV2() public reinitializer(version() + 1) {
        BaseDelegationStorage storage $ = _getBaseDelegationStorage();

        if ($.deprecatedBlsPubKey.length == 0)
            // there is nothing to migrate since no bls pub key is stored
            return;

        $.activated = true;

        (bool success, bytes memory data) = DEPOSIT_CONTRACT.call(abi.encodeWithSignature("getFutureStake(bytes)", $.deprecatedBlsPubKey));
        require(success, "future stake could not be retrieved");
        uint256 futureStake = abi.decode(data, (uint256));

        $.validators.push(Validator(
            $.deprecatedBlsPubKey,
            futureStake,
            owner(),
            owner()
        ));

        $.deprecatedBlsPubKey = "";
    }

    function _authorizeUpgrade(address newImplementation) internal onlyOwner virtual override {}

    function _join(bytes calldata blsPubKey, address controlAddress) internal onlyOwner virtual {
        BaseDelegationStorage storage $ = _getBaseDelegationStorage();
        $.activated = true;

        for (uint256 i = 0; i < $.validators.length; i++)
            require(keccak256($.validators[i].blsPubKey) != keccak256(blsPubKey), "validator with provided bls pub key already added");

        (bool success, bytes memory data) = DEPOSIT_CONTRACT.call(abi.encodeWithSignature("getFutureStake(bytes)", blsPubKey));
        require(success, "future stake could not be retrieved");
        uint256 futureStake = abi.decode(data, (uint256));

        (success, data) = DEPOSIT_CONTRACT.call(abi.encodeWithSignature("getRewardAddress(bytes)", blsPubKey));
        require(success, "reward address could not be retrieved");
        address rewardAddress = abi.decode(data, (address));

        // the control address should have been set to this contract
        // by the original control address otherwise the call will fail
        (success, ) = DEPOSIT_CONTRACT.call(abi.encodeWithSignature("setRewardAddress(bytes,address)", blsPubKey, address(this)));
        require(success, "reward address could not be changed");

        $.validators.push(Validator(
            blsPubKey,
            futureStake,
            rewardAddress,
            controlAddress
        ));
        emit ValidatorJoined(blsPubKey);
    }
    
    function _leave(bytes calldata blsPubKey) internal virtual {
        BaseDelegationStorage storage $ = _getBaseDelegationStorage();
        for (uint256 i = 0; i < $.validators.length; i++)
            if (keccak256($.validators[i].blsPubKey) == keccak256(blsPubKey)) {
                require(_msgSender() == $.validators[i].controlAddress, "only the control address can initiate leaving");
            
                (bool success, ) = DEPOSIT_CONTRACT.call(abi.encodeWithSignature("setRewardAddress(bytes,address)", blsPubKey, $.validators[i].rewardAddress));
                require(success, "reward address could not be changed");

                (success, ) = DEPOSIT_CONTRACT.call(abi.encodeWithSignature("setControlAddress(bytes,address)", blsPubKey, $.validators[i].controlAddress));
                require(success, "control address could not be changed");

                if (i < $.validators.length - 1)
                    $.validators[i] = $.validators[$.validators.length - 1];
                $.validators.pop();

                emit ValidatorLeft(blsPubKey);
                return;
            }
        revert("validator with provided bls key not found");
    }

    function validators() public view returns(Validator[] memory) {
        BaseDelegationStorage storage $ = _getBaseDelegationStorage();
        return $.validators;
    }

    function _deposit(
        bytes calldata blsPubKey,
        bytes calldata peerId,
        bytes calldata signature,
        uint256 depositAmount
    ) internal virtual {
        BaseDelegationStorage storage $ = _getBaseDelegationStorage();
        require(!_isActivated(), "deposit already performed");
        $.activated = true;
        $.validators.push(Validator(
            blsPubKey,
            depositAmount,
            owner(),
            owner()
        ));
        (bool success, ) = DEPOSIT_CONTRACT.call{
            value: depositAmount
        }(
            abi.encodeWithSignature("deposit(bytes,bytes,bytes,address,address)",
                blsPubKey,
                peerId,
                signature,
                address(this),
                owner()
            )
        );
        require(success, "deposit failed");
        emit ValidatorJoined(blsPubKey);
    }

    function join(bytes calldata blsPubKey, address controlAddress) public virtual;

    function leave(bytes calldata blsPubKey) public virtual;

    function deposit(
        bytes calldata blsPubKey,
        bytes calldata peerId,
        bytes calldata signature
    ) public virtual payable;

    function _increaseDeposit(uint256 amount) internal virtual {
        // topup the deposit only if already activated as a validator
        if (_isActivated()) {
            BaseDelegationStorage storage $ = _getBaseDelegationStorage();
//TODO: increase all validators' deposit proportionally, currently we increase only the last validator's deposit
            $.validators[$.validators.length - 1].futureStake += amount;
            //TODO: alternatively, increase the smallest validator's deposit
            (bool success, ) = DEPOSIT_CONTRACT.call{
                value: amount
            }(
                abi.encodeWithSignature("depositTopup(bytes)", 
                    $.validators[$.validators.length - 1].blsPubKey
                )
            );
            require(success, "deposit increase failed");
        }
    }

    function _decreaseDeposit(uint256 amount) internal virtual {
        // unstake the deposit only if already activated as a validator
        if (_isActivated()) {
            BaseDelegationStorage storage $ = _getBaseDelegationStorage();
//TODO: decrease all validators' deposit proportionally, currently we decrease only the last validator's deposit
            //TODO: alternatively, decrease the largest validator's deposit or at least
            //      ensure the no validator's deposit falls below the minimum stake
            $.validators[$.validators.length - 1].futureStake -= amount;
//TODO: if the validator's futureStake becomes zero then force it to leave
            (bool success, ) = DEPOSIT_CONTRACT.call(
                abi.encodeWithSignature("unstake(bytes,uint256)",
                    $.validators[$.validators.length - 1].blsPubKey,
                    amount
                )
            );
            require(success, "deposit decrease failed");
        }
    }

    function _withdrawDeposit() internal virtual {
        // withdraw the unstaked deposit only if already activated as a validator
        if (_isActivated()) {
        BaseDelegationStorage storage $ = _getBaseDelegationStorage();
//TODO: withdraw all validators' unstaked deposits, currently we withdraw only the last validator's unstaked deposit
            (bool success, ) = DEPOSIT_CONTRACT.call(
                abi.encodeWithSignature("withdraw(bytes)",
                    $.validators[$.validators.length - 1].blsPubKey
                )
            );
            require(success, "deposit withdrawal failed");
        }
    }

    // return if the first validator has been deposited already
    // otherwise we are supposed to be in the fundraising phase
    function _isActivated() internal virtual view returns(bool) {
        BaseDelegationStorage storage $ = _getBaseDelegationStorage();
        return $.activated;
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

    function getCommission() public virtual view returns(uint256 numerator, uint256 denominator) {
        BaseDelegationStorage storage $ = _getBaseDelegationStorage();
        numerator = $.commissionNumerator;
        denominator = DENOMINATOR;
    }

    function getMinDelegation() public virtual view returns(uint256) {
        return MIN_DELEGATION;
    }

    function stake() external virtual payable;

    function unstake(uint256) external virtual returns(uint256);

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

    function getPendingClaims() public virtual view returns(uint256[2][] memory claims) {
        BaseDelegationStorage storage $ = _getBaseDelegationStorage();
        WithdrawalQueue.Fifo storage fifo = $.withdrawals[_msgSender()];
        uint256 index = fifo.first;
        while (fifo.ready(index))
            index++;
        uint256 firstPending = index;
        claims = new uint256[2][](fifo.last - index);
        while (fifo.notReady(index)) {
            WithdrawalQueue.Item storage item = fifo.items[index];
            claims[index - firstPending] = [item.blockNumber, item.amount];
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

    function getRewards() public virtual view returns(uint256 total) {
        if (!_isActivated())
            return 0;
        // currently all validators have the same reward address,
        // which is the address of this delegation contract
        total = address(this).balance;
        /* if the validators had separate vault contracts as reward address
        BaseDelegationStorage storage $ = _getBaseDelegationStorage();
        for (uint256 i = 0; i < $.validators.length; i++) {
            (bool success, bytes memory data) = DEPOSIT_CONTRACT.staticcall(
                abi.encodeWithSignature("getRewardAddress(bytes)", $.validators[i].blsPubKey)
            );
            require(success, "could not retrieve reward address");
            address rewardAddress = abi.decode(data, (address));
            //TODO: only if no other validator had the same reward address
            //      to prevent adding its balance multiple times
            total += rewardAddress.balance;
        }
        */
    }

    function getStake() public virtual view returns(uint256 total) {
        if (!_isActivated())
            return address(this).balance;
        BaseDelegationStorage storage $ = _getBaseDelegationStorage();
        for (uint256 i = 0; i < $.validators.length; i++)
            total += $.validators[i].futureStake;
    }

    function getStake(bytes calldata blsPubKey) public virtual view returns(uint256) {
        (bool success, bytes memory data) = DEPOSIT_CONTRACT.staticcall(
            abi.encodeWithSignature("getFutureStake(bytes)", blsPubKey)
        );
        require(success, "could not retrieve staked amount");
        return abi.decode(data, (uint256));
    }

}
