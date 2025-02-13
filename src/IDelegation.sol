// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity ^0.8.26;

/**
 * @title The minimum interface delegation contracts are supposed to implement.
 *
 * @dev It ensures compatibility with the Zilliqa 2.0 staking portal.
 * 
 */
interface IDelegation {

/**
 * @dev Emit the event when `delegator` stakes `amount` and store additional
 * information such as the amount of minted liquid staking tokens in `data`.
 */
    event Staked(address indexed delegator, uint256 amount, bytes data);

/**
 * @dev Emit the event when `delegator` unstakes `amount` of tokens used to
 * represent shares of the total stake, and store additional information
 * such as the unstaked amount in ZIL in `data`.
 */
    event Unstaked(address indexed delegator, uint256 amount, bytes data);

/**
 * @dev Emit the event when `delegator` withdraws `amount` after the unbonding
 * period, which was previously unstaked in one or more tranches and store
 * additional information in `data`.
 */
    event Claimed(address indexed delegator, uint256 amount, bytes data);

/**
 * @dev Emit the event when transferring `commission` to `receiver`.
 */
    event CommissionPaid(address indexed receiver, uint256 commission);

/**
 * @dev Stake the ZIL transferred in the transaction.
 */
    function stake() external payable;

/**
 * @dev Unstake the number of tokens specified by the argument and return
 * the corresponding amount of ZIL.
 */
    function unstake(uint256) external returns(uint256);

/**
 * @dev Transfer all funds unstaked by the caller that are available after
 * the unbonding period.
 */
    function claim() external;

/**
 * @dev Transfer all outstanding commissions to the configured receiver.
 * Must be called by the contract owner.
 */
    function collectCommission() external;

/**
 * @dev Stake rewards accumulated in the contract balance.
 */
    function stakeRewards() external;

/**
 * @dev Return the lowest amount of ZIL that can be delegated in a transaction.
 */
    function getMinDelegation() external view returns(uint256);

/**
 * @dev The first value returned is the commission rate multiplied
 * by `DENOMINATOR`, the second value returned is `DENOMINATOR`.
 */
    function getCommission() external view returns(uint256, uint256);

/**
 * @dev Return the total amount delegated to the staking pool. 
 */
    function getStake() external view returns(uint256);

/**
 * @dev Return the amount of unstaked ZIL available for withdrawal
 * after the unbonding period.
 */
    function getClaimable() external view returns(uint256);

/**
 * @dev Returns an array of tuples whose first element is the unstaked amount
 * in ZIL and the second element is the block number at which the unbonding
 * period is over and amount can be withdrawn using {claim}.
 */
    function getPendingClaims() external view returns(uint256[2][] memory);
}