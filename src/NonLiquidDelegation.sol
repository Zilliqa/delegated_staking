// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity ^0.8.26;

import {IDelegation} from "src/IDelegation.sol";
import {BaseDelegation} from "src/BaseDelegation.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

/**
 * @notice Minimal interface with functions specific to the {NonLiquidDelegation} variant.
 * There must be at least one function that makes the interface unique among all variants.
 *
 * @dev Do not change this interface, otherwise it will break the detection of the staking
 * variant of already deployed delegation contracts.
 */
interface INonLiquidDelegation {
    function interfaceId() external pure returns (bytes4);
    function getDelegatedAmount() external view returns(uint256);
    function rewards() external view returns(uint256);
}

/**
 * @notice The non-liquid variant of the stake delegation contract. It record every change
 * to the delegated stake in the {Staking} history. Based on the entries in the history
 * it calculates the rewards due to each delegator.
 *
 * @dev Every time a delegator stakes or unstakes, the stake proportions of all delegators
 * change. It is essential to record the rewards accrued between two {Staking} events in
 * order to be able to calculate each delegator's share of the rewards during that period.
 * Note that the rewards accrued since the last {Staking} event are in the contract balance
 * which is increasing in every block.
 */
contract NonLiquidDelegation is IDelegation, BaseDelegation, INonLiquidDelegation {
    using SafeCast for int256;

    /**
    * @dev `staker` is the address of the delegator who staked or unstaked, after which the
    * delegator had `amount` and the pool had `total` staked ZIL, and pool earned `rewards`
    * since the previous {Staking} event or since its launch in case it is the first event.
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
    * - `stakingIndices` maps delegator addresses to arrays of indices in `stakings`
    * in ascending order that the respective delegator performed.
    *
    * - `firstStakingIndex` is the index of the element in a validator's
    * `stakingIndices` array from which their outstanding rewards are calculated.
    *
    * - `availableTaxedRewards` is the portion of a delegator's rewards from which the
    * commission was already deducted.
    *
    * - `lastTaxedStakingIndex` is the `nextStakingIndex` returned from {_rewards} up to
    * which the delegator's rewards have already been included in `availableTaxedRewards`.
    *
    * - `taxedSinceLastStaking` are a validator's taxed rewards accrued since the last
    * entry in the {Staking} history.
    *
    * - `immutableRewards` is the total of rewards in the {Staking} history after deducting
    * the commission, that has not been withdrawn or staked yet.
    *
    * - `newAddress` maps a delegator's address to another address that replaces it as soon
    * as that other address calls {replaceOldAddress}.
    */
    /// @custom:storage-location erc7201:zilliqa.storage.NonLiquidDelegation
    struct NonLiquidDelegationStorage {
        Staking[] stakings;
        mapping(address => uint64[]) stakingIndices;
        mapping(address => uint64) firstStakingIndex;
        mapping(address => uint256) availableTaxedRewards;
        mapping(address => uint64) lastTaxedStakingIndex;
        mapping(address => uint256) taxedSinceLastStaking;
        int256 immutableRewards;
        mapping(address => address) newAddress;
    }

    // keccak256(abi.encode(uint256(keccak256("zilliqa.storage.NonLiquidDelegation")) - 1)) & ~bytes32(uint256(0xff))
    // solhint-disable const-name-snakecase
    bytes32 private constant NonLiquidDelegationStorageLocation = 0x66c8dc4f9c8663296597cb1e39500488e05713d82a9122d4f548b19a70fc2000;

    function _getNonLiquidDelegationStorage() private pure returns (NonLiquidDelegationStorage storage $) {
        assembly {
            $.slot := NonLiquidDelegationStorageLocation
        }
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
    * @dev Let {BaseDelegation} migrate `fromVersion` to the current `VERSION`.
    */
    function reinitialize(uint64 fromVersion) public reinitializer(VERSION) {
        migrate(fromVersion);
    }

    /**
    * @dev Initialize the base contracts.
    */
    function initialize(address initialOwner) public initializer {
        __BaseDelegation_init(initialOwner);
    }

    /**
    * @dev Return the current amount of `immutableRewards`.
    * See {NonLiquidDelegationStorage}.
    */
    function getImmutableRewards() public view returns(int256) {
        NonLiquidDelegationStorage storage $ = _getNonLiquidDelegationStorage();
        return $.immutableRewards;
    }

    /**
    * @dev Return the history of `stakings`.
    * See {NonLiquidDelegationStorage}.
    */
    function getStakingHistory() public view returns(Staking[] memory) {
        NonLiquidDelegationStorage storage $ = _getNonLiquidDelegationStorage();
        return $.stakings;
    }

    /**
    * @dev Return the data stored about the caller as delegated.
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
    * The previously set address is overwritten or deleted if `to == address(0)` 
    */
    function setNewAddress(address to) public {
        NonLiquidDelegationStorage storage $ = _getNonLiquidDelegationStorage();
        $.newAddress[_msgSender()] = to;
    }

    /**
    * @dev The caller address replaces the `old` delegator address which nominated
    * the caller using {setNewAddress}.
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
    * @dev Emit the event when `reward` was transferred to `delegator`. 
    */
    event RewardPaid(address indexed delegator, uint256 reward);

    /// @inheritdoc BaseDelegation
    function join(bytes calldata blsPubKey, address controlAddress) public override onlyOwner {
        _join(blsPubKey, controlAddress);

        // the node's deposit must also be recorded in the staking history otherwise
        // its owner would not benefit from the rewards accrued due to the deposit
        _append(int256(getStake(blsPubKey)), controlAddress);
    }

    /// @inheritdoc BaseDelegation
    function leave(bytes calldata blsPubKey) public override {
        if (!_preparedToLeave(blsPubKey))
            return;
        NonLiquidDelegationStorage storage $ = _getNonLiquidDelegationStorage();
        require($.stakingIndices[_msgSender()].length > 0, StakerNotFound(_msgSender()));
        uint256 amount = $.stakings[$.stakingIndices[_msgSender()][$.stakingIndices[_msgSender()].length - 1]].amount;
        _append(-int256(amount), _msgSender());
        uint256 currentDeposit = getStake(blsPubKey);
        if (amount > currentDeposit) {
            _initiateLeaving(blsPubKey, currentDeposit);
            _enqueueWithdrawal(amount - currentDeposit);
            _decreaseDeposit(amount - currentDeposit);
        } else
            _initiateLeaving(blsPubKey, amount);
    }

    /// @inheritdoc BaseDelegation
    function deposit(
        bytes calldata blsPubKey,
        bytes calldata peerId,
        bytes calldata signature
    ) public payable override onlyOwner {
        _increaseStake(msg.value);
        _deposit(
            blsPubKey,
            peerId,
            signature
        );
        // the owner's deposit must also be recorded as staking otherwise
        // the owner would not benefit from the rewards accrued by the deposit
        if (msg.value > 0)
            _append(int256(msg.value), _msgSender());
    }

    /**
    * @inheritdoc IDelegation
    */
    function claim() public override(BaseDelegation, IDelegation) whenNotPaused {
        uint256 total = _dequeueWithdrawals();
        if (total == 0)
            return;
        // withdraw the unstaked deposit once the unbonding period is over
        _withdrawDeposit();
        _decreaseStake(total);
        (bool success, ) = _msgSender().call{
            value: total
        }("");
        require(success, TransferFailed(_msgSender(), total));
        emit Claimed(_msgSender(), total, "");
    }

    /**
    * @inheritdoc IDelegation
    */
    function stake() public override(BaseDelegation, IDelegation) payable whenNotPaused {
        _increaseStake(msg.value);
        _increaseDeposit(msg.value);
        _append(int256(msg.value), _msgSender());
        emit Staked(_msgSender(), msg.value, "");
    }

    /**
    * @inheritdoc IDelegation
    */
    function unstake(uint256 value) public override(BaseDelegation, IDelegation) whenNotPaused returns(uint256 amount) {
        _append(-int256(value), _msgSender());
        _decreaseDeposit(uint256(value));
        _enqueueWithdrawal(value);
        emit Unstaked(_msgSender(), value, "");
        return value;
    }

    /**
    * @dev Append an entry to the {Staking} history based on the currently staked (positive) or
    * unstaked (negative) `value`.
    */
    function _append(int256 value, address staker) internal {
        if (value > 0)
            require(uint256(value) >= MIN_DELEGATION, DelegatedAmountTooLow(uint256(value)));
        NonLiquidDelegationStorage storage $ = _getNonLiquidDelegationStorage();
        int256 amount = value;
        if ($.stakingIndices[staker].length > 0)
            amount += int256($.stakings[$.stakingIndices[staker][$.stakingIndices[staker].length - 1]].amount);
        if (value < 0)
            require(
                amount >= 0,
                RequestedAmountTooHigh(uint256(-value), $.stakings[$.stakingIndices[staker][$.stakingIndices[staker].length - 1]].amount)
            );
        uint256 newRewards; // no rewards before the first staker is added
        if ($.stakings.length > 0) {
            value += int256($.stakings[$.stakings.length - 1].total);
            newRewards = (int256(getRewards()) - $.immutableRewards).toUint256();
        }
        $.immutableRewards = int256(getRewards());
        $.stakings.push(Staking(staker, uint256(amount), uint256(value), newRewards));
        $.stakingIndices[staker].push(uint64($.stakings.length - 1));
    }

    /**
    * @dev Returns the taxed rewards the caller can withdraw by traversing the {Staking} history
    * in `1 + additionalSteps`.
    */
    function rewards(uint64 additionalSteps) public view returns(uint256) {
        NonLiquidDelegationStorage storage $ = _getNonLiquidDelegationStorage();
        (uint256 resultInTotal, , , ) = _rewards(additionalSteps);
        resultInTotal -= $.taxedSinceLastStaking[_msgSender()];
        return resultInTotal - resultInTotal * getCommissionNumerator() / DENOMINATOR + $.availableTaxedRewards[_msgSender()];
    }

    /**
    * @dev Return the total amount of taxed rewards the caller is eligible to withdraw.
    */
    function rewards() public view returns(uint256) {
        NonLiquidDelegationStorage storage $ = _getNonLiquidDelegationStorage();
        (uint256 resultInTotal, , , ) = _rewards();
        resultInTotal -= $.taxedSinceLastStaking[_msgSender()];
        return resultInTotal - resultInTotal * getCommissionNumerator() / DENOMINATOR + $.availableTaxedRewards[_msgSender()];
    }

    /**
    * @dev Deduct the commission from the yet untaxed rewards and transfer it to the configured
    * commission receiver address.
    */
    function taxRewards(uint256 untaxedRewards) internal returns (uint256) {
        NonLiquidDelegationStorage storage $ = _getNonLiquidDelegationStorage();
        uint256 commission = untaxedRewards * getCommissionNumerator() / DENOMINATOR;
        if (commission == 0)
            return untaxedRewards;
        $.immutableRewards -= int256(commission);
        // commissions are not subject to the unbonding period
        (bool success, ) = getCommissionReceiver().call{
            value: commission
        }("");
        require(success, TransferFailed(getCommissionReceiver(), commission));
        emit CommissionPaid(getCommissionReceiver(), commission);
        return untaxedRewards - commission;
    }

    /**
    * @dev Withdraw the taxed rewards of the caller calculated by traversing the {Staking} history
    * in `1 + additionalSteps` and return the withdrawn amount.
    */
    function withdrawAllRewards(uint64 additionalSteps) public whenNotPaused returns(uint256) {
        return withdrawRewards(type(uint256).max, additionalSteps);
    }

    /**
    * @dev Withdraw the total amount of taxed rewards of the caller and return the withdrawn amount.
    */
    function withdrawAllRewards() public whenNotPaused returns(uint256) {
        return withdrawRewards(type(uint256).max, type(uint64).max);
    }

    /**
    * @dev Withdraw `amount` from the taxed rewards of the caller and return the withdrawn amount.
    */
    function withdrawRewards(uint256 amount) public whenNotPaused returns(uint256) {
        return withdrawRewards(amount, type(uint64).max);
    }

    /**
    * @dev Withdraw `amount` from the taxed rewards of the caller by traversing the {Staking} history
    * in `1 + additionalSteps`. The `taxedRewards` returned is the increase in the taxed rewards of
    * the caller before subtracting the `amount` transferred to the caller.
    */
    function withdrawRewards(uint256 amount, uint64 additionalSteps) public whenNotPaused returns(uint256 taxedRewards) {
        (amount, taxedRewards) = _useRewards(amount, additionalSteps);
        (bool success, ) = _msgSender().call{value: amount}("");
        require(success, TransferFailed(_msgSender(), amount));
        emit RewardPaid(_msgSender(), amount);
    }

    /**
    * @inheritdoc IDelegation
    */
    function stakeRewards() public override(BaseDelegation, IDelegation) whenNotPaused {
        (uint256 amount, ) = _useRewards(type(uint256).max, type(uint64).max);
        _increaseStake(amount);
        _increaseDeposit(amount);
        _append(int256(amount), _msgSender());
        emit Staked(_msgSender(), amount, "");
    }

    /**
    * @dev Make the requested `amount` of taxed rewards available to the caller for staking or
    * withdrawing by traversing the {Staking} history in `1 + additionalSteps`.
    * If `amount == type(uint256).max` then all rewards were requested. In that case return the
    * total amount of rewards available otherwise the requested amount. The second return value
    * is the amount by which the taxed rewards of the caller were increased.
    */
    function _useRewards(uint256 amount, uint64 additionalSteps) internal whenNotPaused returns(uint256, uint256) {
        NonLiquidDelegationStorage storage $ = _getNonLiquidDelegationStorage();
        (
            uint256 resultInTotal,
            uint256 resultAfterLastStaking,
            uint64 posInStakingIndices,
            uint64 nextStakingIndex
        ) = additionalSteps == type(uint64).max ?
            _rewards() :
            _rewards(additionalSteps);
        // the caller has not delegated any stake yet
        if (nextStakingIndex == 0)
            return (0, 0);
        // store the rewards accrued since the last staking (`resultAfterLastStaking`)
        // in order to know next time how much the caller has already withdrawn, and
        // reduce the current withdrawal (`resultInTotal`) by the amount that was stored
        // last time (`taxedSinceLastStaking`) - this is essential because the reward
        // amount since the last staking is growing all the time, but only the delta accrued
        // since the last withdrawal shall be taken into account in the current withdrawal
        ($.taxedSinceLastStaking[_msgSender()], resultInTotal) = (resultAfterLastStaking, resultInTotal - $.taxedSinceLastStaking[_msgSender()]);
        uint256 taxedRewards = taxRewards(resultInTotal);
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
        $.immutableRewards -= int256(amount);
        return (amount, taxedRewards);
    }

    /**
    * @dev Return the total amount of untaxed rewards of the caller.
    */
    function _rewards() internal view returns (
        uint256 resultInTotal,
        uint256 resultAfterLastStaking,
        uint64 posInStakingIndices,
        uint64 nextStakingIndex
    ) {
        return _rewards(type(uint64).max);
    }

    /**
    * @dev Returns the untaxed rewards of the caller by traversing the {Staking} history
    * in `1 + additionalSteps`.
    */
    function _rewards(uint64 additionalSteps) internal view returns (
        uint256 resultInTotal,
        uint256 resultAfterLastStaking,
        uint64 posInStakingIndices,
        uint64 nextStakingIndex
    ) {
        NonLiquidDelegationStorage storage $ = _getNonLiquidDelegationStorage();
        uint64 firstStakingIndex;
        uint256 amount;
        uint256 total;
        for (
            posInStakingIndices = $.firstStakingIndex[_msgSender()];
            posInStakingIndices < $.stakingIndices[_msgSender()].length;
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
                if (total > 0)
                    resultInTotal += $.stakings[nextStakingIndex].rewards * amount / total;
                total = $.stakings[nextStakingIndex].total;
                nextStakingIndex++;
                if (nextStakingIndex - firstStakingIndex > additionalSteps)
                    return (resultInTotal, resultAfterLastStaking, posInStakingIndices, nextStakingIndex);
            }    
        }

        // all rewards recorded in the staking history have been taken into account
        if (nextStakingIndex == $.stakings.length) {
            // the last step is to add the rewards accrued since the last staking
            if (total > 0) {
                resultAfterLastStaking = (int256(getRewards()) - $.immutableRewards).toUint256() * amount / total;
                resultInTotal += resultAfterLastStaking;
            }
        }

        // ensure that the next time the function is called the initial value of posInStakingIndices
        // refers to the last amount and total among the stakingIndices of the staker that already
        // existed during the current call of the function so that we can continue from there
        if (posInStakingIndices > 0)
            posInStakingIndices--;
    }

    /**
    * @inheritdoc IDelegation
    * @dev Commission is deducted when delegators withdraw their share of the rewards.
    */
    function collectCommission() public override(BaseDelegation, IDelegation) {}

    /// @inheritdoc IDelegation
    function getStake() public override(BaseDelegation, IDelegation) view returns(uint256 total) {
        total = super.getStake();
        assert(!_isActivated() || total == getDelegatedTotal());
    }

    /**
    * @dev See https://eips.ethereum.org/EIPS/eip-165
    */
    function supportsInterface(bytes4 _interfaceId) public view override returns (bool) {
       return _interfaceId == type(INonLiquidDelegation).interfaceId || super.supportsInterface(_interfaceId);
    }

    /**
    * @dev Returns the interface id that can be used to identify which delegated staking
    * variant the contract implements.  
    */
    function interfaceId() public pure returns (bytes4) {
       return type(INonLiquidDelegation).interfaceId;
    }

}