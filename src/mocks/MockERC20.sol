// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

/**
 * @title MockERC20
 * @dev A mock implementation of the ERC20 token contract.
 */
contract MockERC20 is ERC20 {
    uint8 private mockDecimals;

    /**
     * @dev Initializes the MockERC20 contract.
     * @param name The name of the token.
     * @param symbol The symbol of the token.
     * @param _decimals The number of decimals for the token.
     */
    constructor(
        string memory name,
        string memory symbol,
        uint8 _decimals
    ) ERC20(name, symbol) {
        mockDecimals = (_decimals < 18) ? _decimals : 18;
    }

    /**
     * @dev Mints new tokens and assigns them to the specified account.
     * @param account The account to which the tokens will be minted.
     * @param amount The amount of tokens to mint.
     */
    function mint(address account, uint amount) external {
        _mint(account, amount);
    }

    /**
     * @dev Returns the number of decimals for the token.
     * @return The number of decimals.
     */
    function decimals() public view override returns (uint8) {
        return mockDecimals;
    }
}
