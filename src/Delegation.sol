// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity ^0.8.26;

interface Delegation {

    // data can store additional information e.g. liquid staking tokens
    event Staked(address indexed delegator, uint256 amount, bytes data);
    event Unstaked(address indexed delegator, uint256 amount, bytes data);
    event Claimed(address indexed delegator, uint256 amount, bytes data);
    event CommissionPaid(address indexed owner, uint256 commission);
    
    function stake() external payable;
    function unstake(uint256) external returns(uint256);
    function claim() external;
    function collectCommission() external;
    function stakeRewards() external;
    function getMinDelegation() external view returns(uint256);
    function getCommission() external view returns(uint256, uint256);
    function getStake() external view returns(uint256);
    function getClaimable() external view returns(uint256);
    function getPendingClaims() external view returns(uint256[2][] memory);
}