// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "src/NonRebasingLST.sol";

contract Delegation is Initializable, PausableUpgradeable, Ownable2StepUpgradeable, UUPSUpgradeable {

    /// @custom:storage-location erc7201:zilliqa.storage.Delegation
    struct Storage {
        address lst;
    }

    // keccak256(abi.encode(uint256(keccak256("zilliqa.storage.Delegation")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant STORAGE_POSITION = 0x669e9cfa685336547bc6d91346afdd259f6cd8c0cb6d0b16603b5fa60cb48800;

    function _getStorage() private pure returns (Storage storage $) {
        assembly {
            $.slot := STORAGE_POSITION
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
        Storage storage $ = _getStorage();
        $.lst = address(new NonRebasingLST(address(this)));
    }

    function _authorizeUpgrade(address newImplementation) internal onlyOwner override {}

    receive() payable external {
    } 

    function getLST() public view returns(address) {
        Storage storage $ = _getStorage();
        return $.lst;
    }

}
