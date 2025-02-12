// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity ^0.8.26;

import {BaseDelegation} from "src/BaseDelegation.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

// do not change this interface, it will break the detection of
// the staking variant of an already deployed delegation contract
interface INonLiquidDelegation {
    function interfaceId() external pure returns (bytes4);
    function getDelegatedAmount() external view returns(uint256);
    function rewards() external view returns(uint256);
}

contract NonLiquidDelegation is BaseDelegation, INonLiquidDelegation {
    using SafeCast for int256;

    struct Staking {
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
        // indices of (un)stakings by the respective staker
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
        // all rewards accrued until the last staking whereas the balance
        // also reflects the rewards accrued since then; the immutable
        // rewards only change when some of it is withdrawn or staked 
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

    function reinitialize(uint64 fromVersion) public reinitializer(VERSION) {
        migrate(fromVersion);
    }

    function initialize(address initialOwner) public initializer {
        __BaseDelegation_init(initialOwner);
    }

    // called when stake withdrawn from the deposit contract is claimed
    // but not called when rewards are assigned to the reward address
    receive() external payable {
        require(_msgSender() == DEPOSIT_CONTRACT, "sender must be the deposit contract");
        NonLiquidDelegationStorage storage $ = _getNonLiquidDelegationStorage();
        // add the stake withdrawn from the deposit to the reward balance
        $.immutableRewards += int256(msg.value);
    }

    function getImmutableRewards() public view returns(int256) {
        NonLiquidDelegationStorage storage $ = _getNonLiquidDelegationStorage();
        return $.immutableRewards;
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

    function getDelegatedAmount() public view returns(uint256 result) {
        NonLiquidDelegationStorage storage $ = _getNonLiquidDelegationStorage();
        uint64[] storage stakingIndices = $.stakingIndices[_msgSender()];
        if (stakingIndices.length > 0)
            result = $.stakings[stakingIndices[stakingIndices.length - 1]].amount;
    }

    function getDelegatedTotal() public view returns(uint256 result) {
        NonLiquidDelegationStorage storage $ = _getNonLiquidDelegationStorage();
        if ($.stakings.length > 0)
            result = $.stakings[$.stakings.length - 1].total;
    }

    function getNewAddress() public view returns(address) {
        NonLiquidDelegationStorage storage $ = _getNonLiquidDelegationStorage();
        return $.newAddress[_msgSender()];
    }

    function setNewAddress(address to) public {
        NonLiquidDelegationStorage storage $ = _getNonLiquidDelegationStorage();
        $.newAddress[_msgSender()] = to;
    }

    function replaceOldAddress(address old) public {
        NonLiquidDelegationStorage storage $ = _getNonLiquidDelegationStorage();
        address sender = _msgSender();
        require($.newAddress[old] == sender, "must be called by the new address");
        /* keep the original staking addresses to save gas
        for (uint64 i = 0; i < $.stakingIndices[old].length; i++)
            $.stakings[$.stakingIndices[old][i]].staker = sender;
        */
        $.stakingIndices[sender] = $.stakingIndices[old];
        delete $.stakingIndices[old];
        $.firstStakingIndex[sender] = $.firstStakingIndex[old];
        $.allWithdrawnRewards[sender] = $.allWithdrawnRewards[old];
        $.lastWithdrawnStakingIndex[sender] = $.lastWithdrawnStakingIndex[old];
        $.withdrawnAfterLastStaking[sender] = $.withdrawnAfterLastStaking[old];
        delete $.firstStakingIndex[old];
        delete $.allWithdrawnRewards[old];
        delete $.lastWithdrawnStakingIndex[old];
        delete $.withdrawnAfterLastStaking[old];
        delete $.newAddress[old];
    } 

    event RewardPaid(address indexed delegator, uint256 reward);

    // called by the contract owner to add an already deposited validator to the staking pool
    function join(bytes calldata blsPubKey, address controlAddress) public override onlyOwner {
        _join(blsPubKey, controlAddress);

        // the node's deposit must also be recorded in the staking history otherwise
        // its owner would not benefit from the rewards accrued due to the deposit
        _append(int256(getStake(blsPubKey)), controlAddress);
    }

    function _completeLeaving(uint256 amount) internal override {
        // if there is no other validator left, the withdrawn deposit will not
        // be deposited with the remaining validators but stay in the balance
        if (validators().length > 1) {
            NonLiquidDelegationStorage storage $ = _getNonLiquidDelegationStorage();
            $.immutableRewards -= int256(amount);
        }
    }

    // called by the validator node's original control address to remove the validator from
    // the staking pool, reducing the pool's total stake by the validator's current deposit
    function leave(bytes calldata blsPubKey) public override {
        if (!_preparedToLeave(blsPubKey))
            return;
        NonLiquidDelegationStorage storage $ = _getNonLiquidDelegationStorage();
        require($.stakingIndices[_msgSender()].length > 0, "staker not found");
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

    // called by the contract owner to turn the staking pool's first node into a validator
    // by depositing the value sent with this transaction and the amounts delegated before 
    function deposit(
        bytes calldata blsPubKey,
        bytes calldata peerId,
        bytes calldata signature
    ) public payable override onlyOwner {
        _deposit(
            blsPubKey,
            peerId,
            signature,
            getStake()
        );

        // the owner's deposit must also be recorded as staking otherwise
        // the owner would not benefit from the rewards accrued by the deposit
        if (msg.value > 0)
            _append(int256(msg.value), _msgSender());
    }

    function claim() public override whenNotPaused {
        NonLiquidDelegationStorage storage $ = _getNonLiquidDelegationStorage();
        uint256 total = _dequeueWithdrawals();
        /*if (total == 0)
            return;*/
        // withdraw the unstaked deposit once the unbonding period is over
        _withdrawDeposit();
        $.immutableRewards -= int256(total);
        (bool success, ) = _msgSender().call{
            value: total
        }("");
        require(success, "transfer of funds failed");
        emit Claimed(_msgSender(), total, "");
    }

    function stake() public override payable whenNotPaused {
        _increaseDeposit(msg.value);
        _append(int256(msg.value), _msgSender());
        emit Staked(_msgSender(), msg.value, "");
    }

    function unstake(uint256 value) public override whenNotPaused returns(uint256 amount) {
        _append(-int256(value), _msgSender());
        if (validators().length > 0)
            _decreaseDeposit(uint256(value));
        _enqueueWithdrawal(value);
        emit Unstaked(_msgSender(), value, "");
        return value;
    }

    function _append(int256 value, address staker) internal {
        if (value > 0)
            require(uint256(value) >= MIN_DELEGATION, "delegated amount too low");
        NonLiquidDelegationStorage storage $ = _getNonLiquidDelegationStorage();
        int256 amount = value;
        if ($.stakingIndices[staker].length > 0)
            amount += int256($.stakings[$.stakingIndices[staker][$.stakingIndices[staker].length - 1]].amount);
        require(amount >= 0, "can not unstake more than staked before");
        uint256 newRewards; // no rewards before the first staker is added
        if ($.stakings.length > 0) {
            value += int256($.stakings[$.stakings.length - 1].total);
            newRewards = (int256(getRewards()) - $.immutableRewards).toUint256();
        }
        $.immutableRewards = int256(getRewards());
        $.stakings.push(Staking(staker, uint256(amount), uint256(value), newRewards));
        $.stakingIndices[staker].push(uint64($.stakings.length - 1));
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
        $.immutableRewards -= int256(commission);
        // commissions are not subject to the unbonding period
        (bool success, ) = getCommissionReceiver().call{
            value: commission
        }("");
        require(success, "transfer of commission failed");
        emit CommissionPaid(getCommissionReceiver(), commission);
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
        _append(int256(amount), _msgSender());
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
        $.immutableRewards -= int256(amount);
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
        uint256 amount;
        uint256 total;
        for (
            posInStakingIndices = $.firstStakingIndex[_msgSender()];
            posInStakingIndices < $.stakingIndices[_msgSender()].length;
            posInStakingIndices++
        ) {
            nextStakingIndex = $.stakingIndices[_msgSender()][posInStakingIndices];
            amount = $.stakings[nextStakingIndex].amount;
            if (nextStakingIndex < $.lastWithdrawnStakingIndex[_msgSender()])
                nextStakingIndex = $.lastWithdrawnStakingIndex[_msgSender()];
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

    function collectCommission() public override {}

    function supportsInterface(bytes4 _interfaceId) public view override returns (bool) {
       return _interfaceId == type(INonLiquidDelegation).interfaceId || super.supportsInterface(_interfaceId);
    }

    function interfaceId() public pure returns (bytes4) {
       return type(INonLiquidDelegation).interfaceId;
    }

}