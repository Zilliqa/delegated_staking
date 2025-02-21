// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity ^0.8.26;

import {IDelegation} from "src/IDelegation.sol";
import {BaseDelegation} from "src/BaseDelegation.sol";
import {NonRebasingLST} from "src/NonRebasingLST.sol";

/**
 * @notice Minimal interface with functions specific to the {LiquidDelegation} variant.
 * There must be at least one function that makes the interface unique among all variants.
 *
 * @dev Do not change this interface, otherwise it will break the detection of the staking
 * variant of already deployed delegation contracts.
 */
interface ILiquidDelegation {
    function interfaceId() external pure returns (bytes4);
    function getLST() external view returns (address);
    function getPrice() external view returns(uint256);
}

/**
 * @notice The liquid variant of the stake delegation contract. It uses {NonRebasingLST}
 * as liquid staking token implementation. Every time users stake ZIL they receive the
 * corresponding amount of liquid staking tokens depending on the current token price.
 * The liquid staking token is non-rebasing, i.e. the token balances are not adjusted
 * to reflect the rewards earned by the staking pool. Instead, the taxed rewards, i.e.
 * the rewards after deducting the commission are included in the token price.
 *
 * @dev The contract is registered as the reward address of all validators in the
 * staking pool, i.e. its balance can increase in every block. Since this does not
 * happen in form of transactions, the {receive} function will not notice it.
 */
contract LiquidDelegation is IDelegation, BaseDelegation, ILiquidDelegation {

    /**
    * @dev `lst` is the address of the {NonRebasingLST} token issued by the {LiquidDelegation}.
    * `taxedRewards` is the amount of rewards accrued that the {LiquidDelegation} contract is
    * aware of and has already deducted the commission (tax) from. The contract balance is higher
    * if new (untaxed) rewards have been added to it since the last update of `taxedRewards`.
    */
    /// @custom:storage-location erc7201:zilliqa.storage.LiquidDelegation
    struct LiquidDelegationStorage {
        address lst;
        uint256 taxedRewards;
    }

    // keccak256(abi.encode(uint256(keccak256("zilliqa.storage.LiquidDelegation")) - 1)) & ~bytes32(uint256(0xff))
    // solhint-disable const-name-snakecase
    bytes32 private constant LiquidDelegationStorageLocation = 0xfa57cbed4b267d0bc9f2cbdae86b4d1d23ca818308f873af9c968a23afadfd00;

    function _getLiquidDelegationStorage() private pure returns (LiquidDelegationStorage storage $) {
        assembly {
            $.slot := LiquidDelegationStorageLocation
        }
    }

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
    function initialize(address initialOwner, string calldata name, string calldata symbol) public initializer {
        __BaseDelegation_init(initialOwner);
        LiquidDelegationStorage storage $ = _getLiquidDelegationStorage();
        $.lst = address(new NonRebasingLST(name, symbol));
    }

    /// @inheritdoc BaseDelegation
    function join(bytes calldata blsPubKey, address controlAddress) public override onlyOwner {
        // deduct the commission from the yet untaxed rewards before calculating the number of shares
        taxRewards();
        _stake(getStake(blsPubKey), controlAddress);
        // increases the deposited stake hence it must be called after calculating the shares
        _join(blsPubKey, controlAddress);
    }

    /// @inheritdoc BaseDelegation
    function leave(bytes calldata blsPubKey) public override {
        if (!_preparedToLeave(blsPubKey))
            return;
        // deduct the commission from the yet untaxed rewards before calculating the amount
        taxRewards();
        LiquidDelegationStorage storage $ = _getLiquidDelegationStorage();
        uint256 amount = _unstake(NonRebasingLST($.lst).balanceOf(_msgSender()), _msgSender());
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
    ) public override payable onlyOwner {
        if (msg.value > 0)
            _stake(msg.value, _msgSender());
        // the total stake must not be increased before the price is determined
        _increaseStake(msg.value);
        _deposit(
            blsPubKey,
            peerId,
            signature
        );
    } 

    /**
    * @inheritdoc IDelegation
    * @dev Deduct the commission from the yet untaxed rewards before calculating the number of liquid
    * staking tokens corresponsing to the delegated amount. Increase the deposit of the validators in
    * the staking pool by the delegated amount.
    */
    function stake() public override(BaseDelegation, IDelegation) payable whenNotPaused {
        LiquidDelegationStorage storage $ = _getLiquidDelegationStorage();
        // if we are in the fundraising phase getRewards() would return 0 and taxedRewards would
        // be greater i.e. the commission calculated in taxRewards() would be negative, therefore
        if (_isActivated()) {
            // the amount just delegated is now part of the rewards since it was added to the balance
            // therefore add it to the taxed rewards too to avoid commission and remove it after taxing
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
    * @dev Calculate the shares of the `staker` based on the delegated `value` and mint the corresponding
    * liquid staking tokens.
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
    * @dev Deduct the commission from the yet untaxed rewards before calculating the amount corresponding
    * to the unstaked liquid staking tokens. Decrease the deposit of the validators in the staking pool
    * by the calculated amount.
    */
    function unstake(uint256 shares) public override(BaseDelegation, IDelegation) whenNotPaused returns(uint256 amount) {
        // if we are in the fundraising phase getRewards() would return 0 and taxedRewards would
        // be greater i.e. the commission calculated in taxRewards() would be negative, therefore
        if (_isActivated())
            // deduct the commission from the yet untaxed rewards before calculating the amount
            taxRewards();
        amount = _unstake(shares, _msgSender());
        _enqueueWithdrawal(amount);
        _decreaseDeposit(amount);
    }

    /**
    * @dev Calculate and return the `amount` of ZIL corresponding to the unstaked `shares` i.e. liquid
    * staking tokens of the `staker` and burn the unstaked liquid staking tokens.
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
    * @dev Return the amount of ZIL equivalent to 10**18 shares of the liquid staking token supply.
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
    * @dev Deduct the commission from the yet untaxed rewards and transfer it to the configured
    * commission receiver address.
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
    */
    function claim() public override(BaseDelegation, IDelegation) whenNotPaused {
        uint256 total = _dequeueWithdrawals();
        if (total == 0)
            return;
        // before the balance changes deduct the commission from the yet untaxed rewards
        taxRewards();
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
    function stakeRewards() public override(BaseDelegation, IDelegation) onlyOwner {
        require(_isActivated(), StakingPoolNotActivated());
        _stakeRewards();
    }

    /**
    * @dev Stake only the portion of the taxed rewards that are not needed for covering
    * the pending withdrawals.
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
    * @inheritdoc IDelegation
    */
    function collectCommission() public override(BaseDelegation, IDelegation) onlyOwner {
        taxRewards();
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
    * @dev See https://eips.ethereum.org/EIPS/eip-165
    */
    function supportsInterface(bytes4 _interfaceId) public view override returns (bool) {
       return _interfaceId == type(ILiquidDelegation).interfaceId || super.supportsInterface(_interfaceId);
    }

    /**
    * @dev Returns the interface id that can be used to identify which delegated staking
    * variant the contract implements.  
    */
    function interfaceId() public pure returns (bytes4) {
       return type(ILiquidDelegation).interfaceId;
    }

}