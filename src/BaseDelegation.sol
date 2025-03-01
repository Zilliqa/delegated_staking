// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity ^0.8.26;

import {IDelegation} from "src/IDelegation.sol";
import {WithdrawalQueue} from "src/WithdrawalQueue.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ERC165Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol";

/**
 * @notice The contract that all variants of delegated staking contracts are based on.
 * It manages the validators of the staking pool, the unbonding period, the commision
 * rate and the commission receiver, as well as the withdrawal of unstaked funds.
 *
 * @dev It is the only contract that calls functions of the `DEPOSIT_CONTRACT`
 * and might need to be adjusted if the `DEPOSIT_CONTRACT` is upgraded. All variants
 * of delegated staking contracts inherit their {version} from the {BaseDelegation}
 * contract i.e even if the contracts of only one variant change, all variants are
 * supposed to be upgraded to the same latest version. We use semantic versioning
 * instead of incremental version numbers and keep the original contract file names
 * across all versions to avoid updating the `Upgrade` script to import new files.
 */
abstract contract BaseDelegation is IDelegation, PausableUpgradeable, Ownable2StepUpgradeable, UUPSUpgradeable, ERC165Upgradeable {

    using WithdrawalQueue for WithdrawalQueue.Fifo;

    /**
    * @dev If a validator's status is `RequestedToLeave` then its deposit must
    * not be decreased anymore to avoid further pending withdrawals that delay
    * the validator's leaving. If the status is `ReadyToLeave` then there are
    * no more pending withdrawals due to delegators unstaking but the validator
    * deposit had to be decreased to match the value of the stake of its original
    * control address and the unbonding is not over.
    */
    enum ValidatorStatus {Active, RequestedToLeave, ReadyToLeave}

    /**
    * @dev The validator's `futureStake` i.e. its deposit after all pending changes
    * become effective is cached to avoid unnecessary calls to the `DEPOSIT_CONTRACT`.
    * The `rewardAddress` and the `controlAddress` are stored so that their original
    * values can be restored in the `DEPOSIT_CONTRACT` if the validator leaves the pool.
    * The `pendingWithdrawals` is the total amount of unstaked deposit waiting for the
    * unbonding period to end. 
    */
    struct Validator {
        bytes blsPubKey;
        uint256 futureStake;
        address rewardAddress;
        address controlAddress;
        uint256 pendingWithdrawals;
        ValidatorStatus status;
    }

    /**
    * @dev {BaseDelegation} has the following state variables:
    *
    * - `validatorIndex` maps the validators' BLS public keys to their position in
    * the staking pool's validator list, starting at 1. The value 0 means that the
    * BLS public key does not belong to any validator in the list.
    *
    * - `activated` becomes `true` as soon as the first validator joins the pool.
    *
    * - `commissionNumerator` is the commission rate multiplied by `DENOMINATOR`
    * and `commissionReceiver` is the address the deducted commissions are sent to.
    *
    * - `withdrawals` holds the withdrawal queues of addresses that unstaked.
    *
    * - `pendingRebalancedDeposit` is the total amount of pending withdrawals
    * initiated to reduce the deposits of leaving validators to match the stake
    * of their control address.
    *
    * - `validators` holds the current {Validator} list of the staking pool.
    *
    * - `nonRewards` is the portion of the contract balance that does not
    * represent rewards. The first part of it is `undepositedClaims` which
    * are the unstaked funds withdrawn from the validators' deposits that can
    * be claimed. The seconds part of it is `depositedClaims` which represent
    * unstaked funds that could not be withdrawn from the validators' deposits
    * because of the required minimum but can be claimed, so they have to be
    * paid out of the contract balance. The third part of it is the stake that
    * could not be deposited because there was no validator in the pool whose
    * deposit could have been topped up.
    */
    /// @custom:storage-location erc7201:zilliqa.storage.BaseDelegation
    struct BaseDelegationStorage {
        // the actual position in the validators array is the validatorIndex - 1 
        mapping(bytes => uint256) validatorIndex;
        bool activated;
        uint256 commissionNumerator;
        mapping(address => WithdrawalQueue.Fifo) withdrawals;
        uint256 pendingRebalancedDeposit;
        Validator[] validators;
        address commissionReceiver;
        uint256 nonRewards;
        uint256 undepositedClaims;
        uint256 depositedClaims;
    }

    // keccak256(abi.encode(uint256(keccak256("zilliqa.storage.BaseDelegation")) - 1)) & ~bytes32(uint256(0xff))
    // solhint-disable const-name-snakecase
    bytes32 private constant BaseDelegationStorageLocation = 0xc8ff0e571ef581b660c1651f85bbac921a40f9489bd04631c07fa723c13c6000;

    function _getBaseDelegationStorage() private pure returns (BaseDelegationStorage storage $) {
        assembly {
            $.slot := BaseDelegationStorageLocation
        }
    }

    /// @dev The minimum amount of ZIL that can be delegated in a single transaction.
    uint256 public constant MIN_DELEGATION = 10 ether;

    /// @dev The address of the deposit contract.
    address public constant DEPOSIT_CONTRACT = address(0x5A494C4445504F53495450524F5859);

    /// @dev A power of 10 that determines the precision of the commission rate.
    uint256 public constant DENOMINATOR = 10_000;

    /// @dev Emitted when validator identified by `blsPubKey` joins the staking pool.
    event ValidatorJoined(bytes indexed blsPubKey);
    
    /// @dev Emitted when validator identified by `blsPubKey` completes leaving the staking pool.
    event ValidatorLeft(bytes indexed blsPubKey);

    /// @dev Emitted when validator identified by `blsPubKey` requests leaving the staking pool.
    event ValidatorLeaving(bytes indexed blsPubKey, bool success);

    /**
    * @dev Thrown if the amount `withdrawn` from the leaving validator's deposit identified by
    * `blsPubKey` does not match the amount that had to be `unstaked` from its deposit because
    * it was not fully covered by the stake held by the validator's control address.
    */
    error UnstakedDepositMismatch(bytes blsPubKey, uint256 withdrawn, uint256 unstaked);

    /**
    * @dev Thrown if the {Validator} identified by `blsPubKey` can not be found in the validator
    * list of the staking pool.
    */
    error ValidatorNotFound(bytes blsPubKey);

    /**
    * @dev Thrown if the {Validator} identified by `blsPubKey` trying to join is already
    * in the staking pool.
    */
    error ValidatorAlreadyAdded(bytes blsPubKey);

    /**
    * @dev Thrown if the function was calledf by `caller` instead of `expectedCaller`.
    */
    error InvalidCaller(address caller, address expectedCaller);

    /**
    * @dev Thrown if a call to the `DEPOSIT_CONTRACT` using `callData` failed and returned `errorData`.
    */
    error DepositContractCallFailed(bytes callData, bytes errorData);

    /**
    * @dev Thrown if the `status` of the {Validator} identified by `blsPubKey` is `currentStatus`
    * instead of `expectedStatus`.
    */
    error InvalidValidatorStatus(bytes blsPubKey, ValidatorStatus currentStatus, ValidatorStatus expectedStatus);

    /**
    * @dev Thrown if the transfer of `amount` commissions, rewards or unstaked funds to `recipient` failed.
    */
    error TransferFailed(address recipient, uint256 amount);

    /**
    * @dev Thrown if the validator identified by `blsPubKey` has `amount` of withdrawals pendinbg
    * when it should not have any.
    */
    error WithdrawalsPending(bytes blsPubKey, uint256 amount);

    /**
    * @dev Thrown if the staking pool has less undeposited stake `available` than `required`.
    */
    error InsufficientUndepositedStake(uint256 available, uint256 required);

    /**
    * @dev Thrown if the commission rate specified by `numerator` is invalid.
    */
    error InvalidCommissionRate(uint256 numerator);

    /**
    * @dev Thrown if the major, minor or patch `version` is invalid.
    */
    error InvalidVersionNumber(uint256 version);

    /**
    * @dev Thrown if the `amount` to be staked is less than the required minimum.
    */
    error DelegatedAmountTooLow(uint256 amount);

    /**
    * @dev Thrown if the `requested` amount to be unstaked or reward to be withdrawn is more
    * than currently `available`.
    */
    error RequestedAmountTooHigh(uint256 requested, uint256 available);

    /**
    * @dev Thrown if the operation requires the staking pool to be activated i.e.
    * at least one validator to be deposited.
    */
    error StakingPoolNotActivated();

    /**
    * @dev Thrown if there is no stake delegated by `staker`.
    */
    error StakerNotFound(address staker);

    /**
    * @dev The current version of all upgradeable contracts in the repository.
    */
    uint64 internal immutable VERSION = encodeVersion(0, 5, 0);

    /**
    * @dev Return the contracts' version.
    */
    function version() public view returns(uint64) {
        return _getInitializedVersion();
    } 

    /**
    * @dev Return the contracts' major, minor and patch version.
    */
    function decodedVersion() public view returns(uint24, uint24, uint24) {
        return decodeVersion(_getInitializedVersion());
    } 

    /**
    * @dev Return the version number composed of the `major`, `minor` and `patch` version.
    */
    function encodeVersion(uint24 major, uint24 minor, uint24 patch) pure public returns(uint64) {
        require(major < 2**20, InvalidVersionNumber(major));
        require(minor < 2**20, InvalidVersionNumber(minor));
        require(patch < 2**20, InvalidVersionNumber(patch));
        return uint64(major * 2**40 + minor * 2**20 + patch);
    }

    /**
    * @dev Decompose the version number `v` into `major`, `minor` and `patch` version.
    */
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

    /**
    * @dev Deprecated part of the storage layout used in version 0.2.x that needs to be
    * modified during the migration to higher versions.
    */
    struct DeprecatedStorage {
        bytes blsPubKey;
        bytes peerId;
    }

    /**
    * @dev Perform storage modifications needed to upgrade `fromVersion` to the current {VERSION}.
    */
    function migrate(uint64 fromVersion) internal {

        // the contract has been deployed but not upgraded yet
        if (fromVersion == 1)
            return;

        // the contract has been upgraded to a version which
        // is higher or same as the current version
        if (fromVersion >= VERSION)
            return;

        BaseDelegationStorage storage $ = _getBaseDelegationStorage();

        if (fromVersion < encodeVersion(0, 4, 0))
            // the contract has been upgraded to a version which may have
            // changed the totalWithdrawals which has to be zero initially
            $.pendingRebalancedDeposit = 0;

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

        bytes memory callData =
            abi.encodeWithSignature("getFutureStake(bytes)",
            temp.blsPubKey
            );
        (bool success, bytes memory data) = DEPOSIT_CONTRACT.call(callData);
        require(success, DepositContractCallFailed(callData, data));
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

    /**
    * @dev The contract owner is allowed to upgrade the contract to `newImplementation`.
    */
    function _authorizeUpgrade(address newImplementation) internal onlyOwner virtual override {}

    /**
    * @dev Increase `nonRewards` to reflect the amount that was withdrawn from a validators'
    * deposits and added to the contract balance.
    */
    receive() external payable {
        require(
            _msgSender() == DEPOSIT_CONTRACT,
            InvalidCaller(_msgSender(), DEPOSIT_CONTRACT)
        );
        BaseDelegationStorage storage $ = _getBaseDelegationStorage();
        $.nonRewards += msg.value;
    }

    /**
    * @dev Append an entry to the staking pool's list of validators to record the joining validator's
    * deposit, current reward address and control address. Set the validator's reward address to the
    * pool contact's address. Increase the validator's deposit by `ùndepositedStake` that is not needed
    * to cover {totalPendingWithdrawals}.
    */
    function _join(bytes calldata blsPubKey, address controlAddress) internal onlyOwner virtual {
        BaseDelegationStorage storage $ = _getBaseDelegationStorage();
        $.activated = true;
        require($.validatorIndex[blsPubKey] == 0, ValidatorAlreadyAdded(blsPubKey));

        bytes memory callData =
            abi.encodeWithSignature("getFutureStake(bytes)",
            blsPubKey
            );
        (bool success, bytes memory data) = DEPOSIT_CONTRACT.call(callData);
        require(success, DepositContractCallFailed(callData, data));
        uint256 futureStake = abi.decode(data, (uint256));

        callData =
            abi.encodeWithSignature("getRewardAddress(bytes)",
            blsPubKey
            );
        (success, data) = DEPOSIT_CONTRACT.call(callData);
        require(success, DepositContractCallFailed(callData, data));
        address rewardAddress = abi.decode(data, (address));

        // the control address should be set to this contract by the
        // original control address otherwise the call will fail
        callData =
            abi.encodeWithSignature("setRewardAddress(bytes,address)",
            blsPubKey,
            address(this)
            );
        (success, data) = DEPOSIT_CONTRACT.call(callData);
        require(success, DepositContractCallFailed(callData, data));

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

        uint256 availableStake = $.nonRewards - $.undepositedClaims - $.depositedClaims;
        if (availableStake > 0)
            _increaseDeposit(availableStake);
    }

    /**
    * @dev Try to withdraw the deposit unstaked in {_initiateLeaving} and if successful
    * i.e. the unbonding period is over, distribute the withdrawn amount among the other
    * validators to increase their deposit. If there is no unstaked deposit to withdraw
    * call {_leave} to remove the validator.
    */
    function completeLeaving(bytes calldata blsPubKey) public virtual {
        BaseDelegationStorage storage $ = _getBaseDelegationStorage();
        uint256 i = $.validatorIndex[blsPubKey];
        require(
            i-- > 0,
            ValidatorNotFound(blsPubKey)
        );
        require(
            _msgSender() == $.validators[i].controlAddress,
            InvalidCaller(_msgSender(), $.validators[i].controlAddress)
        );
        require(
            $.validators[i].status == ValidatorStatus.ReadyToLeave,
            InvalidValidatorStatus(blsPubKey, $.validators[i].status, ValidatorStatus.ReadyToLeave)
        );
        uint256 amount = address(this).balance;
        bytes memory callData =
            abi.encodeWithSignature("withdraw(bytes)",
                $.validators[i].blsPubKey
            );
        (bool success, bytes memory data) = DEPOSIT_CONTRACT.call(callData);
        require(success, DepositContractCallFailed(callData, data));
        amount = address(this).balance - amount;
        if (amount == 0)
            return;
        if (amount == $.validators[i].pendingWithdrawals) {
            $.pendingRebalancedDeposit -= $.validators[i].pendingWithdrawals;
            $.validators[i].pendingWithdrawals = 0;
            _increaseDeposit(amount);
        } else
            revert UnstakedDepositMismatch(blsPubKey, amount, $.validators[i].pendingWithdrawals);
        _leave(i);
    }

    /**
    * @dev Set the validator's reward address and control address to
    * the original value and remove the entry from the validator list.
    */
    function _leave(uint256 index) internal virtual {
        BaseDelegationStorage storage $ = _getBaseDelegationStorage();

        bytes memory callData =
            abi.encodeWithSignature("setRewardAddress(bytes,address)",
                $.validators[index].blsPubKey,
                $.validators[index].rewardAddress
            );
        (bool success, bytes memory data) = DEPOSIT_CONTRACT.call(callData);
        require(success, DepositContractCallFailed(callData, data));

        callData =
            abi.encodeWithSignature("setControlAddress(bytes,address)",
                $.validators[index].blsPubKey,
                $.validators[index].controlAddress
            );
        (success, data) = DEPOSIT_CONTRACT.call(callData);
        require(success, DepositContractCallFailed(callData, data));

        emit ValidatorLeft($.validators[index].blsPubKey);

        delete $.validatorIndex[$.validators[index].blsPubKey];
        if (index < $.validators.length - 1) {
            $.validators[index] = $.validators[$.validators.length - 1];
            $.validatorIndex[$.validators[index].blsPubKey] = index + 1;
        }
        $.validators.pop();
    }

    /**
    * @dev Return if there are pending withdrawals from the validator's deposit
    * and set the {ValidatorStatus} to `RequestedToLeave` to prevent that new
    * unstake requests delay the validator's leaving. 
    */
    function _preparedToLeave(bytes calldata blsPubKey) internal virtual returns(bool prepared) {
        BaseDelegationStorage storage $ = _getBaseDelegationStorage();
        uint256 i = $.validatorIndex[blsPubKey];
        require(i-- > 0, ValidatorNotFound(blsPubKey));
        prepared = $.validators[i].pendingWithdrawals == 0;
        if ($.validators[i].status == ValidatorStatus.Active) {
            $.validators[i].status = ValidatorStatus.RequestedToLeave;
            emit ValidatorLeaving(blsPubKey, prepared);
        }
    }

    /**
    * @dev Unstake the difference between the `leavingStake` of the original control
    * address and the validator's current deposit. If there is no difference call
    * {_leave} to remove the validator.
    */
    function _initiateLeaving(bytes calldata blsPubKey, uint256 leavingStake) internal virtual {
        BaseDelegationStorage storage $ = _getBaseDelegationStorage();
        uint256 i = $.validatorIndex[blsPubKey];
        require(i-- > 0, ValidatorNotFound(blsPubKey));
        require(
            _msgSender() == $.validators[i].controlAddress,
            InvalidCaller(_msgSender(), $.validators[i].controlAddress)
        );
        require(
            $.validators[i].status == ValidatorStatus.RequestedToLeave,
            InvalidValidatorStatus(blsPubKey, $.validators[i].status, ValidatorStatus.RequestedToLeave)
        );
        require(
            $.validators[i].pendingWithdrawals == 0,
            WithdrawalsPending(blsPubKey, $.validators[i].pendingWithdrawals)
        );
        $.validators[i].status = ValidatorStatus.ReadyToLeave;
        if ($.validators[i].futureStake > leavingStake) {
            bytes memory callData =
                abi.encodeWithSignature("unstake(bytes,uint256)",
                    $.validators[i].blsPubKey,
                    $.validators[i].futureStake - leavingStake
                );
            (bool success, bytes memory data) = DEPOSIT_CONTRACT.call(callData);
            require(success, DepositContractCallFailed(callData, data));
            $.validators[i].pendingWithdrawals = $.validators[i].futureStake - leavingStake;
            $.validators[i].futureStake = leavingStake;
            $.pendingRebalancedDeposit += $.validators[i].pendingWithdrawals;
        } else
            _leave(i);
    }

    /**
    * @dev Return whether the validator has any pending withdrawals. The withdrawal necessary to match
    * the stake of the control address when the validator's `status` is `ReadyToLeave` does not count.
    */
    function pendingWithdrawals(bytes calldata blsPubKey) public virtual view returns(bool) {
        BaseDelegationStorage storage $ = _getBaseDelegationStorage();
        uint256 i = $.validatorIndex[blsPubKey];
        require(i-- > 0, ValidatorNotFound(blsPubKey));
        return $.validators[i].status < ValidatorStatus.ReadyToLeave && $.validators[i].pendingWithdrawals > 0;
    }

    /**
    * @dev Return the `total` pending withdrawals of all validators in the pool. The withdrawal
    * necessary to match the stake of the control address when the validator's `status` is
    * `ReadyToLeave` does not count.
    */
    function totalPendingWithdrawals() public virtual view returns(uint256 total) {
        BaseDelegationStorage storage $ = _getBaseDelegationStorage();
        for(uint256 i = 0; i < $.validators.length; i++ )
            if ($.validators[i].status < ValidatorStatus.ReadyToLeave)
                total += $.validators[i].pendingWithdrawals;
    }

    /**
    * @dev Return the {Validator}s in the staking pool.
    */
    function validators() public view returns(Validator[] memory) {
        BaseDelegationStorage storage $ = _getBaseDelegationStorage();
        return $.validators;
    }

    /**
    * @dev Append an entry to the staking pool's list of validators. Use the pool contract's
    * owner address as reward address and control address in the entry. Register the validator
    * by transferring the available stake to the `DEPOSIT_CONTRACT`.
    */
    function _deposit(
        bytes calldata blsPubKey,
        bytes calldata peerId,
        bytes calldata signature
    ) internal virtual {
        BaseDelegationStorage storage $ = _getBaseDelegationStorage();
        $.activated = true;
        uint256 availableStake = $.nonRewards - $.undepositedClaims - $.depositedClaims;
        $.validators.push(Validator(
            blsPubKey,
            availableStake,
            owner(),
            owner(),
            0,
            ValidatorStatus.Active
        ));

        $.validatorIndex[blsPubKey] = $.validators.length;

        bytes memory callData =
            abi.encodeWithSignature("deposit(bytes,bytes,bytes,address,address)",
                blsPubKey,
                peerId,
                signature,
                address(this),
                owner()
            );
        (bool success, bytes memory data) = DEPOSIT_CONTRACT.call{
            value: availableStake
        }(callData);
        require(success, DepositContractCallFailed(callData, data));

        $.nonRewards = totalPendingWithdrawals();
        emit ValidatorJoined(blsPubKey);
    }

    /**
    * @dev Add the validator identified by `blsPubKey` to the staking pool. Can be called by
    * the contract owner if the `controlAddress` has called the `setControlAddress` function
    * of the `DEPOSIT_CONTRACT` before. The joining validator's deposit is treated as if staked
    * by the `controlAddress`. The `controlAddress` is restored in the `DEPOSIT_CONTRACT` when
    * the validator leaves the pool later.
    */
    function join(bytes calldata blsPubKey, address controlAddress) public virtual;

    /**
    * @dev Remove the validator identified by `blsPubKey` from the staking pool. Must be
    * called by the validator's original control address.
    *
    * If there are pending withdrawals from the validator's deposit, the validator can
    * not proceed with leaving, but no further deposit withdrawals will be initiated
    * by delegators' unstaking requests. As soon as the unbonding period of the last
    * pending deposit withdrawal is over, {leave} must be called again to proceed with
    * one of the following scenarios:
    * 
    * 1. If the caller's current stake is higher than the validator's current deposit
    * then the caller can withdraw the surplus after the unbonding period.
    *
    * 2. If the validator's deposit is higher than the caller's stake then the deposit
    * is reduced to match the caller's stake unless it becomes lower than the minimum
    * deposit required and reverts the transaction. If {leave} was successful the control
    * address must call {BaseDelegation-completeLeaving} after the unbonding period to
    * withdraw the unstaked surplus from the validator's deposit and distribute it among
    * the validators remaining in the pool.
    */
    function leave(bytes calldata blsPubKey) public virtual;

    /**
    * @dev Turn a fully synced node into a validator using the stake in the pool's balance.
    * Must be called by the contract owner. The staking pool must have at least the minimum
    * stake required of validators in its balance including the amount transferred by the
    * contract owner in the current transaction.
    */
    function deposit(
        bytes calldata blsPubKey,
        bytes calldata peerId,
        bytes calldata signature
    ) public virtual payable;

    /**
    * @dev Increase the `nonRewards` portion of the balance by the `amount` either staked
    * by a delegator or staked out of the rewards in the contract balance.
    */
    function _increaseStake(uint256 amount) internal {
        BaseDelegationStorage storage $ = _getBaseDelegationStorage();
        $.nonRewards += amount;
    }

    /**
    * @dev Topup the deposits by `amount` distributed in proportion to the validators'
    * current deposit.
    */
    function _increaseDeposit(uint256 amount) internal virtual {
        BaseDelegationStorage storage $ = _getBaseDelegationStorage();
        uint256[] memory contribution = new uint256[]($.validators.length);
        uint256 totalContribution;
        for (uint256 i = 0; i < $.validators.length; i++)
            if ($.validators[i].status < ValidatorStatus.ReadyToLeave) {
                contribution[i] = $.validators[i].futureStake;
                totalContribution += contribution[i];
            }
        uint256 totalDeposited;
        for (uint256 i = 0; i < $.validators.length; i++)
            if (contribution[i] > 0) {
                uint256 value = amount * contribution[i] / totalContribution;
                totalDeposited += value;
                $.validators[i].futureStake += value;
                bytes memory callData =
                    abi.encodeWithSignature("depositTopup(bytes)", 
                        $.validators[i].blsPubKey
                    );
                (bool success, bytes memory data) = DEPOSIT_CONTRACT.call{
                    value: value
                }(callData);
                require(success, DepositContractCallFailed(callData, data));
            }
        $.nonRewards -= totalDeposited;
    }

    /**
    * @dev Unstake `amount` from the deposits proportionally to the validators'
    * surplus deposit exceeding the required minimum stake.
    */
    function _decreaseDeposit(uint256 amount) internal virtual {
        BaseDelegationStorage storage $ = _getBaseDelegationStorage();
        bytes memory callData =
            abi.encodeWithSignature("minimumStake()");
        (bool success, bytes memory data) = DEPOSIT_CONTRACT.call(callData);
        require(success, DepositContractCallFailed(callData, data));
        uint256 minimumDeposit = abi.decode(data, (uint256));
        uint256[] memory contribution = new uint256[]($.validators.length);
        uint256 totalContribution;
        for (uint256 i = 0; i < $.validators.length; i++)
            if ($.validators[i].status == ValidatorStatus.Active) {
                contribution[i] = $.validators[i].futureStake - minimumDeposit;
                totalContribution += contribution[i];
            }
        if (totalContribution < amount) {
            $.depositedClaims += amount - totalContribution;
            require(
                $.nonRewards - $.undepositedClaims >= $.depositedClaims,
                InsufficientUndepositedStake($.nonRewards - $.undepositedClaims, $.depositedClaims)
            );
            amount = totalContribution;
        }
        uint256[] memory undeposited = new uint256[]($.validators.length);
        uint256 totalUndeposited;
        for (uint256 i = 0; i < $.validators.length; i++)
            if (contribution[i] > 0) {
                undeposited[i] = amount * contribution[i] / totalContribution;
                totalUndeposited += undeposited[i];
            }
        // rounding error that was not unstaked from the deposits but can be claimed
        // after the unbonding period
        uint256 delta = amount - totalUndeposited;
        // increment the values to be undeposited unless they equal the respective
        // validator's contribution i.e. the validator can't contribute more, until
        // the delta bounded by the number of contributing validators becomes zero
        for (uint256 i = 0; i < $.validators.length; i++) {
            uint256 value = undeposited[i];
            if (value > 0) {
                if (delta > 0 && value < contribution[i]) {
                    value++;
                    delta--;
                }
                $.validators[i].futureStake -= value;
                $.validators[i].pendingWithdrawals += value;
                callData =
                    abi.encodeWithSignature("unstake(bytes,uint256)",
                        $.validators[i].blsPubKey,
                        value
                    );
                (success, data) = DEPOSIT_CONTRACT.call(callData);
                require(success, DepositContractCallFailed(callData, data));
            }
        }
    }

    /**
    * @dev Withdraw and return the pending unstaked deposits of all validators.
    */
    function _withdrawDeposit() internal virtual returns(uint256 total) {
        BaseDelegationStorage storage $ = _getBaseDelegationStorage();
        // we accept the constant amount of gas wasted per validator whose unbonding
        // period is not over i.e. there is nothing to withdraw yet
        for (uint256 i = 0; i < $.validators.length; i++)
            if ($.validators[i].pendingWithdrawals > 0) {
                // currently all validators have the same reward address,
                // which is the address of this delegation contract
                uint256 amount = address(this).balance;
                bytes memory callData =
                    abi.encodeWithSignature("withdraw(bytes)",
                        $.validators[i].blsPubKey
                    );
                (bool success, bytes memory data) = DEPOSIT_CONTRACT.call(callData);
                require(success, DepositContractCallFailed(callData, data));
                amount = address(this).balance - amount;
                total += amount;
                $.validators[i].pendingWithdrawals -= amount;
            }
    }

    /**
    * @dev Return whether the first validator has already been deposited.
    * In case it is `false` the staking pool is in the fundraising phase,
    * collecting delegated stake to deposit its first validator node later.
    */
    function _isActivated() internal virtual view returns(bool) {
        BaseDelegationStorage storage $ = _getBaseDelegationStorage();
        return $.activated;
    }

    /**
    * @dev Return the commission rate multiplied by `DENOMINATOR`.
    */
    function getCommissionNumerator() public virtual view returns(uint256) {
        BaseDelegationStorage storage $ = _getBaseDelegationStorage();
        return $.commissionNumerator;
    }

    /**
    * @dev Set the commission rate to `_commissionNumerator / DENOMINATOR`.
    */
    function setCommissionNumerator(uint256 _commissionNumerator) public virtual onlyOwner {
        require(_commissionNumerator < DENOMINATOR, InvalidCommissionRate(_commissionNumerator));
        BaseDelegationStorage storage $ = _getBaseDelegationStorage();
        $.commissionNumerator = _commissionNumerator;
    }

    /// @inheritdoc IDelegation
    function getCommission() public virtual view returns(uint256 numerator, uint256 denominator) {
        BaseDelegationStorage storage $ = _getBaseDelegationStorage();
        numerator = $.commissionNumerator;
        denominator = DENOMINATOR;
    }

    /**
    * @dev Return the address the commission is to be transferred to.
    */
    function getCommissionReceiver() public virtual view returns(address) {
        BaseDelegationStorage storage $ = _getBaseDelegationStorage();
        return $.commissionReceiver;
    }

    /**
    * @dev Set the address the commission is to be transferred to. Must be called by the
    * contract owner.
    */
    function setCommissionReceiver(address _commissionReceiver) public virtual onlyOwner {
        BaseDelegationStorage storage $ = _getBaseDelegationStorage();
        $.commissionReceiver = _commissionReceiver;
    }

    /// @inheritdoc IDelegation
    function getMinDelegation() public virtual view returns(uint256) {
        return MIN_DELEGATION;
    }

    /// @inheritdoc IDelegation
    function stake() external virtual payable;

    /// @inheritdoc IDelegation
    function unstake(uint256) external virtual returns(uint256);

    /// @inheritdoc IDelegation
    function claim() public virtual whenNotPaused {
        uint256 total = _dequeueWithdrawals();
        if (total == 0)
            return;
        BaseDelegationStorage storage $ = _getBaseDelegationStorage();
        // withdraw the unstaked deposit once the unbonding period is over
        uint256 withdrawn = _withdrawDeposit();
        $.undepositedClaims += withdrawn;
        // if the pool has not been activated yet, all the stake lands in nonRewards
        // and withdrawn is zero hence undepositedClaims is zero too
        if (_isActivated())
            if ($.undepositedClaims >= total) 
                // total is part of withdrawn now or it has already been withdrawn before
                // i.e. in both cases it has already been added to undepositedClaims
                $.undepositedClaims -= total;
            else {
                $.depositedClaims -= total - $.undepositedClaims;
                $.undepositedClaims = 0;
            }
        $.nonRewards -= total;
        (bool success, ) = _msgSender().call{
            value: total
        }("");
        require(success, TransferFailed(_msgSender(), total));
        emit Claimed(_msgSender(), total, "");
    }

    /// @inheritdoc IDelegation
    function collectCommission() public virtual;

    /// @inheritdoc IDelegation
    function stakeRewards() public virtual;

    /// @inheritdoc IDelegation
    function getClaimable() public virtual view returns(uint256 total) {
        BaseDelegationStorage storage $ = _getBaseDelegationStorage();
        WithdrawalQueue.Fifo storage fifo = $.withdrawals[_msgSender()];
        uint256 index = fifo.first;
        while (fifo.ready(index)) {
            total += fifo.items[index].amount;
            index++;
        }
    }

    /// @inheritdoc IDelegation
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

    /**
    * @dev Remove all entries whose unbonding period is over from the
    * withdrawal queue and return their `total` amount.
    */
    function _dequeueWithdrawals() internal virtual returns (uint256 total) {
        BaseDelegationStorage storage $ = _getBaseDelegationStorage();
        WithdrawalQueue.Fifo storage fifo = $.withdrawals[_msgSender()];
        while (fifo.ready())
            total += fifo.dequeue().amount;
    }

    /**
    * @dev Add `amount` to the withdrawals queue.
    */
    function _enqueueWithdrawal(uint256 amount) internal virtual {
        BaseDelegationStorage storage $ = _getBaseDelegationStorage();
        $.withdrawals[_msgSender()].enqueue(amount, unbondingPeriod());
    }

    /// @inheritdoc IDelegation
    function unbondingPeriod() public view returns(uint256) {
        if (!_isActivated())
            return 0;
        bytes memory callData =
            abi.encodeWithSignature("withdrawalPeriod()");
        (bool success, bytes memory data) = DEPOSIT_CONTRACT.staticcall(callData);
        require(success, DepositContractCallFailed(callData, data));
        return abi.decode(data, (uint256));
    }

    /**
    * @dev Return the rewards accumulated on the balance of the contract,
    * which is the reward address of all validators in the staking pool.
    * Note that `total` also includes rewards from which no commission
    * has been deducted yet which include stake that could not be deposited
    * because there was no validator whose deposit could be topped up. 
    */
    function getRewards() public virtual view returns(uint256 total) {
        if (!_isActivated())
            return 0;
        BaseDelegationStorage storage $ = _getBaseDelegationStorage();
        // currently all validators have the same reward address,
        // which is the address of their pool's delegation contract
        total = address(this).balance - $.nonRewards;
    }

    /**
    * @dev Return the staked amount that is currently not deposited
    * with any of the validators in the pool. 
    */
    function getUndepositedStake() public view returns(uint256) {
        BaseDelegationStorage storage $ = _getBaseDelegationStorage();
        return $.nonRewards;
    }

    /// @inheritdoc IDelegation
    function getStake() public virtual view returns(uint256 total) {
        BaseDelegationStorage storage $ = _getBaseDelegationStorage();
        total = $.nonRewards;
        for (uint256 i = 0; i < $.validators.length; i++)
            if ($.validators[i].status < ValidatorStatus.ReadyToLeave)
                total += $.validators[i].futureStake;
        total += $.pendingRebalancedDeposit;
        total -= $.undepositedClaims;
        total -= $.depositedClaims;
    }

    /**
    * @dev Return the deposit of the validator identified by `blsPubKey`
    * after applying all pending changes to it. Note that the validator
    * does not have to be part of the staking pool.
    */
    function getStake(bytes calldata blsPubKey) public virtual view returns(uint256) {
        BaseDelegationStorage storage $ = _getBaseDelegationStorage();
        uint256 i = $.validatorIndex[blsPubKey];
        if (i > 0)
            return $.validators[--i].futureStake;
        bytes memory callData =
            abi.encodeWithSignature("getFutureStake(bytes)", blsPubKey);
        (bool success, bytes memory data) = DEPOSIT_CONTRACT.staticcall(callData);
        require(success, DepositContractCallFailed(callData, data));
        return abi.decode(data, (uint256));
    }

}
