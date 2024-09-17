// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title MockStETH
 * @dev A mock implementation of the StETH token.
 */
contract MockStETH is ERC20 {
    /**
     * @dev Initializes the MockStETH contract.
     * @param name The name of the token.
     * @param symbol The symbol of the token.
     */
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    /**
     * @dev Mints new tokens and assigns them to the specified address.
     * @param to The address to which the tokens will be minted.
     * @param amount The amount of tokens to mint.
     */
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    /**
     * @dev Burns tokens from the specified account.
     * @param account The account from which the tokens will be burned.
     * @param amount The amount of tokens to burn.
     * @return A boolean indicating whether the burn was successful.
     */
    function burnFrom(address account, uint256 amount) external returns (bool) {
        _burn(account, amount);
        return true;
    }
}
