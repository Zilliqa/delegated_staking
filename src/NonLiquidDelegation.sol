// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity ^0.8.26;

import "src/BaseDelegation.sol";

contract NonLiquidDelegation is BaseDelegation {

    //TODO: allow stakers to withdraw the rewards that accrued since the last staking 

    struct Staking {
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
        mapping(address => uint256[]) stakingIndices;
        // the first among the stakingIndices of the respective staker
        // based on which new rewards can be withdrawn
        mapping(address => uint256) firstStakingIndex;
        // already calculated portion of the rewards of the
        // respective staker that can be fully/partially
        // transferred to the staker
        mapping(address => uint256) allWithdrawnRewards;
        // the last staking index up to which the rewards
        // of the respective staker have been calculated
        // and added to allWithdrawnRewards
        mapping(address => uint256) lastWithdrawnRewardIndex;
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

    // TODO: check - call the _init() functions of the base contracts
    //       here or in __BaseDelegation_init()?
    function initialize(address initialOwner) initializer public {
        __BaseDelegation_init();
        __Pausable_init();
        __Ownable_init(initialOwner);
        __Ownable2Step_init();
        __UUPSUpgradeable_init();
    }

    function _authorizeUpgrade(address newImplementation) internal onlyOwner override {}

    receive() payable external {}

    //TODO: implement deposit

    function stake() public payable whenNotPaused {
        _append(int256(msg.value));
    }

    function unstake(uint256 value) public whenNotPaused {
        _append(-int256(value));
        //TODO: enqueue the withdrawal request so that it can be claimed after the unbonding period
    }

    function _append(int256 value) internal {
        NonLiquidDelegationStorage storage $ = _getNonLiquidDelegationStorage();
        int256 amount = value;
        if ($.stakingIndices[msg.sender].length > 0)
            amount += int256($.stakings[$.stakingIndices[msg.sender].length - 1].amount);
        require(amount >= 0, "can not unstake more than staked before");
        uint256 newRewards; // no rewards before the first staker is added
        if ($.stakings.length > 0) {
            value += int256($.stakings[$.stakings.length - 1].total);
            newRewards = 10_000; // address(this).balance;
        }
        $.stakings.push(Staking(uint256(amount), uint256(value), newRewards));
        $.stakingIndices[msg.sender].push($.stakings.length - 1);
    }

    // return how much gas it would cost to withdraw rewards from a certain
    // number of stakings as an indication of when we hit the block limit
    // note that the gas spent in the withdraw functions themselves is on top
    // TODO: check and fix the value returned, it varies based on the argument
    function getRewardsGas(uint256 additionalWithdrawals) public view returns(uint256) {
        uint256 gasStart = gasleft();
        rewards(additionalWithdrawals);
        return gasStart - gasleft() + 646;
    }

    // return how much gas it would cost to withdraw all rewards
    // as an indication of whether we hit the block limit
    // note that the gas spent in the withdraw functions is on top
    // TODO: check and fix the value returned
    function getRewardsGas() public view returns(uint256) {
        uint256 gasStart = gasleft();
        rewards();
        return gasStart - gasleft() + 327;
    }

    function rewards(uint256 additionalWithdrawals) public view returns(uint256) {
        NonLiquidDelegationStorage storage $ = _getNonLiquidDelegationStorage();
        (uint256 result, , ) = _rewards(additionalWithdrawals);
        return result + $.allWithdrawnRewards[msg.sender];
    }

    function rewards() public view returns(uint256) {
        NonLiquidDelegationStorage storage $ = _getNonLiquidDelegationStorage();
        (uint256 result, , ) = _rewards();
        return result + $.allWithdrawnRewards[msg.sender];
    }

    function withdrawRewards(uint256 amount) public whenNotPaused {
        withdrawRewards(amount, type(uint256).max);
    }

    // additionalWithdrawals is the number of additional stakings from which the rewards are withdrawn
    // if zero, the rewards are only withdrawn from the first staking from which they have not been withdrawn yet
    function withdrawRewards(uint256 amount, uint256 additionalWithdrawals) public whenNotPaused {
        NonLiquidDelegationStorage storage $ = _getNonLiquidDelegationStorage();
        (uint256 result, uint256 i, uint256 index) = _rewards(additionalWithdrawals);
        //TODO: shall we deduct and return the commission in _rewards(uint256)?
        $.allWithdrawnRewards[msg.sender] += result;
        $.firstStakingIndex[msg.sender] = i;
        $.lastWithdrawnRewardIndex[msg.sender] = index - 1;
        require(amount <= $.allWithdrawnRewards[msg.sender], "can not withdraw more than accrued");
        require(amount > 0, "can not withdraw zero amount");
        $.allWithdrawnRewards[msg.sender] -= amount;
        (bool success, ) = msg.sender.call{value: amount}("");
        require(success, "transfer of rewards failed");
    }

    function withdrawAllRewards() public whenNotPaused {
        NonLiquidDelegationStorage storage $ = _getNonLiquidDelegationStorage();
        (uint256 result, uint256 i, uint256 index) = _rewards();
        //TODO: shall we deduct and return the commission in _rewards(uint256)?
        $.allWithdrawnRewards[msg.sender] += result;
        $.firstStakingIndex[msg.sender] = i;
        $.lastWithdrawnRewardIndex[msg.sender] = index - 1;
        uint256 amount = $.allWithdrawnRewards[msg.sender];
        require(amount > 0, "can not withdraw zero amount");
        delete $.allWithdrawnRewards[msg.sender];
        (bool success, ) = msg.sender.call{value: amount}("");
        require(success, "transfer of rewards failed");
    }

    function _rewards() internal view returns(uint256 result, uint256 i, uint256 index) {
        return _rewards(type(uint256).max);
    }

    function _rewards(uint256 additionalWithdrawals) internal view returns(uint256 result, uint256 i, uint256 index) {
        NonLiquidDelegationStorage storage $ = _getNonLiquidDelegationStorage();
        uint256 firstIndex;
        for (i = $.firstStakingIndex[msg.sender]; i < $.stakingIndices[msg.sender].length; i++) {
            index = $.stakingIndices[msg.sender][i];
            if (index < $.lastWithdrawnRewardIndex[msg.sender])
                index = $.lastWithdrawnRewardIndex[msg.sender];
            uint256 amount = $.stakings[index].amount;
            uint256 total = $.stakings[index].total;
            index++;
            if (firstIndex == 0)
                firstIndex = index;
            while (i == $.stakingIndices[msg.sender].length - 1 ? index < $.stakings.length : index <= $.stakingIndices[msg.sender][i+1]) {
                result += $.stakings[index].rewards * amount / total;
                total = $.stakings[index].total;
                index++;
                if (index - firstIndex > additionalWithdrawals)
                    return (result, i, index);
            }
        }
        // ensure that the next time the function is called the initial value of i refers
        // to the last amount and total among the stakingIndices of the staker that already
        // existed during the current call of the function so that we can continue from there 
        i--;
    }

}