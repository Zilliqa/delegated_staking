// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity ^0.8.26;

import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "src/NonRebasingLST.sol";

contract LiquidDelegation is Initializable, PausableUpgradeable, Ownable2StepUpgradeable, UUPSUpgradeable {

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

    address public constant DEPOSIT_CONTRACT = 0x000000000000000000005a494C4445504F534954;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function version() public view returns(uint64) {
        return _getInitializedVersion();
    } 

    function initialize(address initialOwner) initializer public {
        __Pausable_init();
        __Ownable_init(initialOwner);
        __Ownable2Step_init();
        __UUPSUpgradeable_init();
        LiquidDelegationStorage storage $ = _getLiquidDelegationStorage();
        $.lst = address(new NonRebasingLST(address(this)));
    }

    function _authorizeUpgrade(address newImplementation) internal onlyOwner override {}

    receive() payable external {
    } 

    function getLST() public view returns(address) {
        LiquidDelegationStorage storage $ = _getLiquidDelegationStorage();
        return $.lst;
    }

}
