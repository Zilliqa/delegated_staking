// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity ^0.8.26;

import "src/BaseDelegation.sol";

interface INonLiquidDelegation {
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

    // TODO: check - call the _init() functions of the base contracts
    //       here or in __BaseDelegation_init()?
    function initialize(address initialOwner) initializer public {
        __BaseDelegation_init();
        __Pausable_init();
        __Ownable_init(initialOwner);
        __Ownable2Step_init();
        __UUPSUpgradeable_init();
        __ERC165_init();
    }

    //TODO: remove?
    receive() payable external {
    }

    function stake() external payable {
        revert("not implemented");
    }

    function unstake(uint256) external {
        revert("not implemented");
    }

    function claim() external {
        revert("not implemented");
    }

    function collectCommission() public override {
        revert("not implemented");
    }

    function rewards() public view returns(uint256) {
        revert("not implemented");
    }

    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
       return interfaceId == type(INonLiquidDelegation).interfaceId || super.supportsInterface(interfaceId);
    }

}
