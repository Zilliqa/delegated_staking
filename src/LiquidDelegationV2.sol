// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity ^0.8.26;

import {BaseDelegation} from "src/BaseDelegation.sol";
import {ILiquidDelegation} from "src/LiquidDelegation.sol";
import {NonRebasingLST} from "src/NonRebasingLST.sol";

// the contract is supposed to be deployed with the node's signer account
contract LiquidDelegationV2 is BaseDelegation, ILiquidDelegation {

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

    // automatically incrementing the version number allows for
    // upgrading the contract without manually specifying the next
    // version number in the source file - use with caution since
    // it won't be possible to identify the actual version of the
    // source file without a hardcoded version number, but storing
    // the file versions in separate folders would help
    function reinitialize() public reinitializer(version() + 1) {
    }

    // called when stake withdrawn from the deposit contract is claimed
    // but not called when rewards are assigned to the reward address
    receive() external payable {
        LiquidDelegationStorage storage $ = _getLiquidDelegationStorage();
        // do not deduct commission from the withdrawn stake
        $.taxedRewards += msg.value;
    }

    // called by the node's owner who deployed this contract
    // to turn the already deposited validator node into a staking pool
    function migrate(bytes calldata blsPubKey) public override onlyOwner {
        _migrate(blsPubKey);
        LiquidDelegationStorage storage $ = _getLiquidDelegationStorage();
        require(NonRebasingLST($.lst).totalSupply() == 0, "stake already delegated");
        NonRebasingLST($.lst).mint(owner(), getStake());
    }

    // called by the node's owner who deployed this contract
    // to deposit the node as a validator using the delegated stake
    function depositLater(
        bytes calldata blsPubKey,
        bytes calldata peerId,
        bytes calldata signature
    ) public override onlyOwner {
        _deposit(
            blsPubKey,
            peerId,
            signature,
            address(this).balance
        );
    }

    // called by the node's owner who deployed this contract
    // with at least the minimum stake to deposit the node
    // as a validator before any stake is delegated to it
    function depositFirst(
        bytes calldata blsPubKey,
        bytes calldata peerId,
        bytes calldata signature
    ) public override payable onlyOwner {
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

    function stake() public override payable whenNotPaused {
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
        uint256 depositedStake = getStake();
        if (NonRebasingLST($.lst).totalSupply() == 0)
            // if the validator hasn't deposited yet, the formula for calculating the shares would divide by zero, therefore
            shares = msg.value;
        else
            // otherwise depositedStake is greater than zero even if the deposit hasn't been activated yet
            shares = NonRebasingLST($.lst).totalSupply() * msg.value / (depositedStake + $.taxedRewards);
        NonRebasingLST($.lst).mint(_msgSender(), shares);
        _increaseDeposit(msg.value);
        emit Staked(_msgSender(), msg.value, abi.encode(shares));
    }

    function unstake(uint256 shares) public override whenNotPaused returns(uint256 amount) {
        LiquidDelegationStorage storage $ = _getLiquidDelegationStorage();
        // before calculating the amount deduct the commission from the yet untaxed rewards
        taxRewards();
        if (NonRebasingLST($.lst).totalSupply() == 0)
            amount = shares;
        else
            amount = (getStake() + $.taxedRewards) * shares / NonRebasingLST($.lst).totalSupply();
        // stake the surplus of taxed rewards not needed for covering the pending withdrawals
        // before we increase the pending withdrawals by enqueueing the current amount
        _stakeRewards();
        _enqueueWithdrawal(amount);
        // maintain a balance that is always sufficient to cover the claims
        _decreaseDeposit(amount);
        NonRebasingLST($.lst).burn(_msgSender(), shares);
        emit Unstaked(_msgSender(), amount, abi.encode(shares));
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
        emit CommissionPaid(owner(), commission);
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
        $.taxedRewards -= total;
        (bool success, ) = _msgSender().call{
            value: total
        }("");
        require(success, "transfer of funds failed");
        emit Claimed(_msgSender(), total, "");
    }

    function stakeRewards() public override onlyOwner {
        _stakeRewards();
    }

    function _stakeRewards() internal {
        LiquidDelegationStorage storage $ = _getLiquidDelegationStorage();
        // rewards must be taxed before deposited since
        // they will not be taxed when they are unstaked
        taxRewards();
        // we must not deposit the funds we need to pay out the claims
        if (address(this).balance > getTotalWithdrawals()) {
            // not only the rewards (balance) must be reduced
            // by the deposit topup but also the taxed rewards
            $.taxedRewards -= address(this).balance - getTotalWithdrawals();
            _increaseDeposit(address(this).balance - getTotalWithdrawals());
        }
        // TODO: replace address(this).balance everywhere with getRewards()
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