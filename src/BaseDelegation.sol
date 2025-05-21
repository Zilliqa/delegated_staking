// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity 0.8.28;

import { Ownable2StepUpgradeable } from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import { IDelegation } from "src/IDelegation.sol";
import { WithdrawalQueue } from "src/WithdrawalQueue.sol";

/**
 * @notice The base contract that all variants of delegated staking contracts
 * inherit from. It manages the validators of the staking pool and their deposited
 * stake, the unbonding period and the withdrawal of unstaked funds by delegators,
 * as well as the commission rate and the commission receiver.
 *
 * @dev It is the only contract that calls the functions of the `DEPOSIT_CONTRACT`
 * and might need to be adjusted if the `DEPOSIT_CONTRACT` is upgraded. All variants
 * of delegated staking contracts inherit their {version} from the {BaseDelegation}
 * contract, i.e even if the contracts of only one variant change, all variants are
 * supposed to be upgraded to the same latest version. It uses semantic versioning
 * instead of incremental version numbers and keeps the original contract file names
 * across all versions to avoid updating the `Upgrade` script to import new files.
 */
abstract contract BaseDelegation is IDelegation, PausableUpgradeable, Ownable2StepUpgradeable, UUPSUpgradeable {

    using WithdrawalQueue for WithdrawalQueue.Fifo;

    // ************************************************************************
    // 
    //                                 STATE
    // 
    // ************************************************************************

    /**
    * @dev If a validator's status is `RequestedToLeave` then its deposit must
    * not be decreased anymore to avoid further pending withdrawals that delay
    * the validator's leaving. If the status is `ReadyToLeave` then there are
    * no more pending withdrawals due to delegators unstaking but the validator
    * deposit had to be decreased to match the value of the stake of its original
    * control address. If the status in `FullyUndeposited` then the validator's
    * entire deposit had to be unstaked to cover the amount a delegator unstaked
    * because the remaining deposit would have been less than the minimum required.
    * In this status the validator's `futureStake` stores the excess deposit that
    * in not claimable by the delegator.
    */
    enum ValidatorStatus {Active, RequestedToLeave, ReadyToLeave, FullyUndeposited}

    /**
    * @dev The validator's `futureStake` i.e. its deposit after all pending changes
    * become effective is cached to avoid unnecessary calls to the `DEPOSIT_CONTRACT`.
    * The `rewardAddress` and the `controlAddress` are stored so that their original
    * values can be restored in the `DEPOSIT_CONTRACT` if the validator leaves the
    * pool. The `pendingWithdrawals` is the total amount of unstaked deposit waiting
    * for the unbonding period to end. 
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
    * `lastCommissionChange` is the block height of the last commission change.
    *
    * - `withdrawals` holds the withdrawal queues of addresses that unstaked.
    *
    * - `pendingRebalancedDeposit` is the total amount of pending withdrawals
    * that were either unstaked to reduce the deposits of leaving validators to
    * match the stake of their control address or were unstaked because of the
    * minimim stake requirement which did not allow to unstake only the deposit
    * that equals the amount unstaked by a delegator, but required to unstake the 
    * full deposit of the validator instead.
    *
    * - `validators` holds the current {Validator} list of the staking pool.
    *
    * - `nonRewards` is the portion of the contract balance that does not
    * represent rewards. The first part of it is `withdrawnDepositedClaims`,
    * representing unstaked funds that have already been withdrawn from the
    * pool's deposits. The second part, `nonDepositedClaims`, is reserved for
    * future claims arising from unstaked funds that can not be withdrawn from
    * the deposits. The last part represents stake that was not deposited e.g.
    * because the pool had no validators whose deposits could be increased, or
    * it remained from rounding errors during the deposit top-ups.
    *
    * - `controlAddresses` maps the BLS public keys of validator nodes waiting to
    * join the pool to their original control address, which becomes a delegator
    * once the validator is added to the pool and is also allowed to make it leave
    * the staking pool.
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
        uint256 withdrawnDepositedClaims;
        uint256 nonDepositedClaims;
        mapping(bytes => address) controlAddresses;
        uint256 lastCommissionChange;
    }

    // keccak256(abi.encode(uint256(keccak256("zilliqa.storage.BaseDelegation")) - 1)) & ~bytes32(uint256(0xff))
    // solhint-disable const-name-snakecase, private-vars-leading-underscore
    bytes32 private constant BaseDelegationStorageLocation = 
        0xc8ff0e571ef581b660c1651f85bbac921a40f9489bd04631c07fa723c13c6000;

    function _getBaseDelegationStorage() private pure returns (BaseDelegationStorage storage $) {
        assembly {
            $.slot := BaseDelegationStorageLocation
        }
    }

    // ************************************************************************
    // 
    //                                 ERRORS
    // 
    // ************************************************************************

    /**
    * @dev Thrown if the amount `withdrawn` from the leaving validator's deposit
    * identified by `blsPubKey` is not equal to the amount that was `unstaked`
    * from its deposit to match the stake held by the validator's control address.
    */
    error UnstakedDepositMismatch(bytes blsPubKey, uint256 withdrawn, uint256 unstaked);

    /**
    * @dev Thrown if the {Validator} identified by `blsPubKey` can not be found
    * in the validator list of the staking pool.
    */
    error ValidatorNotFound(bytes blsPubKey);

    /**
    * @dev Thrown if the {Validator} identified by `blsPubKey` can not be added to
    * the validator list of the staking pool because it has reached its upper limit.
    */
    error TooManyValidators(bytes blsPubKey);

    /**
    * @dev Thrown if the {Validator} identified by `blsPubKey` trying to join is
    * already in the staking pool.
    */
    error ValidatorAlreadyAdded(bytes blsPubKey);

    /**
    * @dev Thrown if the function was calledf by `caller` instead of `expectedCaller`.
    */
    error InvalidCaller(address caller, address expectedCaller);

    /**
    * @dev Thrown if a call to the `DEPOSIT_CONTRACT` using `callData` failed
    * and returned `errorData`.
    */
    error DepositContractCallFailed(bytes callData, bytes errorData);

    /**
    * @dev Thrown if the `status` of the {Validator} identified by `blsPubKey`
    * is `currentStatus` instead of `expectedStatus`.
    */
    error InvalidValidatorStatus(bytes blsPubKey, ValidatorStatus currentStatus, ValidatorStatus expectedStatus);

    /**
    * @dev Thrown if the transfer of `amount` commissions, rewards or unstaked
    * funds to `recipient` failed.
    */
    error TransferFailed(address recipient, uint256 amount);

    /**
    * @dev Thrown if the validator identified by `blsPubKey` has `amount`
    * of withdrawals pending when it should not have any.
    */
    error WithdrawalsPending(bytes blsPubKey, uint256 amount);

    /**
    * @dev Thrown if the commission rate specified by `numerator` is invalid or
    * the requested change is too high or too early after the last change.
    */
    error InvalidCommissionChange(uint256 numerator);

    /**
    * @dev Thrown if the major, minor or patch `version` is invalid.
    */
    error InvalidVersionNumber(uint256 version);

    /**
    * @dev Thrown if the `amount` to be staked or unstaked is less than the
    * required minimum.
    */
    error AmountTooLow(uint256 amount);

    /**
    * @dev Thrown if the `requested` amount to be unstaked or reward to be
    * withdrawn is more than currently `available`.
    */
    error RequestedAmountTooHigh(uint256 requested, uint256 available);

    /**
    * @dev Thrown if the operation requires the staking pool to be activated
    * i.e. at least one validator to be deposited.
    */
    error StakingPoolNotActivated();

    /**
    * @dev Thrown if there is no stake delegated by `staker`.
    */
    error StakerNotFound(address staker);

    /**
    * @dev Thrown if the caller tried to set its new address to another `staker` address.
    */
    error StakerAlreadyExists(address staker);

    /**
    * @dev Thrown if the contract can not be upgraded `fromVersion`.
    */
    error IncompatibleVersion(uint64 fromVersion);

    /**
    * @dev Thrown if the zero address was used where it is not allowed.
    */
    error ZeroAddressNotAllowed();

    // ************************************************************************
    // 
    //                                 VERSION
    // 
    // ************************************************************************

    /// @dev The current version of all upgradeable contracts in the repository.
    uint64 internal immutable VERSION = encodeVersion(1, 1, 0);

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
    *
    * Revert with {InvalidVersionNumber} containing the `major`, `minor` or `patch`
    * version number if it is has 20 bits or more.
    */
    function encodeVersion(uint24 major, uint24 minor, uint24 patch) public pure returns(uint64) {
        require(major < 2**20, InvalidVersionNumber(major));
        require(minor < 2**20, InvalidVersionNumber(minor));
        require(patch < 2**20, InvalidVersionNumber(patch));
        return uint64(major * 2**40 + minor * 2**20 + patch);
    }

    /**
    * @dev Decompose the version number `v` into `major`, `minor` and `patch` version.
    */
    function decodeVersion(uint64 v) public pure returns(uint24 major, uint24 minor, uint24 patch) {
        patch = uint24(v & (2**20 - 1));
        minor = uint24((v >> 20) & (2**20 - 1)); 
        major = uint24((v >> 40) & (2**20 - 1)); 
    }

    /**
    * @dev Return the staking variant identifier implemented by the contract.
    */
    function variant() public virtual pure returns(bytes32);

    // solhint-disable func-name-mixedcase
    function __BaseDelegation_init(address initialOwner) internal onlyInitializing {
        __Pausable_init_unchained();
        __Ownable2Step_init_unchained();
        __Ownable_init_unchained(initialOwner);
        __UUPSUpgradeable_init_unchained();
        __BaseDelegation_init_unchained(initialOwner);
    }

    function __BaseDelegation_init_unchained(address initialOwner) internal onlyInitializing {
        BaseDelegationStorage storage $ = _getBaseDelegationStorage();
        $.commissionReceiver = initialOwner;
    }

    /**
    * @dev Deprecated part of the storage layout used in version 0.2.x that needs
    * to be modified during the migration to higher versions.
    */
    struct DeprecatedStorage {
        bytes blsPubKey;
        bytes peerId;
    }

    /**
    * @dev Perform storage modifications needed to upgrade `fromVersion` to the
    * current {VERSION}.
    *
    * Revert with {IncompatibleVersion} containing `fromVersion` that was deployed
    * before the ongoing upgrade if it is not the initial upgrade during deployment
    * and `fromVersion` is not upgradeable to the current {VERSION}.
    */
    function _migrate(uint64 fromVersion) internal {
        // the contract was just deployed, now upgrading from the initial version
        if (fromVersion == 1)
            return;
        require(fromVersion >= encodeVersion(1, 0, 0), IncompatibleVersion(fromVersion));
    }

    /**
    * @dev The contract owner is allowed to upgrade the contract to `newImplementation`.
    */
    function _authorizeUpgrade(address newImplementation) internal onlyOwner virtual override {}

    // ************************************************************************
    // 
    //                                 VALIDATORS
    // 
    // ************************************************************************

    /// @dev The address of the deposit contract.
    address public constant DEPOSIT_CONTRACT = address(0x5A494C4445504F53495450524F5859);

    /// @dev The maximum number of validators allowed.
    uint256 public constant MAX_VALIDATORS = 100;

    /// @dev Emitted when validator identified by `blsPubKey` joins the staking pool.
    event ValidatorJoined(bytes indexed blsPubKey);
    
    /// @dev Emitted when validator identified by `blsPubKey` completes leaving of the staking pool.
    event ValidatorLeft(bytes indexed blsPubKey);

    /// @dev Emitted when validator identified by `blsPubKey` requests leaving of the staking pool.
    event ValidatorLeaving(bytes indexed blsPubKey, bool success);

    /**
    * @dev Return the {Validator}s in the staking pool.
    */
    function validators() public view returns(Validator[] memory) {
        BaseDelegationStorage storage $ = _getBaseDelegationStorage();
        return $.validators;
    }

    /**
    * @dev Check and register the `controlAddress` of the validator identified
    * by `blsPubKey` before it replaces itself with the pool contract's address
    * in the `DEPOSIT_CONTRACT`.
    */
    function registerControlAddress(
        bytes calldata blsPubKey
    ) public virtual {
        BaseDelegationStorage storage $ = _getBaseDelegationStorage();
        bytes memory callData =
            abi.encodeWithSignature("getControlAddress(bytes)",
            blsPubKey
            );
        (bool success, bytes memory data) = DEPOSIT_CONTRACT.call(callData);
        require(success, DepositContractCallFailed(callData, data));
        address controlAddress = abi.decode(data, (address));
        require(
            _msgSender() == controlAddress,
            InvalidCaller(_msgSender(), controlAddress)
        );
        $.controlAddresses[blsPubKey] = controlAddress;
    }

    /**
    * @dev Return the registered `controlAddress` of the validator identified by
    * `blsPubKey`.
    */
    function getRegisteredControlAddress(
        bytes calldata blsPubKey
    ) public virtual view returns(address) {
        BaseDelegationStorage storage $ = _getBaseDelegationStorage();
        return $.controlAddresses[blsPubKey];
    }

    /**
    * @dev Reset the original `controlAddress` of the validator identified by
    * `blsPubKey` in the `DEPOSIT_CONTRACT` before the pool contract owner calls
    * {joinPool} to add the validator to the pool.
    */
    function unregisterControlAddress(
        bytes calldata blsPubKey
    ) public virtual {
        BaseDelegationStorage storage $ = _getBaseDelegationStorage();
        require(
            _msgSender() == $.controlAddresses[blsPubKey],
            InvalidCaller(_msgSender(), $.controlAddresses[blsPubKey])
        );
        bytes memory callData =
            abi.encodeWithSignature("setControlAddress(bytes,address)",
            blsPubKey,
            $.controlAddresses[blsPubKey]
            );
        (bool success, bytes memory data) = DEPOSIT_CONTRACT.call(callData);
        require(success, DepositContractCallFailed(callData, data));
        delete $.controlAddresses[blsPubKey];
    }

    /**
    * @dev Turn a fully synced node into a validator using the stake in the pool's
    * balance. It must be called by the contract owner. The staking pool must have
    * at least the minimum stake required of validators in its balance including
    * the amount transferred by the contract owner in the current transaction.
    */
    function depositFromPool(
        bytes calldata blsPubKey,
        bytes calldata peerId,
        bytes calldata signature
    ) public virtual payable;

    /**
    * @dev Add the validator identified by `blsPubKey` to the staking pool. It
    * can be called by the contract owner if the `controlAddress` has called the
    * pool contract's {registerControlAddress} function and the `setControlAddress`
    * function of the `DEPOSIT_CONTRACT` before and the `controlAddress` has not
    * cancelled the handover by calling {unregisterControlAddress}. The joining
    * validator's deposit is treated as if staked by the `controlAddress`. The
    * `controlAddress` is restored in the `DEPOSIT_CONTRACT` when the validator
    * leaves the pool later.
    */
    function joinPool(
        bytes calldata blsPubKey
    ) public virtual;

    /**
    * @dev Release the validator identified by `blsPubKey` from the staking pool.
    *It must be called by the validator's original control address.
    *
    * If there are pending withdrawals from the validator's deposit, the validator
    * can't proceed with leaving, but no further deposit withdrawals will be initiated
    * by delegators' unstaking requests. As soon as the unbonding period of the last
    * pending deposit withdrawal is over, {leavePool} must be called again to proceed
    * with one of the following scenarios:
    * 
    * 1. If the caller's current stake is higher than the validator's current deposit
    * then the caller can withdraw the surplus after the unbonding period.
    *
    * 2. If the validator's deposit is higher than the caller's stake then the deposit
    * is reduced to match the caller's stake unless it becomes lower than the minimum
    * deposit required and reverts the transaction. If {leavePool} was successful the
    * control address must call {BaseDelegation-completeLeaving} after the unbonding
    * period to withdraw the unstaked surplus from the validator's deposit and to
    * distribute it among the validators remaining in the pool.
    */
    function leavePool(
        bytes calldata blsPubKey
    ) public virtual;

    /**
    * @dev Append an entry to the staking pool's list of validators. Use the pool
    * contract's owner address as reward address and control address in the entry.
    * Register a validator by transferring the stake available in the contract
    * balance to `DEPOSIT_CONTRACT`.
    *
    * Emit {ValidatorJoined} containing the `blsPubKey` of the validator.
    *
    * Revert with {DepositContractCallFailed} containing the call data and the
    * error data returned if the call to the `DEPOSIT_CONTRACT` fails.
    */
    function _depositAndAddToPool(
        bytes calldata blsPubKey,
        bytes calldata peerId,
        bytes calldata signature
    ) internal virtual {
        BaseDelegationStorage storage $ = _getBaseDelegationStorage();
        if (!$.activated)
            $.activated = true;
        uint256 availableStake = $.nonRewards - $.withdrawnDepositedClaims - $.nonDepositedClaims;

        require($.validators.length < MAX_VALIDATORS, TooManyValidators(blsPubKey));
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

        $.nonRewards = $.withdrawnDepositedClaims + $.nonDepositedClaims;
        emit ValidatorJoined(blsPubKey);
    }

    /**
    * @dev Append an entry to the staking pool's list of validators to record
    * the joining validator's deposit, current reward address and control address.
    * Set the validator's reward address to the pool contact's address. Increase
    * all validators' deposit by the stake currently available in the contract
    * balance.
    *
    * Emit {ValidatorJoined} containing the `blsPubKey` of the validator.
    *
    * Revert with {DepositContractCallFailed} containing the call data and
    * the error data returned if the call to the `DEPOSIT_CONTRACT` fails.
    *
    * Revert with {ValidatorAlreadyAdded} containing `blsPubKey` if the
    * validator identified by it has already been added to the staking pool.
    */
    function _addToPool(
        bytes calldata blsPubKey,
        address controlAddress
    ) internal onlyOwner virtual {
        BaseDelegationStorage storage $ = _getBaseDelegationStorage();
        if (!$.activated)
            $.activated = true;
        // the original control address can't cancel the handover after this point
        delete $.controlAddresses[blsPubKey];
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

        require($.validators.length < MAX_VALIDATORS, TooManyValidators(blsPubKey));
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

        uint256 availableStake = $.nonRewards - $.withdrawnDepositedClaims - $.nonDepositedClaims;
        if (availableStake > 0)
            _increaseDeposit(availableStake);
    }

    /**
    * @dev Return if there are pending withdrawals from the validator's deposit
    * and set the {ValidatorStatus} to `RequestedToLeave` to prevent that new
    * unstake requests delay the validator's leaving.
    *
    * Emit {ValidatorLeaving} containing the `blsPubKey` of the validator.
    *
    * Revert with {ValidatorNotFound} containing `blsPubKey` if the validator
    * identified by it is not part of the staking pool.
    */
    function _preparedToLeave(
        bytes calldata blsPubKey
    ) internal virtual returns(bool prepared) {
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
    * @dev Unstake the difference between the `leavingStake` of the original
    * control address and the validator's current deposit. If there is no
    * difference call {_removeFromPool} to remove the validator.
    *
    * Revert with {DepositContractCallFailed} containing the call data and the
    * error data returned if the call to the `DEPOSIT_CONTRACT` fails.
    *
    * Revert with {ValidatorNotFound} containing `blsPubKey` if the validator
    * identified by it is not part of the staking pool.
    *
    * Revert with {InvalidCaller} containing the address of the caller and the
    * address of that validator's original control address that was expected to
    * call the function.
    *
    * Revert with {InvalidValidatorStatus} containing the validator's `blsPubKey`,
    * its current status and the expected status.
    *
    * Revert with {WithdrawalsPending} containing the `blsPubKey` and the total
    * amount of pending withdrawals from the validator's deposit that prevent
    * the validator's leaving.
    */
    function _initiateLeaving(
        bytes calldata blsPubKey,
        uint256 leavingStake
    ) internal virtual {
        BaseDelegationStorage storage $ = _getBaseDelegationStorage();
        uint256 i = $.validatorIndex[blsPubKey];
        require(i-- > 0, ValidatorNotFound(blsPubKey));
        require(
            _msgSender() == $.validators[i].controlAddress,
            InvalidCaller(_msgSender(), $.validators[i].controlAddress)
        );
        require(
            $.validators[i].status == ValidatorStatus.RequestedToLeave,
            InvalidValidatorStatus(
                blsPubKey,
                $.validators[i].status,
                ValidatorStatus.RequestedToLeave
            )
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
            _removeFromPool(i);
    }

    /**
    * @dev Try to withdraw the deposit unstaked in {_initiateLeaving} and if
    * successful i.e. the unbonding period is over, distribute the withdrawn
    * amount among the other validators to increase their deposit. If there is
    * no unstaked deposit to withdraw call {_removeFromPool} to remove the validator.
    *
    * Revert with {DepositContractCallFailed} containing the call data and the
    * error data returned if the call to the `DEPOSIT_CONTRACT` fails.
    *
    * Revert with {ValidatorNotFound} containing `blsPubKey` if the validator
    * identified by it is not part of the staking pool.
    *
    * Revert with {InvalidCaller} containing the address of the caller and the
    * address of that validator's original control address that was expected to
    * call the function.
    *
    * Revert with {InvalidValidatorStatus} containing the validator's `blsPubKey`,
    * its current status and the expected status.
    */
    function completeLeaving(bytes calldata blsPubKey) public virtual {
        BaseDelegationStorage storage $ = _getBaseDelegationStorage();
        uint256 i = $.validatorIndex[blsPubKey];
        require(i-- > 0, ValidatorNotFound(blsPubKey));
        require(
            _msgSender() == $.validators[i].controlAddress,
            InvalidCaller(_msgSender(), $.validators[i].controlAddress)
        );
        require(
            $.validators[i].status == ValidatorStatus.ReadyToLeave,
            InvalidValidatorStatus(
                blsPubKey,
                $.validators[i].status, ValidatorStatus.ReadyToLeave
            )
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
            // the pending withdrawal has been completed and must be removed
            // from the pendingRebalancedDeposit regardless of how much of it
            // can de deposited with other validators in _increaseDeposit 
            $.pendingRebalancedDeposit -= $.validators[i].pendingWithdrawals;
            $.validators[i].pendingWithdrawals = 0;
            _increaseDeposit(amount);
        } else
            revert UnstakedDepositMismatch(
                blsPubKey,
                amount,
                $.validators[i].pendingWithdrawals
            );
        _removeFromPool(i);
    }

    /**
    * @dev Set the validator's reward address and control address to the
    * original value and remove the entry from the validator list.
    *
    * Emit {ValidatorLeft} containing the `blsPubKey` of the validator.
    *
    * Revert with {DepositContractCallFailed} containing the call data and
    * the error data returned if the call to the `DEPOSIT_CONTRACT` fails.
    *
    * Revert with {DepositContractCallFailed} containing the call data and
    * the error data returned if the call to the `DEPOSIT_CONTRACT` fails.
    */
    function _removeFromPool(uint256 index) internal virtual {
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
    * @dev Return whether the validator has any pending withdrawals. The withdrawal
    * required to match the stake of the control address when the validator's `status`
    * is `ReadyToLeave` does not count.
    *
    * Revert with {ValidatorNotFound} containing `blsPubKey` if the validator
    * identified by it is not part of the staking pool.
    */
    function pendingWithdrawals(bytes calldata blsPubKey) public virtual view returns(bool) {
        BaseDelegationStorage storage $ = _getBaseDelegationStorage();
        uint256 i = $.validatorIndex[blsPubKey];
        require(i-- > 0, ValidatorNotFound(blsPubKey));
        return 
            $.validators[i].status < ValidatorStatus.ReadyToLeave &&
            $.validators[i].pendingWithdrawals > 0;
    }

    /**
    * @dev Return the `total` pending withdrawals of all validators in the pool.
    * The withdrawal necessary to match the stake of the control address when the
    * validator's `status` is `ReadyToLeave` does not count.
    */
    function totalPendingWithdrawals() public virtual view returns(uint256 total) {
        BaseDelegationStorage storage $ = _getBaseDelegationStorage();
        uint256 len = $.validators.length;
        for(uint256 i = 0; i < len; i++)
            if ($.validators[i].status < ValidatorStatus.ReadyToLeave)
                total += $.validators[i].pendingWithdrawals;
    }

    /**
    * @dev Topup the deposits by `amount` distributed in proportion to the validators'
    * current deposit.
    *
    * Revert with {DepositContractCallFailed} containing the call data and the error
    * data returned if the call to the `DEPOSIT_CONTRACT` fails.
    */
    function _increaseDeposit(uint256 amount) internal virtual {
        BaseDelegationStorage storage $ = _getBaseDelegationStorage();
        uint256[] memory contribution = new uint256[]($.validators.length);
        uint256 totalContribution;
        uint256 len = $.validators.length;
        for (uint256 i = 0; i < len; i++)
            if ($.validators[i].status < ValidatorStatus.ReadyToLeave) {
                contribution[i] = $.validators[i].futureStake;
                totalContribution += contribution[i];
            }
        uint256 totalDeposited;
        for (uint256 i = 0; i < len; i++)
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
    * @dev Unstake `amount` from the deposits in proportion to the validators'
    * surplus deposit exceeding the required minimum stake, unless the contract
    * balance reserved for `nonRewards` plus the total surplus of all validators'
    * deposits is less than the claims already unstaked plus the `amount` to be
    * unstaked. In the latter case, unstake the last validator's entire deposit
    * and reduce the `amount` to be unstaked until the remaining `amount` is
    * fully covered by the unstaked deposit. 
    *
    * Revert with {DepositContractCallFailed} containing the call data and the
    * error data returned if the call to the `DEPOSIT_CONTRACT` fails.
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
        uint256 len = $.validators.length;
        for (uint256 i = 0; i < len; i++)
            if ($.validators[i].status == ValidatorStatus.Active) {
                contribution[i] = $.validators[i].futureStake - minimumDeposit;
                totalContribution += contribution[i];
            }
        uint256 j = len;
        while (
            j > 0 &&
            (
                $.nonRewards + totalContribution < 
                $.withdrawnDepositedClaims + $.nonDepositedClaims + amount
            )
        )
            if ($.validators[--j].status == ValidatorStatus.Active) {
                $.validators[j].pendingWithdrawals +=
                    $.validators[j].futureStake;
                callData =
                    abi.encodeWithSignature("unstake(bytes,uint256)",
                        $.validators[j].blsPubKey,
                        $.validators[j].futureStake
                    );
                (success, data) = DEPOSIT_CONTRACT.call(callData);
                require(success, DepositContractCallFailed(callData, data));
                $.validators[j].status = ValidatorStatus.FullyUndeposited;
                totalContribution -= contribution[j];
                contribution[j] = 0;
                if (amount > $.validators[j].futureStake) {
                    amount -= $.validators[j].futureStake;
                    $.validators[j].futureStake = 0;
                }
                else {
                    // store the excess deposit withdrawn that was not requested
                    // by the unstaking delegator so that we can distuingish it
                    // later from the claimable amount unstaked by the delegator
                    $.validators[j].futureStake -= amount;
                    $.pendingRebalancedDeposit += $.validators[j].futureStake;
                    return;
                }
            }
        // if this condition is met there are no validators that can be fully
        // undeposited but the balance must contain sufficient stake that was
        // not deposited before
        if (totalContribution < amount) {
            $.nonDepositedClaims += amount - totalContribution;
            amount = totalContribution;
        }
        uint256[] memory undeposited = new uint256[]($.validators.length);
        uint256 totalUndeposited;
        for (uint256 i = 0; i < len; i++)
            if (contribution[i] > 0) {
                undeposited[i] = amount * contribution[i] / totalContribution;
                totalUndeposited += undeposited[i];
            }
        // rounding error that was not unstaked from the deposits but can be
        // claimed after the unbonding period
        uint256 delta = amount - totalUndeposited;
        // increment the values to be undeposited unless they equal the respective
        // validator's contribution i.e. the validator can't contribute more, until
        // the delta bounded by the number of contributing validators becomes zero
        for (uint256 i = 0; i < len; i++) {
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
    *
    * Revert with {DepositContractCallFailed} containing the call data and the
    * error data returned if the call to the `DEPOSIT_CONTRACT` fails.
    */
    function _withdrawDeposit() internal virtual returns(uint256 total) {
        BaseDelegationStorage storage $ = _getBaseDelegationStorage();
        uint256 len = $.validators.length;
        // we accept the constant gas wasted on every validator whose
        // unbonding period is not over, i.e. the withdrawn amount is zero
        for (uint256 j = 1; j <= len; j++) {
            uint256 i = len - j;
            if (
                $.validators[i].pendingWithdrawals > 0 &&
                $.validators[i].status != ValidatorStatus.ReadyToLeave
            ) {
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
                $.validators[i].pendingWithdrawals -= amount;
                total += amount;
            }
            if ($.validators[i].status == ValidatorStatus.FullyUndeposited) {
                // when the function was called pendingWithdrawals contained
                // the whole withdrawn amount i.e. the users' unstaked funds
                // plus the surplus futureStake that was withdrawn, therefore
                // pendingWithdrawal now must be zero
                assert($.validators[i].pendingWithdrawals == 0);
                // the surplus futureStake that was withdrawn alongside the
                // users' unstaked funds is now part of total, but it should be
                // deposited again and not added to withdrawnDepositedClaims
                // when the call returns
                total -= $.validators[i].futureStake;
                $.pendingRebalancedDeposit -= $.validators[i].futureStake;
                // the fraction of the futureStake that can not be deposited
                // again remains part of the contract's balance and nonRewards
                _increaseDeposit($.validators[i].futureStake);
                $.validators[i].futureStake = 0;
                _removeFromPool(i);
            }
        }
    }

    /**
    * @dev Return the deposit of the validator identified by `blsPubKey` after
    * applying all pending changes to it. If the validator is not part of the
    * staking pool, retrieve its deposit from `DEPOSIT_CONTRACT`.
    *
    * Revert with {DepositContractCallFailed} containing the call data and the
    * error data returned if the call to the `DEPOSIT_CONTRACT` fails.
    */
    function getDeposit(bytes calldata blsPubKey) public virtual view returns(uint256) {
        BaseDelegationStorage storage $ = _getBaseDelegationStorage();
        uint256 i = $.validatorIndex[blsPubKey];
        if (i > 0)
            return $.validators[--i].status != ValidatorStatus.FullyUndeposited ?
                $.validators[i].futureStake :
                0;
        bytes memory callData =
            abi.encodeWithSignature("getFutureStake(bytes)", blsPubKey);
        (bool success, bytes memory data) = DEPOSIT_CONTRACT.staticcall(callData);
        require(success, DepositContractCallFailed(callData, data));
        return abi.decode(data, (uint256));
    }

    // ************************************************************************
    // 
    //                            STAKE AND REWARDS
    // 
    // ************************************************************************

    /// @dev The minimum amount of ZIL that can be delegated in a single transaction.
    uint256 public constant MIN_DELEGATION = 100 ether;

    /**
    * @dev Increase `nonRewards` to reflect the amount of stake withdrawn from
    * the validators' deposits and added to the contract's balance.
    *
    * Revert with {InvalidCaller} containing the sender if it's not `DEPOSIT_CONTRACT`.
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
    * @dev Return whether the first validator has already been deposited.
    * In case it is `false` the staking pool is in the fundraising phase,
    * collecting delegated stake to deposit its first validator node later.
    */
    function _isActivated() internal virtual view returns(bool) {
        BaseDelegationStorage storage $ = _getBaseDelegationStorage();
        return $.activated;
    }

    /**
    * @dev Increase the `nonRewards` portion of the balance by the `amount` either
    * staked by a delegator or staked out of the rewards in the contract balance.
    */
    function _increaseStake(uint256 amount) internal {
        BaseDelegationStorage storage $ = _getBaseDelegationStorage();
        $.nonRewards += amount;
    }

    /// @inheritdoc IDelegation
    function getMinDelegation() public virtual view returns(uint256) {
        return MIN_DELEGATION;
    }

    /// @inheritdoc IDelegation
    function stake() external virtual payable;

    /// @inheritdoc IDelegation
    function unstake(uint256) external virtual returns(uint256);

    /**
    * @inheritdoc IDelegation
    *
    * @dev Emit {Claimed} containing the caller address and the total amount transferred.
    *
    * Revert with {TransferFailed} containing the caller address and the amount
    * to be transferred if the transfer failed.
    */
    function claim() public virtual whenNotPaused {
        uint256 total = _dequeueWithdrawals();
        if (total == 0)
            return;
        BaseDelegationStorage storage $ = _getBaseDelegationStorage();
        // withdraw the unstaked deposit once the unbonding period is over
        uint256 withdrawn = _withdrawDeposit();
        $.withdrawnDepositedClaims += withdrawn;
        if ($.withdrawnDepositedClaims >= total) 
            // total is part of withdrawn now or it has already been withdrawn before
            // i.e. in both cases it has already been added to withdrawnDepositedClaims
            $.withdrawnDepositedClaims -= total;
        else {
            $.nonDepositedClaims -= total - $.withdrawnDepositedClaims;
            $.withdrawnDepositedClaims = 0;
        }
        $.nonRewards -= total;
        (bool success, ) = _msgSender().call{
            value: total
        }("");
        require(success, TransferFailed(_msgSender(), total));
        emit Claimed(_msgSender(), total, "");
    }

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

    /**
    * @inheritdoc IDelegation
    *
    * @dev Revert with {DepositContractCallFailed} containing the call data
    * and the error data returned if the call to the `DEPOSIT_CONTRACT` fails.
    */
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
    * @dev Return the part of the pool's balance that does not represent
    * rewards accrued due to the validators' deposits. 
    */
    function getNonRewards() public view returns(uint256) {
        BaseDelegationStorage storage $ = _getBaseDelegationStorage();
        return $.nonRewards;
    }

    /// @inheritdoc IDelegation
    function getStake() public virtual view returns(uint256 total) {
        BaseDelegationStorage storage $ = _getBaseDelegationStorage();
        total = $.nonRewards;
        uint256 len = $.validators.length;
        for (uint256 i = 0; i < len; i++)
            if ($.validators[i].status < ValidatorStatus.ReadyToLeave)
                total += $.validators[i].futureStake;
        total += $.pendingRebalancedDeposit;
        total -= $.withdrawnDepositedClaims;
        total -= $.nonDepositedClaims;
    }

    // ************************************************************************
    // 
    //                                 COMMISSION
    // 
    // ************************************************************************

    /// @dev A power of 10 that determines the precision of the commission rate.
    uint256 public constant DENOMINATOR = 10_000;

    /// @dev The minimum number of blocks between changes to the commission rate.
    uint256 public constant DELAY = 86_400;

    /// @dev Emitted when `oldReceiver` of the commission is changed to `newReceiver`.
    event CommissionReceiverChanged(address indexed oldReceiver, address indexed newReceiver);

    /**
    * @dev Return the commission rate multiplied by `DENOMINATOR`.
    */
    function getCommissionNumerator() public virtual view returns(uint256) {
        BaseDelegationStorage storage $ = _getBaseDelegationStorage();
        return $.commissionNumerator;
    }

    /**
    * @dev Return the block height of the last change to the commission rate.
    */
    function getLastCommissionChange() public virtual view returns(uint256) {
        BaseDelegationStorage storage $ = _getBaseDelegationStorage();
        return $.lastCommissionChange;
    }

    /**
    * @dev Set the commission rate to `_commissionNumerator / DENOMINATOR`. It
    * must be called by the contract owner.
    *
    * Revert with {InvalidCommissionChange} containing `_commissionNumerator` if
    * it's greater than or equal to the {DENOMINATOR}. If the pool has any stake,
    * also revert if the absolute change is greater than or equal to 2 percentage
    * points or the last change is not at least {DELAY} blocks old.
    */
    function setCommissionNumerator(uint256 _commissionNumerator) public virtual onlyOwner {
        require(
            _commissionNumerator < DENOMINATOR, 
            InvalidCommissionChange(_commissionNumerator)
        );
        BaseDelegationStorage storage $ = _getBaseDelegationStorage();
        uint256 delta =
            _commissionNumerator > $.commissionNumerator ?
            _commissionNumerator - $.commissionNumerator :
            $.commissionNumerator - _commissionNumerator;
        require(
            getStake() == 0 ||
            delta < 2 * DENOMINATOR / 100 &&
            block.number - $.lastCommissionChange >= DELAY,
            InvalidCommissionChange(_commissionNumerator)
        ); 
        emit CommissionChanged($.commissionNumerator, _commissionNumerator);
        $.commissionNumerator = _commissionNumerator;
        $.lastCommissionChange = block.number;
    }

    /// @inheritdoc IDelegation
    function getCommission() public virtual view returns(
        uint256 numerator,
        uint256 denominator
    ) {
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
    * @dev Set the address the commission is to be transferred to. It must be
    * called by the contract owner.
    *
    * Throw `ZeroAddressNotAllowed` if the zero address was passed as argument.
    */
    function setCommissionReceiver(address _commissionReceiver) public virtual onlyOwner {
        require(_commissionReceiver != address(0), ZeroAddressNotAllowed());
        BaseDelegationStorage storage $ = _getBaseDelegationStorage();
        emit CommissionReceiverChanged($.commissionReceiver, _commissionReceiver);
        $.commissionReceiver = _commissionReceiver;
    }

    /// @inheritdoc IDelegation
    function collectCommission() public virtual;

}
