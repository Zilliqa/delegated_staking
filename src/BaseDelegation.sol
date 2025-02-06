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

    enum ValidatorStatus {Active, PreparingToLeave, WaitingToLeave, ReadyToLeave}

    struct Validator {
        bytes blsPubKey;
        uint256 futureStake;
        address rewardAddress;
        address controlAddress;
        uint256 pendingWithdrawals;
        ValidatorStatus status;
    }

    /// @custom:storage-location erc7201:zilliqa.storage.BaseDelegation
    struct BaseDelegationStorage {
        // the actual position in the validators array is the validatorIndex - 1 
        mapping(bytes => uint256) validatorIndex;
        bool activated;
        uint256 commissionNumerator;
        mapping(address => WithdrawalQueue.Fifo) withdrawals;
        uint256 totalWithdrawals;
        Validator[] validators;
        address commissionReceiver;
    }

    // keccak256(abi.encode(uint256(keccak256("zilliqa.storage.BaseDelegation")) - 1)) & ~bytes32(uint256(0xff))
    // solhint-disable const-name-snakecase
    bytes32 private constant BaseDelegationStorageLocation = 0xc8ff0e571ef581b660c1651f85bbac921a40f9489bd04631c07fa723c13c6000;

    function _getBaseDelegationStorage() private pure returns (BaseDelegationStorage storage $) {
        assembly {
            $.slot := BaseDelegationStorageLocation
        }
    }

    uint256 public constant MIN_DELEGATION = 10 ether;
    address public constant DEPOSIT_CONTRACT = WithdrawalQueue.DEPOSIT_CONTRACT;
    uint256 public constant DENOMINATOR = 10_000;

    event ValidatorJoined(bytes indexed blsPubKey);
    event ValidatorLeft(bytes indexed blsPubKey);
    event ValidatorLeaving(bytes indexed blsPubKey, bool success);

    // use semver instead of simple incremental version numbers
    // contract file names remain the same across all versions
    // so that the upgrade script does not need to be modified
    // to import the new version each time there is one
    uint64 internal immutable VERSION = encodeVersion(0, 3, 3);

    function version() public view returns(uint64) {
        return _getInitializedVersion();
    } 

    function decodedVersion() public view returns(uint24, uint24, uint24) {
        return decodeVersion(_getInitializedVersion());
    } 

    function encodeVersion(uint24 major, uint24 minor, uint24 patch) pure public returns(uint64) {
        require(major < 2**20, "incorrect major version");
        require(minor < 2**20, "incorrect minor version");
        require(patch < 2**20, "incorrect patch version");
        return uint64(major * 2**40 + minor * 2**20 + patch);
    }

    function decodeVersion(uint64 v) pure public returns(uint24 major, uint24 minor, uint24 patch) {
        patch = uint24(v & (2**20 - 1));
        minor = uint24((v >> 20) & (2**20 - 1)); 
        major = uint24((v >> 40) & (2**20 - 1)); 
    }

    // solhint-disable func-name-mixedcase
    function __BaseDelegation_init(address initialOwner) internal onlyInitializing {
        __Pausable_init_unchained();
        __Ownable2Step_init_unchained();
        __Ownable_init_unchained(initialOwner);
        __UUPSUpgradeable_init_unchained();
        __ERC165_init_unchained();
        __BaseDelegation_init_unchained(initialOwner);
    }

    function __BaseDelegation_init_unchained(address initialOwner) internal onlyInitializing {
        BaseDelegationStorage storage $ = _getBaseDelegationStorage();
        $.commissionReceiver = initialOwner;
    }

    struct DeprecatedStorage {
        bytes blsPubKey;
        bytes peerId;
    }

    function migrate(uint64 fromVersion) internal {

        // the contract has been deployed but not upgraded yet
        if (fromVersion == 1)
            return;

        // the contract has been upgraded to a version which
        // is higher or same as the current version
        if (fromVersion >= VERSION)
            return;

        BaseDelegationStorage storage $ = _getBaseDelegationStorage();

        if (fromVersion < encodeVersion(0, 3, 0))
            // the contract has been upgraded to a version which did not
            // set the commission receiver or allow the owner to change it
            $.commissionReceiver = owner();

        if (fromVersion >= encodeVersion(0, 2, 0))
            // the contract has been upgraded to a version which has
            // already migrated the blsPubKey to the validators array
            return;

        // the contract has been upgraded from the initial version but the length
        // of the peerId stored in the same slot as the activated bool is zero
        if (!$.activated)
            return;

        DeprecatedStorage storage temp;
        uint256 peerIdLength;
        assembly {
            temp.slot := BaseDelegationStorageLocation
            peerIdLength := sload(add(BaseDelegationStorageLocation, 1))
        }

        // if the upgraded contract hadn't been migrated yet then the peerIdLength stored
        // in the same slot as activated would be larger, but it was overwritten with true
        if (peerIdLength == 1)
            return;

        (bool success, bytes memory data) = DEPOSIT_CONTRACT.call(abi.encodeWithSignature("getFutureStake(bytes)", temp.blsPubKey));
        require(success, "future stake could not be retrieved");
        uint256 futureStake = abi.decode(data, (uint256));

        // validators migrated from version < 0.2.0 use the contract owner
        // as their original reward address and control address, i.e. after
        // leaving the staking pool the contract owner must set the actual
        // control address, which can then set the actual reward address 
        $.validators.push(Validator(
            temp.blsPubKey,
            futureStake,
            owner(),
            owner(),
            0,
            ValidatorStatus.Active
        ));

        $.validatorIndex[temp.blsPubKey] = $.validators.length;

        // it overwrites the peerId length with 1 and prevents repeating the whole migration again
        $.activated = true;

        // remove the blsPubKey stored in the same slot at the validatorIndex of 0x before the migration 
        delete $.validatorIndex[""];
    }

    function _authorizeUpgrade(address newImplementation) internal onlyOwner virtual override {}

    function _join(bytes calldata blsPubKey, address controlAddress) internal onlyOwner virtual {
        BaseDelegationStorage storage $ = _getBaseDelegationStorage();
        $.activated = true;

        require($.validatorIndex[blsPubKey] == 0, "validator with provided bls pub key already added");

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
            controlAddress,
            0,
            ValidatorStatus.Active
        ));
        $.validatorIndex[blsPubKey] = $.validators.length;
        emit ValidatorJoined(blsPubKey);
    }

    function completeLeaving(bytes calldata blsPubKey) public virtual {
        BaseDelegationStorage storage $ = _getBaseDelegationStorage();
        uint256 i = $.validatorIndex[blsPubKey];
        require(i-- > 0, "validator with provided bls key not found");
        require(_msgSender() == $.validators[i].controlAddress, "only the control address can complete leaving");                
        require($.validators[i].status >= ValidatorStatus.WaitingToLeave, "the control address has not initiated leaving yet");
        if ($.validators[i].status == ValidatorStatus.WaitingToLeave) {
            // currently all validators have the same reward address, which is the address of this delegation contract
            uint256 amount = address(this).balance;
            (bool success, ) = DEPOSIT_CONTRACT.call(
                abi.encodeWithSignature("withdraw(bytes)",
                    $.validators[i].blsPubKey
                )
            );
            require(success, "deposit withdrawal failed");
            amount = address(this).balance - amount;
            if (amount > 0) {
                _increaseDeposit(amount);
                $.validators[i].status = ValidatorStatus.ReadyToLeave;
            }
        }
        if ($.validators[i].status == ValidatorStatus.ReadyToLeave) {
            (bool success, ) = DEPOSIT_CONTRACT.call(abi.encodeWithSignature("setRewardAddress(bytes,address)", $.validators[i].blsPubKey, $.validators[i].rewardAddress));
            require(success, "reward address could not be changed");

            (success, ) = DEPOSIT_CONTRACT.call(abi.encodeWithSignature("setControlAddress(bytes,address)", $.validators[i].blsPubKey, $.validators[i].controlAddress));
            require(success, "control address could not be changed");

            emit ValidatorLeft($.validators[i].blsPubKey);

            delete $.validatorIndex[$.validators[i].blsPubKey];
            if (i < $.validators.length - 1) {
                $.validators[i] = $.validators[$.validators.length - 1];
                $.validatorIndex[$.validators[i].blsPubKey] = i + 1;
            }
            $.validators.pop();
        }
    }

    function _preparedToLeave(bytes calldata blsPubKey) internal virtual returns(bool prepared) {
        BaseDelegationStorage storage $ = _getBaseDelegationStorage();
        uint256 i = $.validatorIndex[blsPubKey];
        require(i-- > 0, "validator with provided bls key not found");
        prepared = $.validators[i].pendingWithdrawals == 0;
        $.validators[i].status = ValidatorStatus.PreparingToLeave;
        emit ValidatorLeaving(blsPubKey, prepared);
    }

    function _initiateLeaving(bytes calldata blsPubKey, uint256 leavingStake) internal virtual {
        BaseDelegationStorage storage $ = _getBaseDelegationStorage();
        uint256 i = $.validatorIndex[blsPubKey];
        require(i-- > 0, "validator with provided bls key not found");
        require(_msgSender() == $.validators[i].controlAddress, "only the control address can initiate leaving");                
        require($.validators[i].status == ValidatorStatus.PreparingToLeave, "validator is not prepared to leave");
        require($.validators[i].pendingWithdrawals == 0, "there must not be pending withdrawals");
        if ($.validators[i].futureStake > leavingStake) {
            $.validators[i].status = ValidatorStatus.WaitingToLeave;
            (bool success, ) = DEPOSIT_CONTRACT.call(
                abi.encodeWithSignature("unstake(bytes,uint256)",
                    $.validators[i].blsPubKey,
                    $.validators[i].futureStake - leavingStake
                )
            );
            require(success, "deposit decrease failed");
            $.validators[i].futureStake = leavingStake;
        } else {
            $.validators[i].status = ValidatorStatus.ReadyToLeave;
            completeLeaving(blsPubKey);
        }
    }

    function pendingWithdrawals(bytes calldata blsPubKey) public virtual view returns(bool) {
        BaseDelegationStorage storage $ = _getBaseDelegationStorage();
        uint256 i = $.validatorIndex[blsPubKey];
        require(i-- > 0, "validator with provided bls key not found");                
        return $.validators[i].pendingWithdrawals > 0;
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
            owner(),
            0,
            ValidatorStatus.Active
        ));

        $.validatorIndex[blsPubKey] = $.validators.length;

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

    // topup the deposits proportionally to the validators' current deposit
    function _increaseDeposit(uint256 amount) internal virtual {
        // topup the deposit only if already activated as a validator
        if (_isActivated()) {
            BaseDelegationStorage storage $ = _getBaseDelegationStorage();
            uint256[] memory contribution = new uint256[]($.validators.length);
            uint256 total;
            for (uint256 i = 0; i < $.validators.length; i++) {
                contribution[i] = $.validators[i].futureStake;
                total += contribution[i];
            }
            require(total > 0, "no validators in the staking pool");
            for (uint256 i = 0; i < $.validators.length; i++)
                if (contribution[i] > 0) {
                    uint256 value = amount * contribution[i] / total;
                    $.validators[i].futureStake += value;
                    (bool success, ) = DEPOSIT_CONTRACT.call{
                        value: value
                    }(
                        abi.encodeWithSignature("depositTopup(bytes)", 
                            $.validators[i].blsPubKey
                        )
                    );
                    require(success, "deposit increase failed");
                }
        }
    }

    // unstake from the deposits proportionally to the validators' surplus exceeding the required minimum deposit
    function _decreaseDeposit(uint256 amount) internal virtual {
        // unstake the deposit only if already activated as a validator
        if (_isActivated()) {
            (bool success, bytes memory data) = DEPOSIT_CONTRACT.call(
                abi.encodeWithSignature("minimumStake()")
            );
            require(success, "minimum deposit unknown");
            uint256 minimumDeposit = abi.decode(data, (uint256));
            BaseDelegationStorage storage $ = _getBaseDelegationStorage();
            uint256[] memory contribution = new uint256[]($.validators.length);
            uint256 total;
            for (uint256 i = 0; i < $.validators.length; i++)
                if ($.validators[i].status == ValidatorStatus.Active) {
                    contribution[i] = $.validators[i].futureStake - minimumDeposit;
                    total += contribution[i];
                }
            require(total >= amount, "available deposits insufficient");
            for (uint256 i = 0; i < $.validators.length; i++)
                if (contribution[i] > 0) {
                    uint256 value = amount * contribution[i] / total;
                    $.validators[i].futureStake -= value;
                    $.validators[i].pendingWithdrawals += value;
                    (success, ) = DEPOSIT_CONTRACT.call(
                        abi.encodeWithSignature("unstake(bytes,uint256)",
                            $.validators[i].blsPubKey,
                            value
                        )
                    );
                    require(success, "deposit decrease failed");
                }
        }
    }

    // withdraw the pending unstaked deposits of all validators
    //TODO: measure how much gas it wastes if there is nothing to withdraw yet
    function _withdrawDeposit() internal virtual {
        // withdraw the unstaked deposit only if already activated as a validator
        if (_isActivated()) {
        BaseDelegationStorage storage $ = _getBaseDelegationStorage();
            for (uint256 i = 0; i < $.validators.length; i++)
                if ($.validators[i].pendingWithdrawals > 0) {
                    // currently all validators have the same reward address,
                    // which is the address of this delegation contract
                    uint256 amount = address(this).balance;
                    (bool success, ) = DEPOSIT_CONTRACT.call(
                        abi.encodeWithSignature("withdraw(bytes)",
                            $.validators[i].blsPubKey
                        )
                    );
                    require(success, "deposit withdrawal failed");
                    amount = address(this).balance - amount;
                    $.validators[i].pendingWithdrawals -= amount;
                }
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

    function getCommissionReceiver() public virtual view returns(address) {
        BaseDelegationStorage storage $ = _getBaseDelegationStorage();
        return $.commissionReceiver;
    }

    function setCommissionReceiver(address _commissionReceiver) public virtual onlyOwner {
        BaseDelegationStorage storage $ = _getBaseDelegationStorage();
        $.commissionReceiver = _commissionReceiver;
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
        WithdrawalQueue.Fifo storage fifo = $.withdrawals[_msgSender()];
        while (fifo.ready())
            total += fifo.dequeue().amount;
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
        BaseDelegationStorage storage $ = _getBaseDelegationStorage();
        uint256 i = $.validatorIndex[blsPubKey];
        if (i > 0)
            return $.validators[--i].futureStake;
        (bool success, bytes memory data) = DEPOSIT_CONTRACT.staticcall(
            abi.encodeWithSignature("getFutureStake(bytes)", blsPubKey)
        );
        require(success, "could not retrieve staked amount");
        return abi.decode(data, (uint256));
    }

}
