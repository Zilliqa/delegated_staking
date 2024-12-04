// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity ^0.8.26;

import "src/BaseDelegation.sol";

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

    function initialize(address initialOwner) initializer public {
        __BaseDelegation_init(initialOwner);
    }

    function deposit(
        bytes calldata blsPubKey,
        bytes calldata peerId,
        bytes calldata signature
    ) public override payable {
        revert("not implemented");
    }

    function deposit2(
        bytes calldata blsPubKey,
        bytes calldata peerId,
        bytes calldata signature
    ) public override {
        revert("not implemented");
    }

    function stake() external payable override {
        revert("not implemented");
    }

    function unstake(uint256) external override {
        revert("not implemented");
    }

    function claim() external override {
        revert("not implemented");
    }

    function collectCommission() public override {
        revert("not implemented");
    }

    function stakeRewards() public override {
        revert("not implemented");
    }

    function rewards() public view returns(uint256) {
        revert("not implemented");
    }

    function rewards(uint64) public view returns(uint256) {
        revert("not implemented");
    }

    function getDelegatedStake() public view returns(uint256) {
        revert("not implemented");
    }

    function withdrawRewards(uint256, uint64) public returns(uint256) {
        revert("not implemented");
    }

    function withdrawRewards(uint256) public returns(uint256) {
        revert("not implemented");
    }

    function withdrawAllRewards(uint64) public returns(uint256) {
        revert("not implemented");
    }

    function withdrawAllRewards() public returns(uint256) {
        revert("not implemented");
    }

    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
       return interfaceId == type(INonLiquidDelegation).interfaceId || super.supportsInterface(interfaceId);
    }

    function interfaceId() public pure returns (bytes4) {
       return type(INonLiquidDelegation).interfaceId;
    }

}
