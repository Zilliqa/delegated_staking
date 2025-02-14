// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity ^0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @notice Non-rebasing liquid staking token issued by the {LiquidDelegation}
 * contract of the respective staking pool.
 *
 * @dev The `owner` is the {LiquidDelegation} contract that deployed the token
 * contract. It is allowed to {mint} and {burn} tokens.
 * 
 */
contract NonRebasingLST is ERC20, Ownable {

    /**
    * @dev Create an `ERC20` token with the specified `name` and `symbol`.
    */
    constructor(string memory name, string memory symbol)
        ERC20(name, symbol)
        Ownable(msg.sender)
    {}

    /**
    * @dev Mint `amount` liquid staking tokens when `to` stakes with the
    * {LiquidDelegation} contract that is the `owner` of this contract.
    */
    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }

    /**
    * @dev Burn `amount` liquid staking tokens when `from` unstakes from
    * the {LiquidDelegation} contract that is the `owner` of this contract.
    */
    function burn(address from, uint256 amount) public onlyOwner {
        _burn(from, amount);
    }
}

