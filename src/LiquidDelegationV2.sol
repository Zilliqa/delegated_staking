// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity ^0.8.26;

import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "src/NonRebasingLST.sol";

library WithdrawalQueue {

    //TODO: add it to the variables and implement a getter and an onlyOwner setter
    //      since a governance vote can change the unbonding period anytime or fetch
    //      it from the deposit contract
    uint256 public constant UNBONDING_PERIOD = 30; //approx. 30s, used only for testing

    struct Item {
        uint256 blockNumber;
        uint256 amount;
    }

    struct Fifo {
        uint256 first;
        uint256 last;
        mapping(uint256 => Item) items;
    }

    function queue(Fifo storage fifo, uint256 amount) internal {
        fifo.items[fifo.last] = Item(block.number + UNBONDING_PERIOD, amount);
        fifo.last++;
    }

    function dequeue(Fifo storage fifo) internal returns(Item memory result) {
        require(fifo.first < fifo.last, "queue empty");
        result = fifo.items[fifo.first];
        delete fifo.items[fifo.first];
        fifo.first++;
    }

    function ready(Fifo storage fifo, uint256 index) internal view returns(bool) {
        return index < fifo.last && fifo.items[index].blockNumber <= block.number;
    }

    function ready(Fifo storage fifo) internal view returns(bool) {
        return ready(fifo, fifo.first);
    }
}

// the contract is supposed to be deployed with the node's signer account
contract LiquidDelegationV2 is Initializable, PausableUpgradeable, Ownable2StepUpgradeable, UUPSUpgradeable {

    using WithdrawalQueue for WithdrawalQueue.Fifo;

    /// @custom:storage-location erc7201:zilliqa.storage.LiquidDelegation
    struct LiquidDelegationStorage {
        address lst;
        bytes blsPubKey;
        bytes peerId;
        uint256 commissionNumerator;
        uint256 taxedRewards;
        mapping(address => WithdrawalQueue.Fifo) withdrawals;
        uint256 totalWithdrawals;
    }

    // keccak256(abi.encode(uint256(keccak256("zilliqa.storage.LiquidDelegation")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant LiquidDelegationStorageLocation = 0xfa57cbed4b267d0bc9f2cbdae86b4d1d23ca818308f873af9c968a23afadfd00;

    function _getLiquidDelegationStorage() private pure returns (LiquidDelegationStorage storage $) {
        assembly {
            $.slot := LiquidDelegationStorageLocation
        }
    }

    uint256 public constant MIN_DELEGATION = 100 ether;
    address public constant DEPOSIT_CONTRACT = 0x000000000000000000005a494C4445504F534954;
    uint256 public constant DENOMINATOR = 10_000;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function version() public view returns(uint64) {
        return _getInitializedVersion();
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

    function _deposit(
        bytes calldata blsPubKey,
        bytes calldata peerId,
        bytes calldata signature,
        uint256 depositAmount
    ) internal {
        LiquidDelegationStorage storage $ = _getLiquidDelegationStorage();
        require($.blsPubKey.length == 0, "deposit already performed");
        $.blsPubKey = blsPubKey;
        $.peerId = peerId;
        (bool success, bytes memory data) = DEPOSIT_CONTRACT.call{
            value: depositAmount
        }(
            //abi.encodeWithSignature("deposit(bytes,bytes,bytes,address,address)",
            //TODO: replace next line with the previous one once the signer address is implemented
            abi.encodeWithSignature("deposit(bytes,bytes,bytes,address)",
                blsPubKey,
                peerId,
                signature,
                address(this)
                //TODO: enable next line once the signer address is implemented
                //owner()
            )
        );
        require(success, "deposit failed");
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
        if ($.blsPubKey.length > 0) {
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
        // increase the deposit only if already activated as a validator
        if ($.blsPubKey.length > 0) {
            (bool success, bytes memory data) = DEPOSIT_CONTRACT.call{
                value: msg.value
            }(
                abi.encodeWithSignature("tempIncreaseDeposit(bytes)",
                    $.blsPubKey
                )
            );
            require(success, "deposit increase failed");
        }
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
        $.withdrawals[msg.sender].queue(amount);
        $.totalWithdrawals += amount;
        if ($.blsPubKey.length > 0) {
            // maintain a balance that is always sufficient to cover the claims
            if (address(this).balance < $.totalWithdrawals) {
                (bool success, bytes memory data) = DEPOSIT_CONTRACT.call(
                    abi.encodeWithSignature("tempDecreaseDeposit(bytes,uint256)",
                        $.blsPubKey,
                        $.totalWithdrawals - address(this).balance
                    )
                );
                require(success, "deposit decrease failed");
            }
        }
        NonRebasingLST($.lst).burn(msg.sender, shares);
        emit Unstaked(msg.sender, amount, shares);
    }

    function getCommissionNumerator() public view returns(uint256) {
        LiquidDelegationStorage storage $ = _getLiquidDelegationStorage();
        return $.commissionNumerator;
    }

    function setCommissionNumerator(uint256 _commissionNumerator) public onlyOwner {
        require(_commissionNumerator < DENOMINATOR, "invalid commission");
        LiquidDelegationStorage storage $ = _getLiquidDelegationStorage();
        $.commissionNumerator = _commissionNumerator;
    }

    // return the amount of ZIL equivalent to 1 LST (share)
    function getPrice() public view returns(uint256 amount) {
        LiquidDelegationStorage storage $ = _getLiquidDelegationStorage();
        uint256 rewards = getRewards();
        uint256 commission = (rewards - $.taxedRewards) * $.commissionNumerator / DENOMINATOR;
        if (NonRebasingLST($.lst).totalSupply() == 0)
            amount = 1 ether;
        else
            amount = (getStake() + rewards - commission) * 1 ether / NonRebasingLST($.lst).totalSupply();
    }

    function taxRewards() internal {
        LiquidDelegationStorage storage $ = _getLiquidDelegationStorage();
        uint256 rewards = getRewards();
        uint256 commission = (rewards - $.taxedRewards) * $.commissionNumerator / DENOMINATOR;
        $.taxedRewards = rewards - commission;
        if (commission == 0)
            return;
        // commissions are not subject to the unbonding period
        (bool success, bytes memory data) = owner().call{
            value: commission
        }("");
        require(success, "transfer of commission failed");
        emit CommissionPaid(owner(), rewards, commission);
    }

    function getClaimable() public view returns(uint256 total) {
        LiquidDelegationStorage storage $ = _getLiquidDelegationStorage();
        WithdrawalQueue.Fifo storage fifo = $.withdrawals[msg.sender];
        uint256 index = fifo.first;
        while (fifo.ready(index)) {
            total += fifo.items[index].amount;
            index++;
        }
    }

    function claim() public whenNotPaused {
        LiquidDelegationStorage storage $ = _getLiquidDelegationStorage();
        uint256 total;
        while ($.withdrawals[msg.sender].ready())
            total += $.withdrawals[msg.sender].dequeue().amount;
        /*if (total == 0)
            return;*/
        // before the balance changes deduct the commission from the yet untaxed rewards
        taxRewards();
        //TODO: claim all deposit withdrawals requested whose unbonding period is over
        (bool success, bytes memory data) = msg.sender.call{
            value: total
        }("");
        require(success, "transfer of funds failed");
        $.totalWithdrawals -= total;
        $.taxedRewards -= total;
        emit Claimed(msg.sender, total);
    }

    //TODO: make it onlyOwnerOrContract and call it every time someone stakes, unstakes or claims?
    function stakeRewards() public onlyOwner {
        LiquidDelegationStorage storage $ = _getLiquidDelegationStorage();
        // before the balance changes deduct the commission from the yet untaxed rewards
        taxRewards();
        if ($.blsPubKey.length > 0) {
            (bool success, bytes memory data) = DEPOSIT_CONTRACT.call{
                value: address(this).balance - $.totalWithdrawals
            }(
                abi.encodeWithSignature("tempIncreaseDeposit(bytes)",
                    $.blsPubKey
                )
            );
            require(success, "deposit increase failed");
        }
    }

    function collectCommission() public onlyOwner {
        taxRewards();
    }

    function getTaxedRewards() public view returns(uint256) {
        LiquidDelegationStorage storage $ = _getLiquidDelegationStorage();
        return $.taxedRewards;
    } 

    function getTotalWithdrawals() public view returns(uint256) {
        LiquidDelegationStorage storage $ = _getLiquidDelegationStorage();
        return $.totalWithdrawals;
    }

    function getRewards() public view returns(uint256) {
        LiquidDelegationStorage storage $ = _getLiquidDelegationStorage();
        if ($.blsPubKey.length == 0)
            return 0;
        (bool success, bytes memory data) = DEPOSIT_CONTRACT.staticcall(
            abi.encodeWithSignature("getRewardAddress(bytes)", $.blsPubKey)
        );
        require(success, "could not retrieve reward address");
        address rewardAddress = abi.decode(data, (address));
        return rewardAddress.balance;
    }

    function getStake() public view returns(uint256) {
        LiquidDelegationStorage storage $ = _getLiquidDelegationStorage();
        if ($.blsPubKey.length == 0)
            return address(this).balance;
        (bool success, bytes memory data) = DEPOSIT_CONTRACT.staticcall(
            abi.encodeWithSignature("getStake(bytes)", $.blsPubKey)
        );
        require(success, "could not retrieve staked amount");
        return abi.decode(data, (uint256));
    }

    function getLST() public view returns(address) {
        LiquidDelegationStorage storage $ = _getLiquidDelegationStorage();
        return $.lst;
    }

}