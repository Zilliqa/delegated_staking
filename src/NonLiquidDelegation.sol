// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity ^0.8.26;

import {BaseDelegation} from "src/BaseDelegation.sol";

// do not change this interface, it will break the detection of
// the staking variant of an already deployed delegation contract
interface INonLiquidDelegation {
    function interfaceId() external pure returns (bytes4);
    function getDelegatedStake() external view returns(uint256);
    function rewards() external view returns(uint256);
}

contract NonLiquidDelegation is BaseDelegation, INonLiquidDelegation {

    /* commented out because defining empty structs is disallowed
    /// @custom:storage-location erc7201:zilliqa.storage.NonLiquidDelegation
    struct NonLiquidDelegationStorage {
    }
    */

    // keccak256(abi.encode(uint256(keccak256("zilliqa.storage.NonLiquidDelegation")) - 1)) & ~bytes32(uint256(0xff))
    // solhint-disable const-name-snakecase
    bytes32 private constant NonLiquidDelegationStorageLocation = 0x66c8dc4f9c8663296597cb1e39500488e05713d82a9122d4f548b19a70fc2000;

    /* commented out because defining empty structs is disallowed
    function _getNonLiquidDelegationStorage() private pure returns (NonLiquidDelegationStorage storage $) {
        assembly {
            $.slot := NonLiquidDelegationStorageLocation
        }
    }
    */

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address initialOwner) public initializer {
        __BaseDelegation_init(initialOwner);
    }

    function deposit(
        bytes calldata,
        bytes calldata,
        bytes calldata
    ) public override payable {
        revert("not implemented");
    }

    function join(bytes calldata, address) public pure override {
        revert("not implemented");
    }

    function leave(bytes calldata) public pure override {
        revert("not implemented");
    }

    function stake() external payable override {
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

    function rewards() public pure returns(uint256) {
        revert("not implemented");
    }

    function rewards(uint64) public pure returns(uint256) {
        revert("not implemented");
    }

    function getDelegatedStake() public pure returns(uint256) {
        revert("not implemented");
    }

    function withdrawRewards(uint256, uint64) public pure returns(uint256) {
        revert("not implemented");
    }

    function withdrawRewards(uint256) public pure returns(uint256) {
        revert("not implemented");
    }

    function withdrawAllRewards(uint64) public pure returns(uint256) {
        revert("not implemented");
    }

    function withdrawAllRewards() public pure returns(uint256) {
        revert("not implemented");
    }

    function supportsInterface(bytes4 _interfaceId) public view override returns (bool) {
       return _interfaceId == type(INonLiquidDelegation).interfaceId || super.supportsInterface(_interfaceId);
    }

    function interfaceId() public pure returns (bytes4) {
       return type(INonLiquidDelegation).interfaceId;
    }

}
