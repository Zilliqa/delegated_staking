// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity ^0.8.26;

import "src/BaseDelegation.sol";
import "src/NonRebasingLST.sol";

interface ILiquidDelegation {
    function getPrice() external view returns(uint256);
}

contract LiquidDelegation is BaseDelegation, ILiquidDelegation {

    /// @custom:storage-location erc7201:zilliqa.storage.LiquidDelegation
    struct LiquidDelegationStorage {
        address lst;
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

    // TODO: check - call the _init() functions of the base contracts
    //       here or in __BaseDelegation_init()?
    function initialize(address initialOwner) initializer public {
        __BaseDelegation_init();
        __Pausable_init();
        __Ownable_init(initialOwner);
        __Ownable2Step_init();
        __UUPSUpgradeable_init();
        __ERC165_init();
        LiquidDelegationStorage storage $ = _getLiquidDelegationStorage();
        $.lst = address(new NonRebasingLST(address(this)));
    }

    //TODO: remove?
    receive() payable external {
    }

    function getLST() public view returns(address) {
        LiquidDelegationStorage storage $ = _getLiquidDelegationStorage();
        return $.lst;
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

    function getPrice() public view returns(uint256) {
        revert("not implemented");
    }

    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
       return interfaceId == type(ILiquidDelegation).interfaceId || super.supportsInterface(interfaceId);
    }

}
