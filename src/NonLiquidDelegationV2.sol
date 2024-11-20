// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity ^0.8.26;

import "src/BaseDelegation.sol";
import "src/NonLiquidDelegation.sol";
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
        // the last staking index up to which the rewards
        // of the respective staker have been calculated
        // and added to allWithdrawnRewards
        mapping(address => uint64) lastWithdrawnRewardIndex;
        // balance of the reward address minus the
        // rewards accrued since the last staking
        int256 totalRewards;
    }

    // keccak256(abi.encode(uint256(keccak256("zilliqa.storage.NonLiquidDelegation")) - 1)) & ~bytes32(uint256(0xff))
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
    function reinitialize() reinitializer(version() + 1) public {
    }

    // called when stake withdrawn from the deposit contract is claimed
    // but not called when rewards are assigned to the reward address
    receive() payable external {
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
        uint64 lastWithdrawnRewardIndex
    ) {
        NonLiquidDelegationStorage storage $ = _getNonLiquidDelegationStorage();
        stakingIndices = $.stakingIndices[_msgSender()];
        firstStakingIndex = $.firstStakingIndex[_msgSender()];
        allWithdrawnRewards = $.allWithdrawnRewards[_msgSender()];
        lastWithdrawnRewardIndex = $.lastWithdrawnRewardIndex[_msgSender()];
    }

    function getDelegatedStake() public view returns(uint256 result) {
        NonLiquidDelegationStorage storage $ = _getNonLiquidDelegationStorage();
        uint64[] storage stakingIndices = $.stakingIndices[_msgSender()];
        if (stakingIndices.length > 0)
            result = $.stakings[stakingIndices[stakingIndices.length - 1]].amount;
    }

    event RewardPaid(address indexed owner, uint256 reward);
    event CommissionPaid(address indexed owner, uint256 commission);

    // called by the node's account that deployed this contract and is its owner
    // to request the node's activation as a validator using the delegated stake
    function deposit2(
        bytes calldata blsPubKey,
        bytes calldata peerId,
        bytes calldata signature
    ) public onlyOwner {
        _deposit(
            blsPubKey,
            peerId,
            signature,
            address(this).balance
        );
    }

    // called by the node's account that deployed this contract and is its owner
    // with at least the minimum stake to request the node's activation as a validator
    // before any stake is delegated to it
    function deposit(
        bytes calldata blsPubKey,
        bytes calldata peerId,
        bytes calldata signature
    ) public payable onlyOwner {
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
        (bool success, ) = _msgSender().call{
            value: total
        }("");
        $.totalRewards -= int256(total);
        require(success, "transfer of funds failed");
        emit Claimed(_msgSender(), total, "");
    }

    function stake() public override payable whenNotPaused {
        if (_isActivated())
            _increaseDeposit(msg.value);
        _append(int256(msg.value));
        emit Staked(_msgSender(), msg.value, "");
    }

    function unstake(uint256 value) public override whenNotPaused {
        _append(-int256(value));
        if (_isActivated())
            _decreaseDeposit(uint256(value));
        _enqueueWithdrawal(value);
        emit Unstaked(_msgSender(), value, "");
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
        (uint256 result, , ) = _rewards(additionalSteps);
        return result - result * getCommissionNumerator() / DENOMINATOR + $.allWithdrawnRewards[_msgSender()];
    }

    function rewards() public view returns(uint256) {
        NonLiquidDelegationStorage storage $ = _getNonLiquidDelegationStorage();
        (uint256 result, , ) = _rewards();
        return result - result * getCommissionNumerator() / DENOMINATOR + $.allWithdrawnRewards[_msgSender()];
    }

    function taxRewards(uint256 untaxedRewards) internal returns (uint256) {
        NonLiquidDelegationStorage storage $ = _getNonLiquidDelegationStorage();
        uint256 commission = untaxedRewards * getCommissionNumerator() / DENOMINATOR;
        if (commission == 0)
            return untaxedRewards;
        // commissions are not subject to the unbonding period
        (bool success, ) = owner().call{
            value: commission
        }("");
        require(success, "transfer of commission failed");
        $.totalRewards -= int256(commission);
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

    // if there have been more than 11,000 stakings or unstakings since the delegator's last reward
    // withdrawal, calling withdrawAllRewards() would exceed the block gas limit additionalSteps is
    // the number of additional stakings from which the rewards are withdrawn if zero, the rewards
    // are only withdrawn from the first staking from which they have not been withdrawn yet
    function withdrawRewards(uint256 amount, uint64 additionalSteps) public whenNotPaused returns(uint256) {
        NonLiquidDelegationStorage storage $ = _getNonLiquidDelegationStorage();
        (uint256 result, uint64 i, uint64 index) = additionalSteps == type(uint64).max ?
            _rewards() :
            _rewards(additionalSteps);
        // the caller has not delegated any stake
        if (index == 0)
            return 0;
        uint256 taxedRewards = taxRewards(result);
        $.allWithdrawnRewards[_msgSender()] += taxedRewards;
        $.firstStakingIndex[_msgSender()] = i;
        $.lastWithdrawnRewardIndex[_msgSender()] = index - 1;
        if (amount == type(uint256).max)
            amount = $.allWithdrawnRewards[_msgSender()];
        require(amount <= $.allWithdrawnRewards[_msgSender()], "can not withdraw more than accrued");
        $.allWithdrawnRewards[_msgSender()] -= amount;
        $.totalRewards -= int256(amount);
        (bool success, ) = _msgSender().call{value: amount}("");
        require(success, "transfer of rewards failed");
        emit RewardPaid(_msgSender(), amount);
        //TODO: shouldn't we return amount instead?
        return taxedRewards;
    }

    function _rewards() internal view returns(uint256 result, uint64 i, uint64 index) {
        return _rewards(type(uint64).max);
    }

    function _rewards(uint64 additionalSteps) internal view returns(uint256 result, uint64 i, uint64 index) {
        NonLiquidDelegationStorage storage $ = _getNonLiquidDelegationStorage();
        uint64 firstIndex;
        for (i = $.firstStakingIndex[_msgSender()]; i < $.stakingIndices[_msgSender()].length; i++) {
            index = $.stakingIndices[_msgSender()][i];
            uint256 amount = $.stakings[index].amount;
            if (index < $.lastWithdrawnRewardIndex[_msgSender()])
                index = $.lastWithdrawnRewardIndex[_msgSender()];
            uint256 total = $.stakings[index].total;
            index++;
            if (firstIndex == 0)
                firstIndex = index;
            while (i == $.stakingIndices[_msgSender()].length - 1 ? index < $.stakings.length : index <= $.stakingIndices[_msgSender()][i+1]) {
                if (total > 0)
                    result += $.stakings[index].rewards * amount / total;
                total = $.stakings[index].total;
                index++;
                if (index - firstIndex > additionalSteps)
                    return (result, i, index);
            }
            // all rewards recorded in the stakings were taken into account
            if (index == $.stakings.length) {
                // ensure that the next time we call withdrawRewards() the last index
                // representing the rewards accrued since the last staking are not
                // included in the result any more - however, what if there have
                // been no stakings i.e. the last index remains the same, but there
                // have been additional rewards - how can we determine the amount of
                // rewards added since we called withdrawRewards() last time?
                // index++;
                // the last step is to add the rewards accrued since the last staking
                if (total > 0)
                    result += (int256(getRewards()) - $.totalRewards).toUint256() * amount / total;
            }
        }
        // ensure that the next time the function is called the initial value of i refers
        // to the last amount and total among the stakingIndices of the staker that already
        // existed during the current call of the function so that we can continue from there
        if (i > 0)
            i--;
    }

    function collectCommission() public override {}

    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
       return interfaceId == type(INonLiquidDelegation).interfaceId || super.supportsInterface(interfaceId);
    }

    function interfaceId() public pure returns (bytes4) {
       return type(INonLiquidDelegation).interfaceId;
    }

}