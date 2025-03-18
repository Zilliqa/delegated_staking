// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity ^0.8.28;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {BaseDelegation} from "src/BaseDelegation.sol";
import {IDelegation} from "src/IDelegation.sol";

// keccak256(abi.encode(uint256(keccak256("zilliqa.storage.NonLiquidDelegation")) - 1)) & ~bytes32(uint256(0xff))
bytes32 constant NONLIQUID_VARIANT = 0x66c8dc4f9c8663296597cb1e39500488e05713d82a9122d4f548b19a70fc2000;

/**
 * @notice The non-liquid variant of the stake delegation contract. It records
 * every change to the delegated stake in the {Staking} history. Based on the
 * entries in the history it calculates the rewards due to each delegator.
 *
 * @dev Every time a delegator stakes or unstakes, the stake proportions of all
 * delegators change. It is essential to record the rewards accrued between two
 * {Staking} events in order to be able to calculate each delegator's share of
 * the rewards during that period. Note that the rewards accrued since the last
 * {Staking} event are in the contract balance which is increasing in every block.
 */
contract NonLiquidDelegation is IDelegation, BaseDelegation {
    using SafeCast for int256;

    // ************************************************************************
    // 
    //                                 STATE
    // 
    // ************************************************************************

    /**
    * @dev `staker` is the address of the delegator who staked or unstaked, after
    * which the delegator had `amount` and the pool had `total` staked ZIL, and
    * pool earned taxed `rewards` since the previous {Staking} event or since its
    * launch in case it is the first event.
    */
    struct Staking {
        address staker;
        uint256 amount;
        uint256 total;
        uint256 rewards;
    }

    /**
    * @dev {NonLiquidDelegation} has the following state variables:
    *
    * - `stakings` stores the append-only history of {Staking} events.
    *
    * - `stakingIndices` maps delegator addresses to arrays of indices in
    * `stakings` in ascending order that the respective delegator performed.
    *
    * - `firstStakingIndex` is the first item in a validator's `stakingIndices`
    * starting from which the outstanding rewards are calculated.
    *
    * - `availableTaxedRewards` is the portion of a delegator's rewards from
    * which the commission was already deducted.
    *
    * - `lastTaxedStakingIndex` is the last index in the staking history whose
    * rewards have been included in the delegator's `availableTaxedRewards`.
    *
    * - `taxedSinceLastStaking` are a validator's taxed rewards accrued since
    * the last entry in the {Staking} history.
    *
    * - `historicalTaxedRewards` is the portion of the total rewards in the
    * contract's balance that was taxed and stored in the {Staking} history and
    * has not been withdrawn or staked yet. `taxedRewards` is the portion of the
    * total rewards in the contract's balance from which the commission has been
    * already deducted. Note that `taxedRewards >= historicalTaxedRewards`.
    *
    * - `newAddress` maps delegator addressed to another address that replaces
    * them as soon as that other address calls {replaceOldAddress}.
    *
    * - `roundingErrors` maps delegator addresses to remainders of integer
    * divisions smaller than 1 `wei` scaled up by a factor of `10**18` that
    * have not been withdrawn as rewards by the respective delegators.
    * `totalRoundingErrors` holds the sum of all remainders.
    */
    /// @custom:storage-location erc7201:zilliqa.storage.NonLiquidDelegation
    struct NonLiquidDelegationStorage {
        Staking[] stakings;
        mapping(address => uint64[]) stakingIndices;
        mapping(address => uint64) firstStakingIndex;
        mapping(address => uint256) availableTaxedRewards;
        mapping(address => uint64) lastTaxedStakingIndex;
        mapping(address => uint256) taxedSinceLastStaking;
        int256 historicalTaxedRewards;
        mapping(address => address) newAddress;
        mapping(address => uint256) roundingErrors;
        uint256 totalRoundingErrors;
        int256 taxedRewards;
    }

    // solhint-disable const-name-snakecase, private-vars-leading-underscore
    bytes32 private constant NonLiquidDelegationStorageLocation = NONLIQUID_VARIANT;

    function _getNonLiquidDelegationStorage() private pure returns (NonLiquidDelegationStorage storage $) {
        assembly {
            $.slot := NonLiquidDelegationStorageLocation
        }
    }

    // ************************************************************************
    // 
    //                                 VERSION
    // 
    // ************************************************************************

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
    * @dev Let {BaseDelegation} migrate `fromVersion` to the current `VERSION`.
    */
    function reinitialize(uint64 fromVersion) public reinitializer(VERSION) {
        _migrate(fromVersion);
        NonLiquidDelegationStorage storage $ = _getNonLiquidDelegationStorage();
        if (fromVersion < encodeVersion(0, 7, 0))
            require($.stakings.length == 0, IncompatibleVersion(fromVersion));
    }

    /**
    * @dev Initialize the base contracts.
    */
    function initialize(address initialOwner) public initializer {
        __BaseDelegation_init(initialOwner);
    }

    /// @inheritdoc BaseDelegation
    function variant() public override pure returns(bytes32) {
        return NONLIQUID_VARIANT;
    }

    // ************************************************************************
    // 
    //                                 VALIDATORS
    // 
    // ************************************************************************

    /// @inheritdoc BaseDelegation
    function depositFromPool(
        bytes calldata blsPubKey,
        bytes calldata peerId,
        bytes calldata signature
    ) public payable override onlyOwner {
        _increaseStake(msg.value);
        _depositAndAddToPool(
            blsPubKey,
            peerId,
            signature
        );
        // the owner's deposit must also be recorded as staking otherwise
        // the owner would not benefit from the rewards accrued by the deposit
        if (msg.value > 0)
            _appendToHistory(int256(msg.value), _msgSender());
    }

    /// @inheritdoc BaseDelegation
    function joinPool(
        bytes calldata blsPubKey,
        address controlAddress
    ) public override onlyOwner {
        // when the validator joins, all available stake that is not deposited
        // yet will be added to the validator's deposit, but the stake appended
        // to the history shall only be the validator's own deposit before joining
        uint256 depositBeforeJoining = getDeposit(blsPubKey);
        _addToPool(blsPubKey, controlAddress);
        // the node's deposit must also be recorded in the staking history otherwise
        // its owner would not benefit from the rewards accrued due to the deposit
        _appendToHistory(int256(depositBeforeJoining), controlAddress);
    }

    /**
    * @inheritdoc BaseDelegation
    *
    * @dev Revert with {StakerNotFound} containing the caller address if it can
    * not be found among the stakers.
    */
    function leavePool(
        bytes calldata blsPubKey
    ) public override {
        if (!_preparedToLeave(blsPubKey))
            return;
        NonLiquidDelegationStorage storage $ = _getNonLiquidDelegationStorage();
        require($.stakingIndices[_msgSender()].length > 0, StakerNotFound(_msgSender()));
        uint256 amount = $.stakings[
            $.stakingIndices[_msgSender()][$.stakingIndices[_msgSender()].length - 1]
        ].amount;
        _appendToHistory(-int256(amount), _msgSender());
        uint256 currentDeposit = getDeposit(blsPubKey);
        if (amount > currentDeposit) {
            _initiateLeaving(blsPubKey, currentDeposit);
            _enqueueWithdrawal(amount - currentDeposit);
            _decreaseDeposit(amount - currentDeposit);
        } else
            _initiateLeaving(blsPubKey, amount);
    }

    // ************************************************************************
    // 
    //                                 STAKE
    // 
    // ************************************************************************

    /**
    * @dev Return the history of `stakings`.
    * See {NonLiquidDelegationStorage}.
    */
    function getStakingHistory() public view returns(Staking[] memory) {
        NonLiquidDelegationStorage storage $ = _getNonLiquidDelegationStorage();
        return $.stakings;
    }

    /**
    * @dev Return the data stored about the caller as delegator.
    * See {NonLiquidDelegationStorage}.
    */
    function getStakingData() public view returns(
        uint64[] memory stakingIndices,
        uint64 firstStakingIndex,
        uint256 availableTaxedRewards,
        uint64 lastTaxedStakingIndex,
        uint256 taxedSinceLastStaking
    ) {
        NonLiquidDelegationStorage storage $ = _getNonLiquidDelegationStorage();
        stakingIndices = $.stakingIndices[_msgSender()];
        firstStakingIndex = $.firstStakingIndex[_msgSender()];
        availableTaxedRewards = $.availableTaxedRewards[_msgSender()];
        lastTaxedStakingIndex = $.lastTaxedStakingIndex[_msgSender()];
        taxedSinceLastStaking = $.taxedSinceLastStaking[_msgSender()];
    }

    /**
    * @dev Return the amount currently delegated by the caller.
    */
    function getDelegatedAmount() public view returns(uint256 result) {
        NonLiquidDelegationStorage storage $ = _getNonLiquidDelegationStorage();
        uint64[] storage stakingIndices = $.stakingIndices[_msgSender()];
        if (stakingIndices.length > 0)
            result = $.stakings[stakingIndices[stakingIndices.length - 1]].amount;
    }

    /**
    * @dev Return the total amount of ZIL delegated to the staking pool.
    */
    function getDelegatedTotal() public view returns(uint256 result) {
        NonLiquidDelegationStorage storage $ = _getNonLiquidDelegationStorage();
        if ($.stakings.length > 0)
            result = $.stakings[$.stakings.length - 1].total;
    }

    /**
    * @dev Return which address is supposed to replace the caller as delegator.
    */
    function getNewAddress() public view returns(address) {
        NonLiquidDelegationStorage storage $ = _getNonLiquidDelegationStorage();
        return $.newAddress[_msgSender()];
    }

    /**
    * @dev Set an address that is supposed to replace the caller as delegator.
    * The previously set address is overwritten or deleted if `to == address(0)`.
    *
    * Revert with {StakerNotFound} containing the caller address if it can't be
    * found among the stakers.
    *
    * Revert with {StakerAlreadyExists} containing the `to` address if it is
    * one of the stakers. The new address must be one that has not been used
    * for staking with the pool yet.
    */
    function setNewAddress(address to) public {
        NonLiquidDelegationStorage storage $ = _getNonLiquidDelegationStorage();
        require(
            $.stakingIndices[_msgSender()].length != 0,
            StakerNotFound(_msgSender())
        );
        require(
            $.stakingIndices[to].length == 0,
            StakerAlreadyExists(to)
        );
        $.newAddress[_msgSender()] = to;
    }

    /**
    * @dev The caller address replaces the `old` delegator address which
    * nominated the caller using {setNewAddress}.
    *
    * Revert with {InvalidCaller} containing the caller address if the function
    * was not called from the address the `old` address set in {setNewAddress}. 
    */
    function replaceOldAddress(address old) public {
        NonLiquidDelegationStorage storage $ = _getNonLiquidDelegationStorage();
        address sender = _msgSender();
        require(
            sender == $.newAddress[old],
            InvalidCaller(sender, $.newAddress[old])
        );
        /* keep the original staking addresses to save gas
        for (uint64 i = 0; i < $.stakingIndices[old].length; i++)
            $.stakings[$.stakingIndices[old][i]].staker = sender;
        */
        $.stakingIndices[sender] = $.stakingIndices[old];
        delete $.stakingIndices[old];
        $.firstStakingIndex[sender] = $.firstStakingIndex[old];
        $.availableTaxedRewards[sender] = $.availableTaxedRewards[old];
        $.lastTaxedStakingIndex[sender] = $.lastTaxedStakingIndex[old];
        $.taxedSinceLastStaking[sender] = $.taxedSinceLastStaking[old];
        delete $.firstStakingIndex[old];
        delete $.availableTaxedRewards[old];
        delete $.lastTaxedStakingIndex[old];
        delete $.taxedSinceLastStaking[old];
        delete $.newAddress[old];
    } 

    /**
    * @inheritdoc IDelegation
    *
    * @dev Emit {Staked} containing the caller address and the amount delegated.
    */
    function stake() public override(BaseDelegation, IDelegation) payable whenNotPaused {
        _increaseStake(msg.value);
        _increaseDeposit(msg.value);
        _appendToHistory(int256(msg.value), _msgSender());
        emit Staked(_msgSender(), msg.value, "");
    }

    /**
    * @inheritdoc IDelegation
    *
    * @dev Emit {Unstaked} containing the caller address and the `value` unstaked.
    */
    function unstake(uint256 value)
        public
        override(BaseDelegation, IDelegation)
        whenNotPaused
        returns(uint256 amount)
    {
        _appendToHistory(-int256(value), _msgSender());
        _decreaseDeposit(uint256(value));
        _enqueueWithdrawal(value);
        emit Unstaked(_msgSender(), value, "");
        return value;
    }

    /**
    * @dev Append an entry to the {Staking} history based on the currently
    * staked (positive) or unstaked (negative) `value`.
    *
    * Revert with {DelegatedAmountTooLow} containing `value` if it's lower
    * than `MIN_DELEGATION`.
    *
    * Revert with {RequestedAmountTooHigh} containing the negative `value` and the
    * caller's stake if the `value` to be unstaked is greater than the current stake.
    */
    function _appendToHistory(int256 value, address staker) internal {
        if (value > 0)
            require(uint256(value) >= MIN_DELEGATION, DelegatedAmountTooLow(uint256(value)));
        NonLiquidDelegationStorage storage $ = _getNonLiquidDelegationStorage();
        int256 amount = value;
        if ($.stakingIndices[staker].length > 0)
            amount += int256($.stakings[
                $.stakingIndices[staker][$.stakingIndices[staker].length - 1]
            ].amount);
        if (value < 0)
            require(
                amount >= 0,
                RequestedAmountTooHigh(
                    uint256(-value),
                    $.stakings[
                        $.stakingIndices[staker][$.stakingIndices[staker].length - 1]
                    ].amount
                )
            );
        uint256 newRewards;
        // no rewards before the first staker is added
        if ($.stakings.length > 0) {
            value += int256($.stakings[$.stakings.length - 1].total);
            newRewards = ($.taxedRewards - $.historicalTaxedRewards).toUint256();
            newRewards += _taxRewards((int256(getRewards()) - $.taxedRewards).toUint256());
        }
        $.historicalTaxedRewards = int256(getRewards());
        $.taxedRewards = $.historicalTaxedRewards;
        $.stakings.push(Staking(staker, uint256(amount), uint256(value), newRewards));
        $.stakingIndices[staker].push(uint64($.stakings.length - 1));
    }

    // ************************************************************************
    // 
    //                            REWARDS, COMMISSION
    // 
    // ************************************************************************

    /**
    * @dev Emit the event when `reward` was transferred to `delegator`. 
    */
    event RewardPaid(address indexed delegator, uint256 reward);

    /**
    * @dev Return the number of `additionalSteps` that would be needed in
    * {withdrawAllRewards} to withdraw all rewards the caller is entitled to.
    * Note that this number of steps may be too high to withdraw at once, in
    * which case the rewards can be withdrawn in multiple transactions using a
    * lower number of steps each.
    */
    function getAdditionalSteps() public view returns(uint256) {
        NonLiquidDelegationStorage storage $ = _getNonLiquidDelegationStorage();
        return $.stakings.length - $.lastTaxedStakingIndex[_msgSender()] - 1;
    }

    /**
    * @dev Return the taxed rewards the caller can withdraw by traversing the
    * {Staking} history in `1 + additionalSteps`.
    */
    function rewards(uint64 additionalSteps) public view returns(uint256) {
        NonLiquidDelegationStorage storage $ = _getNonLiquidDelegationStorage();
        (uint256 resultInTotal, , , , ) = _rewards(additionalSteps);
        resultInTotal -= $.taxedSinceLastStaking[_msgSender()];
        return
            resultInTotal +
            $.availableTaxedRewards[_msgSender()];
    }

    /**
    * @dev Return the total amount of taxed rewards the caller is eligible to withdraw.
    */
    function rewards() public view returns(uint256) {
        NonLiquidDelegationStorage storage $ = _getNonLiquidDelegationStorage();
        (uint256 resultInTotal, , , , ) = _rewards();
        resultInTotal -= $.taxedSinceLastStaking[_msgSender()];
        return
            resultInTotal +
            $.availableTaxedRewards[_msgSender()];
    }

    /**
    * @dev Deduct the commission from the yet untaxed rewards and transfer it to
    * the configured commission receiver address.
    *
    * Emit {CommissionPaid} containing the receiver address and the amount transferred.
    *
    * Revert with {TransferFailed} containing the reciever address and the amount
    * to be transferred if the transfer failed.
    */
    function _taxRewards(uint256 untaxedRewards) internal returns (uint256) {
        uint256 commission = untaxedRewards * getCommissionNumerator() / DENOMINATOR;
        if (commission == 0)
            return untaxedRewards;
        // commissions are not subject to the unbonding period
        (bool success, ) = getCommissionReceiver().call{
            value: commission
        }("");
        require(success, TransferFailed(getCommissionReceiver(), commission));
        emit CommissionPaid(getCommissionReceiver(), commission);
        return untaxedRewards - commission;
    }

    /**
    * @dev Withdraw the taxed rewards of the caller calculated by traversing the
    * {Staking} history in `1 + additionalSteps` and return the withdrawn amount.
    */
    function withdrawAllRewards(uint64 additionalSteps) public whenNotPaused returns(uint256) {
        return withdrawRewards(type(uint256).max, additionalSteps);
    }

    /**
    * @dev Withdraw the total amount of taxed rewards of the caller and return
    * the withdrawn amount.
    */
    function withdrawAllRewards() public whenNotPaused returns(uint256) {
        return withdrawRewards(type(uint256).max, type(uint64).max);
    }

    /**
    * @dev Withdraw `amount` from the taxed rewards of the caller and return
    * the withdrawn amount.
    */
    function withdrawRewards(uint256 amount) public whenNotPaused returns(uint256) {
        return withdrawRewards(amount, type(uint64).max);
    }

    /**
    * @dev Withdraw `amount` from the taxed rewards of the caller by traversing
    * the {Staking} history in `1 + additionalSteps`. The `taxedRewards` returned
    * is the increase in the taxed rewards of the caller before subtracting the
    * `amount` transferred to the caller.
    *
    * Emit {RewardPaid} containing the caller address and the amount transferred.
    *
    * Revert with {TransferFailed} containing the reciever address and the amount
    * to be transferred if the transfer failed.
    */
    function withdrawRewards(uint256 amount, uint64 additionalSteps)
        public
        whenNotPaused
        returns(uint256 taxedRewards)
    {
        (amount, taxedRewards) = _useRewards(amount, additionalSteps);
        (bool success, ) = _msgSender().call{value: amount}("");
        require(success, TransferFailed(_msgSender(), amount));
        emit RewardPaid(_msgSender(), amount);
    }

    /**
    * @inheritdoc IDelegation
    *
    * @dev Emit {Staked} containing the caller address and the amount of rewards staked.
    */
    function stakeRewards() public override(BaseDelegation, IDelegation) whenNotPaused {
        (uint256 amount, ) = _useRewards(type(uint256).max, type(uint64).max);
        _increaseStake(amount);
        _increaseDeposit(amount);
        _appendToHistory(int256(amount), _msgSender());
        emit Staked(_msgSender(), amount, "");
    }

    /**
    * @dev Returns the amount of rewards, scaled by a factor of `10**18`, that
    * are remainders of integer divisions in the reward calculation that have
    * not yet been withdrawn.
    */
    function totalRoundingErrors() public view returns(uint256) {
        NonLiquidDelegationStorage storage $ = _getNonLiquidDelegationStorage();
        return $.totalRoundingErrors;
    }

    /**
    * @dev Return the current amount of `historicalTaxedRewards`.
    * See {NonLiquidDelegationStorage}.
    */
    function getHistoricalTaxedRewards() public view returns(int256) {
        NonLiquidDelegationStorage storage $ = _getNonLiquidDelegationStorage();
        return $.historicalTaxedRewards;
    }

    /**
    * @dev Return the current amount of `taxedRewards`.
    * See {NonLiquidDelegationStorage}.
    */
    function getTaxedRewards() public view returns(int256) {
        NonLiquidDelegationStorage storage $ = _getNonLiquidDelegationStorage();
        return $.taxedRewards;
    }

    /**
    * @dev Make the requested `amount` of taxed rewards available to the caller
    * for staking or withdrawing by traversing `1 + additionalSteps` entries of
    * the {Staking} history. If `amount == type(uint256).max` then all rewards
    * were requested. In that case return the total amount of rewards available
    * otherwise the requested amount. The second return value is the amount by
    * which the taxed rewards of the caller were increased.
    *
    * Revert with {RequestedAmountTooHigh} containing the `amount` and the
    * actually available rewards if the amount is higher than the rewards.
    */
    function _useRewards(
        uint256 amount,
        uint64 additionalSteps
    ) internal returns(uint256, uint256) {
        NonLiquidDelegationStorage storage $ = _getNonLiquidDelegationStorage();
        uint256 oldRoundingError = $.roundingErrors[_msgSender()];
        (
            uint256 resultInTotal,
            uint256 resultAfterLastStaking,
            uint64 posInStakingIndices,
            uint64 nextStakingIndex,
            uint256 roundingError
        ) = additionalSteps == type(uint64).max ?
            _rewards() :
            _rewards(additionalSteps);
        $.roundingErrors[_msgSender()] = roundingError;
        $.totalRoundingErrors -= oldRoundingError;
        $.totalRoundingErrors += roundingError;
        // the caller has not delegated any stake yet
        if (nextStakingIndex == 0)
            return (0, 0);
        // store the rewards accrued since the last staking in order to know how
        // much the caller has already withdrawn, and reduce the current withdrawal
        // by the amount that was stored last time, because the reward since the 
        // last staking is growing permanently, but only the delta accrued since
        // the last withdrawal shall be taken into account in the current call
        (
            $.taxedSinceLastStaking[_msgSender()],
            resultInTotal
        ) = (
            resultAfterLastStaking,
            resultInTotal - $.taxedSinceLastStaking[_msgSender()]
        );
        uint256 taxedRewards = resultInTotal;
        $.availableTaxedRewards[_msgSender()] += taxedRewards;
        $.firstStakingIndex[_msgSender()] = posInStakingIndices;
        $.lastTaxedStakingIndex[_msgSender()] = nextStakingIndex - 1;
        if (amount == type(uint256).max)
            amount = $.availableTaxedRewards[_msgSender()];
        require(
            amount <= $.availableTaxedRewards[_msgSender()], 
            RequestedAmountTooHigh(amount, $.availableTaxedRewards[_msgSender()])
        );
        $.availableTaxedRewards[_msgSender()] -= amount;
        $.historicalTaxedRewards -= int256(amount);
        $.taxedRewards -= int256(amount);
        return (amount, taxedRewards);
    }

    /**
    * @dev Return the total amount of untaxed rewards of the caller.
    */
    function _rewards() internal view returns (
        uint256 resultInTotal,
        uint256 resultAfterLastStaking,
        uint64 posInStakingIndices,
        uint64 nextStakingIndex,
        uint256 roundingError
    ) {
        return _rewards(type(uint64).max);
    }

    /**
    * @dev Return the untaxed rewards of the caller calculated by traversing
    * `1 + additionalSteps` entries of the {Staking} history.
    */
    function _rewards(uint64 additionalSteps) internal view returns (
        uint256 resultInTotal,
        uint256 resultAfterLastStaking,
        uint64 posInStakingIndices,
        uint64 nextStakingIndex,
        uint256 roundingError
    ) {
        NonLiquidDelegationStorage storage $ = _getNonLiquidDelegationStorage();
        uint64 firstStakingIndex;
        uint256 amount;
        uint256 total;
        roundingError = $.roundingErrors[_msgSender()];
        uint256 len = $.stakingIndices[_msgSender()].length;
        for (
            posInStakingIndices = $.firstStakingIndex[_msgSender()];
            posInStakingIndices < len;
            posInStakingIndices++
        ) {
            nextStakingIndex = $.stakingIndices[_msgSender()][posInStakingIndices];
            amount = $.stakings[nextStakingIndex].amount;
            if (nextStakingIndex < $.lastTaxedStakingIndex[_msgSender()])
                nextStakingIndex = $.lastTaxedStakingIndex[_msgSender()];
            total = $.stakings[nextStakingIndex].total;
            nextStakingIndex++;
            if (firstStakingIndex == 0)
                firstStakingIndex = nextStakingIndex;
            while (
                posInStakingIndices == $.stakingIndices[_msgSender()].length - 1 ?
                nextStakingIndex < $.stakings.length :
                nextStakingIndex <= $.stakingIndices[_msgSender()][posInStakingIndices + 1]
            ) {
                if (total > 0) {
                    resultInTotal += $.stakings[nextStakingIndex].rewards * amount / total;
                    roundingError +=
                        1 ether * $.stakings[nextStakingIndex].rewards * amount / total -
                        1 ether * ($.stakings[nextStakingIndex].rewards * amount / total);
                }
                total = $.stakings[nextStakingIndex].total;
                nextStakingIndex++;
                if (nextStakingIndex - firstStakingIndex > additionalSteps) {
                    if (getRewards() >= resultInTotal + roundingError / 1 ether) {
                        resultInTotal += roundingError / 1 ether;
                        roundingError -= 1 ether * (roundingError / 1 ether);
                    }
                    return (
                        resultInTotal,
                        resultAfterLastStaking, 
                        posInStakingIndices, 
                        nextStakingIndex, 
                        roundingError
                    );
                }
            }
        }

        // all rewards recorded in the staking history have been taken into account
        if (nextStakingIndex == $.stakings.length) {
            // the last step is to add the rewards accrued since the last staking
            if (total > 0) {
                uint256 newRewards = (int256(getRewards()) - $.taxedRewards).toUint256();
                // first deduct the commission from the yet untaxed part of the rewards
                newRewards -= newRewards * getCommissionNumerator() / DENOMINATOR;
                // then add the already taxed part of the rewards
                newRewards += ($.taxedRewards - $.historicalTaxedRewards).toUint256();
                // finally calculate the user's share of the rewards
                resultAfterLastStaking = newRewards * amount / total;
                roundingError +=
                    1 ether * newRewards * amount / total -
                    1 ether * (newRewards * amount / total);
                resultInTotal += resultAfterLastStaking;
            }
        }

        // ensure that the next time the function is called the initial value
        // of posInStakingIndices refers to the last amount and total among the
        // stakingIndices of the staker that already existed during the current
        // call of the function so that we can continue from there
        if (posInStakingIndices > 0)
            posInStakingIndices--;
        if (getRewards() >= resultInTotal + roundingError / 1 ether) {
            resultInTotal += roundingError / 1 ether;
            roundingError -= 1 ether * (roundingError / 1 ether);
        }
    }

    /**
    * @inheritdoc IDelegation
    * @dev Commission is deducted when delegators withdraw their share of the rewards.
    */
    function collectCommission() public override(BaseDelegation, IDelegation) {
        NonLiquidDelegationStorage storage $ = _getNonLiquidDelegationStorage();
        // deduct the commission from the yet untaxed rewards
        _taxRewards((int(getRewards()) - $.taxedRewards).toUint256());
        $.taxedRewards = int(getRewards());
    }

}