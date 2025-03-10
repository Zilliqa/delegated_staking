// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity ^0.8.26;

import {IDelegation} from "src/IDelegation.sol";
import {BaseDelegation} from "src/BaseDelegation.sol";
import {NonRebasingLST} from "src/NonRebasingLST.sol";

// keccak256(abi.encode(uint256(keccak256("zilliqa.storage.LiquidDelegation")) - 1)) & ~bytes32(uint256(0xff))
bytes32 constant LIQUID_VARIANT = 0xfa57cbed4b267d0bc9f2cbdae86b4d1d23ca818308f873af9c968a23afadfd00;

/**
 * @notice The liquid variant of the stake delegation contract that uses a
 * {NonRebasingLST} as liquid staking token. Every time users stake ZIL they
 * receive the corresponding amount of liquid staking tokens depending on the
 * current token price. The liquid staking token is non-rebasing, i.e. the token
 * balances are not adjusted to reflect the rewards earned by the staking pool.
 * Instead, the taxed rewards, i.e. the rewards after deducting the commission
 * are included in the token price.
 *
 * @dev The contract is registered as the reward address of all validators in the
 * staking pool, i.e. its balance can increase in every block. Since this does not
 * happen in form of transactions, the {receive} function will not notice it.
 */
// solhint-disable comprehensive-interface
contract LiquidDelegation is IDelegation, BaseDelegation {

    // ************************************************************************
    // 
    //                                 STATE
    // 
    // ************************************************************************

    /**
    * @dev `lst` stores the address of the {NonRebasingLST} token issued by the
    * {LiquidDelegation}. `taxedRewards` is the amount of rewards accrued that
    * the {LiquidDelegation} contract is aware of and has already deducted the
    * commission from. The contract balance is higher if new (untaxed) rewards
    * have been added to it since the last update of `taxedRewards`.
    */
    /// @custom:storage-location erc7201:zilliqa.storage.LiquidDelegation
    struct LiquidDelegationStorage {
        address lst;
        uint256 taxedRewards;
    }

    // solhint-disable const-name-snakecase
    bytes32 private constant LiquidDelegationStorageLocation = LIQUID_VARIANT;

    function _getLiquidDelegationStorage() private pure returns (LiquidDelegationStorage storage $) {
        assembly {
            $.slot := LiquidDelegationStorageLocation
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
    * @dev Let {BaseDelegation} migrate `fromVersion` to the current  `VERSION`.
    */
    function reinitialize(uint64 fromVersion) public reinitializer(VERSION) {
        migrate(fromVersion);
    }

    /**
    * @dev Initialize the base contracts and create the LST token contract.
    */
    function initialize(
        address initialOwner,
        string calldata name,
        string calldata symbol
    ) public initializer {
        __BaseDelegation_init(initialOwner);
        LiquidDelegationStorage storage $ = _getLiquidDelegationStorage();
        $.lst = address(new NonRebasingLST(name, symbol));
    }

    /// @inheritdoc BaseDelegation
    function variant() public override pure returns(bytes32) {
        return LIQUID_VARIANT;
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
    ) public override payable onlyOwner {
        if (msg.value > 0)
            _stake(msg.value, _msgSender());
        // the total stake must not be increased before the price is determined
        _increaseStake(msg.value);
        _depositAndAddToPool(
            blsPubKey,
            peerId,
            signature
        );
    } 

    /// @inheritdoc BaseDelegation
    function joinPool(
        bytes calldata blsPubKey,
        address controlAddress
    ) public override onlyOwner {
        // deduct the commission from the yet untaxed rewards
        // before calculating the number of shares
        taxRewards();
        _stake(getDeposit(blsPubKey), controlAddress);
        // increases the deposited stake hence it must
        // be called after calculating the shares
        _addToPool(blsPubKey, controlAddress);
    }

    /// @inheritdoc BaseDelegation
    function leavePool(bytes calldata blsPubKey) public override {
        if (!_preparedToLeave(blsPubKey))
            return;
        // deduct the commission from the yet untaxed rewards
        // before calculating the amount
        taxRewards();
        LiquidDelegationStorage storage $ = _getLiquidDelegationStorage();
        uint256 amount = _unstake(NonRebasingLST($.lst).balanceOf(_msgSender()), _msgSender());
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
    //                       STAKE, REWARDS, COMMISSION
    // 
    // ************************************************************************

    /**
    * @inheritdoc IDelegation
    * @dev Deduct the commission from the yet untaxed rewards before calculating the
    * number of liquid staking tokens corresponsing to the delegated amount. Increase
    * the deposit of the validators in the staking pool by the delegated amount.
    */
    function stake() public override(BaseDelegation, IDelegation) payable whenNotPaused {
        LiquidDelegationStorage storage $ = _getLiquidDelegationStorage();
        // if we are in the fundraising phase getRewards() would return 0 and
        // taxedRewards would be greater i.e. the commission calculated in
        // taxRewards() would be negative, therefore
        if (_isActivated()) {
            // the amount just delegated is now part of the rewards since
            // it was added to the balance therefore add it to the taxed
            // rewards too to avoid commission and remove it after taxing
            $.taxedRewards += msg.value;
            taxRewards();
            $.taxedRewards -= msg.value;
        }
        _stake(msg.value, _msgSender());
        // the total stake must not be increased before the price is determined
        _increaseStake(msg.value);
        _increaseDeposit(msg.value);
    }

    /**
    * @dev Calculate the shares of the `staker` based on the delegated `value`
    * and mint the corresponding amount of liquid staking tokens (LST).
    *
    * Emit {Staked} containing the `staker` address, the `value` staked, and
    * the corresponding amount of LST minted to the `staker`.
    *
    * Revert with {DelegatedAmountTooLow} containing the `value` lower
    * than {MIN_DELEGATION}.
    */
    function _stake(uint256 value, address staker) internal {
        require(value >= MIN_DELEGATION, DelegatedAmountTooLow(value));
        uint256 shares;
        LiquidDelegationStorage storage $ = _getLiquidDelegationStorage();
        if (NonRebasingLST($.lst).totalSupply() == 0)
            shares = value;
        else
            shares = NonRebasingLST($.lst).totalSupply() * value / (getStake() + $.taxedRewards);
        NonRebasingLST($.lst).mint(staker, shares);
        emit Staked(staker, value, abi.encode(shares));
    }

    /**
    * @inheritdoc IDelegation
    * @dev Deduct the commission from the yet untaxed rewards before calculating
    * the amount corresponding to the unstaked liquid staking tokens. Decrease
    * the deposit of the validators in the staking pool by the calculated amount.
    */
    function unstake(uint256 shares)
        public
        override(BaseDelegation, IDelegation)
        whenNotPaused
        returns(uint256 amount)
    {
        // if we are in the fundraising phase getRewards() would return 0 and
        // taxedRewards would be greater i.e. the commission calculated in
        // taxRewards() would be negative, therefore
        if (_isActivated())
            // deduct the commission from the yet untaxed rewards
            // before calculating the amount
            taxRewards();
        amount = _unstake(shares, _msgSender());
        _enqueueWithdrawal(amount);
        _decreaseDeposit(amount);
    }

    /**
    * @dev Calculate and return the `amount` of ZIL corresponding to the unstaked
    * `shares` i.e. liquid staking tokens of the `staker` and burn the unstaked
    * liquid staking tokens (LST).
    *
    * Emit {Unstaked} containing the `staker` address, the amount of ZIL unstaked,
    * and the number of LST `shares` burned.
    */
    function _unstake(uint256 shares, address staker) internal returns(uint256 amount) {
        LiquidDelegationStorage storage $ = _getLiquidDelegationStorage();
        if (NonRebasingLST($.lst).totalSupply() == 0)
            amount = shares;
        else
            amount = (getStake() + $.taxedRewards) * shares / NonRebasingLST($.lst).totalSupply();
        _stakeRewards();
        NonRebasingLST($.lst).burn(staker, shares);
        emit Unstaked(staker, amount, abi.encode(shares));
    }

    /**
    * @dev Return the amount of ZIL equivalent to 10**18 shares of the liquid
    * staking token supply.
    */
    function getPrice() public view returns(uint256 amount) {
        LiquidDelegationStorage storage $ = _getLiquidDelegationStorage();
        uint256 rewards = getRewards();
        uint256 commission = (rewards - $.taxedRewards) * getCommissionNumerator() / DENOMINATOR;
        if (NonRebasingLST($.lst).totalSupply() == 0)
            amount = 1 ether;
        else
            amount = (getStake() + rewards - commission) * 1 ether / NonRebasingLST($.lst).totalSupply();
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
    function taxRewards() internal {
        LiquidDelegationStorage storage $ = _getLiquidDelegationStorage();
        uint256 rewards = getRewards();
        uint256 commission = (rewards - $.taxedRewards) * getCommissionNumerator() / DENOMINATOR;
        $.taxedRewards = rewards - commission;
        if (commission == 0)
            return;
        // commissions are not subject to the unbonding period
        (bool success, ) = getCommissionReceiver().call{
            value: commission
        }("");
        require(success, TransferFailed(getCommissionReceiver(), commission));
        emit CommissionPaid(getCommissionReceiver(), commission);
    }

    /**
    * @inheritdoc IDelegation
    *
    * @dev Revert with {StakingPoolNotActivated} if the staking pool has not
    * earned any rewards yet.
    */
    function stakeRewards() public override(BaseDelegation, IDelegation) onlyOwner {
        require(_isActivated(), StakingPoolNotActivated());
        _stakeRewards();
    }

    /**
    * @dev Stake only the portion of the taxed rewards that are not needed for
    * covering the pending withdrawals.
    */
    function _stakeRewards() internal {
        LiquidDelegationStorage storage $ = _getLiquidDelegationStorage();
        // rewards must be taxed before being deposited since
        // they will not be taxed when they are unstaked later
        taxRewards();
        uint256 amount = getRewards();
        _increaseStake(amount);
        $.taxedRewards -= amount;
        _increaseDeposit(amount);
    }

    /**
    * @dev Return the amount of taxed rewards in the contract's balance.
    */
    function getTaxedRewards() public view returns(uint256) {
        LiquidDelegationStorage storage $ = _getLiquidDelegationStorage();
        return $.taxedRewards;
    } 

    /**
    * @dev Return the address of the liquid staking token contract of the staking pool.
    */
    function getLST() public view returns(address) {
        LiquidDelegationStorage storage $ = _getLiquidDelegationStorage();
        return $.lst;
    }

    /**
    * @inheritdoc IDelegation
    */
    function collectCommission() public override(BaseDelegation, IDelegation) onlyOwner {
        taxRewards();
    }

}