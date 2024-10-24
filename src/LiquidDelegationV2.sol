// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity ^0.8.26;

import "src/BaseDelegation.sol";
import "src/NonRebasingLST.sol";

// the contract is supposed to be deployed with the node's signer account
contract LiquidDelegationV2 is BaseDelegation {

    /// @custom:storage-location erc7201:zilliqa.storage.LiquidDelegation
    struct LiquidDelegationStorage {
        address lst;
        uint256 taxedRewards;
    }

    // keccak256(abi.encode(uint256(keccak256("zilliqa.storage.LiquidDelegation")) - 1)) & ~bytes32(uint256(0xff))
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

    function reinitialize() reinitializer(version() + 1) public {
    }

    function _authorizeUpgrade(address newImplementation) internal onlyOwner override {}

    event Staked(address indexed delegator, uint256 amount, uint256 shares);
    event Unstaked(address indexed delegator, uint256 amount, uint256 shares);
    event Claimed(address indexed delegator, uint256 amount);
    event CommissionPaid(address indexed owner, uint256 rewardsBefore, uint256 committion);

    // called when stake withdrawn from the deposit contract is claimed
    // but not called when rewards are assigned to the reward address
    receive() payable external {
        LiquidDelegationStorage storage $ = _getLiquidDelegationStorage();
        // do not deduct commission from the withdrawn stake
        $.taxedRewards += msg.value;
    }

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
        LiquidDelegationStorage storage $ = _getLiquidDelegationStorage();
        require(NonRebasingLST($.lst).totalSupply() == 0, "stake already delegated");
        NonRebasingLST($.lst).mint(owner(), msg.value);
    } 

    function stake() public payable whenNotPaused {
        require(msg.value >= MIN_DELEGATION, "delegated amount too low");
        uint256 shares;
        LiquidDelegationStorage storage $ = _getLiquidDelegationStorage();
        // deduct commission from the rewards only if already activated as a validator
        // otherwise getRewards() returns 0 but taxedRewards would be greater than 0
        if (_isActivated()) {
            // the delegated amount is temporarily part of the rewards as it's in the balance
            // add to the taxed rewards to avoid commission and remove it again after taxing
            $.taxedRewards += msg.value;
            // before calculating the shares deduct the commission from the yet untaxed rewards
            taxRewards();
            $.taxedRewards -= msg.value;
        }
        if (NonRebasingLST($.lst).totalSupply() == 0)
            shares = msg.value;
        else
            shares = NonRebasingLST($.lst).totalSupply() * msg.value / (getStake() + $.taxedRewards);
        NonRebasingLST($.lst).mint(msg.sender, shares);
        _increaseDeposit(msg.value);
        emit Staked(msg.sender, msg.value, shares);
    }

    function unstake(uint256 shares) public whenNotPaused {
        uint256 amount;
        LiquidDelegationStorage storage $ = _getLiquidDelegationStorage();
        // before calculating the amount deduct the commission from the yet untaxed rewards
        taxRewards();
        if (NonRebasingLST($.lst).totalSupply() == 0)
            amount = shares;
        else
            amount = (getStake() + $.taxedRewards) * shares / NonRebasingLST($.lst).totalSupply();
        _enqueueWithdrawal(amount);
        // maintain a balance that is always sufficient to cover the claims
        if (address(this).balance < getTotalWithdrawals())
            _decreaseDeposit(getTotalWithdrawals() - address(this).balance);
        NonRebasingLST($.lst).burn(msg.sender, shares);
        emit Unstaked(msg.sender, amount, shares);
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
        (bool success, ) = owner().call{
            value: commission
        }("");
        require(success, "transfer of commission failed");
        emit CommissionPaid(owner(), rewards, commission);
    }

    function claim() public whenNotPaused {
        LiquidDelegationStorage storage $ = _getLiquidDelegationStorage();
        uint256 total = _dequeueWithdrawals();
        /*if (total == 0)
            return;*/
        // before the balance changes deduct the commission from the yet untaxed rewards
        taxRewards();
        //TODO: claim all deposit withdrawals requested whose unbonding period is over
        (bool success, ) = msg.sender.call{
            value: total
        }("");
        require(success, "transfer of funds failed");
        $.taxedRewards -= total;
        emit Claimed(msg.sender, total);
    }

    //TODO: make it onlyOwnerOrContract and call it every time someone stakes, unstakes or claims?
    function stakeRewards() public onlyOwner {
        // before the balance changes deduct the commission from the yet untaxed rewards
        taxRewards();
        if (address(this).balance > getTotalWithdrawals())
            _increaseDeposit(address(this).balance - getTotalWithdrawals());
    }

    function collectCommission() public onlyOwner {
        taxRewards();
    }

    function getTaxedRewards() public view returns(uint256) {
        LiquidDelegationStorage storage $ = _getLiquidDelegationStorage();
        return $.taxedRewards;
    } 

    function getLST() public view returns(address) {
        LiquidDelegationStorage storage $ = _getLiquidDelegationStorage();
        return $.lst;
    }

}