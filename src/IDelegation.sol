// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity ^0.8.26;

/**
 * @notice The minimum interface delegation contracts are supposed to implement.
 *
 * @dev It ensures compatibility with the Zilliqa 2.0 staking portal.
 * 
 */
interface IDelegation {

    /**
    * @notice Emit the event when `delegator` stakes `amount` and store additional
    * information such as the amount of minted liquid staking tokens in `data`.
    */
    event Staked(address indexed delegator, uint256 amount, bytes data);

    /**
    * @notice Emit the event when `delegator` unstakes `amount` of tokens used to
    * represent shares of the total stake, and store additional information
    * such as the unstaked amount in ZIL in `data`.
    */
    event Unstaked(address indexed delegator, uint256 amount, bytes data);

    /**
    * @notice Emit the event when `delegator` withdraws `amount` after the unbonding
    * period, which was previously unstaked in one or more tranches and store
    * additional information in `data`.
    */
    event Claimed(address indexed delegator, uint256 amount, bytes data);

    /**
    * @notice Emit the event when transferring `commission` to `receiver`.
    */
    event CommissionPaid(address indexed receiver, uint256 commission);

    /**
    * @notice Stake the ZIL transferred in the transaction.
    */
    function stake() external payable;

    /**
    * @notice Unstake the number of tokens specified by the argument and return
    * the corresponding amount of ZIL.
    */
    function unstake(uint256) external returns(uint256);

    /**
    * @notice Transfer all funds unstaked by the caller using {unstake} that are
    * now available because their unbonding period is over.
    */
    function claim() external;

    /**
    * @notice Transfer all outstanding commissions to the configured receiver.
    * It must be called by the contract owner.
    */
    function collectCommission() external;

    /**
    * @notice Stake rewards accumulated in the contract balance.
    */
    function stakeRewards() external;

    /**
    * @notice Return the unbonding period that must be over before unstaked
    * funds can be withdrawn.
    */
    function unbondingPeriod() external view returns(uint256);

    /**
    * @notice Return the lowest amount of ZIL that can be delegated in a transaction.
    */
    function getMinDelegation() external view returns(uint256);

    /**
    * @notice The first value returned is the commission rate multiplied
    * by `DENOMINATOR`, the second value returned is `DENOMINATOR`.
    */
    function getCommission() external view returns(uint256, uint256);

    /**
    * @notice Return the total amount delegated to the staking pool. 
    */
    function getStake() external view returns(uint256);

    /**
    * @notice Return the amount of unstaked ZIL available for withdrawal
    * after the unbonding period using {claim}.
    */
    function getClaimable() external view returns(uint256);

    /**
    * @notice Return an array of tuples whose first element is the unstaked amount
    * in ZIL and the second element is the block number at which the unbonding
    * period is over and amount can be withdrawn using {claim}.
    */
    function getPendingClaims() external view returns(uint256[2][] memory);
}