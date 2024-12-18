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

    function initialize(address initialOwner, string calldata name, string calldata symbol) public initializer {
        __BaseDelegation_init(initialOwner);
        LiquidDelegationStorage storage $ = _getLiquidDelegationStorage();
        $.lst = address(new NonRebasingLST(address(this), name, symbol));
    }

    function getLST() public view returns(address) {
        LiquidDelegationStorage storage $ = _getLiquidDelegationStorage();
        return $.lst;
    }

    function depositFirst(
        bytes calldata,
        bytes calldata,
        bytes calldata
    ) public override payable {
        revert("not implemented");
    }

    function depositLater(
        bytes calldata,
        bytes calldata,
        bytes calldata
    ) public pure override {
        revert("not implemented");
    }

    function migrate(bytes calldata) public pure override {
        revert("not implemented");
    }

    function stake() external override payable {
        revert("not implemented");
    }

    function unstake(uint256) external pure override returns(uint256) {
        revert("not implemented");
    }

    function claim() external pure override {
        revert("not implemented");
    }

    function collectCommission() public pure override {
        revert("not implemented");
    }

    function stakeRewards() public pure override {
        revert("not implemented");
    }

    function getPrice() public pure returns(uint256) {
        revert("not implemented");
    }

    function supportsInterface(bytes4 _interfaceId) public view override returns (bool) {
       return _interfaceId == type(ILiquidDelegation).interfaceId || super.supportsInterface(_interfaceId);
    }

    function interfaceId() public pure returns (bytes4) {
       return type(ILiquidDelegation).interfaceId;
    }
}
