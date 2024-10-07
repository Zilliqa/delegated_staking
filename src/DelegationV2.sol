// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "src/NonRebasingLST.sol";

// the contract is supposed to be deployed with the node's signer account
// TODO: add events
contract DelegationV2 is Initializable, PausableUpgradeable, Ownable2StepUpgradeable, UUPSUpgradeable {

    /// @custom:storage-location erc7201:zilliqa.storage.Delegation
    struct Storage {
        bytes blsPubKey;
        bytes peerId;
        address lst;
    }

    // keccak256(abi.encode(uint256(keccak256("zilliqa.storage.Delegation")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant STORAGE_POSITION = 0x4432bdf0e567007e5ad3c8ad839a7f885ef69723eaa659dd9f06e98a97274300;

    function _getStorage() private pure returns (Storage storage $) {
        assembly {
            $.slot := STORAGE_POSITION
        }
    }

    uint256 public constant MIN_DELEGATION = 100 ether;
    address public constant DEPOSIT_CONTRACT = 0x000000000000000000005a494C4445504F534954;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function version() public view returns(uint64) {
        return _getInitializedVersion();
    } 

    function reinitialize() reinitializer(version() + 1) public {
        Storage storage $ = _getStorage();
        $.lst = address(new NonRebasingLST(address(this)));
    }

    function _authorizeUpgrade(address newImplementation) internal onlyOwner override {}

    event Staked(address indexed delegator, uint256 amount, uint256 shares);
    event UnStaked(address indexed delegator, uint256 amount, uint256 shares);

    // only for test purposes
    receive() payable external {}

    // called by the node's account that deployed this contract and is its owner
    // with at least the minimum stake to request activation as a validator
    function deposit(
        bytes calldata blsPubKey,
        bytes calldata peerId,
        bytes calldata signature
    ) public payable onlyOwner {
        Storage storage $ = _getStorage();
        $.blsPubKey = blsPubKey;
        $.peerId = peerId;
        (bool success, bytes memory data) = DEPOSIT_CONTRACT.call{
            value: msg.value
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
        NonRebasingLST($.lst).mint(owner(), msg.value);
        require(success, "deposit failed");
    } 

    function stake() public payable whenNotPaused {
        require(msg.value >= MIN_DELEGATION, "delegated amount too low");
        //TODO: topup deposit by msg.value so that msg.value becomes part of getStake()
        Storage storage $ = _getStorage();
        uint256 shares = NonRebasingLST($.lst).totalSupply() * msg.value / (getStake() + getRewards());
        NonRebasingLST($.lst).mint(msg.sender, shares);
        emit Staked(msg.sender, msg.value, shares);
    }

    function unstake(uint256 shares) public whenNotPaused {
        Storage storage $ = _getStorage();
        NonRebasingLST($.lst).burn(msg.sender, shares);
        uint256 amount = (getStake() + getRewards()) * shares / NonRebasingLST($.lst).totalSupply();
        //TODO: don't the transfer the amount, msg.sender can claim it after the unbonding period
        msg.sender.call{
            value: amount
        }("");
        emit UnStaked(msg.sender, amount, shares);
    }

    function claim() public whenNotPaused {
    } 

    function restake() public onlyOwner{
    } 

    function getRewards() public view returns(uint256) {
        Storage storage $ = _getStorage();
        (bool success, bytes memory data) = DEPOSIT_CONTRACT.staticcall(
            abi.encodeWithSignature("getRewardAddress(bytes)", $.blsPubKey)
        );
        require(success, "could not retrieve reward address");
        address rewardAddress = abi.decode(data, (address));
        return rewardAddress.balance;
    }

    function getStake() public view returns(uint256) {
        Storage storage $ = _getStorage();
        (bool success, bytes memory data) = DEPOSIT_CONTRACT.staticcall(
            abi.encodeWithSignature("getStake(bytes)", $.blsPubKey)
        );
        require(success, "could not retrieve staked amount");
        return abi.decode(data, (uint256));
    }

    function getLST() public view returns(address) {
        Storage storage $ = _getStorage();
        return $.lst;
    }

}