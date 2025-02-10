// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity ^0.8.26;

import {BaseDelegation} from "src/BaseDelegation.sol";
import {NonRebasingLST} from "src/NonRebasingLST.sol";

// do not change this interface, it will break the detection of
// the staking variant of an already deployed delegation contract
interface ILiquidDelegation {
    function interfaceId() external pure returns (bytes4);
    function getLST() external view returns (address);
    function getPrice() external view returns(uint256);
}

contract LiquidDelegation is BaseDelegation, ILiquidDelegation {

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

    function reinitialize(uint64 fromVersion) public reinitializer(VERSION) {
        migrate(fromVersion);
    }

    function initialize(address initialOwner, string calldata name, string calldata symbol) public initializer {
        __BaseDelegation_init(initialOwner);
        LiquidDelegationStorage storage $ = _getLiquidDelegationStorage();
        $.lst = address(new NonRebasingLST(address(this), name, symbol));
        migrate(1);
    }

    // called when stake withdrawn from the deposit contract is claimed
    // but not called when rewards are assigned to the reward address
    receive() external payable {
        require(_msgSender() == DEPOSIT_CONTRACT, "sender must be the deposit contract");
        LiquidDelegationStorage storage $ = _getLiquidDelegationStorage();
        // do not deduct commission from the withdrawn stake
        $.taxedRewards += msg.value;
    }

    // called by the contract owner to add an already deposited validator to the staking pool
    function join(bytes calldata blsPubKey, address controlAddress) public override onlyOwner {
        // deduct the commission from the yet untaxed rewards before calculating the number of shares
        taxRewards();

        _stake(getStake(blsPubKey), controlAddress);

        // increases the deposited stake hence it must be called after calculating the shares
        _join(blsPubKey, controlAddress);
    }

    function _completeLeaving(uint256 amount) internal override {
        // if there is no other validator left, the withdrawn deposit will not
        // be deposited with the remaining validators but stay in the balance
        if (validators().length > 1) {
            LiquidDelegationStorage storage $ = _getLiquidDelegationStorage();
            $.taxedRewards -= amount;
        }
    }

    // called by the validator node's original control address to remove the validator from
    // the staking pool, reducing the pool's total stake by the validator's current deposit
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

    // called by the contract owner to turn the staking pool's first node into a validator
    // by depositing the value sent with this transaction and the amounts delegated before 
    function deposit(
        bytes calldata blsPubKey,
        bytes calldata peerId,
        bytes calldata signature
    ) public override payable onlyOwner {
        if (msg.value > 0)
            _stake(msg.value, _msgSender());

        _deposit(
            blsPubKey,
            peerId,
            signature,
            getStake()
        );
    } 

    function stake() public override payable whenNotPaused {
        LiquidDelegationStorage storage $ = _getLiquidDelegationStorage();
        // if we are in the fundraising phase getRewards() would return 0 and taxedRewards would
        // be greater i.e. the commission calculated in taxRewards() would be negative, therefore
        if (_isActivated()) {
            // the amount just delegated is now part of the rewards since it was added to the balance
            // therefore add it to the taxed rewards too to avoid commission and remove it after taxing
            $.taxedRewards += msg.value;
            // deduct the commission from the yet untaxed rewards before calculating the number of shares
            taxRewards();
            $.taxedRewards -= msg.value;
        }
        _stake(msg.value, _msgSender());
        _increaseDeposit(msg.value);
    }

    function _stake(uint256 value, address staker) internal {
        require(value >= MIN_DELEGATION, "delegated amount too low");
        uint256 shares;
        LiquidDelegationStorage storage $ = _getLiquidDelegationStorage();
        uint256 depositedStake = getStake();
        // if no validator has been activated yet, the depositedStake equals the
        // balance that contains all delegations including the current one unless
        // the first validator is just joining right now and depositedStake is zero
        if (!_isActivated() && depositedStake > 0)
            depositedStake -= value;
        if (NonRebasingLST($.lst).totalSupply() == 0)
            // if no validator deposited yet the formula for calculating the shares
            // would divide by zero, hence
            shares = value;
        else
            // otherwise depositedStake is greater than zero even if the deposit hasn't been activated yet
            shares = NonRebasingLST($.lst).totalSupply() * value / (depositedStake + $.taxedRewards);
        NonRebasingLST($.lst).mint(staker, shares);
        emit Staked(staker, value, abi.encode(shares));
    }

    function unstake(uint256 shares) public override whenNotPaused returns(uint256 amount) {
        // if we are in the fundraising phase getRewards() would return 0 and taxedRewards would
        // be greater i.e. the commission calculated in taxRewards() would be negative, therefore
        if (_isActivated())
            // deduct the commission from the yet untaxed rewards before calculating the amount
            taxRewards();
        amount = _unstake(shares, _msgSender());
        _enqueueWithdrawal(amount);
        if (validators().length > 0)
            _decreaseDeposit(amount);
    }

    function _unstake(uint256 shares, address staker) internal returns(uint256 amount) {
        LiquidDelegationStorage storage $ = _getLiquidDelegationStorage();
        if (NonRebasingLST($.lst).totalSupply() == 0)
            amount = shares;
        else
            amount = (getStake() + $.taxedRewards) * shares / NonRebasingLST($.lst).totalSupply();
        // stake the surplus of taxed rewards not needed for covering the pending withdrawals
        // before we increase the pending withdrawals by enqueueing the amount being unstaked
        _stakeRewards();
        NonRebasingLST($.lst).burn(staker, shares);
        emit Unstaked(staker, amount, abi.encode(shares));
    }

    // return the amount of ZIL equivalent to 1 LST (share)
    function getPrice() public view returns(uint256 amount) {
        LiquidDelegationStorage storage $ = _getLiquidDelegationStorage();
        uint256 rewards = getRewards();
        uint256 commission = (rewards - $.taxedRewards) * getCommissionNumerator() / DENOMINATOR;
        if (NonRebasingLST($.lst).totalSupply() == 0)
            amount = 1 ether;
        else
            amount = (getStake() + rewards - commission) * 1 ether / NonRebasingLST($.lst).totalSupply();
    }

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
        require(success, "transfer of commission failed");
        emit CommissionPaid(getCommissionReceiver(), commission);
    }

    function claim() public override whenNotPaused {
        LiquidDelegationStorage storage $ = _getLiquidDelegationStorage();
        uint256 total = _dequeueWithdrawals();
        /*if (total == 0)
            return;*/
        // before the balance changes deduct the commission from the yet untaxed rewards
        taxRewards();
        // withdraw the unstaked deposit once the unbonding period is over
        _withdrawDeposit();
        // prevent underflow if there is nothing to withdraw hence taxedRewards is zero
        if (_isActivated())
            $.taxedRewards -= total;
        (bool success, ) = _msgSender().call{
            value: total
        }("");
        require(success, "transfer of funds failed");
        emit Claimed(_msgSender(), total, "");
    }

    function stakeRewards() public override onlyOwner {
        require(_isActivated(), "No validator activated and rewards earned yet");
        _stakeRewards();
    }

    function _stakeRewards() internal {
        LiquidDelegationStorage storage $ = _getLiquidDelegationStorage();
        // rewards must be taxed before deposited since
        // they will not be taxed when they are unstaked
        taxRewards();
        // we must not deposit the funds we need to pay out the claims
        uint256 amount = getRewards();
        if (amount > getTotalWithdrawals()) {
            bool success = _increaseDeposit(amount - getTotalWithdrawals());
            if (success)
                // not only the rewards (balance) must be reduced
                // by the deposit topup but also the taxed rewards
                $.taxedRewards -= amount - getTotalWithdrawals();
        }
    }

    function collectCommission() public override onlyOwner {
        taxRewards();
    }

    // this function was only made public for testing purposes
    function getTaxedRewards() public view returns(uint256) {
        LiquidDelegationStorage storage $ = _getLiquidDelegationStorage();
        return $.taxedRewards;
    } 

    function getLST() public view returns(address) {
        LiquidDelegationStorage storage $ = _getLiquidDelegationStorage();
        return $.lst;
    }

    function supportsInterface(bytes4 _interfaceId) public view override returns (bool) {
       return _interfaceId == type(ILiquidDelegation).interfaceId || super.supportsInterface(_interfaceId);
    }

    function interfaceId() public pure returns (bytes4) {
       return type(ILiquidDelegation).interfaceId;
    }

}