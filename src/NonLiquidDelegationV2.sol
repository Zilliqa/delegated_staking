// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity ^0.8.26;

import {BaseDelegation} from "src/BaseDelegation.sol";
import {INonLiquidDelegation} from "src/NonLiquidDelegation.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

contract NonLiquidDelegationV2 is BaseDelegation, INonLiquidDelegation {
    using SafeCast for int256;

    struct Staking {
        //TODO: just for testing purposes, can be removed
        address staker;
        // the currently staked amount of the staker
        // after the staking/unstaking
        uint256 amount;
        // the currently staked total of all stakers
        // after the staking/unstaking
        uint256 total;
        // the rewards accrued since the last staking/unstaking
        // note that the current staker's share of these rewards
        // is NOT to be calculated based on the new amount and
        // total since those apply only to future rewards
        uint256 rewards;
    }

    /// @custom:storage-location erc7201:zilliqa.storage.NonLiquidDelegation
    struct NonLiquidDelegationStorage {
        // the history of all stakings and unstakings
        Staking[] stakings;
        // indices of the stakings by the respective staker
        mapping(address => uint64[]) stakingIndices;
        // the first among the stakingIndices of the respective staker
        // based on which new rewards can be withdrawn
        mapping(address => uint64) firstStakingIndex;
        // already calculated portion of the rewards of the
        // respective staker that can be fully/partially
        // transferred to the staker
        mapping(address => uint256) allWithdrawnRewards;
        // the last staking nextStakingIndex up to which the rewards
        // of the respective staker have been calculated
        // and added to allWithdrawnRewards
        mapping(address => uint64) lastWithdrawnStakingIndex;
        // the amount that has already been withdrawn from the
        // constantly growing rewards accrued since the last staking
        mapping(address => uint256) withdrawnAfterLastStaking;
        // balance of the reward address minus the
        // rewards accrued since the last staking
        int256 totalRewards;
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

    // automatically incrementing the version number allows for
    // upgrading the contract without manually specifying the next
    // version number in the source file - use with caution since
    // it won't be possible to identify the actual version of the
    // source file without a hardcoded version number, but storing
    // the file versions in separate folders would help
    function reinitialize() public reinitializer(version() + 1) {
    }

    // called when stake withdrawn from the deposit contract is claimed
    // but not called when rewards are assigned to the reward address
    receive() external payable {
        NonLiquidDelegationStorage storage $ = _getNonLiquidDelegationStorage();
        // add the stake withdrawn from the deposit to the reward balance
        $.totalRewards += int256(msg.value);
    }

    function getTotalRewards() public view returns(int256) {
        NonLiquidDelegationStorage storage $ = _getNonLiquidDelegationStorage();
        return $.totalRewards;
    }

    function getStakingHistory() public view returns(Staking[] memory) {
        NonLiquidDelegationStorage storage $ = _getNonLiquidDelegationStorage();
        return $.stakings;
    }

    function getStakingData() public view returns(
        uint64[] memory stakingIndices,
        uint64 firstStakingIndex,
        uint256 allWithdrawnRewards,
        uint64 lastWithdrawnStakingIndex,
        uint256 withdrawnAfterLastStaking
    ) {
        NonLiquidDelegationStorage storage $ = _getNonLiquidDelegationStorage();
        stakingIndices = $.stakingIndices[_msgSender()];
        firstStakingIndex = $.firstStakingIndex[_msgSender()];
        allWithdrawnRewards = $.allWithdrawnRewards[_msgSender()];
        lastWithdrawnStakingIndex = $.lastWithdrawnStakingIndex[_msgSender()];
        withdrawnAfterLastStaking = $.withdrawnAfterLastStaking[_msgSender()];
    }

    function getDelegatedStake() public view returns(uint256 result) {
        NonLiquidDelegationStorage storage $ = _getNonLiquidDelegationStorage();
        uint64[] storage stakingIndices = $.stakingIndices[_msgSender()];
        if (stakingIndices.length > 0)
            result = $.stakings[stakingIndices[stakingIndices.length - 1]].amount;
    }

    event RewardPaid(address indexed delegator, uint256 reward);

    // called by the node's owner who deployed this contract
    // to turn the already deposited validator node into a staking pool
    function migrate(bytes calldata blsPubKey) public override onlyOwner {
        _migrate(blsPubKey);
        NonLiquidDelegationStorage storage $ = _getNonLiquidDelegationStorage();
        require($.stakings.length == 0, "stake already delegated");
        // the owner's deposit must also be recorded as staking otherwise
        // the owner would not benefit from the rewards accrued by the deposit
        _append(int256(getStake()));
    }

    // called by the node's owner who deployed this contract
    // to deposit the node as a validator using the delegated stake
    function depositLater(
        bytes calldata blsPubKey,
        bytes calldata peerId,
        bytes calldata signature
    ) public override onlyOwner {
        _deposit(
            blsPubKey,
            peerId,
            signature,
            address(this).balance
        );
    }

    // called by the node's owner who deployed this contract
    // with at least the minimum stake to deposit the node
    // as a validator before any stake is delegated to it
    function depositFirst(
        bytes calldata blsPubKey,
        bytes calldata peerId,
        bytes calldata signature
    ) public payable override onlyOwner {
        _deposit(
            blsPubKey,
            peerId,
            signature,
            msg.value
        );
        NonLiquidDelegationStorage storage $ = _getNonLiquidDelegationStorage();
        require($.stakings.length == 0, "stake already delegated");
        // the owner's deposit must also be recorded as staking otherwise
        // the owner would not benefit from the rewards accrued by the deposit
        _append(int256(msg.value));
    }

    function claim() public override whenNotPaused {
        NonLiquidDelegationStorage storage $ = _getNonLiquidDelegationStorage();
        uint256 total = _dequeueWithdrawals();
        /*if (total == 0)
            return;*/
        // withdraw the unstaked deposit once the unbonding period is over
        _withdrawDeposit();
        $.totalRewards -= int256(total);
        (bool success, ) = _msgSender().call{
            value: total
        }("");
        require(success, "transfer of funds failed");
        emit Claimed(_msgSender(), total, "");
    }

    function stake() public override payable whenNotPaused {
        _increaseDeposit(msg.value);
        _append(int256(msg.value));
        emit Staked(_msgSender(), msg.value, "");
    }

    function unstake(uint256 value) public override whenNotPaused returns(uint256 amount) {
        _append(-int256(value));
        _decreaseDeposit(uint256(value));
        _enqueueWithdrawal(value);
        emit Unstaked(_msgSender(), value, "");
        return value;
    }

    function _append(int256 value) internal {
        NonLiquidDelegationStorage storage $ = _getNonLiquidDelegationStorage();
        int256 amount = value;
        if ($.stakingIndices[_msgSender()].length > 0)
            amount += int256($.stakings[$.stakingIndices[_msgSender()][$.stakingIndices[_msgSender()].length - 1]].amount);
        require(amount >= 0, "can not unstake more than staked before");
        uint256 newRewards; // no rewards before the first staker is added
        if ($.stakings.length > 0) {
            value += int256($.stakings[$.stakings.length - 1].total);
            newRewards = (int256(getRewards()) - $.totalRewards).toUint256();
        }
        $.totalRewards = int256(getRewards());
        //$.stakings.push(Staking(uint256(amount), uint256(value), newRewards));
        //TODO: just for testing purposes, otherwise replace with the previous line
        $.stakings.push(Staking(_msgSender(), uint256(amount), uint256(value), newRewards));
        $.stakingIndices[_msgSender()].push(uint64($.stakings.length - 1));
    }

    function rewards(uint64 additionalSteps) public view returns(uint256) {
        NonLiquidDelegationStorage storage $ = _getNonLiquidDelegationStorage();
        (uint256 resultInTotal, , , ) = _rewards(additionalSteps);
        resultInTotal -= $.withdrawnAfterLastStaking[_msgSender()];
        return resultInTotal - resultInTotal * getCommissionNumerator() / DENOMINATOR + $.allWithdrawnRewards[_msgSender()];
    }

    function rewards() public view returns(uint256) {
        NonLiquidDelegationStorage storage $ = _getNonLiquidDelegationStorage();
        (uint256 resultInTotal, , , ) = _rewards();
        resultInTotal -= $.withdrawnAfterLastStaking[_msgSender()];
        return resultInTotal - resultInTotal * getCommissionNumerator() / DENOMINATOR + $.allWithdrawnRewards[_msgSender()];
    }

    function taxRewards(uint256 untaxedRewards) internal returns (uint256) {
        NonLiquidDelegationStorage storage $ = _getNonLiquidDelegationStorage();
        uint256 commission = untaxedRewards * getCommissionNumerator() / DENOMINATOR;
        if (commission == 0)
            return untaxedRewards;
        $.totalRewards -= int256(commission);
        // commissions are not subject to the unbonding period
        (bool success, ) = owner().call{
            value: commission
        }("");
        require(success, "transfer of commission failed");
        emit CommissionPaid(owner(), commission);
        return untaxedRewards - commission;
    }

    function withdrawAllRewards(uint64 additionalSteps) public whenNotPaused returns(uint256) {
        return withdrawRewards(type(uint256).max, additionalSteps);
    }

    function withdrawAllRewards() public whenNotPaused returns(uint256) {
        return withdrawRewards(type(uint256).max, type(uint64).max);
    }

    function withdrawRewards(uint256 amount) public whenNotPaused returns(uint256) {
        return withdrawRewards(amount, type(uint64).max);
    }

    function withdrawRewards(uint256 amount, uint64 additionalSteps) public whenNotPaused returns(uint256 taxedRewards) {
        (amount, taxedRewards) = _useRewards(amount, additionalSteps);
        (bool success, ) = _msgSender().call{value: amount}("");
        require(success, "transfer of rewards failed");
        emit RewardPaid(_msgSender(), amount);
    }

    function stakeRewards() public override {
        (uint256 amount, ) = _useRewards(type(uint256).max, type(uint64).max);
        _increaseDeposit(amount);
        _append(int256(amount));
        emit Staked(_msgSender(), amount, "");
    }

    // if there have been more than 11,000 stakings or unstakings since the delegator's last reward
    // withdrawal, calling withdrawAllRewards() would exceed the block gas limit additionalSteps is
    // the number of additional stakings from which the rewards are withdrawn if zero, the rewards
    // are only withdrawn from the first staking from which they have not been withdrawn yet
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
        // the caller has not delegated any stake
        if (nextStakingIndex == 0)
            return (0, 0);
        // store the rewards accrued since the last staking (`resultAfterLastStaking`)
        // in order to know next time how much the caller has already withdrawn, and
        // reduce the current withdrawal (`resultInTotal`) by the amount that was stored
        // last time (`withdrawnAfterLastStaking`) - this is essential because the reward
        // amount since the last staking is growing all the time, but only the delta accrued
        // since the last withdrawal shall be taken into account in the current withdrawal
        ($.withdrawnAfterLastStaking[_msgSender()], resultInTotal) = (resultAfterLastStaking, resultInTotal - $.withdrawnAfterLastStaking[_msgSender()]);
        uint256 taxedRewards = taxRewards(resultInTotal);
        $.allWithdrawnRewards[_msgSender()] += taxedRewards;
        $.firstStakingIndex[_msgSender()] = posInStakingIndices;
        $.lastWithdrawnStakingIndex[_msgSender()] = nextStakingIndex - 1;
        if (amount == type(uint256).max)
            amount = $.allWithdrawnRewards[_msgSender()];
        require(amount <= $.allWithdrawnRewards[_msgSender()], "can not withdraw more than accrued");
        $.allWithdrawnRewards[_msgSender()] -= amount;
        $.totalRewards -= int256(amount);
        return (amount, taxedRewards);
    }

    function _rewards() internal view returns (
        uint256 resultInTotal,
        uint256 resultAfterLastStaking,
        uint64 posInStakingIndices,
        uint64 nextStakingIndex
    ) {
        return _rewards(type(uint64).max);
    }

    function _rewards(uint64 additionalSteps) internal view returns (
        uint256 resultInTotal,
        uint256 resultAfterLastStaking,
        uint64 posInStakingIndices,
        uint64 nextStakingIndex
    ) {
        NonLiquidDelegationStorage storage $ = _getNonLiquidDelegationStorage();
        uint64 firstStakingIndex;
        for (
            posInStakingIndices = $.firstStakingIndex[_msgSender()];
            posInStakingIndices < $.stakingIndices[_msgSender()].length;
            posInStakingIndices++
        ) {
            nextStakingIndex = $.stakingIndices[_msgSender()][posInStakingIndices];
            uint256 amount = $.stakings[nextStakingIndex].amount;
            if (nextStakingIndex < $.lastWithdrawnStakingIndex[_msgSender()])
                nextStakingIndex = $.lastWithdrawnStakingIndex[_msgSender()];
            uint256 total = $.stakings[nextStakingIndex].total;
            nextStakingIndex++;
            if (firstStakingIndex == 0)
                firstStakingIndex = nextStakingIndex;
            while (
                posInStakingIndices == $.stakingIndices[_msgSender()].length - 1 ?
                nextStakingIndex < $.stakings.length :
                nextStakingIndex <= $.stakingIndices[_msgSender()][posInStakingIndices+1]
            ) {
                if (total > 0)
                    resultInTotal += $.stakings[nextStakingIndex].rewards * amount / total;
                total = $.stakings[nextStakingIndex].total;
                nextStakingIndex++;
                if (nextStakingIndex - firstStakingIndex > additionalSteps)
                    return (resultInTotal, resultAfterLastStaking, posInStakingIndices, nextStakingIndex);
            }
            // all rewards recorded in the stakings were taken into account
            if (nextStakingIndex == $.stakings.length) {
                // ensure that the next time we call withdrawRewards() the last nextStakingIndex
                // representing the rewards accrued since the last staking are not
                // included in the result any more - however, what if there have
                // been no stakings i.e. the last nextStakingIndex remains the same, but there
                // have been additional rewards - how can we determine the amount of
                // rewards added since we called withdrawRewards() last time?
                // nextStakingIndex++;
                // the last step is to add the rewards accrued since the last staking
                if (total > 0) {
                    resultAfterLastStaking = (int256(getRewards()) - $.totalRewards).toUint256() * amount / total;
                    resultInTotal += resultAfterLastStaking;
                }
            }
        }
        // ensure that the next time the function is called the initial value of posInStakingIndices
        // refers to the last amount and total among the stakingIndices of the staker that already
        // existed during the current call of the function so that we can continue from there
        if (posInStakingIndices > 0)
            posInStakingIndices--;
    }

    function collectCommission() public override {}

    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
       return interfaceId == type(INonLiquidDelegation).interfaceId || super.supportsInterface(interfaceId);
    }

    function interfaceId() public pure returns (bytes4) {
       return type(INonLiquidDelegation).interfaceId;
    }

}